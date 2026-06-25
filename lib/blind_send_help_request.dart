import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'theme/app_palette.dart';

class BlindSendHelpRequestScreen extends StatefulWidget {
  const BlindSendHelpRequestScreen({super.key});

  @override
  State<BlindSendHelpRequestScreen> createState() =>
      _BlindSendHelpRequestScreenState();
}

class _BlindSendHelpRequestScreenState
    extends State<BlindSendHelpRequestScreen> {
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  String _selectedRequestType = 'shopping';
  String _selectedLanguage = 'english';
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  // Voice command state
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  int _speakGeneration = 0;
  bool _isProcessingVoice = false;
  // Guided voice flow: type -> language -> location -> description -> confirm
  String _currentVoiceStep = 'type';

  final Map<String, IconData> _requestTypes = {
    'shopping': Icons.shopping_cart,
    'navigation': Icons.navigation,
    'reading': Icons.menu_book,
    'tech support': Icons.computer,
    'emergency assistance': Icons.emergency,
    'medical support': Icons.local_hospital,
    'transportation': Icons.directions_car,
  };

  final Map<String, String> _languages = {
    'english': 'English 🇺🇸',
    'spanish': 'Spanish 🇪🇸',
    'mandarin': 'Mandarin 🇨🇳',
    'french': 'French 🇫🇷',
    'german': 'German 🇩🇪',
    'korean': 'Korean 🇰🇷',
  };

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

    _sttAvailable = micStatus.isGranted &&
        await _stt.initialize(
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

    if (mounted) {
      await _speak(
        'This is the request help page. Tap the voice button and I will guide you '
        'through choosing the type of help you need, your preferred language, and your location. '
        'Say back to home page at any time to return home.',
      );
    }
  }

  Future<void> _askCurrentStep() async {
    switch (_currentVoiceStep) {
      case 'type':
        await _speak(
          'What type of help do you need? You can say shopping, navigation, '
          'reading, tech support, emergency assistance, medical support, or transportation.',
        );
        break;
      case 'language':
        await _speak(
          'What language do you prefer? You can say English, Spanish, '
          'Mandarin, French, German, or Korean.',
        );
        break;
      case 'location':
        await _speak(
          'What is your location? For example, Giant Supermarket, KLCC.',
        );
        break;
      case 'description':
        await _speak('Please describe what you need help with.');
        break;
      case 'confirm':
        await _speak(
          'Request type $_selectedRequestType. Language ${_languages[_selectedLanguage]}. '
          'Location ${_locationController.text}. Description ${_descriptionController.text}. '
          'Say submit to send your request, or say cancel to start over.',
        );
        break;
    }
    await _startListening();
  }

  Future<void> _speak(String text) async {
    final myGen = ++_speakGeneration;
    if (_stt.isListening) await _stt.cancel();
    await _tts.stop();
    await Future.delayed(const Duration(milliseconds: 50));
    if (myGen != _speakGeneration) return;

    setState(() => _isSpeaking = true);
    final completer = Completer<void>();

    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    _tts.setErrorHandler((msg) {
      if (!completer.isCompleted) completer.complete();
    });

    await _tts.speak(text);
    await completer.future
        .timeout(const Duration(seconds: 90), onTimeout: () {});

    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _startListening() async {
    if (!_sttAvailable || !mounted || !_shouldListen || _stt.isListening)
      return;

    setState(() => _isListening = true);
    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.finalResult) {
          _processVoiceCommand(result.recognizedWords.toLowerCase());
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 10),
      localeId: 'en_US',
    );
  }

  Future<void> _processVoiceCommand(String command) async {
    if (_isProcessingVoice) return;
    _isProcessingVoice = true;

    if (command.contains('back') && command.contains('home')) {
      await _speak('Returning to home page.');
      _isProcessingVoice = false;
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    if (command.contains('cancel')) {
      await _speak('Cancelling request. Going back.');
      _isProcessingVoice = false;
      if (mounted) Navigator.pop(context);
      return;
    }

    if (command.contains('help') ||
        command.contains('repeat') ||
        command.contains('commands')) {
      _isProcessingVoice = false;
      await _askCurrentStep();
      return;
    }

    if (command.contains('submit') || command.contains('send')) {
      await _speak('Submitting your help request.');
      _isProcessingVoice = false;
      await _submitHelpRequest();
      return;
    }

    switch (_currentVoiceStep) {
      case 'type':
        for (var type in _requestTypes.keys) {
          if (command.contains(type)) {
            setState(() => _selectedRequestType = type);
            await _speak('Selected $type.');
            _currentVoiceStep = 'language';
            _isProcessingVoice = false;
            await _askCurrentStep();
            return;
          }
        }
        await _speak(
          'I did not catch that. What type of help do you need? Say shopping, '
          'navigation, reading, tech support, emergency assistance, medical support, or transportation.',
        );
        _isProcessingVoice = false;
        await _startListening();
        return;

      case 'language':
        for (var lang in _languages.keys) {
          if (command.contains(lang)) {
            setState(() => _selectedLanguage = lang);
            await _speak('Language set to ${_languages[lang]}.');
            _currentVoiceStep = 'location';
            _isProcessingVoice = false;
            await _askCurrentStep();
            return;
          }
        }
        await _speak(
          'I did not catch that. Please say your preferred language: '
          'English, Spanish, Mandarin, French, German, or Korean.',
        );
        _isProcessingVoice = false;
        await _startListening();
        return;

      case 'location':
        if (command.trim().length > 2) {
          _locationController.text = command;
          await _speak('Location set to $command.');
          _currentVoiceStep = 'description';
          _isProcessingVoice = false;
          await _askCurrentStep();
          return;
        }
        await _speak('Please say your location.');
        _isProcessingVoice = false;
        await _startListening();
        return;

      case 'description':
        if (command.trim().length > 2) {
          _descriptionController.text = command;
          await _speak('Got it.');
          _currentVoiceStep = 'confirm';
          _isProcessingVoice = false;
          await _askCurrentStep();
          return;
        }
        await _speak('Please describe what you need help with.');
        _isProcessingVoice = false;
        await _startListening();
        return;

      case 'confirm':
        await _speak(
          'Say submit to send your request, or say cancel to start over.',
        );
        _isProcessingVoice = false;
        await _startListening();
        return;
    }

    await _speak('Command not recognized. Say Help for available commands.');
    _isProcessingVoice = false;
  }

  void _onMicTap() {
    if (!_isProcessingVoice && _sttAvailable && !_isSpeaking) {
      _askCurrentStep();
    }
  }

  Future<void> _submitHelpRequest() async {
    setState(() => _errorMessage = null);

    if (_descriptionController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please describe your request');
      await _speak('Please describe your request');
      return;
    }

    if (_locationController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please provide your location');
      await _speak('Please provide your location');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      final userDoc = await firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) throw Exception('User document not found');

      final userData = userDoc.data() as Map<String, dynamic>;
      final userName =
          '${userData['name'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
      final userPhone = userData['phone'] ?? 'N/A';

      final helpRequestData = {
        'blindUserId': user.uid,
        'blindUserName': userName.isEmpty ? 'User' : userName,
        'blindUserPhone': userPhone,
        'volunteerId': null,
        'volunteerName': null,
        'requestType': _selectedRequestType.toLowerCase(),
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'preferredLanguage': _selectedLanguage.toLowerCase(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'acceptedAt': null,
        'completedAt': null,
        'cancelledAt': null,
        'notes': null,
      };

      await firestore.collection('help_requests').add(helpRequestData);

      if (mounted) {
        await _speak('Help request sent successfully!');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Help request sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => _errorMessage = 'Failed to send request. Please try again.');
        await _speak('Failed to send request. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _shouldListen = false;
    _stt.stop();
    _tts.stop();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavyDeep,
      appBar: AppBar(
        title: const Text('Request Help'),
        backgroundColor: kNavyMid,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Voice Command Card
                GestureDetector(
                  onTap: _onMicTap,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: kCardFill.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color:
                            (_isListening ? Colors.greenAccent : kPinkBright)
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
                                color:
                                    (_isListening ? Colors.green : kPinkBright)
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
                                _isListening
                                    ? 'Listening...'
                                    : 'Voice Command',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Tap and I will guide you through the type of '
                                'help, language, and location.',
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
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: kAccentGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.help_outline,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Need Assistance?',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Our volunteers are ready to help you',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: kRedAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: kRedAccent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: kRedAccent),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(_errorMessage!,
                                style: const TextStyle(color: Colors.white))),
                        GestureDetector(
                          onTap: () => setState(() => _errorMessage = null),
                          child: const Icon(Icons.close, color: kRedAccent),
                        ),
                      ],
                    ),
                  ),

                const Text('Type of Help Needed',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.5,
                  children: _requestTypes.entries.map((entry) {
                    return _buildRequestTypeCard(entry.key, entry.value,
                        _selectedRequestType == entry.key);
                  }).toList(),
                ),
                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kCardFill.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.language, color: kPinkBright),
                          SizedBox(width: 8),
                          Text('Preferred Language',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                          'Select your preferred language for volunteer communication',
                          style:
                              TextStyle(fontSize: 12, color: Colors.white60)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _languages.entries.map((entry) {
                          final isSelected = _selectedLanguage == entry.key;
                          return _buildLanguageChip(
                            entry.value,
                            isSelected,
                            () => setState(() => _selectedLanguage = entry.key),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                const Text('Describe your request',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'e.g., I need help finding the cereal aisle...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                const SizedBox(height: 16),

                const Text('Your Location',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const SizedBox(height: 8),
                TextField(
                  controller: _locationController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'e.g., Giant Supermarket, KLCC',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.location_on, color: Colors.white54),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitHelpRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPinkBright,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Send Help Request',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          // Voice indicator overlay
          if (_isListening)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mic, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                        child: Text('Listening...',
                            style: TextStyle(color: Colors.white))),
                    GestureDetector(
                      onTap: () => _stt.cancel(),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLanguageChip(
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected ? kAccentGradient : null,
          color: isSelected ? null : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check, color: Colors.white, size: 16),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestTypeCard(String type, IconData icon, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _selectedRequestType = type),
      child: Container(
        decoration: BoxDecoration(
          gradient: isSelected ? kAccentGradient : null,
          color: isSelected ? null : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: isSelected ? Colors.white : Colors.white60,
                size: 20),
            const SizedBox(width: 8),
            Text(type.toUpperCase(),
                style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
