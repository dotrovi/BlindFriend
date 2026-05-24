import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'blind_send_help_request.dart';
import 'blind_track_help_request.dart';

class BrowseVolunteersPage extends StatefulWidget {
  const BrowseVolunteersPage({super.key});

  @override
  State<BrowseVolunteersPage> createState() => _BrowseVolunteersPageState();
}

class _BrowseVolunteersPageState extends State<BrowseVolunteersPage> {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isLoading = true;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  bool _gotResult = false;
  bool _cancelledBySpeech = false;
  bool _reaskScheduled = false;

  int _speakGeneration = 0;

  Position? _userPosition;
  List<Map<String, dynamic>> _volunteers = [];
  Map<String, dynamic>? _selectedVolunteer;

  static const double _maxDistanceKm = 50.0;

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
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------------------

  Future<void> _init() async {
    await _initTts();
    await _initStt();
    await _fetchLocation();
    await _fetchVolunteers();
    await _speakPageSummary();
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
  // LOCATION
  // ---------------------------------------------------------------------------

  Future<void> _fetchLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _userPosition = position;
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // FETCH VOLUNTEERS
  // ---------------------------------------------------------------------------

  Future<void> _fetchVolunteers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('volunteers')
          .get();

      final List<Map<String, dynamic>> nearby = [];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final geoPoint = data['location'] as GeoPoint?;
        if (geoPoint == null) continue;

        double distanceKm = 0;
        if (_userPosition != null) {
          distanceKm = _calculateDistanceKm(
            _userPosition!.latitude,
            _userPosition!.longitude,
            geoPoint.latitude,
            geoPoint.longitude,
          );
          if (distanceKm > _maxDistanceKm) continue;
        }

        String name = data['name'] ?? '';
        if (name.isEmpty) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(doc.id)
              .get();
          name = userDoc.data()?['name'] ?? 'Unknown';
        }

        nearby.add({
          ...data,
          'uid': doc.id,
          'name': name,
          'distanceKm': distanceKm,
        });
      }

      nearby.sort((a, b) =>
          (a['distanceKm'] as double).compareTo(b['distanceKm'] as double));

      if (mounted) {
        setState(() {
          _volunteers = nearby;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch volunteers error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _calculateDistanceKm(
      double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  // ---------------------------------------------------------------------------
  // VOICE — same pattern as login_page.dart
  // ---------------------------------------------------------------------------

  Future<void> _speak(String text) async {
    final myGen = ++_speakGeneration;
    _cancelledBySpeech = true;

    // Stop STT and TTS before speaking
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

  // Reasks if STT didn't get a result — same as login page
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
        _speak(
          _selectedVolunteer != null
              ? 'Say request help to confirm, or go back to choose another.'
              : 'Say volunteer followed by a number to select a volunteer, or repeat to hear the list.',
        );
      }
    });
  }

  // Called when mic button is tapped — same as login page
  Future<void> _pressToSpeak() async {
    if (!_sttAvailable || !_shouldListen || _isSpeaking) return;
    if (!_stt.isListening) await _startListening();
  }

  Future<void> _startListening() async {
    if (!_sttAvailable || !mounted || !_shouldListen || _stt.isListening)
      return;

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

  Future<void> _speakPageSummary() async {
    if (_volunteers.isEmpty) {
      await _speak(
        'No volunteers found near you right now. '
        'Say track requests to view your existing requests, '
        'or say go back to return.',
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.write(
      '${_volunteers.length} volunteer${_volunteers.length > 1 ? 's' : ''} found near you. ',
    );

    for (int i = 0; i < _volunteers.length; i++) {
      final v = _volunteers[i];
      final name = v['name'] ?? 'Unknown';
      final distance = (v['distanceKm'] as double).toStringAsFixed(1);
      final specialties = List<String>.from(v['specialties'] ?? []);
      final specialty =
          specialties.isNotEmpty ? specialties.first : 'General help';
      buffer.write(
        'Volunteer ${i + 1}: $name, $distance kilometres away, specialises in $specialty. ',
      );
    }

    buffer.write(
      'Say a number to select a volunteer, '
      'say track requests to view your requests, '
      'or say go back to return.',
    );

    await _speak(buffer.toString());
  }

  Future<void> _processCommand(String command) async {
    debugPrint('🎤 RAW COMMAND HEARD: "$command"');
    if (command.isEmpty) return;

    // Number selection — check first
    final numberMap = {
      'one': 1, 'first': 1,
      'two': 2, 'second': 2,
      'three': 3, 'third': 3,
      'four': 4, 'fourth': 4,
      'five': 5, 'fifth': 5,
      'six': 6, 'seventh': 6,
      'seven': 7, 'sixth': 7,
      'eight': 8, 'eighth': 8,
      'nine': 9, 'ninth': 9,
      'ten': 10, 'tenth': 10,
    };

    // Check word numbers
    for (final entry in numberMap.entries) {
      if (command.contains(entry.key)) {
        final index = entry.value - 1;
        if (index >= 0 && index < _volunteers.length) {
          await _selectVolunteer(index);
          return;
        }
      }
    }

    // Check digit numbers e.g. "volunteer 1", "number 1"
    final digitMatch = RegExp(r'\b(\d+)\b').firstMatch(command);
    if (digitMatch != null) {
      final number = int.tryParse(digitMatch.group(1) ?? '');
      if (number != null && number >= 1 && number <= _volunteers.length) {
        await _selectVolunteer(number - 1);
        return;
      }
    }

    // Selected volunteer — confirm or cancel
    if (_selectedVolunteer != null) {
      if (command.contains('request help') || command.contains('confirm')) {
        await _navigateToRequestHelp(_selectedVolunteer!);
        return;
      }
      if (command.contains('cancel')) {
        setState(() => _selectedVolunteer = null);
        await _speak('Selection cancelled. Say a number to select a volunteer.');
        return;
      }
    }

    // Track requests
    if (command.contains('track') ||
        (command.contains('my') && command.contains('request'))) {
      _shouldListen = false;
      await _speak('Opening your help requests.');
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BlindTrackRequestsScreen()),
      );
      _shouldListen = true;
      await _speak('Back on volunteers page. Tap the mic to speak.');
      return;
    }

    // Repeat
    if (command.contains('repeat') || command.contains('list')) {
      await _speakPageSummary();
      return;
    }

    // Go back
    if (command.contains('back')) {
      await _speak('Going back.');
      if (mounted) Navigator.pop(context);
      return;
    }

    await _speak(
      'Command not recognised. '
      'Say a volunteer followed by a number to select a volunteer, '
      'repeat to hear the list again, '
      'track requests to view your requests, '
      'or go back to return.',
    );
  }

  Future<void> _selectVolunteer(int index) async {
    final v = _volunteers[index];
    setState(() => _selectedVolunteer = v);

    final name = v['name'] ?? 'Unknown';
    final distance = (v['distanceKm'] as double).toStringAsFixed(1);
    final specialties = List<String>.from(v['specialties'] ?? []);
    final languages = List<String>.from(v['language'] ?? []);

    await _speak(
      'You selected $name, $distance kilometres away. '
      'Specialties: ${specialties.join(', ')}. '
      'Languages: ${languages.join(', ')}. '
      'Say request help to send a request, '
      'or say go back to choose another volunteer.',
    );
  }

  Future<void> _navigateToRequestHelp(Map<String, dynamic> volunteer) async {
    _shouldListen = false;
    await _speak('Opening help request form for ${volunteer['name']}.');
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BlindSendHelpRequestScreen()),
    );
    _shouldListen = true;
    if (mounted) await _speak('Back on volunteers page. Tap the mic to speak.');
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Nearby Volunteers'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _speak('Going back.');
            if (mounted) Navigator.pop(context);
          },
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.green),
                  SizedBox(height: 16),
                  Text('Finding volunteers near you...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildVoiceBar(),
                  const SizedBox(height: 16),
                  _buildTrackRequestsCard(),
                  const SizedBox(height: 24),
                  Text(
                    _volunteers.isEmpty
                        ? 'No volunteers nearby'
                        : '${_volunteers.length} volunteer${_volunteers.length > 1 ? 's' : ''} found nearby',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  if (_volunteers.isEmpty)
                    _buildEmptyState()
                  else
                    ...List.generate(
                      _volunteers.length,
                      (i) => _buildVolunteerCard(i, _volunteers[i]),
                    ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // VOICE BAR — full screen tap like login page
  // ---------------------------------------------------------------------------

  Widget _buildVoiceBar() {
    return GestureDetector(
      onTap: _pressToSpeak,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isListening
                ? [const Color(0xFF27AE60), const Color(0xFF2ECC71)]
                : _isSpeaking
                    ? [const Color(0xFF6C3483), const Color(0xFF9B59B6)]
                    : [const Color(0xFF4A90E2), const Color(0xFF9B59B6)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
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
                size: 36,
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
                    _isSpeaking
                        ? 'Please wait...'
                        : _isListening
                            ? 'Say volunteer followed by a number or a command'
                            : 'Say volunteer followed by a number, "repeat", or "go back"',
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

  // ---------------------------------------------------------------------------
  // TRACK REQUESTS CARD
  // ---------------------------------------------------------------------------

  Widget _buildTrackRequestsCard() {
    return GestureDetector(
      onTap: () async {
        _shouldListen = false;
        await _speak('Opening your help requests.');
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BlindTrackRequestsScreen()),
        );
        _shouldListen = true;
        await _speak('Back on volunteers page.');
      },
      child: Container(
        padding: const EdgeInsets.all(16),
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.track_changes,
                  color: Colors.orange, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Track My Requests',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'View status of your help requests',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VOLUNTEER CARD
  // ---------------------------------------------------------------------------

  Widget _buildVolunteerCard(int index, Map<String, dynamic> volunteer) {
    final name = volunteer['name'] ?? 'Unknown';
    final distance =
        (volunteer['distanceKm'] as double).toStringAsFixed(1);
    final specialties =
        List<String>.from(volunteer['specialties'] ?? []);
    final languages = List<String>.from(volunteer['language'] ?? []);
    final address = volunteer['locationAddress'] ?? '';
    final isSelected = _selectedVolunteer?['uid'] == volunteer['uid'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            isSelected ? Border.all(color: Colors.green, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      if (address.isNotEmpty)
                        Text(
                          address,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    '$distance km',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (specialties.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    specialties.map((s) => _chip(s, Colors.blue)).toList(),
              ),
              const SizedBox(height: 8),
            ],
            if (languages.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: languages
                    .map((l) => _chip(l, Colors.purple))
                    .toList(),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.volunteer_activism, size: 18),
                label: const Text('Request Help'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                onPressed: () => _navigateToRequestHelp(volunteer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color.withOpacity(0.8),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'No volunteers nearby',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            'There are no available volunteers within 50km right now. Please try again later.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}