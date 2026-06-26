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

class _BlindHomePageState extends State<BlindHomePage> with TickerProviderStateMixin {
  int _selectedIndex = 0; 
  late TabController _helpTabController; // Added for inner help switcher tracking

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
    _helpTabController = TabController(length: 2, vsync: this);
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

    if (command.contains('request help') || 
        command.contains('send help') ||
        command.contains('help request') ||
        command.contains('need help') ||
        command.contains('call help')) {
      _speak('Opening request help center.');
      _setSelectedIndex(4);
      _helpTabController.animateTo(0);
      return;
    }

    if (command.contains('track') || command.contains('status')) {
      _speak('Opening help tracking status.');
      _setSelectedIndex(4);
      _helpTabController.animateTo(1);
      return;
    }

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

    if (command.contains('obstacle') || 
        command.contains('obs') || 
        command.contains('detection') ||
        command.contains('warning') ||
        command.contains('alert')) {
      _speak('Obstacle detection activated.');
      _setSelectedIndex(2);
      return;
    }

    if (command.contains('volunteer') || 
        command.contains('find help') ||
        command.contains('helper')) {
      _speak('Opening volunteer request panel.');
      _setSelectedIndex(4);
      _helpTabController.animateTo(0);
      return;
    }

    if (command.contains('home') || command.contains('dashboard')) {
      _speak('Returning home.');
      _setSelectedIndex(0);
      return;
    }

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

    if (command.contains('setting') || 
        command.contains('accessibility') ||
        command.contains('contrast') ||
        command.contains('font')) {
      _speak('Opening settings.');
      await _navigateToAccessibilitySettings();
      return;
    }

    if (command.contains('notification') || command.contains('update')) {
      _speak('Opening notifications.');
      _navigateToNotifications();
      return;
    }

    if (command.contains('logout') || command.contains('sign out') || command.contains('log out')) {
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

    if (command.contains('repeat') || command.contains('commands') || command.contains('help')) {
      _speak(
        'Available commands: Shopping, Obstacle, Path, Request Help, '
        'Track Requests, Volunteers, Profile, Settings, Notifications, and Logout.'
      );
      return;
    }

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
    _helpTabController.animateTo(0);
    _speak('Request help page loaded.');
  }

  void _onNavBarTap(int index) {
    _setSelectedIndex(index);
    String pageName = ['Home', 'Shopping Helper', 'Obstacle Detection', 'Navigation', 'Help Center'][index];
    _speak('Opened $pageName');
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
    _helpTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavyDeep,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: kNavyMid,
                border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
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
                            TextSpan(text: 'Blind', style: TextStyle(color: Colors.white)),
                            TextSpan(text: 'Friend', style: TextStyle(color: kPinkBright)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 13, color: Colors.white54),
                          children: [
                            const TextSpan(text: 'Welcome back, '),
                            TextSpan(
                              text: widget.userName,
                              style: const TextStyle(
                                color: kBlueAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          _shouldListen = false;
                          _speak('Opening your profile.');
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const UserProfilePage()),
                          ).then((_) => _shouldListen = true);
                        },
                        icon: const Icon(Icons.account_circle_outlined, size: 26, color: Colors.white70),
                      ),
                      IconButton(
                        onPressed: _navigateToAccessibilitySettings,
                        icon: const Icon(Icons.tune_outlined, size: 24, color: Colors.white70),
                      ),
                      IconButton(
                        onPressed: () async {
                          _shouldListen = false;
                          await _tts.stop();
                          await FirebaseAuth.instance.signOut();
                          if (!mounted) return;
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => const LoginPage()),
                          );
                        },
                        icon: const Icon(
                          Icons.power_settings_new_outlined, 
                          size: 24, 
                          color: kRedAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  _buildHomePage(),
                  _buildShoppingHelper(),
                  _buildObstacleDetection(),
                  _buildPathDetection(),
                  _buildHelpCenter(), // Upgraded combined view rendering tracking alongside help screen
                ],
              ),
            ),

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
                selectedItemColor: kPinkBright,
                unselectedItemColor: Colors.white38,
                selectedFontSize: 11,
                unselectedFontSize: 11,
                elevation: 0,
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Home'),
                  BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), activeIcon: Icon(Icons.shopping_bag), label: 'Shopping'),
                  BottomNavigationBarItem(icon: Icon(Icons.blur_circular), activeIcon: Icon(Icons.lens), label: 'Obstacles'),
                  BottomNavigationBarItem(icon: Icon(Icons.explore_outlined), activeIcon: Icon(Icons.explore), label: 'Path'),
                  BottomNavigationBarItem(icon: Icon(Icons.handshake_outlined), activeIcon: Icon(Icons.handshake), label: 'Help'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomePage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onVoiceButtonTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: kCardFill.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: (_isListening ? Colors.greenAccent : kPinkBright).withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildVoiceWaveBars(reversed: true, compact: false),
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _isListening
                              ? const LinearGradient(colors: [Colors.green, Colors.lightGreen])
                              : kAccentGradient,
                          boxShadow: [
                            BoxShadow(
                              color: (_isListening ? Colors.green : kPinkBright).withValues(alpha: 0.4),
                              blurRadius: 24,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            _isListening ? Icons.mic : Icons.mic_none_outlined,
                            key: ValueKey(_isListening),
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                      ),
                      _buildVoiceWaveBars(reversed: false, compact: false),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _isListening ? 'Listening Intently...' : 'Voice Assistant Idle',
                    style: TextStyle(
                      color: _isListening ? Colors.greenAccent : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isListening ? 'Say your voice action target command' : 'Tap panel or speak trigger phrase directly',
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          _buildLiveLocationCard(),
          const SizedBox(height: 28),

          const Text(
            'Explore Navigation Utilities',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          const SizedBox(height: 14),

          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.25,
            children: [
              _buildFeatureCard(
                icon: Icons.qr_code_scanner_outlined,
                title: 'Shopping Helper',
                description: 'Analyze codes & labels',
                color: kPurpleAccent,
                index: 1,
              ),
              _buildFeatureCard(
                icon: Icons.notifications_active_outlined,
                title: 'Obstacle Alert',
                description: 'Realtime spatial warning',
                color: kAmberAccent,
                index: 2,
              ),
              _buildFeatureCard(
                icon: Icons.map_outlined,
                title: 'Tactile Path',
                description: 'Geometric trail guidelines',
                color: kTealAccent,
                index: 3,
              ),
              _buildFeatureCard(
                icon: Icons.support_agent_outlined,
                title: 'Live Volunteers',
                description: 'Request instant assistance',
                color: kBlueAccent,
                index: 4,
                onTapOverride: _openHelpCenter,
              ),
            ],
          ),
          const SizedBox(height: 28),

          GestureDetector(
            onTap: _navigateToNotifications,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: kBlueAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kBlueAccent.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kBlueAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.notifications_outlined, size: 22, color: kBlueAccent),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'System Notification Hub',
                          style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _unreadNotifications > 0 ? 'You have $_unreadNotifications unread tracking updates' : 'No pending tracking alerts right now',
                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_outlined, size: 20, color: Colors.white30),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ===================== UNIFIED SUB-TAB LAYOUT MANAGER =====================
  Widget _buildHelpCenter() {
    return Column(
      children: [
        Container(
          color: kNavyMid,
          child: TabBar(
            controller: _helpTabController,
            labelColor: kPinkBright,
            unselectedLabelColor: Colors.white38,
            indicatorColor: kPinkBright,
            indicatorWeight: 3,
            tabs: const [
              Tab(icon: Icon(Icons.send_outlined), text: 'New Request'),
              Tab(icon: Icon(Icons.assignment_outlined), text: 'Track Requests'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _helpTabController,
            children: const [
              BlindSendHelpRequestScreen(),
              BlindTrackRequestsScreen(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLiveLocationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.location_on, color: kPurpleAccent, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Live Location',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(radius: 3.5, backgroundColor: Colors.greenAccent),
                    SizedBox(width: 6),
                    Text('Live', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          const Text('You are currently at:', style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 2),
          const Text(
            'Pulai, Iskandar Puteri, Johor',
            style: TextStyle(color: kBlueAccent, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: kNavyDeep.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.07,
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6),
                        itemBuilder: (_, __) => Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 25,
                    left: 30,
                    child: Text('TAMAN\nUNIVERSITI', style: TextStyle(color: Colors.white12, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const Positioned(
                    top: 30,
                    right: 40,
                    child: Text('ISKANDAR\nPUTERI', style: TextStyle(color: Colors.white12, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(radius: 18, backgroundColor: kBlueAccent.withValues(alpha: 0.2)),
                            const CircleAvatar(radius: 6, backgroundColor: Colors.white),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: kBlueAccent, borderRadius: BorderRadius.circular(8)),
                          child: const Text('You are here', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Column(
                      children: [
                        _buildMapMiniButton(Icons.add),
                        const SizedBox(height: 4),
                        _buildMapMiniButton(Icons.remove),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMapMetaItem(Icons.gps_fixed, 'Accuracy', 'High (15m)'),
              _buildMapMetaItem(Icons.access_time, 'Last Updated', 'Just now'),
              _buildMapMetaItem(Icons.share, 'Shared with', '3 volunteers', isAccent: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapMiniButton(IconData icon) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: kNavyMid.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Icon(icon, color: Colors.white70, size: 16),
    );
  }

  Widget _buildMapMetaItem(IconData icon, String label, String value, {bool isAccent = false}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: isAccent ? Colors.greenAccent : Colors.white38),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            Text(
              value,
              style: TextStyle(
                color: isAccent ? Colors.greenAccent : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVoiceWaveBars({required bool reversed, required bool compact}) {
    final heights = compact ? [8.0, 14.0, 20.0, 14.0, 8.0] : [14.0, 26.0, 42.0, 28.0, 12.0];
    final barList = heights.map((h) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        width: 3.5,
        height: _isListening ? h : 6.0,
        decoration: BoxDecoration(
          color: _isListening ? kBlueAccent : Colors.white12,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }).toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: reversed ? barList.reversed.toList() : barList,
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
      color: kCardFill.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTapOverride ?? () => _onNavBarTap(index),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
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