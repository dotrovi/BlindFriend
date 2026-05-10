import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'volunteer_details_page.dart';
import 'services/firebase_service.dart';

final FirebaseService _firebaseService = FirebaseService();

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  String? _selectedUserType;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  bool _isListening = false;
  bool _isSpeaking = false;

  int _speakGeneration = 0;
  bool _cancelledBySpeech = false;
  bool _gotResult = false;
  bool _reaskScheduled = false;

  String _currentStep = 'name'; // name → email → password → type → done

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
      'Please press the button in the middle of the screen to say your name, '
      'or say back to go back to the login page.',
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
        _speak('I did not catch that. ${_getCurrentQuestion()}');
      }
    });
  }

  Future<void> _startListening() async {
    if (!_sttAvailable || !mounted || !_shouldListen || _stt.isListening) return;
    _gotResult = false;
    _cancelledBySpeech = false;
    _reaskScheduled = false;
    setState(() => _isListening = true);
    final pauseFor = _currentStep == 'email'
        ? const Duration(seconds: 5)
        : const Duration(seconds: 3);
    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.recognizedWords.isNotEmpty) _gotResult = true;
        if (!result.finalResult) return;
        Future(() => _handleAnswer(result.recognizedWords.trim()));
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: pauseFor,
      localeId: 'en_US',
    );
  }

  String _getCurrentQuestion() {
    switch (_currentStep) {
      case 'name':
        return 'Please say your name.';
      case 'email':
        return 'Please say your email address.';
      case 'password':
        return 'Please say your password.';
      case 'type':
        return 'Please say blind user or volunteer.';
      default:
        return '';
    }
  }

  String _stepHint() {
    switch (_currentStep) {
      case 'name':
        return 'Say your name';
      case 'email':
        return 'Say your email address';
      case 'password':
        return 'Say your password';
      case 'type':
        return 'Say: blind user or volunteer';
      default:
        return '';
    }
  }

  void _handleAnswer(String answer) {
    if (answer.isEmpty) {
      _speak('I did not hear anything. ${_getCurrentQuestion()}');
      return;
    }

    final lower = answer.toLowerCase();

    if (lower.contains('go back') || lower.contains('cancel') ||
        lower.contains('back')) {
      _shouldListen = false;
      _speak('Going back to the login page.');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.pop(context);
      });
      return;
    }

    switch (_currentStep) {
      case 'name':
        final name = _toTitleCase(answer.trim());
        setState(() => _nameController.text = name);
        _currentStep = 'email';
        _speak('Nice to meet you, $name. '
            'Press the button and say your email address.');
        break;

      case 'email':
        final email = _toEmailFormat(lower);
        if (!email.contains('@') || !email.contains('.')) {
          _speak(
            'That does not sound like a valid email. '
            'Press the button and say your email again. '
            'For example: john at gmail dot com.',
          );
        } else {
          setState(() => _emailController.text = email);
          _currentStep = 'password';
          _speak('Got it. Press the button and say your password. '
              'It must be at least 6 characters.');
        }
        break;

      case 'password':
        final password = answer.trim().replaceAll(' ', '');
        if (password.length < 6) {
          _speak(
            'Password is too short. '
            'It must be at least 6 characters. '
            'Press the button and say your password again.',
          );
        } else {
          setState(() {
            _passwordController.text = password;
            _confirmPasswordController.text = password;
          });
          _currentStep = 'type';
          _speak('Press the button and say: are you a blind user or a volunteer?');
        }
        break;

      case 'type':
        if (lower.contains('blind')) {
          setState(() => _selectedUserType = 'blind');
          _shouldListen = false;
          _speak(
            'Blind user selected. '
            'Name: ${_nameController.text}. '
            'Email: ${_emailController.text}. '
            'Creating your account now. Please wait.',
          );
          _currentStep = 'done';
          _handleRegister();
        } else if (lower.contains('volunteer')) {
          setState(() => _selectedUserType = 'volunteer');
          _shouldListen = false;
          _speak(
            'Volunteer selected. '
            'Name: ${_nameController.text}. '
            'Email: ${_emailController.text}. '
            'Creating your account now. Please wait.',
          );
          _currentStep = 'done';
          _handleRegister();
        } else {
          _speak('Press the button and say: blind user or volunteer.');
        }
        break;
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

  String _toTitleCase(String text) {
    return text.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }

  void _handleRegister() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      User? user = await _firebaseService.registerUser(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        name: _nameController.text.trim(),
        userType: _selectedUserType!,
      );

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (user != null) {
        if (_selectedUserType == 'volunteer') {
          await _speak(
            'Account created successfully. '
            'Welcome ${_nameController.text}. '
            'Please complete your volunteer profile.',
          );
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => VolunteerDetailsPage(
                name: _nameController.text.trim(),
                email: _emailController.text.trim(),
                password: _passwordController.text.trim(),
                uid: user.uid,
              ),
            ),
          );
        } else {
          await _speak(
            'Account created successfully. '
            'Welcome ${_nameController.text}. '
            'A verification email has been sent to ${_emailController.text}. '
            'Please verify your email, then log in.',
          );
          if (mounted) Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      final error = e.toString();
      if (error.contains('email-already-in-use')) {
        setState(() {
          _emailController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
        _currentStep = 'email';
        _shouldListen = true;
        _speak(
          'This email is already registered. '
          'Press the button and say a different email address.',
        );
      } else if (error.contains('invalid-email')) {
        setState(() {
          _emailController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
        _currentStep = 'email';
        _shouldListen = true;
        _speak(
          'The email address was not valid. '
          'Press the button and say your email address again. '
          'For example: john at gmail dot com.',
        );
      } else if (error.contains('weak-password')) {
        setState(() {
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
        _currentStep = 'password';
        _shouldListen = true;
        _speak(
          'Your password is too weak. '
          'Press the button and say a stronger password with at least 6 characters.',
        );
      } else if (error.contains('network-request-failed')) {
        _currentStep = 'name';
        _shouldListen = true;
        _speak(
          'No internet connection. '
          'Please check your connection and try again. '
          'Press the button and say your name.',
        );
      } else {
        setState(() {
          _nameController.clear();
          _emailController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
          _selectedUserType = null;
        });
        _currentStep = 'name';
        _shouldListen = true;
        _speak(
          'Registration failed. Let us try again. '
          'Press the button and say your name.',
        );
      }
    }
  }

  @override
  void dispose() {
    _shouldListen = false;
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
                        'Create your account',
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
                                        ? _stepHint()
                                        : 'Press to ${_stepHint().toLowerCase()}',
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        'Register manually',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Fill in your details to create an account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // User type
                    const Text('I am a:',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedUserType = 'blind'),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _selectedUserType == 'blind'
                                      ? Colors.blue
                                      : Colors.grey.shade300,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                color: _selectedUserType == 'blind'
                                    ? Colors.blue.shade50
                                    : Colors.white,
                              ),
                              child: Center(
                                child: Text(
                                  'Blind User',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: _selectedUserType == 'blind'
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: _selectedUserType == 'blind'
                                        ? Colors.blue
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedUserType = 'volunteer'),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _selectedUserType == 'volunteer'
                                      ? Colors.blue
                                      : Colors.grey.shade300,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                color: _selectedUserType == 'volunteer'
                                    ? Colors.blue.shade50
                                    : Colors.white,
                              ),
                              child: Center(
                                child: Text(
                                  'Volunteer',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight:
                                        _selectedUserType == 'volunteer'
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                    color: _selectedUserType == 'volunteer'
                                        ? Colors.blue
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Name
                    const Text('Name',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'Enter your name',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Please enter your name'
                          : null,
                    ),
                    const SizedBox(height: 20),

                    // Email
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
                    const SizedBox(height: 20),

                    // Password
                    const Text('Password',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Confirm Password
                    const Text('Confirm Password',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: 'Confirm your password',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your password';
                        }
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (!_formKey.currentState!.validate()) return;
                          _shouldListen = false;
                          if (_selectedUserType == null) {
                            setState(() => _selectedUserType = 'blind');
                          }
                          _handleRegister();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: _selectedUserType == 'volunteer'
                              ? Colors.green
                              : Colors.blue,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Register'),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Center(
                      child: TextButton(
                        onPressed: () {
                          _shouldListen = false;
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'Already have an account? Login',
                          style: TextStyle(color: Colors.blue),
                        ),
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
