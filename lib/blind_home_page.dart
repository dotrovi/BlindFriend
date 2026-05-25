import 'dart:async';

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
import 'obstacle_detection_page.dart';

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
  DateTime? _pressStartTime;

  // Track if voice is currently processing to prevent duplicates
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

    _sttAvailable =
        micStatus.isGranted &&
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
        'Welcome to BlindFriend, ${widget.userName}. '
        'Tap the voice button and say: Shopping, Obstacle, Path, Request Help, Track Requests, Volunteers, '
        'Profile, or Logout. For emergency, press and hold the voice button.',
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

  void _onTapDown(TapDownDetails details) {
    _pressStartTime = DateTime.now();
  }

  void _onTapUp(TapUpDetails details) {
    final pressDuration = DateTime.now().difference(
      _pressStartTime ?? DateTime.now(),
    );
    if (pressDuration >= const Duration(seconds: 3)) {
      // Long press - Emergency
      _handleEmergency();
    } else {
      // Short tap - Voice command
      if (!_isProcessingVoice && _sttAvailable && !_isSpeaking) {
        _startListening();
      }
    }
    _pressStartTime = null;
  }

  Future<void> _handleEmergency() async {
    if (_isProcessingVoice) return;
    _isProcessingVoice = true;

    await _speak(
      'Emergency! Calling emergency services. Please stay calm. Help is on the way.',
    );

    // In production, you would integrate with device's emergency call feature
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Emergency'),
          content: const Text(
            'Emergency services have been notified. Stay where you are.',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _isProcessingVoice = false;
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    _isProcessingVoice = false;
  }

  Future<void> _startListening() async {
    if (!_sttAvailable || !mounted || !_shouldListen || _stt.isListening)
      return;

    setState(() => _isListening = true);
    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.finalResult) {
          _processCommand(result.recognizedWords.toLowerCase());
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 2),
      localeId: 'en_US',
    );
  }

  Future<void> _processCommand(String command) async {
    if (_isProcessingVoice) return;
    _isProcessingVoice = true;

    if (command.contains('Shopping') || command.contains('scan')) {
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
      await _speak('Opening your help requests. Here are your recent requests.');
      _navigateToTrackRequests();
    } else if (command.contains('volunteer') || command.contains('help')) {
      await _speak('Finding volunteers. You can request help or track your requests.');
      _setSelectedIndex(4);
    } else if (command.contains('home') || command.contains('dashboard')) {
      await _speak('Returning to home page.');
      _setSelectedIndex(0);
    } else if (command.contains('profile')) {
      _shouldListen = false;
      await _speak('Opening your profile.');
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const UserProfilePage()),
      );
      _shouldListen = true;
      await _speak('Back on home page. Tap the voice button to speak.');
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

  @override
  void dispose() {
    _shouldListen = false;
    _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SafeArea(
        child: Column(
          children: [
            // Top Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BlindFriend',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      Text(
                        'Welcome, ${widget.userName}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () async {
                          _shouldListen = false;
                          await _speak('Opening your profile.');
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const UserProfilePage(),
                            ),
                          );
                          _shouldListen = true;
                        },
                        icon: const Icon(Icons.person, size: 28),
                        color: Colors.blue,
                      ),
                      IconButton(
                        onPressed: () async {
                          print("🔴 Logout button pressed");
                          try {
                            await _tts.stop();
                            await _tts.speak(
                              'Logging out. Goodbye, ${widget.userName}.',
                            );
                            await Future.delayed(
                              const Duration(milliseconds: 800),
                            );

                            print("🔴 Signing out from Firebase");
                            await FirebaseAuth.instance.signOut();

                            print("🔴 Navigating to LoginPage");
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
                            print("🔴 Logout error: $e");
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
                        icon: const Icon(Icons.logout, size: 28),
                        color: Colors.red,
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
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: _onNavBarTap,
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.white,
                selectedItemColor: Colors.blue,
                unselectedItemColor: Colors.grey,
                selectedFontSize: 12,
                unselectedFontSize: 12,
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
          // Voice Command Button
          GestureDetector(
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isListening
                      ? [Colors.green, Colors.lightGreen]
                      : [Colors.blue, Colors.blue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      key: ValueKey(_isListening),
                      color: Colors.white,
                      size: 64,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isListening ? 'Listening...' : 'Tap to Speak',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Press and hold for 3 seconds for Emergency',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Feature Cards
          _buildFeatureCard(
            icon: Icons.qr_code_scanner,
            title: 'Shopping Helper',
            description: 'Scan barcodes and get audio feedback',
            color: Colors.purple,
            index: 1,
          ),
          _buildFeatureCard(
            icon: Icons.warning_amber,
            title: 'Obstacle Detection',
            description: 'Real-time voice alerts for obstacles',
            color: Colors.orange,
            index: 2,
          ),
          _buildFeatureCard(
            icon: Icons.map_outlined,
            title: 'Path Detection',
            description: 'Tactile path guidance recognition',
            color: Colors.teal,
            index: 3,
          ),
          _buildFeatureCard(
            icon: Icons.people_alt,
            title: 'Find Volunteers',
            description: 'Get help from verified volunteers nearby',
            color: Colors.green,
            index: 4,
          ),

          const SizedBox(height: 16),

          // Emergency Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(
              children: [
                const Icon(Icons.emergency, size: 32, color: Colors.red),
                const SizedBox(height: 8),
                const Text(
                  'Emergency Contact',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Press and hold the voice command button for 3 seconds',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _handleEmergency,
                  icon: const Icon(Icons.call),
                  label: const Text('Call Emergency Services'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Voice Commands List
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Voice Commands',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                _buildCommandTile('Shopping', 'Open shopping helper'),
                _buildCommandTile('Obstacle', 'Start obstacle detection'),
                _buildCommandTile('Path', 'Activate path detection'),
                _buildCommandTile('Request Help', 'Send a new help request'),
                _buildCommandTile('Track Requests', 'View your request status'),
                _buildCommandTile('Volunteers or Help', 'Find volunteers nearby'),
                _buildCommandTile('Profile', 'Open your profile'),
                _buildCommandTile('Logout', 'Sign out'),
              ],
            ),
          ),
          const SizedBox(height: 80), // Bottom padding for nav bar
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required int index,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          description,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _setSelectedIndex(index),
      ),
    );
  }

  Widget _buildCommandTile(String command, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              command,
              style: TextStyle(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  // ===================== SHOPPING HELPER PAGE =====================
  Widget _buildShoppingHelper() {
    return const ShoppingHelperPage();
  }

  // ===================== OBSTACLE DETECTION PAGE =====================
  Widget _buildObstacleDetection() {
    return const ObstacleDetectionPage();
  }

  // ===================== PATH DETECTION PAGE =====================
  Widget _buildPathDetection() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.teal.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.map_outlined,
                size: 80,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Path Detection',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tactile path guidance recognition for safe navigation.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                _speak('Starting path detection. Follow the voice guidance.');
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Navigation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
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
              gradient: LinearGradient(
                colors: [Colors.green.shade700, Colors.green.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.people_alt, color: Colors.white, size: 28),
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
                          color: Colors.white.withOpacity(0.8),
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
            color: Colors.blue,
            onTap: _navigateToSendHelpRequest,
          ),
          const SizedBox(height: 16),

          // Track Requests Button
          _buildHelpActionCard(
            icon: Icons.track_changes,
            title: 'Track My Requests',
            description: 'View status of your help requests',
            color: Colors.orange,
            onTap: _navigateToTrackRequests,
          ),
          const SizedBox(height: 16),

          // Information Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.green.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'When you request help, nearby volunteers will be notified and can respond to your request. You can track the status in real-time.',
                    style: TextStyle(fontSize: 14, color: Colors.green.shade700),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                    color: color.withOpacity(0.1),
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
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}