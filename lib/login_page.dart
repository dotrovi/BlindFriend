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
import 'theme/app_palette.dart';

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
  final ScrollController _scrollController = ScrollController();

  String? _selectedUserType;
  bool _rememberMe = false;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _obscurePassword = true;

  int _speakGeneration = 0;
  bool _cancelledBySpeech = false;
  bool _gotResult = false;
  bool _reaskScheduled = false;

  static const String _loginGuide = 'This is the login page. '
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
      await _speak(
        'Microphone permission is required. Please allow it in settings.',
      );
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
      await _speak(
        'Speech recognition is not available. Please type your details instead.',
      );
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
    if (_isSpeaking) await _tts.stop();
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
    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {},
    );
    if (mounted) setState(() => _isSpeaking = false);

    // ── AUTOMATICALLY START LISTENING AFTER SPEAKING FINISHES ──
    if (mounted && _shouldListen && _currentStep != 'done' && !_stt.isListening) {
      _startListening();
    }
  }

  Future<void> _pressToSpeak() async {
    if (!_sttAvailable || !_shouldListen || _currentStep == 'done') return;
    if (!_stt.isListening) _startListening();
  }

  void _scheduleReask() {
    if (!mounted ||
        _cancelledBySpeech ||
        _gotResult ||
        !_shouldListen ||
        _reaskScheduled) {
      return;
    }
    _reaskScheduled = true;
    Future.delayed(const Duration(milliseconds: 100), () {
      _reaskScheduled = false;
      if (mounted && _shouldListen && !_cancelledBySpeech && !_gotResult) {
        _speak('I did not catch that. ${_getCurrentQuestion()}');
      }
    });
  }

  // ===================== ADJUSTED TIMEOUT TIMING =====================
  Future<void> _startListening() async {
    if (!_sttAvailable || !mounted || !_shouldListen || _stt.isListening) {
      return;
    }
    _gotResult = false;
    _cancelledBySpeech = false;
    _reaskScheduled = false;
    setState(() => _isListening = true);

    // Adjusted to 5 seconds of continuous silence before closing,
    // giving ample time to formulate and pronounce long email addresses comfortably.
    const pauseFor = Duration(seconds: 5);

    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.recognizedWords.isNotEmpty) _gotResult = true;
        if (!result.finalResult) return;
        _handleAnswer(result.recognizedWords.trim());
      },
      listenFor: const Duration(seconds: 45),
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
    final selectedType = _selectedUserType ?? 'blind';

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
        String userName = user.displayName ?? 'User';

        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            userType = userDoc.data()?['userType'] ?? 'blind';
            userName = userDoc.data()?['name'] ?? user.displayName ?? 'User';
            print('User found in users collection. Type: $userType, Name: $userName');

            if (selectedType == 'volunteer' && userType != 'volunteer') {
              await _speak(
                'This account is not registered as a volunteer. '
                'Please select Blind User or register as a volunteer.',
              );
              _currentStep = 'email';
              _shouldListen = true;
              return;
            }

            if (selectedType == 'blind' && userType == 'volunteer') {
              await _speak(
                'This account is registered as a volunteer. '
                'Please select Volunteer to login.',
              );
              _currentStep = 'email';
              _shouldListen = true;
              return;
            }
          } else {
            await _speak(
              'Your account is not fully registered. Please register first.',
            );
            _currentStep = 'email';
            _shouldListen = true;
            return;
          }
        } catch (e) {
          await _speak('Error verifying account. Please try again.');
          _currentStep = 'email';
          _shouldListen = true;
          return;
        }

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

        _tts.setCompletionHandler(() {});
        _tts.setErrorHandler((_) {});
        if (_stt.isListening) await _stt.cancel();
        await _tts.stop();

        if (!mounted) return;

        if (userType == 'volunteer') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => VolunteerHomePage(userName: userName),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BlindHomePage(userName: userName),
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

  void _scrollToForm() {
    _scrollController.animateTo(
      MediaQuery.of(context).size.height,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _scrollToVoice() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _tts.stop();
    _shouldListen = false;
    _emailController.dispose();
    _passwordController.dispose();
    _scrollController.dispose();
    _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: kNavyDeep,
      body: SingleChildScrollView(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        child: Column(
          children: [
            _buildVoiceSection(screenHeight),
            _buildFormSection(screenHeight),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceSection(double screenHeight) {
    return Container(
      height: screenHeight,
      width: double.infinity,
      decoration: const BoxDecoration(gradient: kSkyGradient),
      child: Stack(
        children: [
          ..._decorativeBokeh(),
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 28),
                    _buildAppIcon(),
                    const SizedBox(height: 18),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                        children: [
                          TextSpan(text: 'Blind', style: TextStyle(color: Colors.white)),
                          TextSpan(text: 'Friend', style: TextStyle(color: kPinkBright)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'The World Should Not Be Dark Anymore',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    _buildDivider(icon: Icons.favorite, width: 90),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _pressToSpeak,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _buildWaveBars(reversed: true),
                                const SizedBox(width: 18),
                                _buildMicButton(),
                                const SizedBox(width: 18),
                                _buildWaveBars(reversed: false),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Text(
                              _isSpeaking
                                  ? 'Speaking...'
                                  : _isListening
                                      ? 'Listening...'
                                      : 'Tap to Speak',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
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
                              style: const TextStyle(color: Colors.white60, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildPillButton(
                      label: 'Continue Manually',
                      icon: Icons.arrow_forward,
                      filled: false,
                      onTap: _scrollToForm,
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _scrollToForm,
                      child: const Icon(Icons.keyboard_arrow_up, color: Colors.white54, size: 26),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: SizedBox(
                height: 90,
                width: double.infinity,
                child: CustomPaint(painter: _SkylinePainter()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormSection(double screenHeight) {
    return Container(
      constraints: BoxConstraints(minHeight: screenHeight),
      width: double.infinity,
      decoration: const BoxDecoration(gradient: kSkyGradient),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          ..._decorativeBokeh(),
          SizedBox(
            width: double.infinity,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Welcome Back!',
                        style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Sign in to continue your journey',
                        style: TextStyle(color: Colors.white60, fontSize: 14),
                      ),
                      const SizedBox(height: 14),
                      _buildDivider(icon: Icons.favorite, width: 90),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: kCardFill.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'I am a:',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildRoleButton(
                                    label: 'Blind User',
                                    icon: Icons.visibility,
                                    selected: (_selectedUserType ?? 'blind') == 'blind',
                                    onTap: () => setState(() => _selectedUserType = 'blind'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildRoleButton(
                                    label: 'Volunteer',
                                    icon: Icons.people_alt,
                                    selected: _selectedUserType == 'volunteer',
                                    onTap: () => setState(() => _selectedUserType = 'volunteer'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Email',
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
                            _buildDarkField(
                              controller: _emailController,
                              hint: 'Enter your email',
                              icon: Icons.mail_outline,
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) => (value == null || value.isEmpty) ? 'Please enter your email' : null,
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Password',
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
                            _buildDarkField(
                              controller: _passwordController,
                              hint: 'Enter your password',
                              icon: Icons.lock_outline,
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 20),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              validator: (value) => (value == null || value.isEmpty) ? 'Please enter your password' : null,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Transform.scale(
                                  scale: 0.9,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    activeColor: kPinkBright,
                                    checkColor: Colors.white,
                                    side: const BorderSide(color: Colors.white54),
                                    onChanged: (value) => setState(() => _rememberMe = value ?? false),
                                  ),
                                ),
                                const Text('Remember me', style: TextStyle(color: Colors.white70, fontSize: 13)),
                                const Spacer(),
                                TextButton(
                                  onPressed: () {
                                    _shouldListen = false;
                                    _speak('Opening forgot password page.');
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
                                    ).then((_) => _resumeOnReturn(_loginGuide));
                                  },
                                  child: const Text('Forgot Password?', style: TextStyle(color: kPinkBright, fontSize: 13)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildPillButton(
                              label: 'Login',
                              icon: Icons.lock,
                              filled: true,
                              fullWidth: true,
                              onTap: () {
                                _shouldListen = false;
                                if (_selectedUserType == null) {
                                  setState(() => _selectedUserType = 'blind');
                                }
                                _handleLogin();
                              },
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: Text('OR', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                ),
                                Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
                              ],
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  _scrollToVoice();
                                  Future.delayed(const Duration(milliseconds: 550), _pressToSpeak);
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  backgroundColor: kNavyMid.withOpacity(0.6),
                                  side: BorderSide(color: Colors.white.withOpacity(0.25)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                icon: const Icon(Icons.mic, color: Colors.white, size: 18),
                                label: const Text('Login with Voice', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: () {
                                  _shouldListen = false;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const RegisterPage()),
                                  ).then((_) => _resumeOnReturn(_loginGuide));
                                },
                                child: RichText(
                                  text: const TextSpan(
                                    style: TextStyle(color: Colors.white60, fontSize: 13),
                                    children: [
                                      TextSpan(text: "Don't have an account? "),
                                      TextSpan(text: 'Register', style: TextStyle(color: kPinkBright, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/admin');
                      },
                      child: const Text(
                        'Admin Portal', 
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 70),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: SizedBox(
                height: 90,
                width: double.infinity,
                child: CustomPaint(painter: _SkylinePainter()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppIcon() {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        gradient: kAccentGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: kPinkBright.withOpacity(0.45), blurRadius: 24, spreadRadius: 2),
        ],
      ),
      child: const Stack(
        children: [
          Center(child: Icon(Icons.visibility_off_rounded, color: Colors.white, size: 38)),
          Positioned(right: 10, top: 10, child: Icon(Icons.graphic_eq, color: Colors.white70, size: 14)),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    final active = _isListening || _isSpeaking;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: kAccentGradient,
        boxShadow: [
          BoxShadow(
            color: kPinkBright.withOpacity(active ? 0.65 : 0.4),
            blurRadius: active ? 36 : 24,
            spreadRadius: active ? 6 : 2,
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Icon(
          _isListening ? Icons.mic : Icons.mic_none,
          key: ValueKey(_isListening),
          color: Colors.white,
          size: 52,
        ),
      ),
    );
  }

  Widget _buildWaveBars({required bool reversed}) {
    final heights = [10.0, 18.0, 28.0, 18.0, 10.0];
    final active = _isListening;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: heights
          .map(
            (h) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 4,
              height: active ? h : h * 0.5,
              decoration: BoxDecoration(
                color: (reversed ? kBlueAccent : kPinkBright).withOpacity(active ? 0.9 : 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildDivider({required IconData icon, required double width}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: width,
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.transparent, kPinkBright.withOpacity(0.6)]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(icon, color: kPinkBright, size: 14),
        ),
        Container(
          width: width,
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [kPinkBright.withOpacity(0.6), Colors.transparent]),
          ),
        ),
      ],
    );
  }

  Widget _buildPillButton({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
    bool fullWidth = false,
  }) {
    final child = Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: BoxDecoration(
        gradient: filled ? kAccentGradient : null,
        color: filled ? null : Colors.transparent,
        border: filled ? null : Border.all(color: Colors.white.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(30),
        boxShadow: filled ? [BoxShadow(color: kPinkBright.withOpacity(0.35), blurRadius: 16, spreadRadius: 1)] : null,
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
        ],
      ),
    );

    return GestureDetector(onTap: onTap, child: child);
  }

  Widget _buildRoleButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: selected ? kAccentGradient : null,
          color: selected ? null : Colors.white.withOpacity(0.04),
          border: selected ? null : Border.all(color: Colors.white.withOpacity(0.25)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.white70, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDarkField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white54, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kPinkBright),
        ),
        errorStyle: const TextStyle(color: Colors.orangeAccent),
      ),
    );
  }

  List<Widget> _decorativeBokeh() {
    final specs = <List<double>>[
      [40, 0.08, 30, 30],
      [16, 0.5, 70, 260],
      [10, 0.6, 130, 60],
      [22, 0.12, 220, 320],
      [14, 0.45, 300, 40],
      [8, 0.5, 380, 280],
    ];
    return specs
        .map(
          (s) => Positioned(
            top: s[2],
            left: s[3],
            child: Container(
              width: s[0],
              height: s[0],
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(s[1]),
              ),
            ),
          ),
        )
        .toList();
  }
}

class _SkylinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [kBlueAccent.withOpacity(0.5), kPinkBright.withOpacity(0.6)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path()..moveTo(0, size.height);
    const heights = [0.35, 0.6, 0.25, 0.5, 0.3, 0.55, 0.4];
    final segW = size.width / heights.length;
    for (var i = 0; i < heights.length; i++) {
      final x = i * segW;
      final h = size.height * (1 - heights[i]);
      path.lineTo(x, h);
      path.lineTo(x + segW, h);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}