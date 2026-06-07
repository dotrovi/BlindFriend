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

  // Auto-listen control: when true, listening will NOT auto-restart
  // (used while we are navigating away or submitting).
  bool _suspendAutoListen = false;

  // Report state
  String? _selectedReportType;
  bool _awaitingDescription = false;

  static const List<Map<String, String>> _reportTypes = [
    {'id': 'no_show', 'label': 'No show', 'desc': 'Volunteer never arrived'},
    {
      'id': 'inappropriate_behaviour',
      'label': 'Inappropriate behaviour',
      'desc': 'Volunteer acted inappropriately'
    },
    {
      'id': 'did_not_complete',
      'label': 'Did not complete task',
      'desc': 'Volunteer left without finishing'
    },
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
    _suspendAutoListen = true;
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
        }
      },
      onError: (error) {
        debugPrint('STT error: ${error.errorMsg}');
        if (mounted) setState(() => _isListening = false);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // VOICE CORE — speak then auto-listen
  // ---------------------------------------------------------------------------

  /// Speaks [text]. When [thenListen] is true (default), automatically starts
  /// listening once speech finishes — this is what makes the page hands-free.
  Future<void> _speak(String text, {bool thenListen = true}) async {
    final myGen = ++_speakGeneration;

    if (_stt.isListening) await _stt.cancel();
    await _tts.stop();
    await Future.delayed(const Duration(milliseconds: 50));
    if (myGen != _speakGeneration || !mounted) return;

    setState(() => _isSpeaking = true);

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

    if (!mounted) return;
    setState(() => _isSpeaking = false);

    // This speech was superseded by a newer one — don't auto-listen.
    if (myGen != _speakGeneration) return;

    // Auto-listen: start the mic once the prompt finishes, so the blind user
    // can simply respond without tapping anything.
    if (thenListen && _shouldListen && !_suspendAutoListen) {
      // Small gap so the mic doesn't catch the tail of our own speech.
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted && _shouldListen && !_suspendAutoListen && !_isSpeaking) {
        await _startListening();
      }
    }
  }

  Future<void> _startListening() async {
    if (!_sttAvailable || !mounted || !_shouldListen || _stt.isListening) {
      return;
    }
    setState(() => _isListening = true);
    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.finalResult) {
          _processCommand(result.recognizedWords.toLowerCase().trim());
        }
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );
  }

  /// Manual mic button — backup only. Auto-listen handles the normal flow.
  void _onMicTap() {
    if (!_isProcessingVoice && _sttAvailable && !_isSpeaking && !_isListening) {
      _startListening();
    }
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
  // COMMAND PROCESSING
  // ---------------------------------------------------------------------------

  Future<void> _processCommand(String command) async {
    if (_isProcessingVoice) return;
    _isProcessingVoice = true;
    debugPrint('🎤 Report command: "$command"');

    // Empty result — gently re-prompt based on current step.
    if (command.isEmpty) {
      _isProcessingVoice = false;
      await _repromptCurrentStep();
      return;
    }

    // Go back / cancel
    if (command.contains('go back') ||
        command.contains('cancel') ||
        command.contains('exit')) {
      _suspendAutoListen = true;
      _shouldListen = false;
      await _speak('Going back.', thenListen: false);
      _isProcessingVoice = false;
      if (mounted) Navigator.pop(context);
      return;
    }

    // Awaiting a spoken description
    if (_awaitingDescription) {
      if (command.contains('skip')) {
        _awaitingDescription = false;
        _isProcessingVoice = false;
        await _speak(
          'No description added. '
          'Say submit to send the report, or go back to cancel.',
        );
        return;
      }
      setState(() {
        _descriptionController.text = command;
        _awaitingDescription = false;
      });
      _isProcessingVoice = false;
      await _speak(
        'Description saved. '
        'Say submit to send the report, or go back to cancel.',
      );
      return;
    }

    // Report type selection — longer phrases first so "one" doesn't match
    // inside "option one" prematurely.
    final optionMap = <String, int>{
      'option one': 0, 'option two': 1, 'option three': 2, 'option four': 3,
      'first': 0, 'second': 1, 'third': 2, 'fourth': 3,
      'one': 0, 'two': 1, 'three': 2, 'four': 3,
      'option 1': 0, 'option 2': 1, 'option 3': 2, 'option 4': 3,
    };
    final sortedKeys = optionMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in sortedKeys) {
      if (command.contains(key)) {
        final index = optionMap[key]!;
        setState(() => _selectedReportType = _reportTypes[index]['id']);
        final label = _reportTypes[index]['label']!;
        _isProcessingVoice = false;
        await _speak(
          'You selected $label. '
          'Say describe to add more details, '
          'say submit to send the report, '
          'or say go back to cancel.',
        );
        return;
      }
    }

    // Describe
    if (command.contains('describe') || command.contains('description')) {
      if (_selectedReportType == null) {
        _isProcessingVoice = false;
        await _speak(
          'Please select a report type first. '
          'Say option one, two, three, or four.',
        );
        return;
      }
      _awaitingDescription = true;
      _isProcessingVoice = false;
      await _speak(
        'Please say your description now. '
        'For example: The volunteer arrived late and left without helping. '
        'Or say skip to leave it blank.',
      );
      return;
    }

    // Submit
    if (command.contains('submit') || command.contains('send')) {
      if (_selectedReportType == null) {
        _isProcessingVoice = false;
        await _speak(
          'Please select a report type first. '
          'Say option one, two, three, or four.',
        );
        return;
      }
      _isProcessingVoice = false;
      await _submitReport();
      return;
    }

    // Repeat options
    if (command.contains('repeat') || command.contains('options')) {
      _isProcessingVoice = false;
      await _speakWelcome();
      return;
    }

    // Unrecognised
    _isProcessingVoice = false;
    await _speak(
      'Sorry, I did not understand. '
      'Say option one, two, three, or four to select. '
      'Say describe to add details. '
      'Say submit to send. '
      'Or say go back to cancel.',
    );
  }

  /// Re-prompts the user based on whatever step they are currently on.
  Future<void> _repromptCurrentStep() async {
    if (_awaitingDescription) {
      await _speak('I did not catch that. Please say your description, or say skip.');
    } else if (_selectedReportType == null) {
      await _speak(
        'I did not catch that. '
        'Say option one, two, three, or four to choose a report reason.',
      );
    } else {
      await _speak(
        'I did not catch that. '
        'Say describe to add details, submit to send, or go back to cancel.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SUBMIT
  // ---------------------------------------------------------------------------

  Future<void> _submitReport() async {
    if (_selectedReportType == null || _isSubmitting) return;

    _suspendAutoListen = true;
    setState(() => _isSubmitting = true);
    await _speak('Submitting your report. Please wait.', thenListen: false);

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
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Mark the help request as reported so it won't show the report option again
      if (widget.helpRequestId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('help_requests')
            .doc(widget.helpRequestId)
            .update({'reported': true});
      }

      if (mounted) {
        _shouldListen = false;
        await _speak(
          'Your report has been submitted. '
          'Our admin team will review it. Thank you.',
          thenListen: false,
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
        _suspendAutoListen = false;
        setState(() => _isSubmitting = false);
        await _speak('Failed to submit report. Please try again, or say go back to cancel.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to submit report. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
            _suspendAutoListen = true;
            _shouldListen = false;
            await _speak('Going back.', thenListen: false);
            if (mounted) Navigator.pop(context);
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVoiceBar(),
            const SizedBox(height: 20),
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
            ...List.generate(_reportTypes.length, (i) {
              final type = _reportTypes[i];
              final isSelected = _selectedReportType == type['id'];
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedReportType = type['id']);
                  _speak(
                    'Selected ${type['label']}. '
                    'Say describe to add details, or submit to send.',
                  );
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

  Widget _buildVoiceBar() {
    return GestureDetector(
      onTap: _onMicTap,
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
