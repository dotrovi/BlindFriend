import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'login_page.dart';
import 'volunteer_profile_page.dart';
import 'volunteer_received_request.dart';
import 'services/firebase_service.dart';

class VolunteerHomePage extends StatefulWidget {
  final String userName;
  const VolunteerHomePage({super.key, required this.userName});

  @override
  State<VolunteerHomePage> createState() => _VolunteerHomePageState();
}

class _VolunteerHomePageState extends State<VolunteerHomePage> {
  int _selectedIndex = 0; // 0=Home, 1=Requests, 2=Profile

  // Voice
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  int _speakGeneration = 0;
  DateTime? _pressStartTime;
  bool _isProcessingVoice = false;

  // Location & availability
  final FirebaseService _firebaseService = FirebaseService();
  bool _isAvailable = true;
  bool _isUpdatingLocation = false;
  bool _isTogglingAvailability = false;
  String _locationText = 'Not set';
  DateTime? _locationLastUpdated;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _initVoice();
    _checkVolunteerStatus();
    _loadVolunteerData();
  }

  // ── Voice ──────────────────────────────────────────────────────────────

  Future<void> _checkVolunteerStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('volunteers')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final status = doc.data()?['status'] ?? 'pending';
        if (status == 'approved') {
          await _speak(
              'Welcome volunteer ${widget.userName}. Your account is approved. You can now help blind users.');
        } else if (status == 'pending') {
          await _speak(
              'Welcome ${widget.userName}. Your volunteer application is pending approval. You will be notified once approved.');
        } else if (status == 'rejected') {
          await _speak(
              'Welcome ${widget.userName}. Your application was rejected. Please contact support.');
        }
      }
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
        'Welcome to BlindFriend Volunteer Portal, ${widget.userName}. '
        'Tap the voice button and say: Help Requests, Profile, or Logout. '
        'For emergency, press and hold the voice button.',
      );
    }
  }

  Future<void> _speak(String text) async {
    final myGen = ++_speakGeneration;
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
      if (!completer.isCompleted) completer.complete();
    });
    await _tts.speak(text);
    await completer.future.timeout(const Duration(seconds: 90), onTimeout: () {});
    if (mounted) setState(() => _isSpeaking = false);
  }

  void _onTapDown(TapDownDetails details) {
    _pressStartTime = DateTime.now();
  }

  void _onTapUp(TapUpDetails details) {
    final pressDuration =
        DateTime.now().difference(_pressStartTime ?? DateTime.now());
    if (pressDuration >= const Duration(seconds: 3)) {
      _handleEmergency();
    } else {
      if (!_isProcessingVoice && _sttAvailable && !_isSpeaking) {
        _startListening();
      }
    }
    _pressStartTime = null;
  }

  Future<void> _handleEmergency() async {
    if (_isProcessingVoice) return;
    _isProcessingVoice = true;
    await _speak('Emergency! Calling emergency services. Please stay calm.');
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Emergency'),
          content: const Text('Emergency services have been notified.'),
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
    if (!_sttAvailable || !mounted || !_shouldListen || _stt.isListening) {
      return;
    }
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

    if (command.contains('help') && command.contains('request')) {
      await _speak('Opening help requests. Here are requests from blind users.');
      _setSelectedIndex(1);
    } else if (command.contains('profile')) {
      _shouldListen = false;
      await _speak('Opening your profile.');
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const VolunteerProfilePage()),
      );
      _shouldListen = true;
      await _speak('Back on volunteer home page.');
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
    } else if (command.contains('home') || command.contains('dashboard')) {
      await _speak('Returning to home page.');
      _setSelectedIndex(0);
    } else if (command.contains('repeat') || command.contains('commands')) {
      await _speak(
        'You can say: Help Requests to view incoming requests. '
        'Profile to view your account. '
        'Or Logout to sign out.',
      );
    } else {
      await _speak(
          'Command not recognized. Say Repeat to hear available commands.');
    }

    _isProcessingVoice = false;
  }

  void _setSelectedIndex(int index) {
    setState(() => _selectedIndex = index);
    final pageName =
        index == 0 ? 'Home' : index == 1 ? 'Help Requests' : 'Profile';
    _speak('Opened $pageName page');
  }

  // ── Location & availability ────────────────────────────────────────────

  Future<void> _loadVolunteerData() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('volunteers')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data == null || !mounted) return;
      final geoPoint = data['location'] as GeoPoint?;
      final updatedAt = data['locationUpdatedAt'] as Timestamp?;
      setState(() {
        _isAvailable = data['isAvailable'] ?? true;
        if (geoPoint != null) {
          _locationText =
              '${geoPoint.latitude.toStringAsFixed(5)}, ${geoPoint.longitude.toStringAsFixed(5)}';
        }
        _locationLastUpdated = updatedAt?.toDate();
      });
    } catch (_) {}
  }

  Future<void> _updateLocation() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _isUpdatingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(permission == LocationPermission.deniedForever
                ? 'Location permission permanently denied. Please enable in Settings.'
                : 'Location permission denied.'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final success = await _firebaseService.updateVolunteerLocation(
        uid: uid,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      if (success) {
        setState(() {
          _locationText =
              '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
          _locationLastUpdated = DateTime.now();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Location updated successfully!'),
          backgroundColor: Colors.green,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to save location. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not get location: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUpdatingLocation = false);
    }
  }

  Future<void> _toggleAvailability() async {
  final uid = _uid;
  if (uid == null) return;
  setState(() => _isTogglingAvailability = true);
  final newValue = !_isAvailable;
  final success = await _firebaseService.updateVolunteerAvailability(
    uid: uid,
    isAvailable: newValue,
  );
  if (!mounted) return;
  if (success) {
    setState(() => _isAvailable = newValue);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newValue
                ? 'You are now Available. Blind users can find you!'
                : 'You are now Unavailable.',
          ),
          backgroundColor: newValue ? Colors.green : Colors.grey,
        ),
      );
    }
  } else {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Failed to update availability. Please try again.'),
      backgroundColor: Colors.red,
    ));
  }
  setState(() => _isTogglingAvailability = false);
}

  String _formatLastUpdated() {
    if (_locationLastUpdated == null) return 'Never updated';
    final diff = DateTime.now().difference(_locationLastUpdated!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  void dispose() {
    _shouldListen = false;
    _stt.stop();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SafeArea(
        child: Column(
          children: [
            // Top Header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
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
                        'BlindFriend - Volunteer',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
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
                          if (!mounted) return;
                          final nav = Navigator.of(context);
                          await nav.push(MaterialPageRoute(
                            builder: (context) => const VolunteerProfilePage(),
                          ));
                          _shouldListen = true;
                        },
                        icon: const Icon(Icons.person, size: 28),
                        color: Colors.green,
                      ),
                      IconButton(
                        onPressed: () async {
                          await _speak(
                              'Logging out. Goodbye, ${widget.userName}.');
                          await FirebaseAuth.instance.signOut();
                          if (mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LoginPage()),
                            );
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
                  const VolunteerReceivedRequestsScreen(),
                  _buildProfilePage(),
                ],
              ),
            ),

            // Bottom Navigation Bar
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: (index) {
                  setState(() => _selectedIndex = index);
                  final pageName = index == 0
                      ? 'Home'
                      : index == 1
                          ? 'Help Requests'
                          : 'Profile';
                  _speak('Opened $pageName page');
                },
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.white,
                selectedItemColor: Colors.green,
                unselectedItemColor: Colors.grey,
                items: const [
                  BottomNavigationBarItem(
                      icon: Icon(Icons.home), label: 'Home'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.help_center), label: 'Help Requests'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.person), label: 'Profile'),
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
      padding: const EdgeInsets.all(24),
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
                      : [Colors.green.shade700, Colors.green.shade500],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withValues(alpha: 0.3),
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
                    _isSpeaking
                        ? 'Speaking...'
                        : _isListening
                            ? 'Listening...'
                            : 'Tap to Speak',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Press and hold 3 seconds for Emergency',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Availability card
          _buildCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_active,
                        color: _isAvailable ? Colors.green : Colors.grey,
                        size: 28),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Availability Status',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(
                          _isAvailable
                              ? 'Accepting requests'
                              : 'Not accepting requests',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                _isTogglingAvailability
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : ElevatedButton(
                        onPressed: _toggleAvailability,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _isAvailable ? Colors.green : Colors.grey,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                            _isAvailable ? 'Available' : 'Unavailable'),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Location card
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: Colors.purple, size: 28),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Your Location',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            Text('Updated: ${_formatLastUpdated()}',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                    _isUpdatingLocation
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                                strokeWidth: 2))
                        : ElevatedButton(
                            onPressed: _updateLocation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Update'),
                          ),
                  ],
                ),
                if (_locationText != 'Not set') ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.gps_fixed,
                            size: 14, color: Colors.purple),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_locationText,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.purple)),
                        ),
                        const Icon(Icons.check_circle,
                            size: 14, color: Colors.green),
                        const SizedBox(width: 4),
                        const Text('Shared',
                            style: TextStyle(
                                fontSize: 12, color: Colors.green)),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Tap Update to share your location with nearby blind users.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Stats
          _buildStatCard(
            title: 'Pending Requests',
            value: '0',
            icon: Icons.pending_actions,
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            title: 'Accepted Requests',
            value: '0',
            icon: Icons.check_circle,
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            title: 'Completed Help',
            value: '0',
            icon: Icons.verified,
            color: Colors.green,
          ),
          const SizedBox(height: 20),

          // Quick Actions
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quick Actions',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        const Icon(Icons.help_center, color: Colors.blue),
                  ),
                  title: const Text('View Help Requests'),
                  trailing:
                      const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _setSelectedIndex(1),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person, color: Colors.green),
                  ),
                  title: const Text('My Profile'),
                  trailing:
                      const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _setSelectedIndex(2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14, color: Colors.grey.shade600)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePage() {
    final user = FirebaseAuth.instance.currentUser;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.green.shade100,
              child: Icon(Icons.volunteer_activism,
                  size: 60, color: Colors.green.shade700),
            ),
            const SizedBox(height: 24),
            Text(
              widget.userName,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              user?.email ?? 'No email',
              style:
                  TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Volunteer',
                  style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                _shouldListen = false;
                await _speak('Opening profile settings.');
                if (!mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const VolunteerProfilePage()),
                );
                _shouldListen = true;
              },
              icon: const Icon(Icons.edit),
              label: const Text('Edit Profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
