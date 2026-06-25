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
import 'blind_send_help_request.dart'; // Add this import
import 'blind_track_help_request.dart'; // Add this import
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
  int _selectedIndex = 0; // 0=Home, 1=Shopping, 2=Obstacles, 3=Path, 4=Help

  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  int _speakGeneration = 0;

  // Track if voice is currently processing to prevent duplicates
  bool _isProcessingVoice = false;

  StreamSubscription? _unreadNotificationsSub;
  int _unreadNotifications = 0;

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
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BlindNotificationsPage()),
    );
    _shouldListen = true;
    if (mounted) {
      await _speak('Back on home page. Tap the voice button to speak.');
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
    print(
        '🎤 Mic permission status: $micStatus (granted=${micStatus.isGranted})');
    if (!mounted) return;

    final sttInitialized = await _stt.initialize(
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
    print('🎤 STT initialize result: $sttInitialized');
    _sttAvailable = micStatus.isGranted && sttInitialized;
    print('🎤 _sttAvailable: $_sttAvailable');

    if (mounted) {
      await _speak(
        'Welcome to BlindFriend, ${widget.userName}. '
        'Tap the voice button and say: Shopping, Obstacle, Path, Request Help, Track Requests, Volunteers, '
        'Profile, Settings, Notifications, or Logout.',
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
    await completer.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {},
    );

    if (mounted) setState(() => _isSpeaking = false);
  }

  void _onVoiceButtonTap() {
    if (!_isProcessingVoice && _sttAvailable && !_isSpeaking) {
      _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_sttAvailable || !mounted || !_shouldListen || _stt.isListening) {
      return;
    }

    setState(() => _isListening = true);
    await _stt.listen(
      onResult: (result) async {
        if (!mounted) return;
        if (result.finalResult) {
          await _processCommand(result.recognizedWords.toLowerCase());
          // Loop only while on Help Center tab — reuses _selectedIndex.
          if (_selectedIndex == 4 &&
              _shouldListen &&
              mounted &&
              !_stt.isListening) {
            await _startListening();
          }
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 10),
      localeId: 'en_US',
    );
  }

  Future<void> _processCommand(String command) async {
    if (_isProcessingVoice) return;
    _isProcessingVoice = true;

    if (command.contains('shopping') || command.contains('scan')) {
      await _speak('Opening shopping helper. Barcode scanner activated.');
      _setSelectedIndex(1);
    } else if (command.contains('obstacle')) {
      await _speak('Obstacle detection. Real-time voice alerts for obstacles.');
      _setSelectedIndex(2);
    } else if (command.contains('path') || command.contains('navigation')) {
      await _speak('Path detection. Tactile path guidance recognition.');
      _setSelectedIndex(3);
    } else if (command.contains('request help') ||
        (command.contains('send') && command.contains('help'))) {
      await _speak('Opening request help page. Please describe your need.');
      _navigateToSendHelpRequest();
    } else if (command.contains('track') && command.contains('request')) {
      await _speak(
          'Opening your help requests. Here are your recent requests.');
      _navigateToTrackRequests();
    } else if (command.contains('volunteer') || command.contains('help')) {
      await _speak(
          'Finding volunteers. You can request help or track your requests.');
      _setSelectedIndex(4);
    } else if (command.contains('home') || command.contains('dashboard')) {
      await _speak('Returning to home page.');
      _setSelectedIndex(0);
    } else if (command.contains('profile')) {
      _shouldListen = false;
      _speak('Opening your profile.');
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const UserProfilePage()),
      );
      _shouldListen = true;
      _speak('Back on home page. Tap the voice button to speak.');
    } else if (command.contains('setting') ||
        command.contains('accessibility') ||
        command.contains('contrast') ||
        command.contains('font')) {
      _speak('Opening accessibility settings.');
      await _navigateToAccessibilitySettings();
    } else if (command.contains('notification')) {
      await _speak('Opening your notifications.');
      _navigateToNotifications();
    } else if (command.contains('logout') || command.contains('sign out')) {
      _shouldListen = false;
      await _speak('Logging out. Goodbye, ${widget.userName}.');
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
      return;
    } else if (command.contains('repeat') || command.contains('commands')) {
      await _speak(
        'You can say: Shopping to scan barcodes. '
        'Obstacle for obstacle detection. '
        'Path for path detection. '
        'Request Help to send a new help request. '
        'Track Requests to see your request status. '
        'Volunteers to find help nearby. '
        'Profile to view your account. '
        'Settings to adjust font size and contrast. '
        'Notifications to check your updates. '
        'Or Logout to sign out.',
      );
    } else {
      await _speak(
        'Command not recognized. Say Repeat to hear available commands.',
      );
    }

    _isProcessingVoice = false;
  }

  void _setSelectedIndex(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _openHelpCenter() async {
    _setSelectedIndex(4);
    await _speak(
      'Help center. Say Request Help to send a new request, '
      'or say Track Requests to see your existing requests.',
    );
    // Reuse existing listening — just open the mic after speaking.
    if (_sttAvailable && _shouldListen && mounted && !_stt.isListening) {
      await _startListening();
    }
  }

  void _onNavBarTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Speak the page name
    String pageName = '';
    switch (index) {
      case 0:
        pageName = 'Home';
        break;
      case 1:
        pageName = 'Shopping Helper';
        break;
      case 2:
        pageName = 'Obstacle Detection';
        break;
      case 3:
        pageName = 'Path Detection';
        break;
      case 4:
        pageName = 'Help Center';
        break;
    }
    _speak('Opened $pageName page');
  }

  void _navigateToSendHelpRequest() async {
    _shouldListen = false;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BlindSendHelpRequestScreen()),
    );
    _shouldListen = true;
    if (mounted) {
      await _speak('Back on help center page.');
    }
  }

  void _navigateToTrackRequests() async {
    _shouldListen = false;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BlindTrackRequestsScreen()),
    );
    _shouldListen = true;
    if (mounted) {
      await _speak('Back on help center page.');
    }
  }

  Future<void> _navigateToAccessibilitySettings() async {
    if (!mounted) return;
    _shouldListen = false;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccessibilitySettingsPage()),
    );
    _shouldListen = true;
    if (mounted) {
      await _speak('Back on home page. Tap the voice button to speak.');
    }
  }

  @override
  void dispose() {
    _shouldListen = false;
    _stt.stop();
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
                        onPressed: () async {
                          _shouldListen = false;
                          _speak('Opening your profile.');
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const UserProfilePage(),
                            ),
                          );
                          _shouldListen = true;
                        },
                      ),
                      _headerIconButton(
                        icon: Icons.accessibility_new,
                        color: kPurpleAccent,
                        tooltip: 'Accessibility Settings',
                        onPressed: () {
                          _shouldListen = false;
                          _speak('Opening accessibility settings.');
                          _navigateToAccessibilitySettings();
                        },
                      ),
                      _headerIconButton(
                        icon: Icons.logout,
                        color: kRedAccent,
                        onPressed: () async {
                          try {
                            await _tts.stop();
                            await _tts.speak(
                              'Logging out. Goodbye, ${widget.userName}.',
                            );
                            await Future.delayed(
                              const Duration(milliseconds: 800),
                            );

                            await FirebaseAuth.instance.signOut();

                            // Force navigation to login page
                            if (mounted) {
                              Navigator.of(
                                context,
                              ).popUntil((route) => route.isFirst);
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => const LoginPage(),
                                ),
                              );
                            }
                          } catch (e) {
                            // Force navigation even on error
                            if (mounted) {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => const LoginPage(),
                                ),
                              );
                            }
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
                  _buildFindVolunteers(),
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
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.qr_code_scanner),
                    label: 'Shopping',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.warning),
                    label: 'Obstacles',
                  ),
                  BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Path'),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.people),
                    label: 'Help',
                  ),
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
          // Voice Command Card
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
                  color: (_isListening ? Colors.greenAccent : kPinkBright)
                      .withValues(alpha: 0.4),
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
                          ? const LinearGradient(
                              colors: [Colors.green, Colors.lightGreen],
                            )
                          : kAccentGradient,
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening ? Colors.green : kPinkBright)
                              .withValues(alpha: 0.5),
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
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

          // Feature Cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.qr_code_scanner,
                  title: 'Shopping Helper',
                  description: 'Scan barcodes and get audio feedback',
                  color: kPurpleAccent,
                  index: 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.warning_amber,
                  title: 'Obstacle Detection',
                  description: 'Real-time voice alerts for obstacles',
                  color: kAmberAccent,
                  index: 2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.map_outlined,
                  title: 'Path Detection',
                  description: 'Tactile path guidance recognition',
                  color: kTealAccent,
                  index: 3,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.people_alt,
                  title: 'Find Volunteers',
                  description: 'Get help from verified volunteers nearby',
                  color: kTealAccent,
                  index: 4,
                  onTapOverride: _openHelpCenter,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Notifications Section
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
              child: Stack(
                children: [
                  Positioned(
                    right: -10,
                    top: 0,
                    bottom: 0,
                    child: Icon(
                      Icons.notifications_outlined,
                      size: 70,
                      color: kBlueAccent.withValues(alpha: 0.12),
                    ),
                  ),
                  Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kBlueAccent.withValues(alpha: 0.18),
                              boxShadow: [
                                BoxShadow(
                                  color: kBlueAccent.withValues(alpha: 0.4),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.notifications,
                              size: 28,
                              color: kBlueAccent,
                            ),
                          ),
                          if (_unreadNotifications > 0)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: kPinkBright,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                child: Text(
                                  '$_unreadNotifications',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Notifications',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _unreadNotifications > 0
                                  ? '$_unreadNotifications new update${_unreadNotifications == 1 ? '' : 's'} on your requests'
                                  : 'No new updates right now',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.white38,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Voice Commands Grid
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kCardFill.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.graphic_eq, color: kPinkBright, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Voice Commands',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildCommandTile(Icons.shopping_cart, kBlueAccent,
                        'Shopping', 'Open shopping helper'),
                    _buildCommandTile(Icons.warning_amber, kAmberAccent,
                        'Obstacle', 'Start obstacle detection'),
                    _buildCommandTile(Icons.map, kTealAccent, 'Path',
                        'Activate path detection'),
                    _buildCommandTile(Icons.chat_bubble_outline, kPurpleAccent,
                        'Request Help', 'Send a new help request'),
                    _buildCommandTile(Icons.list_alt, kTealAccent,
                        'Track Requests', 'View your request status'),
                    _buildCommandTile(Icons.people_alt, kTealAccent,
                        'Volunteers or Help', 'Find volunteers nearby'),
                    _buildCommandTile(Icons.person, kBlueAccent, 'Profile',
                        'Open your profile'),
                    _buildCommandTile(
                        Icons.logout, kRedAccent, 'Logout', 'Sign out'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 80), // Bottom padding for nav bar
        ],
      ),
    );
  }

  Widget _buildVoiceWaveBars({required bool reversed, required bool compact}) {
    final heights = compact
        ? [6.0, 10.0, 14.0, 10.0, 6.0]
        : [10.0, 18.0, 28.0, 20.0, 30.0, 16.0, 10.0];
    final active = _isListening;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: heights
          .map(
            (h) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: active ? h : h * 0.55,
              decoration: BoxDecoration(
                color: kBlueAccent.withValues(alpha: active ? 0.9 : 0.4),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          )
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
        onTap: onTapOverride ?? () => _setSelectedIndex(index),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: Colors.white38,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommandTile(
      IconData icon, Color color, String command, String description) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  command,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===================== SHOPPING HELPER PAGE =====================
  Widget _buildShoppingHelper() {
    return ShoppingHelperPage(onBackToHome: () => _setSelectedIndex(0));
  }

  // ===================== OBSTACLE DETECTION PAGE =====================
  Widget _buildObstacleDetection() {
    return ObstacleDetectionPage(onBackToHome: () => _setSelectedIndex(0));
  }

  // ===================== PATH DETECTION PAGE =====================
  Widget _buildPathDetection() {
    return TactilePathPage(onBackToHome: () => _setSelectedIndex(0));
  }

  // ===================== FIND VOLUNTEERS PAGE (UPDATED) =====================
  Widget _buildFindVolunteers() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
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
                  child: const Icon(Icons.people_alt,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Help Center',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Get help from verified volunteers',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Request Help Button
          _buildHelpActionCard(
            icon: Icons.add_circle_outline,
            title: 'Request Help',
            description: 'Send a new help request to nearby volunteers',
            color: kBlueAccent,
            onTap: _navigateToSendHelpRequest,
          ),
          const SizedBox(height: 16),

          // Track Requests Button
          _buildHelpActionCard(
            icon: Icons.track_changes,
            title: 'Track My Requests',
            description: 'View status of your help requests',
            color: kAmberAccent,
            onTap: _navigateToTrackRequests,
          ),
          const SizedBox(height: 16),

          // Information Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kTealAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kTealAccent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: kTealAccent),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'When you request help, nearby volunteers will be notified and can respond to your request. You can track the status in real-time.',
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80), // Bottom padding
        ],
      ),
    );
  }

  Widget _buildHelpActionCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
