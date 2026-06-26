import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'services/platform_support.dart';
import 'theme/app_palette.dart';

// left wall & human detection

class ObstacleDetectionPage extends StatefulWidget {
  final VoidCallback? onBackToHome;
  final bool isActive;

  const ObstacleDetectionPage({
    super.key,
    this.onBackToHome,
    this.isActive = true,
  });

  @override
  State<ObstacleDetectionPage> createState() => _ObstacleDetectionPageState();
}

class _ObstacleDetectionPageState extends State<ObstacleDetectionPage>
    with WidgetsBindingObserver {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  bool _sttAvailable = false;
  bool _isListening = false;

  static const String _voiceInstruction =
      'Tap the button and say start detection to start scanning, '
      'stop to stop detection, or back to home page to return.';

  CameraController? _controller;
  ObjectDetector? _detector;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = -1;

  // Drop a trained TFLite image-classification model at this asset path to
  // enable custom obstacle labels. If absent, ML Kit's built-in detector runs.
  static const _customModelAsset = 'assets/models/obstacle_model.tflite';
  bool _usingCustomModel = false;

  bool _isDetecting = false; // user has detection turned on
  bool _isStarting = false; // camera is initializing
  bool _isBusy = false; // a frame is currently being processed

  // On-screen diagnostics so detection problems are visible during field
  // testing, without needing a USB log connection.
  int _framesReceived = 0;
  int _framesConverted = 0;
  int _lastObjectCount = 0;
  String? _lastFrameError;

  _Detection? _currentAlert;
  final List<_Detection> _recent = [];

  DateTime _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastObstacleAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastSpokenMessage;

  // Maps the device orientation to a rotation in degrees, used to convert
  // camera frames into the upright orientation ML Kit expects.
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initTts();
    _initVoice();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
    } catch (_) {
      await _tts.setLanguage('en');
    }
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _initVoice() async {
    final micStatus = await Permission.microphone.request();
    if (!mounted) return;

    if (micStatus.isGranted) {
      _sttAvailable = await _stt.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'listening') {
            setState(() => _isListening = true);
          } else if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (error) {
          debugPrint('STT error: ${error.errorMsg}');
          if (mounted) setState(() => _isListening = false);
        },
      );
    }

    if (mounted) _speak(_voiceInstruction);
  }

  Future<void> _pressMic() async {
    if (!_sttAvailable || _isListening) return;
    setState(() => _isListening = true);
    await _stt.listen(
      onResult: (result) {
        if (!mounted || !result.finalResult) return;
        _handleVoiceCommand(result.recognizedWords.toLowerCase());
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 10),
      localeId: 'en_US',
    );
  }

  void _handleVoiceCommand(String command) {
    if (command.contains('back') && command.contains('home')) {
      _speak('Returning to home page.');
      widget.onBackToHome?.call();
    } else if (command.contains('stop')) {
      if (_isDetecting) {
        _stopDetection();
      } else {
        _speak('Detection is not currently running.');
      }
    } else if (command.contains('start detection') ||
        command.contains('start') ||
        command.contains('detection')) {
      _startDetection();
    } else {
      _speak('I did not catch that. $_voiceInstruction');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _detector?.close();
    _stt.stop();
    _tts.stop();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ObstacleDetectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This page lives inside an IndexedStack, so switching tabs doesn't
    // dispose it — without this, detection and TTS keep running and bleed
    // into whichever tab the user switches to.
    if (oldWidget.isActive && !widget.isActive) {
      if (_isDetecting) _stopDetection(speak: false);
      _stt.stop();
      _tts.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isDetecting) return;
    // Release the camera while backgrounded, then restore it on return.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera().then((_) {
        if (mounted) setState(() {});
      }).catchError((Object e) {
        debugPrint('Camera resume error: $e');
      });
    }
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  // ===================== DETECTION CONTROL =====================

  // Uses the bundled custom TFLite model when present, otherwise falls back
  // to ML Kit's built-in object detector.
  Future<ObjectDetector> _createDetector() async {
    try {
      final modelPath = await _copyModelToFile(_customModelAsset);
      final detector = ObjectDetector(
        options: LocalObjectDetectorOptions(
          mode: DetectionMode.stream,
          modelPath: modelPath,
          classifyObjects: true,
          multipleObjects: true,
        ),
      );
      _usingCustomModel = true;
      return detector;
    } catch (e) {
      debugPrint('Custom model unavailable, using built-in detector: $e');
      _usingCustomModel = false;
      return ObjectDetector(
        options: ObjectDetectorOptions(
          mode: DetectionMode.stream,
          classifyObjects: true,
          multipleObjects: true,
        ),
      );
    }
  }

  // ML Kit needs a real file path, so the bundled asset is copied to disk.
  Future<String> _copyModelToFile(String assetPath) async {
    final dir = await getApplicationSupportDirectory();
    final fileName = assetPath.split('/').last;
    final file = File('${dir.path}/$fileName');
    final assetData = await rootBundle.load(assetPath);
    final bytes = assetData.buffer.asUint8List(
      assetData.offsetInBytes,
      assetData.lengthInBytes,
    );
    // Re-copy when the bundled model changes (e.g. after an app update).
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }

  Future<void> _startDetection() async {
    if (_isStarting || _isDetecting) return;

    if (!obstacleDetectionSupported) {
      _speak(
        'Obstacle detection needs a camera and is not available on this device.',
      );
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: kCardFill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Camera not available',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Obstacle detection needs a camera and only works on Android '
              'or iOS. It is not available on this device.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK', style: TextStyle(color: kBlueAccent)),
              ),
            ],
          ),
        );
      }
      return;
    }

    setState(() => _isStarting = true);

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      setState(() => _isStarting = false);
      _speak(
        'Camera permission is needed for obstacle detection. '
        'Please enable camera access in your settings.',
      );
      return;
    }

    try {
      _detector ??= await _createDetector();
      await _initCamera();
      if (!mounted) return;
      setState(() {
        _isDetecting = true;
        _isStarting = false;
        _currentAlert = null;
        _framesReceived = 0;
        _framesConverted = 0;
        _lastObjectCount = 0;
        _lastFrameError = null;
      });
      _lastSpokenAt = DateTime.now();
      _lastObstacleAt = DateTime.now();
      _lastSpokenMessage = null;
      _speak(
        'Obstacle detection started. Hold your phone upright at chest level, '
        'with the camera facing forward.',
      );
    } catch (e) {
      debugPrint('Obstacle detection start error: $e');
      await _disposeCamera();
      if (!mounted) return;
      setState(() => _isStarting = false);
      _speak('Could not start the camera. Please try again.');
    }
  }

  Future<void> _stopDetection({bool speak = true}) async {
    await _disposeCamera();
    if (!mounted) return;
    setState(() {
      _isDetecting = false;
      _currentAlert = null;
    });
    if (speak) _speak('Obstacle detection stopped.');
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
    }
    if (_cameras.isEmpty) {
      throw Exception('No camera available on this device.');
    }
    _cameraIndex = _cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    if (_cameraIndex == -1) _cameraIndex = 0;

    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    _controller = controller;
    await controller.startImageStream(_processCameraImage);
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
    await controller.dispose();
  }

  // ===================== FRAME PROCESSING =====================

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || !_isDetecting || _detector == null) return;
    _isBusy = true;
    _framesReceived++;
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _lastFrameError = 'Camera frame could not be converted '
            '(format ${image.format.raw}, planes ${image.planes.length}).';
      } else {
        _framesConverted++;
        final objects = await _detector!.processImage(inputImage);
        _lastObjectCount = objects.length;
        _lastFrameError = null;
        if (mounted && _isDetecting) {
          _analyzeObjects(objects, inputImage.metadata!);
        }
      }
    } catch (e) {
      _lastFrameError = e.toString();
      debugPrint('Frame processing error: $e');
    } finally {
      _isBusy = false;
      // Refresh the on-screen diagnostics roughly once per second.
      if (_framesReceived % 15 == 0 && mounted) setState(() {});
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _controller;
    if (controller == null || _cameraIndex < 0) return null;
    final camera = _cameras[_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    // iOS delivers a single BGRA8888 plane.
    if (Platform.isIOS) {
      if (image.planes.length != 1) return null;
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // Android: use NV21 directly if the camera provides it, otherwise convert
    // the YUV_420_888 frame (3 planes) that most devices actually deliver.
    final Uint8List bytes;
    final int bytesPerRow;
    if (image.planes.length == 1) {
      bytes = image.planes.first.bytes;
      bytesPerRow = image.planes.first.bytesPerRow;
    } else if (image.planes.length == 3) {
      bytes = _yuv420ToNv21(image);
      bytesPerRow = image.width;
    } else {
      return null;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  // Converts a YUV_420_888 camera frame (3 planes) into a packed NV21 buffer,
  // the format ML Kit expects on Android. Needed because many devices ignore
  // the requested nv21 image-format group and deliver YUV_420_888 anyway.
  Uint8List _yuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final yP = image.planes[0];
    final uP = image.planes[1];
    final vP = image.planes[2];

    final int ySize = width * height;
    final Uint8List out = Uint8List(ySize + ySize ~/ 2);

    // Y plane.
    int o = 0;
    final int yRowStride = yP.bytesPerRow;
    final int yPixStride = yP.bytesPerPixel ?? 1;
    if (yPixStride == 1 && yRowStride == width) {
      out.setRange(0, ySize, yP.bytes);
      o = ySize;
    } else {
      for (int r = 0; r < height; r++) {
        final int base = r * yRowStride;
        for (int c = 0; c < width; c++) {
          out[o++] = yP.bytes[base + c * yPixStride];
        }
      }
    }

    // Interleaved V/U (NV21 = the Y plane followed by V,U,V,U...).
    final int uvRowStride = uP.bytesPerRow;
    final int uvPixStride = uP.bytesPerPixel ?? 2;
    final int chromaH = height ~/ 2;
    final int chromaW = width ~/ 2;
    for (int r = 0; r < chromaH; r++) {
      final int uBase = r * uvRowStride;
      final int vBase = r * vP.bytesPerRow;
      for (int c = 0; c < chromaW; c++) {
        final int j = c * uvPixStride;
        out[o++] = vP.bytes[vBase + j];
        out[o++] = uP.bytes[uBase + j];
      }
    }
    return out;
  }

  void _analyzeObjects(List<DetectedObject> objects, InputImageMetadata meta) {
    // For 90/270 degree rotations the upright view swaps width and height.
    final rotated = meta.rotation == InputImageRotation.rotation90deg ||
        meta.rotation == InputImageRotation.rotation270deg;
    final viewW = rotated ? meta.size.height : meta.size.width;
    final viewH = rotated ? meta.size.width : meta.size.height;
    final frameArea = viewW * viewH;
    if (frameArea <= 0) return;

    DetectedObject? closest;
    double maxArea = 0;
    for (final o in objects) {
      final area = o.boundingBox.width * o.boundingBox.height;
      if (area > maxArea) {
        maxArea = area;
        closest = o;
      }
    }

    if (closest == null) {
      _handlePathClear();
      return;
    }

    final proximity = _proximityFromArea(maxArea / frameArea);
    if (proximity == null) {
      _handlePathClear();
      return;
    }

    final direction = _directionFromX(closest.boundingBox.center.dx, viewW);
    final subject = _labelFor(closest) ?? 'Obstacle';
    final urgent = proximity == 'very close';
    _registerDetection(subject, direction, proximity, urgent);
  }

  String? _proximityFromArea(double fraction) {
    if (fraction >= 0.45) return 'very close';
    if (fraction >= 0.20) return 'close';
    if (fraction >= 0.06) return 'nearby';
    return null; // too far away or detection noise
  }

  String _directionFromX(double centerX, double viewWidth) {
    final ratio = centerX / viewWidth;
    if (ratio < 0.38) return 'on your left';
    if (ratio > 0.62) return 'on your right';
    return 'ahead';
  }

  // Labels that mean "no specific obstacle" — fall back to a generic alert
  // instead of announcing the class name literally.
  static const _ignoredLabels = {'background', 'none', 'other', 'unknown'};

  // The custom model ships without TFLite metadata, so ML Kit returns numeric
  // class indices instead of names. This list maps index -> name and MUST be
  // in the same order the model was trained on (the alphabetical class list
  // printed by image_dataset_from_directory during training).
  static const _customModelLabels = [
    'chair',
    'door',
    'fence',
    'garbage_bin',
    'obstacle',
    'plant',
    'pothole',
    'stairs',
    'table',
    'vehicle',
  ];

  String? _labelFor(DetectedObject object) {
    if (object.labels.isEmpty) return null;
    final best =
        object.labels.reduce((a, b) => a.confidence >= b.confidence ? a : b);
    if (best.confidence < 0.5) return null;

    var text = best.text;
    if (_usingCustomModel &&
        best.index >= 0 &&
        best.index < _customModelLabels.length) {
      text = _customModelLabels[best.index];
    }
    if (text.isEmpty || _ignoredLabels.contains(text.toLowerCase())) {
      return null;
    }
    return text;
  }

  void _registerDetection(
    String subject,
    String direction,
    String proximity,
    bool urgent,
  ) {
    final now = DateTime.now();
    _lastObstacleAt = now;

    final spoken = '$subject $direction, $proximity';
    final sinceLast = now.difference(_lastSpokenAt);
    final minGap =
        urgent ? const Duration(seconds: 2) : const Duration(seconds: 4);

    if (sinceLast < const Duration(milliseconds: 1500)) return;
    if (spoken == _lastSpokenMessage && sinceLast < minGap) return;

    _lastSpokenAt = now;
    _lastSpokenMessage = spoken;

    final detection = _Detection(
      subject: subject,
      direction: direction,
      proximity: proximity,
      urgent: urgent,
      time: now,
    );
    _speak(detection.spokenAlert);

    if (!mounted) return;
    setState(() {
      _currentAlert = detection;
      _recent.insert(0, detection);
      if (_recent.length > 12) _recent.removeLast();
    });
  }

  void _handlePathClear() {
    if (_currentAlert == null) return;
    // Debounce: object detection can flicker, so wait for a steady gap.
    if (DateTime.now().difference(_lastObstacleAt) <
        const Duration(milliseconds: 1500)) {
      return;
    }
    _lastSpokenMessage = null;
    _speak('Path clear.');
    if (mounted) setState(() => _currentAlert = null);
  }

  void _repeatAlert() {
    final alert = _currentAlert;
    if (alert != null) _speak(alert.spokenAlert);
  }

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavyDeep,
      appBar: AppBar(
        backgroundColor: kNavyMid,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Obstacle Detection',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (!obstacleDetectionSupported)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kAmberAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: kAmberAccent.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: kAmberAccent, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Obstacle detection needs a camera and only works on '
                        'Android or iOS. It isn\'t available on this device.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // Voice Command Card
            GestureDetector(
              onTap: _pressMic,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kCardFill.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (_isListening ? Colors.greenAccent : kPinkBright)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _isListening
                            ? const LinearGradient(
                                colors: [Colors.green, Colors.lightGreen],
                              )
                            : kAccentGradient,
                        boxShadow: [
                          BoxShadow(
                            color: (_isListening ? Colors.green : kPinkBright)
                                .withValues(alpha: 0.5),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isListening ? 'Listening...' : 'Voice Command',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap the button and say "start detection" to '
                            'start scanning.',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            _buildDetectionCard(),
            if (_isDetecting && _currentAlert != null)
              _buildCurrentAlert(_currentAlert!),
            if (!_isDetecting) _buildHowItWorks(),
            if (_recent.isNotEmpty) _buildRecentDetections(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          _buildPreviewOrIcon(),
          const SizedBox(height: 12),
          const Text(
            'Real-time Detection',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Get instant voice alerts about obstacles in your path',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.white60),
          ),
          const SizedBox(height: 20),
          _buildToggleButton(),
          if (_isDetecting) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Detection Active',
                  style: TextStyle(
                    color: Colors.greenAccent.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _usingCustomModel
                  ? 'Using custom obstacle model'
                  : 'Using built-in detector',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
            _buildDiagnostics(),
          ],
        ],
      ),
    );
  }

  // Live diagnostics panel — shows whether camera frames are reaching ML Kit
  // and surfaces any error so the feature can be debugged in the field.
  Widget _buildDiagnostics() {
    final err = _lastFrameError;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: err != null
            ? kRedAccent.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: err != null
              ? kRedAccent.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Diagnostics',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Frames received: $_framesReceived\n'
            'Frames converted: $_framesConverted\n'
            'Objects (last frame): $_lastObjectCount',
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          if (err != null) ...[
            const SizedBox(height: 6),
            Text(
              'Error: $err',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewOrIcon() {
    final controller = _controller;
    final showPreview =
        _isDetecting && controller != null && controller.value.isInitialized;

    if (!showPreview) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Icon(Icons.photo_camera, size: 46, color: kRedAccent),
      );
    }

    final accent = _currentAlert == null
        ? Colors.white24
        : (_currentAlert!.urgent ? kRedAccent : kAmberAccent);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: SizedBox(
          height: 260,
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.previewSize!.height,
              height: controller.value.previewSize!.width,
              child: CameraPreview(controller),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton() {
    final active = _isDetecting;
    final color = active ? Colors.red.shade600 : Colors.green.shade600;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: _isStarting ? Colors.grey : color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _isStarting
              ? null
              : (active ? () => _stopDetection() : () => _startDetection()),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  active ? Icons.stop_circle : Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isStarting
                          ? 'Starting...'
                          : (active ? 'Stop Detection' : 'Start Detection'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      active
                          ? 'Tap to stop monitoring'
                          : 'Tap to start monitoring',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentAlert(_Detection alert) {
    final accent = alert.urgent ? kRedAccent : kAmberAccent;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: accent),
              const SizedBox(width: 8),
              Text(
                'Current Alert',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            alert.displayAlert,
            style: const TextStyle(fontSize: 14, color: Colors.white),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _repeatAlert,
            icon: const Icon(Icons.volume_up, size: 18),
            label: const Text('Repeat Alert'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks() {
    const steps = [
      'Tap "Start Detection" to begin monitoring',
      'Hold your phone at chest level, camera facing forward',
      'You\'ll hear voice alerts about obstacles ahead',
      'Red alerts are urgent (close obstacles)',
      'Yellow alerts are moderate warnings',
      'Tap any detection to hear it again',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How It Works',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•  ',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      step,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentDetections() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Detections',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          for (final detection in _recent.take(6)) _buildRecentRow(detection),
        ],
      ),
    );
  }

  Widget _buildRecentRow(_Detection detection) {
    final accent = detection.urgent ? kRedAccent : kAmberAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _speak(detection.spokenAlert),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_cap(detection.subject)} - ${detection.direction}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Proximity: ${detection.proximity}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.volume_up, size: 20, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Turns model label names like "traffic_cone" into spoken-friendly
  // "Traffic cone".
  static String _cap(String s) {
    final cleaned = s.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    return cleaned.isEmpty
        ? cleaned
        : '${cleaned[0].toUpperCase()}${cleaned.substring(1)}';
  }
}

class _Detection {
  final String subject;
  final String direction;
  final String proximity;
  final bool urgent;
  final DateTime time;

  _Detection({
    required this.subject,
    required this.direction,
    required this.proximity,
    required this.urgent,
    required this.time,
  });

  String get displayAlert => '${urgent ? 'Warning! ' : ''}'
      '${_ObstacleDetectionPageState._cap(subject)} $direction, $proximity.';

  String get spokenAlert => displayAlert;
}
