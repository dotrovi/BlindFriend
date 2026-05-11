import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'register_page.dart';
import 'services/firebase_service.dart';
import 'forgot_password_page.dart';
import 'blind_home_page.dart';
import 'volunteer_home_page.dart';

void main() {
  runApp(const BlindFriendApp());
}

class BlindFriendApp extends StatelessWidget {
  const BlindFriendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlindFriend',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      home: const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _firebaseService = FirebaseService();
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  String? _selectedUserType;
  bool _rememberMe = false;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  bool _isListening = false;
  bool _isSpeaking = false;

  int _speakGeneration = 0;
  bool _cancelledBySpeech = false;
  bool _gotResult = false;
  bool _reaskScheduled = false;

  static const String _loginGuide =
      'This is the login page. '
      'Please press the button in the middle of the screen to say your email and password to log in. '
      'If you do not have an account, say Register. '
      'If you forgot your password, say Forgot Password.';

  // current step: 'email' → 'password' → 'done'
  String _currentStep = 'email';

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
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

    if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
      await _speak('Microphone permission is required. Please allow it in settings.');
      return;
    }

    _sttAvailable = await _stt.initialize(
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

    if (!_sttAvailable) {
      await _speak('Speech recognition is not available. Please type your details instead.');
      return;
    }

    await _speak(_loginGuide);
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
    if (!_sttAvailable || !_shouldListen || _currentStep == 'done') return;
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
      case 'email':
        return 'What is your email address?';
      case 'password':
        return 'What is your password?';
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

    if (lower.contains('forgot password') ||
        lower.contains('forgot my password') ||
        lower.contains('reset password') ||
        lower.contains('reset my password') ||
        lower.contains('lost password') ||
        lower.contains("can't remember")) {
      _shouldListen = false;
      _tts.setCompletionHandler(() {});
      _tts.setErrorHandler((_) {});
      _stt.cancel();
      _tts.stop();
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
        ).then((_) => _resumeOnReturn(_loginGuide));
      }
      return;
    }

    if (lower.contains("register") ||
        lower.contains("sign up") ||
        lower.contains("signup") ||
        lower.contains("create") ||
        lower.contains("new account") ||
        lower.contains("no account") ||
        lower.contains("don't have") ||
        lower.contains("do not have")) {
      _shouldListen = false;
      _speak('Going to the registration page.').then((_) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RegisterPage()),
        ).then((_) => _resumeOnReturn(_loginGuide));
      });
      return;
    }

    switch (_currentStep) {
      case 'email':
        final email = _toEmailFormat(lower);
        if (!email.contains('@') || !email.contains('.')) {
          _speak(
            'That does not sound like a valid email. '
            'Please say your email again. For example: john at gmail dot com.',
          );
        } else {
          setState(() => _emailController.text = email);
          _currentStep = 'password';
          _speak('Got it. What is your password?');
        }
        break;

      case 'password':
        final password = answer.trim().replaceAll(' ', '');
        setState(() => _passwordController.text = password);
        _shouldListen = false;
        _currentStep = 'done';
        _speak('Logging in. Please wait.');
        _handleLogin();
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

  void _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _currentStep = 'email';
      _shouldListen = true;
      await _speak('Please press the button and say your email address.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      User? user = await _firebaseService.loginUser(
        email: email,
        password: password,
      );

      if (mounted) Navigator.pop(context);

      if (user != null) {
        String userType = 'blind';
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          userType = doc.data()?['userType'] ?? 'blind';
        } catch (_) {}

        if (userType == 'volunteer' && !user.emailVerified) {
          await FirebaseAuth.instance.signOut();
          _currentStep = 'email';
          _shouldListen = true;
          await _speak(
            'Your email is not verified. '
            'Please check your inbox and click the verification link first. '
            'Then press the button and say your email address again.',
          );
          return;
        }

        await _saveCredentials();
        // Stop any current TTS/STT and navigate immediately — BlindHomePage
        // speaks its own welcome message so no need to wait here.
        _tts.setCompletionHandler(() {});
        _tts.setErrorHandler((_) {});
        if (_stt.isListening) await _stt.cancel();
        await _tts.stop();

        if (!mounted) return;
        if (userType == 'volunteer') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  VolunteerHomePage(userName: user.displayName ?? 'User'),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  BlindHomePage(userName: user.displayName ?? 'User'),
            ),
          );
        }
      } else {
        _currentStep = 'email';
        _shouldListen = true;
        await _speak(
          'Login failed. The email or password is incorrect. '
          'Press the button and say your email address to try again.',
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _currentStep = 'email';
      _shouldListen = true;
      final error = e.toString();
      if (error.contains('verify your email')) {
        await _speak(
          'Your email is not verified. '
          'Please check your inbox and verify your email first. '
          'Then press the button and say your email address again.',
        );
      } else {
        await _speak(
          'Login failed. Something went wrong. '
          'Press the button and say your email address to try again.',
        );
      }
    }
  }

  Future<void> _resumeOnReturn(String message) async {
    if (!mounted) return;
    _currentStep = 'email';
    _shouldListen = true;
    _speak(message);
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('remember_me') ?? false) {
      setState(() {
        _rememberMe = true;
        _emailController.text = prefs.getString('saved_email') ?? '';
        _passwordController.text = prefs.getString('saved_password') ?? '';
      });
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool('remember_me', true);
      await prefs.setString('saved_email', _emailController.text);
      await prefs.setString('saved_password', _passwordController.text);
    } else {
      await prefs.setBool('remember_me', false);
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
    }
  }

  @override
  void dispose() {
    _shouldListen = false;
    _emailController.dispose();
    _passwordController.dispose();
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
                      // Title
                      const Padding(
                        padding: EdgeInsets.only(top: 48, bottom: 8),
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
                        'Welcome back',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white70,
                        ),
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
                                        ? (_currentStep == 'email'
                                            ? 'Say your email address'
                                            : 'Say your password')
                                        : (_currentStep == 'email'
                                            ? 'Press to say your email'
                                            : _currentStep == 'password'
                                                ? 'Press to say your password'
                                                : 'Processing...'),
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
                        'Sign in manually',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 24),

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
                                child: Text('Blind User',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: _selectedUserType == 'blind'
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: _selectedUserType == 'blind'
                                          ? Colors.blue
                                          : Colors.black87,
                                    )),
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
                                child: Text('Volunteer',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight:
                                          _selectedUserType == 'volunteer'
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                      color: _selectedUserType == 'volunteer'
                                          ? Colors.blue
                                          : Colors.black87,
                                    )),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

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
                      validator: (value) =>
                          (value == null || value.isEmpty)
                              ? 'Please enter your email'
                              : null,
                    ),
                    const SizedBox(height: 24),

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
                      validator: (value) =>
                          (value == null || value.isEmpty)
                              ? 'Please enter your password'
                              : null,
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (value) =>
                              setState(() => _rememberMe = value ?? false),
                        ),
                        const Text('Remember me'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _shouldListen = false;
                          if (_selectedUserType == null) {
                            setState(() => _selectedUserType = 'blind');
                          }
                          _handleLogin();
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
                        child: const Text('Login'),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Center(
                      child: TextButton(
                        onPressed: () {
                          _shouldListen = false;
                          _speak('Opening forgot password page.');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ForgotPasswordPage()),
                          ).then((_) => _resumeOnReturn(_loginGuide));
                        },
                        child: const Text('Forgot Password?',
                            style: TextStyle(color: Colors.blue)),
                      ),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          _shouldListen = false;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RegisterPage()),
                          ).then((_) => _resumeOnReturn(_loginGuide));
                        },
                        child: const Text("Don't have an account? Register",
                            style: TextStyle(color: Colors.blue)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
                const SizedBox(height: 20),

                // Admin portal link
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/admin'),
                    child: const Text(
                      'Admin Portal',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ),
              ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
