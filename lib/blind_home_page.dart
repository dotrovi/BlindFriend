import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_blindfriend/shopping_helper_page.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'login_page.dart';
import 'user_profile_page.dart';
import 'blind_send_help_request.dart'; 
import 'blind_track_help_request.dart'; 
import 'blind_notifications_page.dart';
import 'obstacle_detection_page.dart';
import 'tactile_path_page.dart';
import 'accessibility_settings_page.dart';
import 'theme/app_palette.dart';

class BlindHomePage extends StatefulWidget {
  final String userName;
  const BlindHomePage({super.key, required this.userName});

  @override
  State<BlindHomePage> createState() => _BlindHomePageState();
}

class _BlindHomePageState extends State<BlindHomePage> {
  int _selectedIndex = 0; 

  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  int _speakGeneration = 0;

  bool _isProcessingVoice = false;

  StreamSubscription? _unreadNotificationsSub;
  int _unreadNotifications = 0;
  bool _autoStartScan = false;

  @override
  void initState() {
    super.initState();
    _initVoice();
    _listenForUnreadNotifications();
  }

  void _listenForUnreadNotifications() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _unreadNotificationsSub = FirebaseFirestore.instance
        .collection('notifications')
        .doc(uid)
        .collection('messages')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() => _unreadNotifications = snapshot.docs.length);
    });
  }

  void _navigateToNotifications() async {
    _shouldListen = false;
    if (_stt.isListening) await _stt.stop();
    
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BlindNotificationsPage()),
      );
    }
    _shouldListen = true;
    if (mounted) {
      _speak('Back on home page. Tap the voice button to speak.');
    }
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

    final sttInitialized = await _stt.initialize(
      onStatus: (status) {
        print('🎤 STT Status Update: $status');
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
      debugLogging: false,
    );

    _sttAvailable = micStatus.isGranted && sttInitialized;

    if (mounted) {
      // Temporarily mark processing true during startup intro text execution
      _isProcessingVoice = true;
      await Future.delayed(const Duration(milliseconds: 300));
      await _speak(
        'Welcome to BlindFriend, ${widget.userName}. '
        'Say: Shopping, Obstacle, Path, Request Help, Track Requests, Volunteers, '
        'Profile, Settings, Notifications, or Logout.',
      );
      await _announceUnreadNotifications();
    }
  }

  Future<void> _announceUnreadNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !mounted) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .doc(uid)
          .collection('messages')
          .where('read', isEqualTo: false)
          .get();
      if (!mounted || snapshot.docs.isEmpty) return;

      final docs = snapshot.docs.toList()
        ..sort((a, b) {
          final tsA = a.data()['createdAt'] as Timestamp?;
          final tsB = b.data()['createdAt'] as Timestamp?;
          if (tsA == null || tsB == null) return 0;
          return tsB.compareTo(tsA);
        });

      final count = docs.length;
      final buffer = StringBuffer(
        'You have $count unread notification${count == 1 ? '' : 's'}. ',
      );
      for (final doc in docs.take(5)) {
        final data = doc.data();
        final title = data['title'] ?? '';
        final body = data['body'] ?? '';
        buffer.write('$title. $body. ');
      }
      await _speak(buffer.toString());
    } catch (e) {
      debugPrint('Error announcing unread notifications: $e');
    }
  }

  Future<void> _speak(String text) async {
    final myGen = ++_speakGeneration;
    
    if (_stt.isListening) {
      await _stt.stop();
    }
    if (mounted) {
      setState(() => _isListening = false);
    }

    await _tts.stop();
    await Future.delayed(const Duration(milliseconds: 50));
    if (myGen != _speakGeneration) return;

    if (mounted) setState(() => _isSpeaking = true);
    final completer = Completer<void>();

    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    _tts.setErrorHandler((msg) {
      if (!completer.isCompleted) completer.complete();
    });

    await _tts.speak(text);
    
    await completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () {},
    );

    if (mounted) setState(() => _isSpeaking = false);

    if (mounted && _sttAvailable && _shouldListen) {
      // ── THE ECHO FIX ──
      // Give physical hardware audio components a 600ms clearing delay 
      // before opening the microphone pipeline and dropping the processing lock.
      await Future.delayed(const Duration(milliseconds: 600));
      _isProcessingVoice = false; 
      _startListening();
    }
  }

  void _onVoiceButtonTap() async {
    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
    }
    
    if (_stt.isListening) {
      await _stt.stop();
      setState(() => _isListening = false);
    } else if (_sttAvailable) {
      _isProcessingVoice = false;
      _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_sttAvailable || !mounted || !_shouldListen) return;
    if (_stt.isListening) return;

    setState(() => _isListening = true);

    try {
      await _stt.listen(
        onResult: (result) async {
          if (!mounted) return;
          if (result.recognizedWords.isNotEmpty) {
            final commandStr = result.recognizedWords.toLowerCase().trim();
            
            if (result.finalResult) {
              print('🎤 Final recognized command: $commandStr');
              setState(() => _isListening = false);
              await _stt.stop();
              
              scheduleMicrotask(() => _processCommand(commandStr));
            }
          }
        },
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 4), 
        localeId: 'en_US',
        cancelOnError: true,
        partialResults: false,
        listenMode: ListenMode.confirmation, 
      );
    } catch (e) {
      print('❌ Error calling stt.listen: $e');
      if (mounted) setState(() => _isListening = false);
    }
  }

  Future<void> _processCommand(String command) async {
    if (_isProcessingVoice) return;
    _isProcessingVoice = true;

    print('🎤 Processing command: "$command"');

    // Request Help
    if (command.contains('request help') || 
        command.contains('send help') ||
        command.contains('help request') ||
        command.contains('need help') ||
        command.contains('call help')) {
      _speak('Opening request help page.');
      _setSelectedIndex(4);
      return;
    }

    // Track Requests
    if (command.contains('track')) {
      _speak('Opening your help requests.');
      _navigateToTrackRequests();
      return;
    }

    // Path / Navigation
    if (command.contains('path') || 
        command.contains('pass') ||
        command.contains('pat') ||
        command.contains('navig') || 
        command.contains('direction') ||
        command.contains('tactile')) {
      _speak('Path detection activated.');
      _setSelectedIndex(3);
      return;
    }

    // Shopping
    if (command.contains('shopping') ||
        command.contains('scan') ||
        command.contains('barcode') ||
        command.contains('shop')) {
      final autoStart = command.contains('scan') || command.contains('barcode');
      _speak(autoStart ? 'Opening barcode scanner.' : 'Opening shopping helper.');
      setState(() => _autoStartScan = autoStart);
      _setSelectedIndex(1);
      return;
    }

    // Obstacle
    if (command.contains('obstacle') || 
        command.contains('obs') || 
        command.contains('detection') ||
        command.contains('warning') ||
        command.contains('alert')) {
      _speak('Obstacle detection activated.');
      _setSelectedIndex(2);
      return;
    }

    // Volunteers / Help Center
    if (command.contains('volunteer') || 
        command.contains('find help') ||
        command.contains('helper')) {
      _speak('Opening request help page.');
      _setSelectedIndex(4);
      return;
    }

    // Home
    if (command.contains('home') || command.contains('dashboard')) {
      _speak('Returning home.');
      _setSelectedIndex(0);
      return;
    }

    // Profile
    if (command.contains('profile') || command.contains('account')) {
      _shouldListen = false;
      _speak('Opening your profile.');
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) {
        _isProcessingVoice = false;
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const UserProfilePage()),
      );
      _shouldListen = true;
      _speak('Back on home page.');
      return;
    }

    // Settings
    if (command.contains('setting') || 
        command.contains('accessibility') ||
        command.contains('contrast') ||
        command.contains('font')) {
      _speak('Opening settings.');
      await _navigateToAccessibilitySettings();
      return;
    }

    // Notifications
    if (command.contains('notification') || command.contains('update')) {
      _speak('Opening notifications.');
      _navigateToNotifications();
      return;
    }

    // Logout
    if (command.contains('logout') || command.contains('sign out')) {
      _shouldListen = false;
      await _speak('Logging out.');
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
      return;
    }

    // Repeat commands
    if (command.contains('repeat') || command.contains('commands') || command.contains('help')) {
      _speak(
        'Available commands: Shopping, Obstacle, Path, Request Help, '
        'Track Requests, Volunteers, Profile, Settings, Notifications, and Logout.'
      );
      return;
    }

    // Fallback if nothing matched
    _speak('Command not recognized. Say Repeat to list options.');
  }

  void _setSelectedIndex(int index) {
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  void _openHelpCenter() {
    _setSelectedIndex(4);
    _speak('Request help page loaded.');
  }

  void _onNavBarTap(int index) {
    _setSelectedIndex(index);
    String pageName = ['Home', 'Shopping Helper', 'Obstacle Detection', 'Navigation', 'Request Help'][index];
    _speak('Opened $pageName');
  }

  void _navigateToTrackRequests() async {
    _shouldListen = false;
    if (_stt.isListening) await _stt.stop();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BlindTrackRequestsScreen()),
    );
    _shouldListen = true;
    if (mounted) _speak('Back on home page.');
  }

  Future<void> _navigateToAccessibilitySettings() async {
    _shouldListen = false;
    if (_stt.isListening) await _stt.stop();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccessibilitySettingsPage()),
    );
    _shouldListen = true;
    if (mounted) _speak('Back on home page.');
  }

  @override
  void dispose() {
    _shouldListen = false;
    _stt.stop();
    _tts.stop();
    _unreadNotificationsSub?.cancel();
    super.dispose();
  }

  Widget _headerIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: color.withValues(alpha: 0.18),
        shape: const CircleBorder(),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 22),
          color: color,
          tooltip: tooltip,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavyDeep,
      body: SafeArea(
        child: Column(
          children: [
            // Top Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: kNavyMid,
                border: Border(
                  bottom:
                      BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          children: [
                            TextSpan(
                              text: 'Blind',
                              style: TextStyle(color: Colors.white),
                            ),
                            TextSpan(
                              text: 'Friend',
                              style: TextStyle(color: kPinkBright),
                            ),
                          ],
                        ),
                      ),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white60,
                          ),
                          children: [
                            const TextSpan(text: 'Welcome back, '),
                            TextSpan(
                              text: widget.userName,
                              style: const TextStyle(
                                color: kBlueAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _headerIconButton(
                        icon: Icons.person,
                        color: kBlueAccent,
                        onPressed: () {
                          _shouldListen = false;
                          _speak('Opening your profile.');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const UserProfilePage(),
                            ),
                          ).then((_) => _shouldListen = true);
                        },
                      ),
                      _headerIconButton(
                        icon: Icons.accessibility_new,
                        color: kPurpleAccent,
                        tooltip: 'Accessibility Settings',
                        onPressed: () {
                          _navigateToAccessibilitySettings();
                        },
                      ),
                      _headerIconButton(
                        icon: Icons.logout,
                        color: kRedAccent,
                        onPressed: () async {
                          _shouldListen = false;
                          await _tts.stop();
                          await FirebaseAuth.instance.signOut();
                          if (mounted) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const LoginPage()),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Main Content Area
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  _buildHomePage(),
                  _buildShoppingHelper(),
                  _buildObstacleDetection(),
                  _buildPathDetection(),
                  const BlindSendHelpRequestScreen(),
                ],
              ),
            ),

            // Bottom Navigation Bar
            Container(
              decoration: BoxDecoration(
                color: kNavyMid,
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: _onNavBarTap,
                type: BottomNavigationBarType.fixed,
                backgroundColor: kNavyMid,
                selectedItemColor: kBlueAccent,
                unselectedItemColor: Colors.white38,
                selectedFontSize: 12,
                unselectedFontSize: 12,
                elevation: 0,
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                  BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Shopping'),
                  BottomNavigationBarItem(icon: Icon(Icons.warning), label: 'Obstacles'),
                  BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Path'),
                  BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Help'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== HOME PAGE =====================
  Widget _buildHomePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onVoiceButtonTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kCardFill.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: (_isListening ? Colors.greenAccent : kPinkBright).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  _buildVoiceWaveBars(reversed: true, compact: true),
                  const SizedBox(width: 14),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _isListening
                          ? const LinearGradient(colors: [Colors.green, Colors.lightGreen])
                          : kAccentGradient,
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening ? Colors.green : kPinkBright).withValues(alpha: 0.5),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        key: ValueKey(_isListening),
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isListening ? 'Listening...' : 'Tap to Speak',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap and say a command',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  _buildVoiceWaveBars(reversed: false, compact: false),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.qr_code_scanner,
                  title: 'Shopping Helper',
                  description: 'Scan barcodes',
                  color: kPurpleAccent,
                  index: 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.warning_amber,
                  title: 'Obstacles',
                  description: 'Alert alerts',
                  color: kAmberAccent,
                  index: 2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.map_outlined,
                  title: 'Path',
                  description: 'Tactile path',
                  color: kTealAccent,
                  index: 3,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.people_alt,
                  title: 'Volunteers',
                  description: 'Find help',
                  color: kTealAccent,
                  index: 4,
                  onTapOverride: _openHelpCenter,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          GestureDetector(
            onTap: _navigateToNotifications,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kBlueAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBlueAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.notifications, size: 28, color: kBlueAccent),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _unreadNotifications > 0 ? '$_unreadNotifications updates pending' : 'No new notifications',
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildVoiceWaveBars({required bool reversed, required bool compact}) {
    final heights = compact ? [6.0, 10.0, 14.0, 10.0, 6.0] : [10.0, 18.0, 28.0, 20.0, 10.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: heights
          .map((h) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 3,
                height: _isListening ? h : h * 0.5,
                decoration: BoxDecoration(color: kBlueAccent.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(3)),
              ))
          .toList(),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required int index,
    VoidCallback? onTapOverride,
  }) {
    return Material(
      color: kCardFill.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTapOverride ?? () => _onNavBarTap(index),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShoppingHelper() => ShoppingHelperPage(
        onBackToHome: () => _setSelectedIndex(0),
        autoStartScan: _autoStartScan,
        onAutoScanHandled: () => setState(() => _autoStartScan = false),
      );
  Widget _buildObstacleDetection() => ObstacleDetectionPage(onBackToHome: () => _setSelectedIndex(0));
  Widget _buildPathDetection() => TactilePathPage(onBackToHome: () => _setSelectedIndex(0));
}