import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'barcode_scanner_page.dart';
import 'services/platform_support.dart';
import 'theme/app_palette.dart';

class ShoppingHelperPage extends StatefulWidget {
  final VoidCallback? onBackToHome;
  final bool isActive;
  final bool autoStartScan;
  final VoidCallback? onAutoScanHandled;

  const ShoppingHelperPage({
    super.key,
    this.onBackToHome,
    this.isActive = true,
    this.autoStartScan = false,
    this.onAutoScanHandled,
  });

  @override
  State<ShoppingHelperPage> createState() => _ShoppingHelperPageState();
}

class _ShoppingHelperPageState extends State<ShoppingHelperPage> {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  bool _sttAvailable = false;
  bool _isListening = false;

  static const String _voiceInstruction =
      'Tap the button and say start scan to start scanning, '
      'or say back to home page to return.';

  @override
  void initState() {
    super.initState();
    _initTts();
    _initVoice();
    if (widget.autoStartScan) {
      widget.onAutoScanHandled?.call();
      Future.microtask(_openScanner);
    }
  }

  @override
  void didUpdateWidget(covariant ShoppingHelperPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This page lives inside an IndexedStack, so switching tabs doesn't
    // dispose it — without this, voice activity keeps running and bleeds
    // into whichever tab the user switches to.
    if (oldWidget.isActive && !widget.isActive) {
      _stt.stop();
      _tts.stop();
    }
    if (!oldWidget.autoStartScan && widget.autoStartScan) {
      widget.onAutoScanHandled?.call();
      Future.microtask(_openScanner);
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
    } catch (_) {
      await _tts.setLanguage('en');
    }
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
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

  void _speak(String message) {
    _tts.speak(message);
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
    } else if (command.contains('start scan') ||
        command.contains('scan') ||
        command.contains('start')) {
      _openScanner();
    } else {
      _speak('I did not catch that. $_voiceInstruction');
    }
  }

  void _openScanner() {
    if (!barcodeScanningSupported) {
      _speak(
        'Barcode scanning needs a camera and is not available on this device.',
      );
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: kCardFill,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Camera not available',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Barcode scanning needs a camera and only works on Android, '
            'iOS, macOS, or in a web browser. It is not available on '
            'Windows desktop.',
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
      return;
    }
    _speak('Opening barcode scanner.');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerPage()),
    );
  }

  @override
  void dispose() {
    _stt.stop();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavyDeep,
      appBar: AppBar(
        backgroundColor: kNavyMid,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Shopping Helper',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (!barcodeScanningSupported)
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
                        'Barcode scanning needs a camera and isn\'t available '
                        'on Windows desktop. Try this on Android, iOS, or web.',
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
                            'Tap the button and say "start scan" to start '
                            'scanning.',
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

            // Scan Product Barcode Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: kCardFill.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: kBlueAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.qr_code_scanner,
                        size: 60, color: kBlueAccent),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Scan Product Barcode',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Point your camera at the barcode and tap the scan button',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.white60),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _openScanner,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan Barcode'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBlueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // How to Use Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kCardFill.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.help_outline, color: kBlueAccent),
                      SizedBox(width: 8),
                      Text(
                        'How to Use',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildStep('1', 'Tap the "Scan Barcode" button', kBlueAccent),
                  _buildStep('2', 'Point your camera at the product barcode',
                      kBlueAccent),
                  _buildStep(
                      '3',
                      'Hold steady until you hear product information',
                      kBlueAccent),
                  _buildStep('4', 'Tap the speaker icon to hear details again',
                      kBlueAccent),
                  _buildStep(
                      '5',
                      'Check recent scans to review previous products',
                      kBlueAccent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
