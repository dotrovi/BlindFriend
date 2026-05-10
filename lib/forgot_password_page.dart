import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  bool _isLoading = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  int _speakGeneration = 0;
  bool _cancelledBySpeech = false;
  bool _gotResult = false;
  bool _reaskScheduled = false;

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
    await _tts.setSpeechRate(0.6);
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
          _scheduleReask();
        }
      },
      onError: (error) {
        debugPrint('STT error: ${error.errorMsg}');
        _gotResult = false;
        if (mounted) setState(() => _isListening = false);
        _scheduleReask();
      },
    );

    if (!mounted) return;

    await _speak(
      'This is the forgot password page. '
      'Press the button in the middle of the screen to say your email address. '
      'We will send you a password reset link. '
      'Say Back to return to the login page.',
    );
  }

  Future<void> _speak(String text) async {
    final myGen = ++_speakGeneration;
    _cancelledBySpeech = true;
    _tts.setCompletionHandler(() {});
    _tts.setErrorHandler((_) {});
    if (_stt.isListening) await _stt.cancel();
    await _tts.stop();
    await Future.delayed(const Duration(milliseconds: 50));
    if (myGen != _speakGeneration) return;
    if (mounted) setState(() => _isSpeaking = true);
    final completer = Completer<void>();
    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    _tts.setErrorHandler((msg) {
      debugPrint('TTS error: $msg');
      if (!completer.isCompleted) completer.complete();
    });
    await _tts.speak(text);
    await completer.future.timeout(const Duration(seconds: 30), onTimeout: () {});
    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _pressToSpeak() async {
    if (!_sttAvailable || !_shouldListen) return;
    if (!_stt.isListening) _startListening();
  }

  void _scheduleReask() {
    if (!mounted || _cancelledBySpeech || _gotResult || !_shouldListen ||
        _reaskScheduled) { return; }
    _reaskScheduled = true;
    Future.delayed(const Duration(milliseconds: 100), () {
      _reaskScheduled = false;
      if (mounted && _shouldListen && !_cancelledBySpeech && !_gotResult) {
        _speak('I did not catch that. Please say your email address.');
      }
    });
  }

  Future<void> _startListening() async {
    if (!_sttAvailable || !mounted || !_shouldListen || _stt.isListening) return;
    _gotResult = false;
    _cancelledBySpeech = false;
    _reaskScheduled = false;
    setState(() => _isListening = true);
    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.recognizedWords.isNotEmpty) _gotResult = true;
        if (!result.finalResult) return;
        Future(() => _handleAnswer(result.recognizedWords.trim()));
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      localeId: 'en_US',
    );
  }

  Future<void> _handleAnswer(String answer) async {
    if (answer.isEmpty) {
      await _speak('I did not hear anything. Please say your email address.');
      return;
    }

    final lower = answer.toLowerCase();

    if (lower.contains('back') ||
        lower.contains('cancel') ||
        lower.contains('login') ||
        lower.contains('go back')) {
      _shouldListen = false;
      _tts.setCompletionHandler(() {});
      _tts.setErrorHandler((_) {});
      if (_stt.isListening) await _stt.cancel();
      await _tts.stop();
      if (mounted) Navigator.pop(context);
      return;
    }

    final email = _toEmailFormat(lower);
    if (!email.contains('@') || !email.contains('.')) {
      await _speak(
        'That does not sound like a valid email. '
        'Please say your email again. '
        'For example: john at gmail dot com.',
      );
      return;
    }

    setState(() {
      _emailController.text = email;
      _isLoading = true;
    });
    _shouldListen = false;

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() => _isLoading = false);
      await _speak('A password reset link has been sent to your email. Please check your inbox.');
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _shouldListen = true;
      if (e.code == 'user-not-found') {
        await _speak(
          'No account found with that email address. '
          'Please say your email again.',
        );
      } else {
        await _speak(
          'Something went wrong. Please say your email again.',
        );
      }
    }
  }

  String _toEmailFormat(String spoken) {
    return spoken
        .toLowerCase()
        .replaceAll(' at ', '@')
        .replaceAll(' dot ', '.')
        .replaceAll(' underscore ', '_')
        .replaceAll(' dash ', '-')
        .replaceAll(' hyphen ', '-')
        .replaceAll(' ', '');
  }

  Future<void> _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset email sent! Check your inbox.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Something went wrong. Please try again.';
      if (e.code == 'user-not-found') {
        message = 'No account found with this email.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _shouldListen = false;
    _emailController.dispose();
    _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Full-screen voice button ───────────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pressToSpeak,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: screenHeight,
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
                      // Back button
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white, size: 26),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),

                      // Title
                      const Padding(
                        padding: EdgeInsets.only(top: 16, bottom: 6),
                        child: Text(
                          'BlindFriend',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Text(
                        'Forgot Password',
                        style: TextStyle(fontSize: 18, color: Colors.white70),
                      ),

                      // Centre: mic + status
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
                                        ? 'Say your email address'
                                        : 'Press to say your email address',
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

                      // Scroll hint
                      const Padding(
                        padding: EdgeInsets.only(bottom: 28),
                        child: Column(
                          children: [
                            Icon(Icons.keyboard_arrow_down,
                                color: Colors.white60, size: 28),
                            SizedBox(height: 4),
                            Text(
                              'Scroll down to type manually',
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Manual form ────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        'Reset password manually',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Enter your email and we will send you a reset link.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 32),

                    const Text('Email',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'Enter your email',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _sendResetEmail,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text('Send Reset Email'),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back to Login',
                            style:
                                TextStyle(color: Colors.blue, fontSize: 14)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
