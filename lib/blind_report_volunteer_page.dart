import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

class BlindReportVolunteerPage extends StatefulWidget {
  final String helpRequestId;
  final String volunteerId;
  final String volunteerName;
  final String requestType;

  const BlindReportVolunteerPage({
    super.key,
    required this.helpRequestId,
    required this.volunteerId,
    required this.volunteerName,
    required this.requestType,
  });

  @override
  State<BlindReportVolunteerPage> createState() =>
      _BlindReportVolunteerPageState();
}

class _BlindReportVolunteerPageState extends State<BlindReportVolunteerPage> {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  final _descriptionController = TextEditingController();

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  bool _isProcessingVoice = false;
  bool _isSubmitting = false;
  int _speakGeneration = 0;
  bool _gotResult = false;
  bool _cancelledBySpeech = false;
  bool _reaskScheduled = false;

  // Report state
  String? _selectedReportType;
  bool _awaitingDescription = false;

  // Report type options
  static const List<Map<String, String>> _reportTypes = [
    {'id': 'no_show', 'label': 'No show', 'desc': 'Volunteer never arrived'},
    {'id': 'inappropriate_behaviour', 'label': 'Inappropriate behaviour', 'desc': 'Volunteer acted inappropriately'},
    {'id': 'did_not_complete', 'label': 'Did not complete task', 'desc': 'Volunteer left without finishing'},
    {'id': 'other', 'label': 'Other', 'desc': 'Another reason'},
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _shouldListen = false;
    _stt.stop();
    _tts.stop();
    _descriptionController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------------------

  Future<void> _init() async {
    await _initTts();
    await _initStt();
    await _speakWelcome();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
    } catch (_) {
      await _tts.setLanguage('en');
    }
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _initStt() async {
    final micStatus = await Permission.microphone.request();
    if (!mounted) return;
    if (micStatus.isDenied || micStatus.isPermanentlyDenied) return;

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
  }

  // ---------------------------------------------------------------------------
  // VOICE — same pattern as login_page.dart
  // ---------------------------------------------------------------------------

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
    await completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {},
    );

    if (mounted) setState(() => _isSpeaking = false);
  }

  void _scheduleReask() {
    if (!mounted ||
        _cancelledBySpeech ||
        _gotResult ||
        !_shouldListen ||
        _reaskScheduled) return;

    _reaskScheduled = true;
    Future.delayed(const Duration(milliseconds: 100), () {
      _reaskScheduled = false;
      if (mounted && _shouldListen && !_cancelledBySpeech && !_gotResult) {
        if (_awaitingDescription) {
          _speak('Please say your description or say skip to leave it blank.');
        } else if (_selectedReportType == null) {
          _speak('Say option one, option two, option three, or option four to select a report type.');
        } else {
          _speak('Say describe to add details, submit to send, or go back to cancel.');
        }
      }
    });
  }

  Future<void> _pressToSpeak() async {
    if (!_sttAvailable || !_shouldListen || _isSpeaking) return;
    if (!_stt.isListening) await _startListening();
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
        Future(() => _processCommand(result.recognizedWords.toLowerCase().trim()));
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );
  }

  Future<void> _speakWelcome() async {
    await _speak(
      'Report volunteer page. Reporting ${widget.volunteerName} '
      'for your ${widget.requestType} request. '
      'Say option one for No show. '
      'Say option two for Inappropriate behaviour. '
      'Say option three for Did not complete task. '
      'Say option four for Other. '
      'Or say go back to cancel.',
    );
  }

  // ---------------------------------------------------------------------------
  // VOICE COMMAND PROCESSING
  // ---------------------------------------------------------------------------

  Future<void> _processCommand(String command) async {
    if (_isProcessingVoice) return;
    _isProcessingVoice = true;
    debugPrint('🎤 Report command: "$command"');

    // Go back
    if (command.contains('back') || command.contains('cancel')) {
      await _speak('Going back.');
      if (mounted) Navigator.pop(context);
      _isProcessingVoice = false;
      return;
    }

    // Handle description input when awaiting it
    if (_awaitingDescription) {
      if (command.contains('skip') || command.isEmpty) {
        _awaitingDescription = false;
        await _speak(
          'No description added. '
          'Say submit to send the report, or go back to cancel.',
        );
        _isProcessingVoice = false;
        return;
      }
      // Any other speech is the description
      setState(() {
        _descriptionController.text = command;
        _awaitingDescription = false;
      });
      await _speak(
        'Description set to: $command. '
        'Say submit to send the report, or go back to cancel.',
      );
      _isProcessingVoice = false;
      return;
    }

    // Select report type by "option one/two/three/four" or just number words
    final optionMap = {
      'option one': 0, 'one': 0, 'first': 0,
      'option two': 1, 'two': 1, 'second': 1,
      'option three': 2, 'three': 2, 'third': 2,
      'option four': 3, 'four': 3, 'fourth': 3,
    };

    // Check longer phrases first to avoid "one" matching inside "option one"
    final sortedKeys = optionMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in sortedKeys) {
      if (command.contains(key)) {
        final index = optionMap[key]!;
        setState(() => _selectedReportType = _reportTypes[index]['id']);
        final label = _reportTypes[index]['label']!;
        await _speak(
          'You selected $label. '
          'Say describe to add more details, '
          'say submit to send the report, '
          'or say go back to cancel.',
        );
        _isProcessingVoice = false;
        return;
      }
    }

    // Describe
    if (command.contains('describe') || command.contains('description')) {
      if (_selectedReportType == null) {
        await _speak('Please select a report type first. Say option one, two, three, or four.');
        _isProcessingVoice = false;
        return;
      }
      _awaitingDescription = true;
      await _speak(
        'Please say your description now. '
        'For example: The volunteer arrived late and left without helping.',
      );
      _isProcessingVoice = false;
      return;
    }

    // Submit
    if (command.contains('submit') || command.contains('send')) {
      if (_selectedReportType == null) {
        await _speak('Please select a report type first. Say option one, two, three, or four.');
        _isProcessingVoice = false;
        return;
      }
      _isProcessingVoice = false;
      await _submitReport();
      return;
    }

    // Repeat options
    if (command.contains('repeat') || command.contains('options')) {
      await _speakWelcome();
      _isProcessingVoice = false;
      return;
    }

    await _speak(
      'Command not recognised. '
      'Say option one, two, three, or four to select. '
      'Say describe to add details. '
      'Say submit to send. '
      'Or say go back to cancel.',
    );
    _isProcessingVoice = false;
  }

  // ---------------------------------------------------------------------------
  // SUBMIT
  // ---------------------------------------------------------------------------

  Future<void> _submitReport() async {
    if (_selectedReportType == null) return;
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    await _speak('Submitting your report. Please wait.');

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Not logged in');

      await FirebaseFirestore.instance.collection('reports').add({
        'blindUserId': uid,
        'volunteerId': widget.volunteerId,
        'volunteerName': widget.volunteerName,
        'helpRequestId': widget.helpRequestId,
        'requestType': widget.requestType,
        'reportType': _selectedReportType,
        'description': _descriptionController.text.trim(),
        'status': 'pending', // admin reviews this
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        await _speak(
          'Your report has been submitted. '
          'Our admin team will review it. Thank you.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Submit report error: $e');
      if (mounted) {
        await _speak('Failed to submit report. Please try again.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to submit report. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Report Volunteer'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _speak('Going back.');
            if (mounted) Navigator.pop(context);
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Voice bar
            _buildVoiceBar(),
            const SizedBox(height: 20),

            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag_rounded, color: Colors.red.shade700, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reporting: ${widget.volunteerName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Request type: ${widget.requestType}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'What happened?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            // Report type options
            ...List.generate(_reportTypes.length, (i) {
              final type = _reportTypes[i];
              final isSelected = _selectedReportType == type['id'];
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedReportType = type['id']);
                  _speak('Selected ${type['label']}.');
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.red.shade50 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? Colors.red.shade400
                          : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Number badge
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.red.shade400
                              : Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              type['label']!,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.red.shade700
                                    : Colors.black87,
                              ),
                            ),
                            Text(
                              type['desc']!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle_rounded,
                            color: Colors.red.shade400, size: 20),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 20),

            // Description field
            const Text(
              'Additional Details (optional)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Describe what happened...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),

            // Awaiting description indicator
            if (_awaitingDescription) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.mic, color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Speak your description now...',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.flag_rounded, size: 20),
                label: Text(_isSubmitting ? 'Submitting...' : 'Submit Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedReportType != null
                      ? Colors.red.shade700
                      : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: _selectedReportType != null && !_isSubmitting
                    ? _submitReport
                    : null,
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VOICE BAR
  // ---------------------------------------------------------------------------

  Widget _buildVoiceBar() {
    return GestureDetector(
      onTap: _pressToSpeak,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isListening
                ? [const Color(0xFF27AE60), const Color(0xFF2ECC71)]
                : _isSpeaking
                    ? [const Color(0xFF6C3483), const Color(0xFF9B59B6)]
                    : [Colors.red.shade700, Colors.red.shade500],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                key: ValueKey(_isListening),
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isSpeaking
                        ? 'Speaking...'
                        : _isListening
                            ? 'Listening...'
                            : 'Tap to Speak',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _awaitingDescription
                        ? 'Say your description or "skip"'
                        : _selectedReportType == null
                            ? 'Say "option one" to "option four"'
                            : 'Say "describe", "submit", or "go back"',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
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