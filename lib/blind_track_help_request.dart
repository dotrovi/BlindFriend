import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_blindfriend/blind_rate_volunteer_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'blind_report_volunteer_page.dart';

class HelpRequestModel {
  String? id;
  String blindUserId;
  String blindUserName;
  String blindUserPhone;
  String? volunteerId;
  String? volunteerName;
  String requestType;
  String description;
  String location;
  String status;
  Timestamp createdAt;
  Timestamp? acceptedAt;
  Timestamp? completedAt;
  Timestamp? cancelledAt;
  String? notes;
  String? preferredLanguage;
  int? rating;

  HelpRequestModel({
    this.id,
    required this.blindUserId,
    required this.blindUserName,
    required this.blindUserPhone,
    this.volunteerId,
    this.volunteerName,
    required this.requestType,
    required this.description,
    required this.location,
    required this.status,
    required this.createdAt,
    this.acceptedAt,
    this.completedAt,
    this.cancelledAt,
    this.notes,
    this.preferredLanguage,
    this.rating,
  });

  factory HelpRequestModel.fromMap(String id, Map<String, dynamic> map) {
    return HelpRequestModel(
      id: id,
      blindUserId: map['blindUserId'] ?? '',
      blindUserName: map['blindUserName'] ?? '',
      blindUserPhone: map['blindUserPhone'] ?? '',
      volunteerId: map['volunteerId'],
      volunteerName: map['volunteerName'],
      requestType: map['requestType'] ?? '',
      description: map['description'] ?? '',
      location: map['location'] ?? '',
      status: map['status'] ?? 'pending',
      createdAt: map['createdAt'] ?? Timestamp.now(),
      acceptedAt: map['acceptedAt'],
      completedAt: map['completedAt'],
      cancelledAt: map['cancelledAt'],
      notes: map['notes'],
      preferredLanguage: map['preferredLanguage'],
      rating: map['rating'],
    );
  }
}

class BlindTrackRequestsScreen extends StatefulWidget {
  const BlindTrackRequestsScreen({super.key});

  @override
  State<BlindTrackRequestsScreen> createState() =>
      _BlindTrackRequestsScreenState();
}

class _BlindTrackRequestsScreenState extends State<BlindTrackRequestsScreen> {
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  bool _isLoading = true;
  List<HelpRequestModel> _requests = [];
  List<HelpRequestModel> _cancelledRequests = [];
  String? _errorMessage;

  // Voice command state
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  int _speakGeneration = 0;
  bool _isProcessingVoice = false;
  int _currentRequestIndex = -1;

  @override
  void initState() {
    super.initState();
    _initVoiceAndLoad();
  }

  Future<void> _initVoiceAndLoad() async {
    try {
      await _tts.setLanguage('en-US');
    } catch (_) {
      await _tts.setLanguage('en');
    }
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    final micStatus = await Permission.microphone.request();

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

    await _loadRequests();

    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
      await _speakWelcomeMessage();
    }
  }

  Future<void> _speakWelcomeMessage() async {
    final activeCount = _requests.length;
    final cancelledCount = _cancelledRequests.length;

    if (activeCount == 0 && cancelledCount == 0) {
      await _speak(
        'Track requests page. You have no help requests. Tap the plus button to request help.',
      );
    } else {
      await _speak(
        'Track requests page. You have $activeCount active requests and $cancelledCount cancelled requests. Say Commands to hear what I can do.',
      );
    }
  }

  Future<void> _speak(String text) async {
    print('🔊 Speaking: $text');
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
      print('TTS error: $msg');
      if (!completer.isCompleted) completer.complete();
    });

    await _tts.speak(text);
    await completer.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {},
    );

    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _startListening() async {
    if (!_sttAvailable || !mounted || !_shouldListen || _stt.isListening)
      return;

    setState(() => _isListening = true);
    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.finalResult) {
          _processVoiceCommand(result.recognizedWords.toLowerCase());
        }
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 2),
      localeId: 'en_US',
    );
  }

  Future<void> _speakRequestDetailsOnTap(
    HelpRequestModel request,
    int number,
  ) async {
    String details =
        'Request $number: ${request.requestType}. Status: ${request.status}.';

    if (request.location.isNotEmpty && request.location != 'N/A') {
      details += ' Location: ${request.location}.';
    }

    details += ' Description: ${request.description}.';

    if (request.volunteerName != null && request.volunteerName!.isNotEmpty) {
      details += ' Volunteer assigned: ${request.volunteerName}.';
    } else {
      details += ' No volunteer assigned yet.';
    }

    if (request.preferredLanguage != null &&
        request.preferredLanguage!.isNotEmpty) {
      details +=
          ' Preferred language: ${_getLanguageDisplay(request.preferredLanguage!)}.';
    }

    details += ' Created on ${_formatDate(request.createdAt)}.';

    if (request.acceptedAt != null) {
      details += ' Accepted on ${_formatDate(request.acceptedAt!)}.';
    }

    if (request.completedAt != null) {
      details += ' Completed on ${_formatDate(request.completedAt!)}.';
    }

    await _speak(details);
  }

  Future<void> _processVoiceCommand(String command) async {
    if (_isProcessingVoice) return;
    _isProcessingVoice = true;

    print('🎤 Voice command: $command');

    // ===== NAVIGATION COMMANDS =====
    if (command.contains('back') ||
        command.contains('go back') ||
        command.contains('exit') ||
        command.contains('return')) {
      await _speak('Going back to help center.');
      _isProcessingVoice = false;
      Navigator.pop(context);
      return;
    }

    // ===== REFRESH COMMANDS =====
    if (command.contains('refresh') ||
        command.contains('reload') ||
        command.contains('update')) {
      await _speak('Refreshing your requests.');
      await _loadRequests();
      _isProcessingVoice = false;
      return;
    }

    // ===== COUNT COMMANDS =====
    if (command.contains('how many') ||
        command.contains('count') ||
        command.contains('total')) {
      await _speak(
        'You have ${_requests.length} active requests and ${_cancelledRequests.length} cancelled requests.',
      );
      _isProcessingVoice = false;
      return;
    }

    // ===== ACTIVE REQUESTS ONLY =====
    if (command.contains('active requests') ||
        command.contains('show active')) {
      await _speak('You have ${_requests.length} active requests.');
      if (_requests.isNotEmpty) {
        for (int i = 0; i < _requests.length && i < 5; i++) {
          await _speak(
            '${i + 1}. ${_requests[i].requestType} - ${_requests[i].status}',
          );
          if (_requests[i].volunteerName != null) {
            await _speak('   Volunteer: ${_requests[i].volunteerName}');
          }
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      _isProcessingVoice = false;
      return;
    }

    // ===== CANCELLED REQUESTS ONLY =====
    if (command.contains('cancelled requests') ||
        command.contains('show cancelled')) {
      await _speak('You have ${_cancelledRequests.length} cancelled requests.');
      if (_cancelledRequests.isNotEmpty) {
        for (int i = 0; i < _cancelledRequests.length && i < 5; i++) {
          await _speak(
            '${i + 1}. ${_cancelledRequests[i].requestType} - cancelled',
          );
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      _isProcessingVoice = false;
      return;
    }

    // ===== READ SPECIFIC REQUEST DETAILS =====
    // Pattern: "read request 1", "tell me about request 2", "request details 3", "details of request 1"
    if ((command.contains('read request') ||
            command.contains('tell me about request') ||
            command.contains('request details') ||
            command.contains('details of request')) &&
        RegExp(r'\d+').hasMatch(command)) {
      final numbers = RegExp(r'\d+').allMatches(command);
      if (numbers.isNotEmpty) {
        int requestNum = int.parse(numbers.first.group(0)!);
        int index = requestNum - 1;

        print('🔍 Attempting to read request #$requestNum (index: $index)');
        print('📋 Total active requests: ${_requests.length}');

        if (index >= 0 && index < _requests.length) {
          print('✅ Found request: ${_requests[index].requestType}');
          await _speakRequestDetailsOnTap(_requests[index], requestNum);
        } else {
          await _speak(
            'Request number $requestNum does not exist. You have ${_requests.length} active requests.',
          );
        }
      }
      _isProcessingVoice = false;
      return;
    }

    // ===== READ CANCELLED REQUEST DETAILS =====
    if ((command.contains('cancelled request') ||
            command.contains('read cancelled')) &&
        RegExp(r'\d+').hasMatch(command)) {
      final numbers = RegExp(r'\d+').allMatches(command);
      if (numbers.isNotEmpty) {
        int requestNum = int.parse(numbers.first.group(0)!);
        int index = requestNum - 1;

        if (index >= 0 && index < _cancelledRequests.length) {
          final r = _cancelledRequests[index];
          await _speak(
            'Cancelled request $requestNum: ${r.requestType}. Description: ${r.description}. Cancelled on ${_formatDate(r.cancelledAt ?? r.createdAt)}.',
          );
        } else {
          await _speak(
            'Cancelled request number $requestNum does not exist. You have ${_cancelledRequests.length} cancelled requests.',
          );
        }
      }
      _isProcessingVoice = false;
      return;
    }

    // ===== SUMMARY / OVERVIEW =====
    if (command.contains('summary') || command.contains('overview')) {
      if (_requests.isEmpty && _cancelledRequests.isEmpty) {
        await _speak('You have no help requests.');
      } else {
        await _speak(
          'You have ${_requests.length} active requests. ${_getStatusSummary()}',
        );
        if (_cancelledRequests.isNotEmpty) {
          await _speak(
            'You also have ${_cancelledRequests.length} cancelled requests.',
          );
        }
      }
      _isProcessingVoice = false;
      return;
    }

    // ===== READ ALL ACTIVE REQUESTS (short version) =====
    if (command.contains('read all') || command.contains('list all')) {
      if (_requests.isEmpty) {
        await _speak('You have no active help requests.');
      } else {
        await _speak('Reading all your active help requests.');
        for (int i = 0; i < _requests.length; i++) {
          await _speak(
            '${i + 1}. ${_requests[i].requestType} - ${_requests[i].status}',
          );
          if (_requests[i].volunteerName != null) {
            await _speak('   Volunteer: ${_requests[i].volunteerName}');
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      _isProcessingVoice = false;
      return;
    }

    // ===== MOST RECENT / FIRST REQUEST =====
    if (command.contains('most recent') ||
        command.contains('first request') ||
        command.contains('latest')) {
      if (_requests.isEmpty) {
        await _speak('You have no active help requests.');
      } else {
        await _speakRequestDetailsOnTap(_requests[0], 1);
      }
      _isProcessingVoice = false;
      return;
    }

    // ===== OLDEST REQUEST =====
    if (command.contains('oldest')) {
      if (_requests.isEmpty) {
        await _speak('You have no active help requests.');
      } else {
        await _speakRequestDetailsOnTap(_requests.last, _requests.length);
      }
      _isProcessingVoice = false;
      return;
    }

    // ===== REQUEST TYPES FILTER =====
    if (command.contains('shopping')) {
      final shoppingReqs = _requests
          .where((r) => r.requestType == 'shopping')
          .toList();
      await _speak('You have ${shoppingReqs.length} shopping requests.');
      if (shoppingReqs.isNotEmpty) {
        for (int i = 0; i < shoppingReqs.length && i < 3; i++) {
          await _speak('Request ${i + 1}: ${shoppingReqs[i].status}');
        }
      }
      _isProcessingVoice = false;
      return;
    }

    if (command.contains('navigation')) {
      final navReqs = _requests
          .where((r) => r.requestType == 'navigation')
          .toList();
      await _speak('You have ${navReqs.length} navigation requests.');
      _isProcessingVoice = false;
      return;
    }

    if (command.contains('reading')) {
      final readingReqs = _requests
          .where((r) => r.requestType == 'reading')
          .toList();
      await _speak('You have ${readingReqs.length} reading requests.');
      _isProcessingVoice = false;
      return;
    }

    if (command.contains('emergency')) {
      final emergencyReqs = _requests
          .where((r) => r.requestType == 'emergency assistance')
          .toList();
      await _speak('You have ${emergencyReqs.length} emergency requests.');
      _isProcessingVoice = false;
      return;
    }

    // ===== STATUS FILTER =====
    if (command.contains('pending')) {
      final pendingReqs = _requests
          .where((r) => r.status == 'pending')
          .toList();
      await _speak('You have ${pendingReqs.length} pending requests.');
      _isProcessingVoice = false;
      return;
    }

    if (command.contains('accepted')) {
      final acceptedReqs = _requests
          .where((r) => r.status == 'accepted')
          .toList();
      await _speak('You have ${acceptedReqs.length} accepted requests.');
      _isProcessingVoice = false;
      return;
    }

    if (command.contains('in progress')) {
      final inProgressReqs = _requests
          .where((r) => r.status == 'in_progress')
          .toList();
      await _speak('You have ${inProgressReqs.length} requests in progress.');
      _isProcessingVoice = false;
      return;
    }

    if (command.contains('completed')) {
      final completedReqs = _requests
          .where((r) => r.status == 'completed')
          .toList();
      await _speak('You have ${completedReqs.length} completed requests.');
      _isProcessingVoice = false;
      return;
    }

    // ===== VOLUNTEER INFO =====
    if (command.contains('volunteer') ||
        command.contains('who is helping me')) {
      final assignedReqs = _requests
          .where((r) => r.volunteerName != null && r.volunteerName!.isNotEmpty)
          .toList();
      if (assignedReqs.isEmpty) {
        await _speak('No volunteers are currently assigned to your requests.');
      } else {
        await _speak(
          'You have ${assignedReqs.length} requests with volunteers assigned.',
        );
        for (var r in assignedReqs) {
          await _speak(
            '${r.requestType} request is being helped by ${r.volunteerName}.',
          );
        }
      }
      _isProcessingVoice = false;
      return;
    }

    // ===== CANCEL REQUEST =====
    if (command.contains('cancel request') &&
        command.contains('number') &&
        RegExp(r'\d+').hasMatch(command)) {
      final numbers = RegExp(r'\d+').allMatches(command);
      if (numbers.isNotEmpty) {
        int requestNum = int.parse(numbers.first.group(0)!);
        int index = requestNum - 1;

        if (index >= 0 && index < _requests.length) {
          final request = _requests[index];
          if (request.status == 'pending' || request.status == 'accepted') {
            await _cancelRequest(request);
          } else {
            await _speak(
              'Request $requestNum is ${request.status} and cannot be cancelled.',
            );
          }
        } else {
          await _speak('Request number $requestNum does not exist.');
        }
      }
      _isProcessingVoice = false;
      return;
    }

    // ===== RATE REQUEST =====
    if (command.contains('rate request') && RegExp(r'\d+').hasMatch(command)) {
      final numbers = RegExp(r'\d+').allMatches(command);
      if (numbers.isNotEmpty) {
        int requestNum = int.parse(numbers.first.group(0)!);
        int index = requestNum - 1;

        if (index >= 0 && index < _requests.length) {
          final request = _requests[index];
          if (request.status == 'completed' && request.rating == null) {
            if (request.id != null &&
                request.volunteerId != null &&
                request.volunteerName != null) {
              await _speak('Opening rating page for request $requestNum.');
              _shouldListen = false;
              if (mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BlindRateVolunteerPage(
                      helpRequestId: request.id!,
                      volunteerId: request.volunteerId!,
                      volunteerName: request.volunteerName!,
                    ),
                  ),
                );
              }
              _shouldListen = true;
              await _refreshRequests();
            } else {
              await _speak(
                'Cannot rate request $requestNum, volunteer information is missing.',
              );
            }
          } else if (request.rating != null) {
            await _speak('You have already rated request $requestNum.');
          } else {
            await _speak(
              'Request $requestNum is not completed yet and cannot be rated.',
            );
          }
        } else {
          await _speak('Request number $requestNum does not exist.');
        }
      }
      _isProcessingVoice = false;
      return;
    }

    // ===== HELP COMMANDS =====
    if (command.contains('help') || command.contains('commands')) {
      await _speak(
        'Here are available commands. '
        'Say Count to hear total requests. '
        'Say Active Requests to list active requests. '
        'Say Cancelled Requests to list cancelled requests. '
        'Say Read Request 1 to hear full details of request number one. '
        'Say Read All to hear all requests. '
        'Say Most Recent for latest request. '
        'Say Oldest for first request. '
        'Say Pending Requests to count pending ones. '
        'Say Volunteer to see who is helping you. '
        'Say Cancel Request Number 1 to cancel a request. '
        'Say Rate Request Number 1 to rate a completed request. '
        'Say Refresh to reload. '
        'Or say Back to go back.',
      );
      _isProcessingVoice = false;
      return;
    }

    // Report volunteer
    if (command.contains('report volunteer') || command.contains('complaint')) {
      final reportable = _requests
          .where(
            (r) =>
                (r.status == 'in_progress' || r.status == 'completed') &&
                r.volunteerId != null &&
                r.volunteerId!.isNotEmpty,
          )
          .toList();

      if (reportable.isEmpty) {
        await _speak(
          'You have no requests that can be reported. '
          'You can only report a volunteer during or after a completed request.',
        );
      } else if (reportable.length == 1) {
        final r = reportable.first;
        await _speak(
          'Opening report for volunteer ${r.volunteerName ?? 'Unknown'}.',
        );
        _shouldListen = false;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BlindReportVolunteerPage(
              helpRequestId: r.id ?? '',
              volunteerId: r.volunteerId!,
              volunteerName: r.volunteerName ?? 'Unknown',
              requestType: r.requestType,
            ),
          ),
        );
        _shouldListen = true;
        await _speak('Back on track requests page.');
      } else {
        // Multiple reportable requests — read them out
        await _speak(
          'You have ${reportable.length} reportable requests. '
          'Please open the request card and tap Report Volunteer.',
        );
      }
      _isProcessingVoice = false;
      return;
    }

    // ===== DEFAULT =====
    await _speak('Command not recognized. Say Commands to hear what I can do.');
    _isProcessingVoice = false;
  }

  String _getStatusSummary() {
    int pending = _requests.where((r) => r.status == 'pending').length;
    int accepted = _requests.where((r) => r.status == 'accepted').length;
    int inProgress = _requests.where((r) => r.status == 'in_progress').length;
    int completed = _requests.where((r) => r.status == 'completed').length;

    List<String> parts = [];
    if (pending > 0) parts.add('$pending pending');
    if (accepted > 0) parts.add('$accepted accepted');
    if (inProgress > 0) parts.add('$inProgress in progress');
    if (completed > 0) parts.add('$completed completed');

    return parts.isEmpty ? 'No active requests.' : parts.join(', ');
  }

  void _onMicTap() {
    print('🎤 Mic tapped');
    if (!_isProcessingVoice && _sttAvailable && !_isSpeaking) {
      _startListening();
    }
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      final querySnapshot = await firestore
          .collection('help_requests')
          .where('blindUserId', isEqualTo: userId)
          .get();

      final allRequests = querySnapshot.docs.map((doc) {
        return HelpRequestModel.fromMap(
          doc.id,
          doc.data() as Map<String, dynamic>,
        );
      }).toList();

      // Separate active and cancelled requests
      final active = <HelpRequestModel>[];
      final cancelled = <HelpRequestModel>[];

      for (var r in allRequests) {
        print(
          '📋 Request: ${r.requestType}, Status: ${r.status}, Volunteer: ${r.volunteerName}',
        );
        if (r.status == 'cancelled') {
          cancelled.add(r);
        } else {
          active.add(r);
        }
      }

      // Sort active by createdAt descending (newest first)
      active.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      // Sort cancelled by cancelledAt descending
      cancelled.sort((a, b) => b.cancelledAt!.compareTo(a.cancelledAt!));

      setState(() {
        _requests = active;
        _cancelledRequests = cancelled;
        _isLoading = false;
      });

      print('✅ Loaded ${_requests.length} active requests');
      for (int i = 0; i < _requests.length; i++) {
        print(
          '   ${i + 1}. ${_requests[i].requestType} - Volunteer: ${_requests[i].volunteerName ?? "None"}',
        );
      }
      print('✅ Loaded ${_cancelledRequests.length} cancelled requests');
    } catch (e) {
      print('❌ Error: $e');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshRequests() async {
    await _loadRequests();
    if (_sttAvailable && _shouldListen) {
      await _speak(
        'Refreshed. You have ${_requests.length} active requests and ${_cancelledRequests.length} cancelled requests.',
      );
    }
  }

  Future<void> _cancelRequest(HelpRequestModel request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request'),
        content: Text(
          'Are you sure you want to cancel your ${request.requestType} request?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await firestore.collection('help_requests').doc(request.id).update({
          'status': 'cancelled',
          'cancelledAt': Timestamp.now(),
        });
        await _loadRequests();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Request cancelled')));
          await _speak(
            'Your ${request.requestType} request has been cancelled.',
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error cancelling: $e')));
        }
      }
    }
  }

  @override
  void dispose() {
    _shouldListen = false;
    _stt.stop();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Help Requests'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              color: Colors.white,
            ),
            onPressed: _onMicTap,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshRequests,
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(onRefresh: _refreshRequests, child: _buildContent()),
          if (_isListening)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Listening...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _stt.cancel(),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pop(context);
        },
        backgroundColor: Colors.deepPurple,
        child: const Icon(Icons.add, color: Colors.white),
        tooltip: 'New Request',
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your requests...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              'Error loading requests',
              style: TextStyle(fontSize: 18, color: Colors.red.shade700),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRequests,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_requests.isEmpty && _cancelledRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.help_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No help requests yet',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to request help',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _requests.length + 1,
      itemBuilder: (context, index) {
        if (index < _requests.length) {
          return _buildRequestCard(_requests[index], index + 1);
        } else if (_cancelledRequests.isNotEmpty) {
          return _buildCancelledSection();
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildCancelledSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'CANCELLED REQUESTS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ..._cancelledRequests.map((request) => _buildCancelledCard(request)),
      ],
    );
  }

  Widget _buildCancelledCard(HelpRequestModel request) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cancel, size: 20, color: Colors.red.shade400),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    request.requestType.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Text(
                  'Cancelled',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              request.description,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _formatDate(request.cancelledAt ?? request.createdAt),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(HelpRequestModel request, int number) {
    Color statusColor;
    IconData statusIcon;

    switch (request.status) {
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        break;
      case 'accepted':
        statusColor = Colors.blue;
        statusIcon = Icons.check_circle;
        break;
      case 'in_progress':
        statusColor = Colors.cyan;
        statusIcon = Icons.hourglass_empty;
        break;
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.done_all;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () async {
          await _speakRequestDetailsOnTap(request, number);
          // Also show the dialog
          _showRequestDetails(request);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '#$number ${request.requestType.toUpperCase()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                request.status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _formatDate(request.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                request.description,
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 12,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      request.location,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
              ),
              if (request.volunteerName != null &&
                  request.volunteerName!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person,
                        size: 12,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Volunteer: ${request.volunteerName}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              if (request.status == 'completed' && request.rating == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (request.id != null &&
                            request.volunteerId != null &&
                            request.volunteerName != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BlindRateVolunteerPage(
                                helpRequestId: request.id!,
                                volunteerId: request.volunteerId!,
                                volunteerName: request.volunteerName!,
                              ),
                            ),
                          ).then((_) => _refreshRequests());
                        }
                      },
                      icon: const Icon(Icons.star_outline),
                      label: const Text('Rate Your Volunteer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRequestDetails(HelpRequestModel request) {
    // Check if mounted and context is available
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${request.requestType.toUpperCase()} Request'),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Status:', request.status.toUpperCase()),
              const SizedBox(height: 8),
              _detailRow('Description:', request.description),
              const SizedBox(height: 8),
              _detailRow('Location:', request.location),
              const SizedBox(height: 8),
              _detailRow('Created:', _formatDate(request.createdAt)),
              if (request.volunteerName != null &&
                  request.volunteerName!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _detailRow('Volunteer:', request.volunteerName!),
              ],
              if (request.acceptedAt != null) ...[
                const SizedBox(height: 8),
                _detailRow('Accepted:', _formatDate(request.acceptedAt!)),
              ],
              if (request.completedAt != null) ...[
                const SizedBox(height: 8),
                _detailRow('Completed:', _formatDate(request.completedAt!)),
              ],
              if (request.preferredLanguage != null)
                _detailRow(
                  'Language:',
                  _getLanguageDisplay(request.preferredLanguage!),
                ),
            ],
          ),
        ),
        actions: [
          if (request.status == 'completed' && request.rating == null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog first
                if (!mounted) return;
                if (request.id != null &&
                    request.volunteerId != null &&
                    request.volunteerName != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BlindRateVolunteerPage(
                        helpRequestId: request.id!,
                        volunteerId: request.volunteerId!,
                        volunteerName: request.volunteerName!,
                      ),
                    ),
                  ).then((_) {
                    if (mounted) _refreshRequests();
                  });
                }
              },
              child: const Text(
                'Rate Volunteer',
                style: TextStyle(color: Colors.amber),
              ),
            ),
          if (request.status == 'pending' || request.status == 'accepted')
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _cancelRequest(request);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancel Request'),
            ),
          if ((request.status == 'in_progress' ||
                  request.status == 'completed') &&
              request.volunteerId != null &&
              request.volunteerId!.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BlindReportVolunteerPage(
                      helpRequestId: request.id ?? '',
                      volunteerId: request.volunteerId!,
                      volunteerName: request.volunteerName ?? 'Unknown',
                      requestType: request.requestType,
                    ),
                  ),
                );
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Report Volunteer'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getLanguageDisplay(String languageCode) {
    switch (languageCode) {
      case 'english':
        return 'English 🇺🇸';
      case 'spanish':
        return 'Spanish 🇪🇸';
      case 'mandarin':
        return 'Mandarin 🇨🇳';
      case 'french':
        return 'French 🇫🇷';
      case 'german':
        return 'German 🇩🇪';
      case 'korean':
        return 'Korean 🇰🇷';
      default:
        return languageCode;
    }
  }
}
