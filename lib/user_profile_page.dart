import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'accessibility_settings_page.dart';
import 'theme/app_palette.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  String name = '';
  String email = '';
  String phone = '';
  bool isLoading = true;

  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _sttInitialized = false;
  bool _editingPhone = false;

  Completer<void>? _speechCompleter;

  // ── Convert spoken number words to digits ────────────────────────
  String _wordsToDigits(String input) {
    final mapping = {
      'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
      'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
      'oh': '0', 'plus': '+',
    };
    
    List<String> words = input.toLowerCase().split(RegExp(r'\s+'));
    for (int i = 0; i < words.length; i++) {
      if (mapping.containsKey(words[i])) {
        words[i] = mapping[words[i]]!;
      }
    }
    return words.join('');
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
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
    if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
      await _speak('Microphone permission is required. Please allow it in settings.');
      return;
    }

    _sttInitialized = await _stt.initialize(
      onStatus: (status) {
        if (!mounted) return;
        setState(() => _isListening = status == 'listening');
      },
      onError: (error) {
        debugPrint('STT error: ${error.errorMsg}');
        if (mounted) setState(() => _isListening = false);
      },
    );

    if (!mounted) return;
    if (!_sttInitialized) {
      await _speak('Speech recognition is not available.');
      return;
    }

    // ── CRITICAL CHANGE FOR BLIND ACCESSIBILITY ──
    // Once everything is loaded and initialized, speak commands and open the mic automatically
    _speakCommands().then((_) => _startListening());
  }

  Future<void> _speak(String text) async {
    if (_stt.isListening) await _stt.cancel();
    await _tts.stop();

    setState(() => _isSpeaking = true);
    _speechCompleter = Completer<void>();

    _tts.setCompletionHandler(() {
      if (_speechCompleter != null && !_speechCompleter!.isCompleted) {
        _speechCompleter!.complete();
      }
    });
    
    await _tts.speak(text);

    try {
      await _speechCompleter!.future.timeout(const Duration(seconds: 30));
    } catch (_) {}

    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _startListening({String? prompt}) async {
    if (!_sttInitialized || _isSpeaking) return;
    if (_stt.isListening) await _stt.cancel();
    
    if (prompt != null) {
      await _speak(prompt);
    }

    if (!mounted) return;
    setState(() => _isListening = true);

    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.recognizedWords.isNotEmpty) {
          final command = result.recognizedWords.toLowerCase().trim();
          if (result.finalResult) {
            _handleVoiceCommand(command);
          }
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );
  }

  void _handleVoiceCommand(String command) {
    if (_editingPhone) {
      final normalized = _wordsToDigits(command);
      final digits = normalized.replaceAll(RegExp(r'[^0-9+]'), '');

      if (digits.length >= 7) {
        _savePhoneNumber(digits);
        setState(() => _editingPhone = false);
        _speak('Phone number updated to $digits.').then((_) => _startListening());
      } else {
        _speak('That does not sound like a valid phone number.')
            .then((_) => _startListening(prompt: 'Please say your phone number digit by digit again.'));
      }
      return;
    }

    if (command.contains('edit phone') || command.contains('change phone')) {
      setState(() => _editingPhone = true);
      _startListening(prompt: 'Please say your new phone number digit by digit.');
      return;
    }

    if (command.contains('accessibility settings') || command.contains('settings')) {
      _stt.cancel();
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AccessibilitySettingsPage()));
      return;
    }

    if (command.contains('back') || command.contains('go back') || command.contains('return')) {
      _stt.cancel();
      Navigator.pop(context);
      return;
    }

    if (command.contains('help') || command.contains('repeat')) {
      _speakCommands().then((_) => _startListening());
      return;
    }

    _speak('I did not understand. You can say edit phone, accessibility settings, back, or help.')
        .then((_) => _startListening());
  }

  Future<void> _speakCommands() async {
    final phoneStr = phone.isNotEmpty ? phone : 'not set';
    final message =
        'Profile Page. Your name is $name. Your email is $email. Your phone number is $phoneStr. '
        'Available voice commands are: edit phone, accessibility settings, back, or help.';
    await _speak(message);
  }

  Future<void> _savePhoneNumber(String newPhone) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'phoneNumber': newPhone});
      setState(() => phone = newPhone);
    } catch (e) {
      _speak('Failed to save phone number.');
    }
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!mounted) return;
        setState(() {
          name = doc['name'] ?? '';
          email = doc['email'] ?? '';
          phone = doc['phoneNumber'] ?? '';
          isLoading = false;
        });

        // ── POST FRAME CALLBACK ──
        // This ensures the screen is fully painted visually before checking permissions or playing TTS audio
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _initVoice();
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavyDeep,
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: kBlueAccent))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: kAccentGradient,
                        boxShadow: [
                          BoxShadow(
                            color: kBlueAccent.withOpacity(0.4),
                            blurRadius: 18, spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'U',
                          style: const TextStyle(
                              fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: kBlueAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kBlueAccent.withOpacity(0.4)),
                      ),
                      child: const Text('Blind User',
                          style: TextStyle(color: kBlueAccent, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 40),

                    // Mic button
                    GestureDetector(
                      onTap: () {
                        if (_isListening) {
                          _stt.stop();
                          setState(() => _isListening = false);
                        } else {
                          _tts.stop();
                          _startListening(prompt: 'Listening for command.');
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 120, height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: kAccentGradient,
                          boxShadow: [
                            BoxShadow(
                              color: kBlueAccent.withOpacity(_isListening ? 0.7 : 0.4),
                              blurRadius: _isListening ? 36 : 24,
                              spreadRadius: _isListening ? 6 : 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            color: Colors.white, size: 52,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _isSpeaking
                          ? 'Speaking...'
                          : _isListening
                              ? 'Listening...'
                              : 'Tap to Speak',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSpeaking
                          ? 'Please wait...'
                          : _isListening
                              ? 'Say a command'
                              : 'Tap the microphone to start',
                      style: const TextStyle(color: Colors.white60, fontSize: 14),
                    ),
                    const SizedBox(height: 40),

                    // Info card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kCardFill.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Account Information',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 16),
                          _InfoRow(icon: Icons.person, label: 'Name', value: name),
                          Divider(color: Colors.white.withOpacity(0.1)),
                          _InfoRow(icon: Icons.email, label: 'Email', value: email),
                          Divider(color: Colors.white.withOpacity(0.1)),
                          InkWell(
                            onTap: () {
                              setState(() => _editingPhone = true);
                              _startListening(prompt: 'Please say your new phone number digit by digit.');
                            },
                            child: _InfoRow(
                              icon: Icons.phone, 
                              label: 'Phone (Tap to change via voice)', 
                              value: phone.isNotEmpty ? phone : 'Not set'
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kBlueAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white), softWrap: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}