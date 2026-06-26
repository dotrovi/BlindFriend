import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'theme/app_palette.dart';

class BlindRateVolunteerPage extends StatefulWidget {
  final String helpRequestId;
  final String volunteerId;
  final String volunteerName;

  const BlindRateVolunteerPage({
    super.key,
    required this.helpRequestId,
    required this.volunteerId,
    required this.volunteerName,
  });

  @override
  State<BlindRateVolunteerPage> createState() => _BlindRateVolunteerPageState();
}

class _BlindRateVolunteerPageState extends State<BlindRateVolunteerPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  int _rating = 0;
  bool _isSubmitting = false;
  
  // ✅ Moved these to the correct location (class level)
  final TextEditingController _commentController = TextEditingController();

  // Voice command state
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  int _speakGeneration = 0;
  bool _isProcessingVoice = false;

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
      onError: (error) {
        debugPrint('STT error: ${error.errorMsg}');
        if (mounted) setState(() => _isListening = false);
      },
    );

    if (mounted) {
      await _speak(
        'Please rate your volunteer, ${widget.volunteerName}, on a scale of 1 to 5 stars. '
        'Say "One star", "Two stars", "Three stars", "Four stars", or "Five stars". '
        'Then say "Submit rating" to finish.',
      );
    }
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
    await completer.future.timeout(const Duration(seconds: 90), onTimeout: () {});

    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _startListening() async {
    if (!_sttAvailable || !mounted || !_shouldListen || _stt.isListening) return;

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

    if (command.contains('one') || command.contains('1')) {
      setState(() => _rating = 1);
      await _speak('You selected one star. Say Submit rating to confirm.');
    } else if (command.contains('two') || command.contains('2')) {
      setState(() => _rating = 2);
      await _speak('You selected two stars. Say Submit rating to confirm.');
    } else if (command.contains('three') || command.contains('3')) {
      setState(() => _rating = 3);
      await _speak('You selected three stars. Say Submit rating to confirm.');
    } else if (command.contains('four') || command.contains('4')) {
      setState(() => _rating = 4);
      await _speak('You selected four stars. Say Submit rating to confirm.');
    } else if (command.contains('five') || command.contains('5')) {
      setState(() => _rating = 5);
      await _speak('You selected five stars. Say Submit rating to confirm.');
    } else if (command.contains('submit') || command.contains('confirm') || command.contains('send')) {
      if (_rating == 0) {
        await _speak('Please select a rating from 1 to 5 first.');
      } else {
        await _speak('Submitting your rating.');
        _isProcessingVoice = false;
        await _submitRating();
        return;
      }
    } else if (command.contains('back') && command.contains('home')) {
      await _speak('Returning to home page.');
      _isProcessingVoice = false;
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    } else if (command.contains('cancel') || command.contains('back')) {
      await _speak('Cancelling. Going back.');
      _isProcessingVoice = false;
      Navigator.pop(context);
      return;
    } else {
      await _speak('Command not recognized. Say a number from one to five, or Submit.');
    }

    _isProcessingVoice = false;
  }

  void _onMicTap() {
    if (!_isProcessingVoice && _sttAvailable && !_isSpeaking) {
      _startListening();
    }
  }

  Future<void> _submitRating() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating first.')),
      );
      await _speak('Please select a rating first.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final batch = firestore.batch();

      // 1. Update the help request with rating and comment
      final requestRef = firestore.collection('help_requests').doc(widget.helpRequestId);
      batch.update(requestRef, {
        'rating': _rating,
        'ratedAt': FieldValue.serverTimestamp(),
        'feedbackComment': _commentController.text.trim(),
      });

      // 2. Update the volunteer's average rating and total ratings
      final volunteerRef = firestore.collection('volunteers').doc(widget.volunteerId);
      
      final volunteerDoc = await volunteerRef.get();
      if (volunteerDoc.exists) {
        final data = volunteerDoc.data()!;
        final int currentTotalRatings = data['totalRatings'] ?? 0;
        final double currentAverageRating = (data['averageRating'] ?? 0.0).toDouble();
        
        final int newTotalRatings = currentTotalRatings + 1;
        final double newAverageRating = ((currentAverageRating * currentTotalRatings) + _rating) / newTotalRatings;
        
        batch.update(volunteerRef, {
          'totalRatings': newTotalRatings,
          'averageRating': newAverageRating,
        });
      }

      await batch.commit();

      if (mounted) {
        await _speak('Thank you for rating. Your feedback helps us improve.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rating submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        await _speak('Failed to submit rating. Please try again.');
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _shouldListen = false;
    _commentController.dispose(); // ✅ Dispose the controller
    _stt.stop();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavyDeep,
      appBar: AppBar(
        title: const Text('Rate Volunteer'),
        backgroundColor: kNavyMid,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              color: Colors.white,
            ),
            onPressed: _onMicTap,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'How was your experience with ${widget.volunteerName}?',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Star Rating
            Row(
              children: List.generate(5, (index) {
                return Expanded(
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      color: kAmberAccent,
                      size: 40,
                    ),
                    onPressed: () {
                      setState(() => _rating = index + 1);
                    },
                  ),
                );
              }),
            ),

            const SizedBox(height: 24),

            TextField(
              controller: _commentController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Optional: Leave a comment about your experience...',
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide(color: kPinkBright),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRating,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPinkBright,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Submit Rating',
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}