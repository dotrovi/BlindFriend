import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'theme/app_palette.dart';

class BlindNotificationsPage extends StatefulWidget {
  const BlindNotificationsPage({super.key});

  @override
  State<BlindNotificationsPage> createState() =>
      _BlindNotificationsPageState();
}

class _BlindNotificationsPageState extends State<BlindNotificationsPage> {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _sttAvailable = false;
  bool _isListening = false;
  bool _isLoading = true;
  StreamSubscription? _notificationsSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _notifications = [];

  static const String _voiceInstruction =
      'Tap the button and say read notifications to hear them, '
      'or say back to home page to return.';

  @override
  void initState() {
    super.initState();
    _initTts();
    _listenForNotifications();
    _initVoice();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
    } catch (_) {
      await _tts.setLanguage('en');
    }
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  void _listenForNotifications() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    _notificationsSub = _firestore
        .collection('notifications')
        .doc(uid)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _notifications = snapshot.docs;
        _isLoading = false;
      });
    });
  }

  Future<void> _initVoice() async {
    final micStatus = await Permission.microphone.request();
    if (!mounted) return;

    if (micStatus.isGranted) {
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

    if (!mounted) return;
    final unread =
        _notifications.where((d) => d.data()['read'] != true).length;
    final intro = unread > 0
        ? 'You have $unread unread notification${unread == 1 ? '' : 's'}. '
        : 'You have no new notifications. ';
    await _speak('$intro$_voiceInstruction');
  }

  Future<void> _pressMic() async {
    if (!_sttAvailable || _isListening) return;
    setState(() => _isListening = true);
    await _stt.listen(
      onResult: (result) {
        if (!mounted || !result.finalResult) return;
        _handleVoiceCommand(result.recognizedWords.toLowerCase());
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 10),
      localeId: 'en_US',
    );
  }

  void _handleVoiceCommand(String command) {
    if (command.contains('back') && command.contains('home')) {
      _speak('Returning to home page.');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else if (command.contains('clear') || command.contains('mark all')) {
      _markAllRead();
      _speak('All notifications marked as read.');
    } else if (command.contains('read') || command.contains('notification')) {
      _readAllNotifications();
    } else {
      _speak('I did not catch that. $_voiceInstruction');
    }
  }

  Future<void> _readAllNotifications() async {
    if (_notifications.isEmpty) {
      await _speak('You have no notifications.');
      return;
    }
    for (final doc in _notifications.take(5)) {
      final data = doc.data();
      final title = data['title'] ?? '';
      final body = data['body'] ?? '';
      await _speak('$title. $body');
    }
    await _markAllRead();
  }

  Future<void> _markAllRead() async {
    final unread =
        _notifications.where((d) => d.data()['read'] != true).toList();
    if (unread.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in unread) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> _markRead(DocumentReference<Map<String, dynamic>> ref) async {
    await ref.update({'read': true});
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  @override
  void dispose() {
    _notificationsSub?.cancel();
    _stt.stop();
    _tts.stop();
    super.dispose();
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount =
        _notifications.where((d) => d.data()['read'] != true).length;
    return Scaffold(
      backgroundColor: kNavyDeep,
      appBar: AppBar(
        backgroundColor: kNavyMid,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            _stt.stop();
            _tts.stop();
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: () {
                _markAllRead();
                _speak('All notifications marked as read.');
              },
              child: const Text(
                'Mark all read',
                style: TextStyle(color: kBlueAccent),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Voice Command Card
            GestureDetector(
              onTap: _pressMic,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kCardFill.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (_isListening ? Colors.greenAccent : kPinkBright)
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
                            color: (_isListening ? Colors.green : kPinkBright)
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
                            _isListening ? 'Listening...' : 'Voice Command',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _voiceInstruction,
                            style: const TextStyle(
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
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: CircularProgressIndicator(color: kPinkBright),
              )
            else if (_notifications.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: 64,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No notifications yet',
                      style: TextStyle(color: Colors.white60, fontSize: 16),
                    ),
                  ],
                ),
              )
            else
              ..._notifications.map(_buildNotificationCard),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final title = data['title'] ?? 'Notification';
    final body = data['body'] ?? '';
    final isRead = data['read'] == true;
    final createdAt = data['createdAt'] as Timestamp?;

    return GestureDetector(
      onTap: () {
        if (!isRead) _markRead(doc.reference);
        _speak('$title. $body');
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead
              ? kCardFill.withValues(alpha: 0.35)
              : kCardFill.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRead
                ? Colors.white.withValues(alpha: 0.08)
                : kBlueAccent.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 4, right: 12),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRead ? Colors.transparent : kPinkBright,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight:
                          isRead ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatTime(createdAt),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
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
