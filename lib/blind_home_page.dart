import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'login_page.dart';
import 'user_profile_page.dart';

class BlindHomePage extends StatefulWidget {
  final String userName;
  const BlindHomePage({super.key, required this.userName});

  @override
  State<BlindHomePage> createState() => _BlindHomePageState();
}

class _BlindHomePageState extends State<BlindHomePage> {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  bool _shouldListen = true;
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _sttAvailable = false;
  int _speakGeneration = 0;

  static const String _commandGuide =
      'Press the button in the middle of the screen to speak. '
      'You can say: '
      'Shopping to open shopping helper. '
      'Obstacle to start obstacle detection. '
      'Path to activate path detection. '
      'Volunteers to find help nearby. '
      'Emergency to call emergency services. '
      'Profile to open your profile. '
      'Or Logout to sign out. '
      'Say Repeat anytime to hear these commands again.';

  @override
  void initState() {
    super.initState();
    _initVoice();
  }

  Future<void> _initVoice() async {
    try {
      await _tts.setLanguage('en-US');
    } catch (_) {
      await _tts.setLanguage('en');
    }
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    final micStatus = await Permission.microphone.request();
    if (!mounted) return;

    _sttAvailable = micStatus.isGranted && await _stt.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'listening') {
          setState(() => _isListening = true);
        } else if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isListening = false);
      },
    );

    if (mounted) {
      await _speak(
        'Welcome to BlindFriend, ${widget.userName}. '
        '$_commandGuide',
      );
    }
  }

  Future<void> _speak(String text, {bool thenListen = false}) async {
    _isSpeaking = true;
    if (mounted) setState(() => _isListening = false);
    final myGen = ++_speakGeneration;
    _tts.setCompletionHandler(() {});
    _tts.setErrorHandler((_) {});
    if (_stt.isListening) await _stt.cancel();
    await _tts.stop();
    // 50 ms drain: flush any residual callbacks into the no-op handlers
    await Future.delayed(const Duration(milliseconds: 50));
    if (myGen != _speakGeneration) {
      _isSpeaking = false;
      if (mounted) setState(() {});
      return;
    }
    final completer = Completer<void>();
    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    _tts.setErrorHandler((msg) {
      debugPrint('TTS error: $msg');
      if (!completer.isCompleted) completer.complete();
    });
    await _tts.speak(text);
    await completer.future.timeout(const Duration(seconds: 90), onTimeout: () {});
    _isSpeaking = false;
    if (mounted) setState(() {});
    if (myGen != _speakGeneration) return;
    if (thenListen && mounted && _shouldListen) _startListening();
  }

  Future<void> _pressToSpeak() async {
    if (!_sttAvailable || _isSpeaking || _isListening) return;
    _startListening();
  }

  Future<void> _startListening() async {
    if (!_sttAvailable || !mounted || !_shouldListen || _stt.isListening) return;
    setState(() => _isListening = true);
    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.finalResult) {
          _processCommand(result.recognizedWords.toLowerCase());
        }
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );
  }

  Future<void> _processCommand(String command) async {
    if (command.contains('repeat') ||
        command.contains('forgot') ||
        command.contains('again') ||
        command.contains('command')) {
      await _speak(_commandGuide);
    } else if (command.contains('shopping')) {
      await _speak('Shopping Helper. Scan barcodes and get audio feedback.');
    } else if (command.contains('obstacle')) {
      await _speak('Obstacle Detection. Real-time voice alerts for obstacles.');
    } else if (command.contains('path')) {
      await _speak('Path Detection. Tactile path guidance recognition.');
    } else if (command.contains('volunteer') || command.contains('help')) {
      await _speak('Finding Volunteers. Searching for verified volunteers nearby.');
    } else if (command.contains('home')) {
      await _speak('You are already on the home page.');
    } else if (command.contains('emergency')) {
      await _speak('Calling Emergency Services now. Stay calm, help is on the way.');
    } else if (command.contains('profile')) {
      _shouldListen = false;
      await _speak('Opening your profile.');
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const UserProfilePage()),
      ).then((_) {
        if (mounted) {
          _shouldListen = true;
          _speak(
            'Back on the home page. '
            'Press the button in the middle of the screen to speak. '
            'Say Repeat to hear available commands.',
          );
        }
      });
    } else if (command.contains('logout') || command.contains('sign out')) {
      _shouldListen = false;
      await _speak('Logging out. Goodbye, ${widget.userName}.');
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } else if (command.isEmpty) {
      await _speak(
        'No command detected. Press the button and try again.',
      );
    } else {
      await _speak(
        'Command not recognized. '
        'Press the button and say Repeat to hear available commands.',
      );
    }
  }

  @override
  void dispose() {
    _shouldListen = false;
    _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _pressToSpeak,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isListening
                  ? [const Color(0xFF27AE60), const Color(0xFF2ECC71)]
                  : _isSpeaking
                      ? [const Color(0xFF6C3483), const Color(0xFF9B59B6)]
                      : [const Color(0xFF4A90E2), const Color(0xFF9B59B6)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ── Top bar ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'BlindFriend',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Welcome, ${widget.userName}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Semantics(
                            label: 'Open profile page',
                            button: true,
                            child: IconButton(
                              onPressed: () {
                                _shouldListen = false;
                                _speak('Opening your profile.');
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const UserProfilePage(),
                                  ),
                                ).then((_) {
                                  if (mounted) {
                                    _shouldListen = true;
                                    _speak(
                                      'Back on the home page. '
                                      'Press the button in the middle of the screen to speak.',
                                    );
                                  }
                                });
                              },
                              icon: const Icon(Icons.person,
                                  color: Colors.white, size: 26),
                            ),
                          ),
                          Semantics(
                            label: 'Logout',
                            button: true,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                _shouldListen = false;
                                await _speak(
                                  'Logging out. Goodbye, ${widget.userName}.',
                                );
                                await FirebaseAuth.instance.signOut();
                                if (context.mounted) {
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const LoginPage(),
                                    ),
                                    (route) => false,
                                  );
                                }
                              },
                              icon: const Icon(Icons.logout,
                                  size: 16, color: Colors.white),
                              label: const Text('Logout',
                                  style: TextStyle(color: Colors.white)),
                              style: OutlinedButton.styleFrom(
                                side:
                                    const BorderSide(color: Colors.white54),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Centre: mic icon + status ─────────────────────────
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            key: ValueKey(_isListening),
                            color: Colors.white,
                            size: 100,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _isSpeaking
                              ? 'Speaking...'
                              : _isListening
                                  ? 'Listening...'
                                  : 'Tap to Speak',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isSpeaking
                              ? 'Please wait...'
                              : _isListening
                                  ? 'Say your command now'
                                  : 'Press anywhere on the screen',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 17,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Bottom hint ──────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Text(
                    'Say "Repeat" to hear available commands',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
