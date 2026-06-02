import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

// Tactile paving guidance.
//
// Unlike obstacle detection (which uses ML Kit to find objects), this feature
// keeps the user walking along the textured guidance strip. The reliable
// signal is the strip's distinctive warm yellow colour, so we segment yellow
// pixels directly from the camera frame's chroma data — no model, runs offline.
//
// The frame's lower-centre band (nearest the walker's feet) is split into
// vertical columns. From the per-column yellow counts we derive:
//   * coverage  — how much of the band is the strip (detects "path lost"),
//   * centroid  — where the strip sits left/right (detects drift),
//   * clusters  — separated runs of strip (detects branching paths).
// Temporal smoothing then prevents transient dirt/leaves from causing false
// "path lost" alerts.

class TactilePathPage extends StatefulWidget {
  const TactilePathPage({super.key});

  @override
  State<TactilePathPage> createState() => _TactilePathPageState();
}

enum _Guidance { ahead, easeLeft, easeRight, branch, obscured, lost, scanning }

class _TactilePathPageState extends State<TactilePathPage>
    with WidgetsBindingObserver {
  final FlutterTts _tts = FlutterTts();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = -1;

  bool _isDetecting = false;
  bool _isStarting = false;
  bool _isBusy = false;

  // ---- Tunable calibration constants (tuned for faded yellow/orange strips) -
  // Yellow in YUV: bright luma, low blue-difference (U), elevated red-diff (V).
  static const int _yMin = 70;   // strip must be reasonably lit
  static const int _uMax = 122;  // below neutral 128 (yellow has little blue)
  static const int _vMin = 132;  // above neutral 128 (warm hue)
  static const int _vMax = 205;  // reject strong red (above this is not yellow)

  // Band of the frame we analyse, in upright/normalised coordinates.
  static const double _bandTop = 0.55;   // near-field starts past mid-frame
  static const double _bandBottom = 0.97;
  static const double _bandLeft = 0.12;  // ignore far edges (grass/kerb)
  static const double _bandRight = 0.88;
  static const int _columns = 9;
  static const int _sampleStep = 6;       // sample every Nth pixel (perf)

  static const double _binActive = 0.22;  // column counts as "strip" above this
  static const double _lostFloor = 0.05;  // below this the strip is effectively gone
  static const double _obscuredFloor = 0.16; // good lock sits well above this

  // ---- Temporal smoothing -------------------------------------------------
  // A short history so dirt/leaves over one or two frames don't flip us to
  // "lost", and a branch must be seen repeatedly before it's announced.
  static const int _historyLen = 6;
  final List<_PathReading> _history = [];
  int _consecutiveLost = 0;

  _Guidance _guidance = _Guidance.scanning;

  DateTime _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);
  _Guidance? _lastSpokenGuidance;

  // On-screen diagnostics for field testing.
  int _framesReceived = 0;
  int _framesAnalysed = 0;
  double _lastCoverage = 0;
  double _lastCentroid = 0.5;
  int _lastClusters = 0;
  String? _lastError;

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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _tts.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isDetecting) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera()
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((Object e) {
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

  Future<void> _startDetection() async {
    if (_isStarting || _isDetecting) return;
    setState(() => _isStarting = true);

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      setState(() => _isStarting = false);
      _speak(
        'Camera permission is needed for path guidance. '
        'Please enable camera access in your settings.',
      );
      return;
    }

    try {
      await _initCamera();
      if (!mounted) return;
      setState(() {
        _isDetecting = true;
        _isStarting = false;
        _guidance = _Guidance.scanning;
        _framesReceived = 0;
        _framesAnalysed = 0;
        _lastError = null;
      });
      _history.clear();
      _consecutiveLost = 0;
      _lastSpokenAt = DateTime.now();
      _lastSpokenGuidance = null;
      _speak(
        'Path guidance started. Point the camera down at the tactile strip, '
        'about two steps ahead of your feet.',
      );
    } catch (e) {
      debugPrint('Path guidance start error: $e');
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
      _guidance = _Guidance.scanning;
    });
    if (speak) _speak('Path guidance stopped.');
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
    if (_isBusy || !_isDetecting) return;
    _isBusy = true;
    _framesReceived++;
    try {
      final reading = _scanFrame(image);
      if (reading == null) {
        _lastError =
            'Frame not readable (format ${image.format.raw}, '
            'planes ${image.planes.length}).';
      } else {
        _framesAnalysed++;
        _lastError = null;
        _lastCoverage = reading.coverage;
        _lastCentroid = reading.centroid;
        _lastClusters = reading.clusterCount;
        _updateGuidance(reading);
      }
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Path frame error: $e');
    } finally {
      _isBusy = false;
      if (_framesReceived % 10 == 0 && mounted) setState(() {});
    }
  }

  // Maps the rotation degrees needed to make the sensor frame upright.
  int? _rotationDegrees() {
    final controller = _controller;
    if (controller == null || _cameraIndex < 0) return null;
    final camera = _cameras[_cameraIndex];
    final sensor = camera.sensorOrientation;
    if (Platform.isIOS) return sensor;
    final compensation = _orientations[controller.value.deviceOrientation];
    if (compensation == null) return null;
    if (camera.lensDirection == CameraLensDirection.front) {
      return (sensor + compensation) % 360;
    }
    return (sensor - compensation + 360) % 360;
  }

  // Scans the lower-centre band and returns per-column strip coverage.
  // Coordinates are handled in the upright view; each sampled upright point is
  // mapped back to the raw sensor pixel for the current rotation.
  _PathReading? _scanFrame(CameraImage image) {
    final rotation = _rotationDegrees();
    if (rotation == null) return null;

    final sensorW = image.width;
    final sensorH = image.height;
    final rotated = rotation == 90 || rotation == 270;
    final uprightW = rotated ? sensorH : sensorW;
    final uprightH = rotated ? sensorW : sensorH;

    // Per-platform pixel readers return whether a sensor pixel is "strip yellow".
    final bool Function(int sx, int sy) isStrip;
    if (Platform.isIOS && image.planes.length == 1) {
      final plane = image.planes.first;
      final bytes = plane.bytes;
      final rowStride = plane.bytesPerRow;
      isStrip = (sx, sy) {
        final i = sy * rowStride + sx * 4; // BGRA
        if (i + 2 >= bytes.length) return false;
        final b = bytes[i], g = bytes[i + 1], r = bytes[i + 2];
        return _isWarmRgb(r, g, b);
      };
    } else if (image.planes.length == 1) {
      // Android NV21: Y plane then interleaved V,U.
      final bytes = image.planes.first.bytes;
      final yStride = image.planes.first.bytesPerRow;
      final uvStart = yStride * sensorH;
      isStrip = (sx, sy) {
        final yi = sy * yStride + sx;
        if (yi >= bytes.length) return false;
        final y = bytes[yi];
        final uvi = uvStart + (sy >> 1) * yStride + (sx & ~1);
        if (uvi + 1 >= bytes.length) return false;
        final v = bytes[uvi];
        final u = bytes[uvi + 1];
        return _isWarmYuv(y, u, v);
      };
    } else if (image.planes.length == 3) {
      // Android YUV_420_888: separate Y / U / V planes.
      final yP = image.planes[0], uP = image.planes[1], vP = image.planes[2];
      final yb = yP.bytes, ub = uP.bytes, vb = vP.bytes;
      final yStride = yP.bytesPerRow;
      final uvRow = uP.bytesPerRow;
      final uvPix = uP.bytesPerPixel ?? 2;
      isStrip = (sx, sy) {
        final yi = sy * yStride + sx;
        if (yi >= yb.length) return false;
        final y = yb[yi];
        final ci = (sy >> 1) * uvRow + (sx >> 1) * uvPix;
        if (ci >= ub.length || ci >= vb.length) return false;
        return _isWarmYuv(y, ub[ci], vb[ci]);
      };
    } else {
      return null;
    }

    final counts = List<int>.filled(_columns, 0);
    final totals = List<int>.filled(_columns, 0);

    final int uy0 = (uprightH * _bandTop).floor();
    final int uy1 = (uprightH * _bandBottom).floor();
    final int ux0 = (uprightW * _bandLeft).floor();
    final int ux1 = (uprightW * _bandRight).floor();
    final double colSpan = (ux1 - ux0) / _columns;
    if (colSpan <= 0) return null;

    for (int uy = uy0; uy < uy1; uy += _sampleStep) {
      for (int ux = ux0; ux < ux1; ux += _sampleStep) {
        final col = ((ux - ux0) / colSpan).floor().clamp(0, _columns - 1);
        // Map upright (ux,uy) back to the raw sensor pixel.
        int sx, sy;
        switch (rotation) {
          case 90:
            sx = uy;
            sy = (sensorH - 1) - ux;
            break;
          case 180:
            sx = (sensorW - 1) - ux;
            sy = (sensorH - 1) - uy;
            break;
          case 270:
            sx = (sensorW - 1) - uy;
            sy = ux;
            break;
          default: // 0
            sx = ux;
            sy = uy;
        }
        if (sx < 0 || sy < 0 || sx >= sensorW || sy >= sensorH) continue;
        totals[col]++;
        if (isStrip(sx, sy)) counts[col]++;
      }
    }

    return _PathReading.fromColumns(counts, totals);
  }

  // YUV warm-yellow test (chroma is 0..255, neutral at 128).
  static bool _isWarmYuv(int y, int u, int v) =>
      y >= _yMin && u <= _uMax && v >= _vMin && v <= _vMax;

  // RGB fallback (iOS BGRA): warm, bright, and clearly low on blue.
  static bool _isWarmRgb(int r, int g, int b) =>
      r > 110 && g > 80 && b < 150 && (r - b) > 35 && (g - b) > 5;

  // ===================== GUIDANCE LOGIC =====================

  void _updateGuidance(_PathReading reading) {
    _history.add(reading);
    if (_history.length > _historyLen) _history.removeAt(0);

    // Hysteresis: only escalate to "lost" after several low frames in a row,
    // so dirt, leaves, or a momentary glare don't trigger a false alarm.
    if (reading.coverage < _lostFloor) {
      _consecutiveLost++;
    } else {
      _consecutiveLost = 0;
    }

    final next = _decideGuidance(reading);
    if (next == _guidance && next != _Guidance.branch) {
      // Re-announce branches periodically even if state is unchanged.
      _maybeRepeat();
      return;
    }
    _guidance = next;
    _announce(next);
    if (mounted) setState(() {});
  }

  _Guidance _decideGuidance(_PathReading reading) {
    if (_consecutiveLost >= 4) return _Guidance.lost;

    // A branch must persist across recent frames before we trust it — a single
    // frame split by a crack or shadow shouldn't be called a fork.
    final branchFrames =
        _history.where((r) => r.clusterCount >= 2 && r.coverage >= _obscuredFloor).length;
    if (branchFrames >= 3) return _Guidance.branch;

    if (reading.coverage < _lostFloor) {
      // Dropping out but not yet confirmed lost.
      return _Guidance.obscured;
    }
    if (reading.coverage < _obscuredFloor) {
      // Strip is partially covered (grime/leaves) but still trackable.
      return _Guidance.obscured;
    }

    // Smooth the centroid over recent frames to ignore jitter from debris.
    final tracked = _history.where((r) => r.coverage >= _obscuredFloor).toList();
    if (tracked.isEmpty) return _Guidance.obscured;
    final avgCentroid =
        tracked.map((r) => r.centroid).reduce((a, b) => a + b) / tracked.length;

    if (avgCentroid < 0.40) return _Guidance.easeLeft;
    if (avgCentroid > 0.60) return _Guidance.easeRight;
    return _Guidance.ahead;
  }

  void _maybeRepeat() {
    // Keep urgent states (branch/lost) alive in the user's ear.
    if (_guidance != _Guidance.branch && _guidance != _Guidance.lost) return;
    if (DateTime.now().difference(_lastSpokenAt) >= const Duration(seconds: 3)) {
      _announce(_guidance, force: true);
    }
  }

  void _announce(_Guidance g, {bool force = false}) {
    final now = DateTime.now();
    final sinceLast = now.difference(_lastSpokenAt);
    final urgent = g == _Guidance.lost || g == _Guidance.branch;
    final minGap = urgent ? const Duration(seconds: 2) : const Duration(seconds: 3);

    if (!force) {
      if (sinceLast < const Duration(milliseconds: 1200)) return;
      if (g == _lastSpokenGuidance && sinceLast < minGap) return;
    }
    _lastSpokenAt = now;
    _lastSpokenGuidance = g;
    _speak(_phraseFor(g));
  }

  static String _phraseFor(_Guidance g) {
    switch (g) {
      case _Guidance.ahead:
        return 'Path ahead. Keep going straight.';
      case _Guidance.easeLeft:
        return 'Path is on your left. Ease left to stay on it.';
      case _Guidance.easeRight:
        return 'Path is on your right. Ease right to stay on it.';
      case _Guidance.branch:
        return 'The path splits ahead. Stop and choose a direction.';
      case _Guidance.obscured:
        return 'Path may be covered. Slow down and keep going carefully.';
      case _Guidance.lost:
        return 'Path lost. Stop, and scan slowly left and right to find it.';
      case _Guidance.scanning:
        return 'Searching for the path.';
    }
  }

  void _repeatGuidance() => _speak(_phraseFor(_guidance));

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Path Guidance',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildCard(),
            if (_isDetecting) _buildCurrentGuidance(),
            if (!_isDetecting) _buildHowItWorks(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          _buildPreviewOrIcon(),
          const SizedBox(height: 12),
          const Text(
            'Tactile Path Guidance',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Voice guidance to keep you walking along the tactile strip',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          _buildToggleButton(),
          if (_isDetecting) ...[
            const SizedBox(height: 12),
            _buildDiagnostics(),
          ],
        ],
      ),
    );
  }

  Widget _buildDiagnostics() {
    final err = _lastError;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: err != null ? Colors.red.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: err != null ? Colors.red.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Diagnostics',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Frames: $_framesReceived received, $_framesAnalysed analysed\n'
            'Strip coverage: ${(_lastCoverage * 100).toStringAsFixed(0)}%\n'
            'Centroid: ${_lastCentroid.toStringAsFixed(2)}  '
            'Clusters: $_lastClusters',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          if (err != null) ...[
            const SizedBox(height: 6),
            Text(
              'Error: $err',
              style: TextStyle(
                fontSize: 11,
                color: Colors.red.shade700,
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
        child: Icon(Icons.alt_route, size: 46, color: Colors.teal),
      );
    }

    final accent = _accentFor(_guidance);
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
    final color = active ? Colors.red.shade600 : Colors.teal.shade600;
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
                  active ? Icons.stop_circle : Icons.navigation,
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
                          : (active ? 'Stop Guidance' : 'Start Guidance'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      active ? 'Tap to stop' : 'Tap to start walking',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
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

  Widget _buildCurrentGuidance() {
    final accent = _accentFor(_guidance);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(_guidance), color: accent),
              const SizedBox(width: 8),
              Text(
                'Guidance',
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
            _phraseFor(_guidance),
            style: TextStyle(fontSize: 15, color: accent),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _repeatGuidance,
            icon: const Icon(Icons.volume_up, size: 18),
            label: const Text('Repeat'),
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
      'Tap "Start Guidance" to begin',
      'Hold the phone and point the camera down at the strip ahead of your feet',
      'You\'ll hear "keep going straight" while you stay on the strip',
      'You\'ll be told to ease left or right if you drift off',
      'You\'ll be warned if the path splits, or is covered or lost',
      'Tap "Repeat" to hear the last guidance again',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How It Works',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ',
                      style: TextStyle(
                          fontSize: 14, color: Colors.grey.shade700)),
                  Expanded(
                    child: Text(step,
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade700)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Color _accentFor(_Guidance g) {
    switch (g) {
      case _Guidance.ahead:
        return Colors.green;
      case _Guidance.easeLeft:
      case _Guidance.easeRight:
        return Colors.orange.shade800;
      case _Guidance.obscured:
        return Colors.amber.shade800;
      case _Guidance.branch:
        return Colors.deepPurple;
      case _Guidance.lost:
        return Colors.red;
      case _Guidance.scanning:
        return Colors.grey;
    }
  }

  static IconData _iconFor(_Guidance g) {
    switch (g) {
      case _Guidance.ahead:
        return Icons.straight;
      case _Guidance.easeLeft:
        return Icons.turn_left;
      case _Guidance.easeRight:
        return Icons.turn_right;
      case _Guidance.obscured:
        return Icons.visibility_off;
      case _Guidance.branch:
        return Icons.alt_route;
      case _Guidance.lost:
        return Icons.error_outline;
      case _Guidance.scanning:
        return Icons.search;
    }
  }
}

// A single frame's reading of the tactile strip across the analysed band.
class _PathReading {
  final double coverage;    // fraction of sampled band that is strip
  final double centroid;    // 0 (left) .. 1 (right) of analysed columns
  final int clusterCount;   // separated runs of strip columns (branch = 2+)

  _PathReading({
    required this.coverage,
    required this.centroid,
    required this.clusterCount,
  });

  factory _PathReading.fromColumns(List<int> counts, List<int> totals) {
    final n = counts.length;
    int yellowSum = 0, totalSum = 0;
    double weighted = 0;
    final active = List<bool>.filled(n, false);

    for (int i = 0; i < n; i++) {
      yellowSum += counts[i];
      totalSum += totals[i];
      weighted += counts[i] * i;
      final frac = totals[i] == 0 ? 0.0 : counts[i] / totals[i];
      if (frac >= _TactilePathPageState._binActive) active[i] = true;
    }

    final coverage = totalSum == 0 ? 0.0 : yellowSum / totalSum;
    final centroid = yellowSum == 0
        ? 0.5
        : (weighted / yellowSum) / (n - 1); // normalise 0..1

    // Count separated runs of active columns. A gap of >=1 inactive column
    // between two active runs marks a real split (a branching path).
    int clusters = 0;
    bool inRun = false;
    for (int i = 0; i < n; i++) {
      if (active[i] && !inRun) {
        clusters++;
        inRun = true;
      } else if (!active[i]) {
        inRun = false;
      }
    }

    return _PathReading(
      coverage: coverage,
      centroid: centroid,
      clusterCount: clusters,
    );
  }
}
