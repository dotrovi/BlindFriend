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
  bool reported;

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
    this.reported = false,
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
      reported: map['reported'] == true,
    );
  }

  bool get hasVolunteer => volunteerId != null && volunteerId!.isNotEmpty;
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

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _sttAvailable = false;
  bool _shouldListen = true;
  bool _isProcessingVoice = false;
  int _speakGeneration = 0;
  bool _suspendAutoListen = false;

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

    await _loadRequests();

    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
      await _speakWelcomeMessage();
    }
  }

  Future<void> _speakWelcomeMessage() async {
    final activeCount = _requests.length;
    if (activeCount == 0 && _cancelledRequests.isEmpty) {
      await _speak(
        'Track requests page. You have no help requests. '
        'Say help for options, or say back to return.',
      );
    } else {
      await _speak(
        'Track requests page. You have $activeCount active requests. '
        'Say a command, or say help for the list.',
      );
    }
  }

  Future<void> _speak(String text, {bool thenListen = true}) async {
    print('🔊 Speaking: $text');
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
      print('TTS error: $msg');
      if (!completer.isCompleted) completer.complete();
    });

    await _tts.speak(text);
    await completer.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {},
    );

    if (!mounted) return;
    setState(() => _isSpeaking = false);

    if (myGen != _speakGeneration) return;

    if (thenListen && _shouldListen && !_suspendAutoListen) {
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
          _processVoiceCommand(result.recognizedWords.toLowerCase());
        }
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 2),
      localeId: 'en_US',
    );
  }

  void _onMicTap() {
    print('🎤 Mic tapped');
    if (!_isProcessingVoice && _sttAvailable && !_isListening) {
      _startListening();
    }
  }

  Future<void> _speakRequestDetailsOnTap(
    HelpRequestModel request,
    int number, {
    bool thenListen = true,
  }) async {
    String details = 'Request $number: ${request.requestType}. '
        '${_statusInWords(request.status)}.';

    if (request.hasVolunteer) {
      final name =
          (request.volunteerName != null && request.volunteerName!.isNotEmpty)
              ? request.volunteerName!
              : 'a volunteer';
      details += ' Volunteer: $name.';
    } else {
      details += ' No volunteer yet.';
    }

    if (request.location.isNotEmpty && request.location != 'N/A') {
      details += ' At ${request.location}.';
    }

    await _speak(details, thenListen: thenListen);
  }

  String _statusInWords(String status) {
    switch (status) {
      case 'in_progress':
        return 'In progress';
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  Future<void> _processVoiceCommand(String command) async {
    if (_isProcessingVoice) return;
    _isProcessingVoice = true;

    print('🎤 Voice command: $command');

    if (command.trim().isEmpty) {
      _isProcessingVoice = false;
      await _speak('I did not catch that. Say a command, or say help.');
      return;
    }

    if (command.contains('back') ||
        command.contains('exit') ||
        command.contains('return')) {
      _suspendAutoListen = true;
      _shouldListen = false;
      await _speak('Going back to help center.', thenListen: false);
      _isProcessingVoice = false;
      if (mounted) Navigator.pop(context);
      return;
    }

    if (command.contains('refresh') ||
        command.contains('reload') ||
        command.contains('update')) {
      await _speak('Refreshing your requests.', thenListen: false);
      await _loadRequests();
      _isProcessingVoice = false;
      await _speak('Refreshed. You have ${_requests.length} active requests.');
      return;
    }

    if (command.contains('my report') ||
        command.contains('view report') ||
        command.contains('reports filed') ||
        command.contains('my complaint')) {
      _isProcessingVoice = false;
      await _readMyReports();
      return;
    }

    if (command.contains('how many') ||
        command.contains('count') ||
        command.contains('total')) {
      _isProcessingVoice = false;
      await _speak(
        'You have ${_requests.length} active requests '
        'and ${_cancelledRequests.length} cancelled requests.',
      );
      return;
    }

    if (command.contains('active requests') ||
        command.contains('show active')) {
      await _speak('You have ${_requests.length} active requests.',
          thenListen: false);
      for (int i = 0; i < _requests.length && i < 5; i++) {
        await _speak(
          '${i + 1}. ${_requests[i].requestType} - ${_requests[i].status}',
          thenListen: false,
        );
      }
      _isProcessingVoice = false;
      await _speak('Say a command, or say help.');
      return;
    }

    if (command.contains('cancelled requests') ||
        command.contains('show cancelled')) {
      await _speak('You have ${_cancelledRequests.length} cancelled requests.',
          thenListen: false);
      for (int i = 0; i < _cancelledRequests.length && i < 5; i++) {
        await _speak(
          '${i + 1}. ${_cancelledRequests[i].requestType} - cancelled',
          thenListen: false,
        );
      }
      _isProcessingVoice = false;
      await _speak('Say a command, or say help.');
      return;
    }

    if ((command.contains('read request') ||
            command.contains('tell me about request') ||
            command.contains('request details') ||
            command.contains('details of request')) &&
        RegExp(r'\d+').hasMatch(command)) {
      final numbers = RegExp(r'\d+').allMatches(command);
      if (numbers.isNotEmpty) {
        int requestNum = int.parse(numbers.first.group(0)!);
        int index = requestNum - 1;
        if (index >= 0 && index < _requests.length) {
          _isProcessingVoice = false;
          await _speakRequestDetailsOnTap(_requests[index], requestNum);
          return;
        } else {
          _isProcessingVoice = false;
          await _speak(
            'Request number $requestNum does not exist. '
            'You have ${_requests.length} active requests.',
          );
          return;
        }
      }
      _isProcessingVoice = false;
      return;
    }

    if (command.contains('summary') || command.contains('overview')) {
      _isProcessingVoice = false;
      if (_requests.isEmpty && _cancelledRequests.isEmpty) {
        await _speak('You have no help requests.');
      } else {
        await _speak(
          'You have ${_requests.length} active requests. ${_getStatusSummary()}',
        );
      }
      return;
    }

    if (command.contains('read all') || command.contains('list all')) {
      if (_requests.isEmpty) {
        _isProcessingVoice = false;
        await _speak('You have no active help requests.');
        return;
      }
      await _speak('Reading all your active help requests.', thenListen: false);
      for (int i = 0; i < _requests.length; i++) {
        final r = _requests[i];
        final namePart = r.hasVolunteer
            ? '. Volunteer: ${(r.volunteerName != null && r.volunteerName!.isNotEmpty) ? r.volunteerName : 'assigned'}'
            : '';
        await _speak(
          '${i + 1}. ${r.requestType} - ${r.status}$namePart',
          thenListen: false,
        );
      }
      _isProcessingVoice = false;
      await _speak('That is all. Say a command, or say help.');
      return;
    }

    if (command.contains('most recent') ||
        command.contains('first request') ||
        command.contains('latest')) {
      _isProcessingVoice = false;
      if (_requests.isEmpty) {
        await _speak('You have no active help requests.');
      } else {
        await _speakRequestDetailsOnTap(_requests[0], 1);
      }
      return;
    }

    if (command.contains('oldest')) {
      _isProcessingVoice = false;
      if (_requests.isEmpty) {
        await _speak('You have no active help requests.');
      } else {
        await _speakRequestDetailsOnTap(_requests.last, _requests.length);
      }
      return;
    }

    if (command.contains('report') || command.contains('complaint')) {
      final reportable = _requests
          .where((r) =>
              (r.status == 'in_progress' || r.status == 'completed') &&
              r.hasVolunteer &&
              !r.reported)
          .toList();

      final alreadyReported = _requests
          .where((r) =>
              (r.status == 'in_progress' || r.status == 'completed') &&
              r.hasVolunteer &&
              r.reported)
          .toList();

      if (reportable.isEmpty) {
        _isProcessingVoice = false;
        if (alreadyReported.isNotEmpty) {
          await _speak(
            'You have already reported your reportable requests. '
            'Say my reports to hear your filed reports.',
          );
        } else {
          await _speak(
            'You have no requests that can be reported. '
            'You can only report a volunteer during or after a completed request.',
          );
        }
        return;
      } else if (reportable.length == 1) {
        final r = reportable.first;
        _suspendAutoListen = true;
        _shouldListen = false;
        await _speak(
          'Opening report for your ${r.requestType} request.',
          thenListen: false,
        );
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlindReportVolunteerPage(
                helpRequestId: r.id ?? '',
                volunteerId: r.volunteerId!,
                volunteerName:
                    (r.volunteerName != null && r.volunteerName!.isNotEmpty)
                        ? r.volunteerName!
                        : 'your volunteer',
                requestType: r.requestType,
              ),
            ),
          );
        }
        _suspendAutoListen = false;
        _shouldListen = true;
        await _loadRequests();
        _isProcessingVoice = false;
        await _speak('Back on track requests page.');
        return;
      } else {
        _isProcessingVoice = false;
        await _speak(
          'You have ${reportable.length} reportable requests. '
          'Please open a request card and tap Report Volunteer.',
        );
        return;
      }
    }

    if (command.contains('rate') && RegExp(r'\d+').hasMatch(command)) {
      final numbers = RegExp(r'\d+').allMatches(command);
      if (numbers.isNotEmpty) {
        int requestNum = int.parse(numbers.first.group(0)!);
        int index = requestNum - 1;
        if (index >= 0 && index < _requests.length) {
          final request = _requests[index];
          if (request.status == 'completed' && request.rating == null) {
            if (request.id != null && request.hasVolunteer) {
              _suspendAutoListen = true;
              _shouldListen = false;
              await _speak('Opening rating page for request $requestNum.',
                  thenListen: false);
              if (mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BlindRateVolunteerPage(
                      helpRequestId: request.id!,
                      volunteerId: request.volunteerId!,
                      volunteerName: (request.volunteerName != null &&
                              request.volunteerName!.isNotEmpty)
                          ? request.volunteerName!
                          : 'your volunteer',
                    ),
                  ),
                );
              }
              _suspendAutoListen = false;
              _shouldListen = true;
              await _loadRequests();
              _isProcessingVoice = false;
              await _speak('Back on track requests page.');
              return;
            } else {
              _isProcessingVoice = false;
              await _speak(
                'Cannot rate request $requestNum, volunteer information is missing.',
              );
              return;
            }
          } else if (request.rating != null) {
            _isProcessingVoice = false;
            await _speak('You have already rated request $requestNum.');
            return;
          } else {
            _isProcessingVoice = false;
            await _speak(
              'Request $requestNum is not completed yet and cannot be rated.',
            );
            return;
          }
        } else {
          _isProcessingVoice = false;
          await _speak('Request number $requestNum does not exist.');
          return;
        }
      }
      _isProcessingVoice = false;
      return;
    }

    if (command.contains('pending')) {
      final reqs = _requests.where((r) => r.status == 'pending').toList();
      _isProcessingVoice = false;
      await _speak('You have ${reqs.length} pending requests.');
      return;
    }
    if (command.contains('in progress')) {
      final reqs = _requests.where((r) => r.status == 'in_progress').toList();
      _isProcessingVoice = false;
      await _speak('You have ${reqs.length} requests in progress.');
      return;
    }
    if (command.contains('completed')) {
      final reqs = _requests.where((r) => r.status == 'completed').toList();
      _isProcessingVoice = false;
      await _speak('You have ${reqs.length} completed requests.');
      return;
    }

    if (command.contains('cancel request') && RegExp(r'\d+').hasMatch(command)) {
      final numbers = RegExp(r'\d+').allMatches(command);
      if (numbers.isNotEmpty) {
        int requestNum = int.parse(numbers.first.group(0)!);
        int index = requestNum - 1;
        if (index >= 0 && index < _requests.length) {
          final request = _requests[index];
          if (request.status == 'pending' || request.status == 'accepted') {
            _isProcessingVoice = false;
            await _cancelRequest(request);
            return;
          } else {
            _isProcessingVoice = false;
            await _speak(
              'Request $requestNum is ${request.status} and cannot be cancelled.',
            );
            return;
          }
        } else {
          _isProcessingVoice = false;
          await _speak('Request number $requestNum does not exist.');
          return;
        }
      }
      _isProcessingVoice = false;
      return;
    }

    if (command.contains('volunteer') ||
        command.contains('who is helping me')) {
      final assignedReqs = _requests.where((r) => r.hasVolunteer).toList();
      if (assignedReqs.isEmpty) {
        _isProcessingVoice = false;
        await _speak('No volunteers are currently assigned to your requests.');
        return;
      } else {
        await _speak(
          'You have ${assignedReqs.length} requests with volunteers assigned.',
          thenListen: false,
        );
        for (var r in assignedReqs) {
          final name =
              (r.volunteerName != null && r.volunteerName!.isNotEmpty)
                  ? r.volunteerName!
                  : 'a volunteer';
          await _speak(
            'Your ${r.requestType} request is being helped by $name.',
            thenListen: false,
          );
        }
        _isProcessingVoice = false;
        await _speak('Say a command, or say help.');
        return;
      }
    }

    if (command.contains('help') || command.contains('command')) {
      _isProcessingVoice = false;
      await _speak(
        'Available commands. '
        'Say Count for totals. '
        'Say Active Requests to list them. '
        'Say Read Request 1 for full details. '
        'Say Read All for everything. '
        'Say Most Recent for the latest. '
        'Say Pending for pending requests. '
        'Say Volunteer to hear who is helping you. '
        'Say Cancel Request 1 to cancel. '
        'Say Rate Request 1 to rate. '
        'Say Report to report a volunteer. '
        'Say My Reports to hear filed reports. '
        'Say Refresh to reload. '
        'Or say Back to return.',
      );
      return;
    }

    _isProcessingVoice = false;
    await _speak('Sorry, I did not understand. Say a command, or say help.');
  }

  Future<void> _readMyReports() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      await _speak('You are not logged in.');
      return;
    }
    await _speak('Checking your filed reports.', thenListen: false);
    try {
      final snap = await firestore
          .collection('reports')
          .where('blindUserId', isEqualTo: uid)
          .get();

      final reports = snap.docs;
      if (reports.isEmpty) {
        await _speak('You have not filed any reports.');
        return;
      }

      reports.sort((a, b) {
        final ta = a.data()['createdAt'];
        final tb = b.data()['createdAt'];
        if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
        return 0;
      });

      await _speak('You have filed ${reports.length} reports.',
          thenListen: false);

      for (int i = 0; i < reports.length && i < 5; i++) {
        final d = reports[i].data();
        final type = _reportTypeLabel(d['reportType']?.toString() ?? '');
        final status = d['status']?.toString() ?? 'pending';
        final requestType = d['requestType']?.toString() ?? 'a';
        await _speak(
          'Report ${i + 1}. For your $requestType request. '
          'Reason: $type. Report Status: $status.',
          thenListen: false,
        );
      }
      await _speak('That is all your reports. Say a command, or say help.');
    } catch (e) {
      print('❌ Read reports error: $e');
      await _speak('Could not load your reports right now. Please try again.');
    }
  }

  String _reportTypeLabel(String id) {
    switch (id) {
      case 'no_show':
        return 'No show';
      case 'inappropriate_behaviour':
        return 'Inappropriate behaviour';
      case 'did_not_complete':
        return 'Did not complete task';
      case 'other':
        return 'Other';
      default:
        return id.isEmpty ? 'Unknown' : id;
    }
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

    return parts.isEmpty ? 'No active requests.' : '${parts.join(', ')}.';
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

      await _resolveVolunteerNames(allRequests);

      final active = <HelpRequestModel>[];
      final cancelled = <HelpRequestModel>[];

      for (var r in allRequests) {
        if (r.status == 'cancelled') {
          cancelled.add(r);
        } else {
          active.add(r);
        }
      }

      active.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      cancelled.sort((a, b) =>
          (b.cancelledAt ?? b.createdAt).compareTo(a.cancelledAt ?? a.createdAt));

      setState(() {
        _requests = active;
        _cancelledRequests = cancelled;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error: $e');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _resolveVolunteerNames(List<HelpRequestModel> requests) async {
    final Map<String, String> nameCache = {};

    for (final r in requests) {
      if (r.hasVolunteer &&
          (r.volunteerName == null || r.volunteerName!.isEmpty)) {
        final id = r.volunteerId!;
        if (nameCache.containsKey(id)) {
          r.volunteerName = nameCache[id];
          continue;
        }
        try {
          final vDoc = await firestore.collection('volunteers').doc(id).get();
          String? name = vDoc.data()?['name'] as String?;

          if (name == null || name.isEmpty) {
            final uDoc = await firestore.collection('users').doc(id).get();
            name = uDoc.data()?['name'] as String?;
          }

          if (name != null && name.isNotEmpty) {
            r.volunteerName = name;
            nameCache[id] = name;
          }
        } catch (e) {
          print('⚠️ Could not resolve volunteer name for $id: $e');
        }
      }
    }
  }

  Future<void> _refreshRequests() async {
    await _loadRequests();
    if (_sttAvailable && _shouldListen) {
      await _speak('Refreshed. You have ${_requests.length} active requests.');
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request cancelled')),
          );
          await _speak(
            'Your ${request.requestType} request has been cancelled.',
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error cancelling: $e')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _shouldListen = false;
    _suspendAutoListen = true;
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
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
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
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 20),
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
        tooltip: 'New Request',
        child: const Icon(Icons.add, color: Colors.white),
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
          await _speakRequestDetailsOnTap(request, number, thenListen: false);
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
                  Icon(Icons.location_on, size: 12, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      request.location,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ),
                ],
              ),
              if (request.hasVolunteer)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.person,
                          size: 12, color: Colors.green.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Volunteer: ${(request.volunteerName != null && request.volunteerName!.isNotEmpty) ? request.volunteerName : 'Assigned'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              if (request.reported)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.flag, size: 12, color: Colors.red.shade400),
                      const SizedBox(width: 4),
                      Text(
                        'Reported',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.shade400,
                          fontWeight: FontWeight.w600,
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
                        if (request.id != null && request.hasVolunteer) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BlindRateVolunteerPage(
                                helpRequestId: request.id!,
                                volunteerId: request.volunteerId!,
                                volunteerName: (request.volunteerName != null &&
                                        request.volunteerName!.isNotEmpty)
                                    ? request.volunteerName!
                                    : 'your volunteer',
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
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${request.requestType.toUpperCase()} Request'),
        content: SizedBox(
          width: double.maxFinite,
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
              if (request.hasVolunteer) ...[
                const SizedBox(height: 8),
                _detailRow(
                  'Volunteer:',
                  (request.volunteerName != null &&
                          request.volunteerName!.isNotEmpty)
                      ? request.volunteerName!
                      : 'Assigned',
                ),
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
              if (request.reported) ...[
                const SizedBox(height: 8),
                _detailRow('Report:', 'Already reported'),
              ],
            ],
          ),
        ),
        actions: [
          if (request.status == 'completed' && request.rating == null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (mounted && request.id != null && request.hasVolunteer) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BlindRateVolunteerPage(
                        helpRequestId: request.id!,
                        volunteerId: request.volunteerId!,
                        volunteerName: (request.volunteerName != null &&
                                request.volunteerName!.isNotEmpty)
                            ? request.volunteerName!
                            : 'your volunteer',
                      ),
                    ),
                  ).then((_) {
                    if (mounted) _refreshRequests();
                  });
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.amber),
              child: const Text('Rate Volunteer'),
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
              request.hasVolunteer &&
              !request.reported)
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
                      volunteerName: (request.volunteerName != null &&
                              request.volunteerName!.isNotEmpty)
                          ? request.volunteerName!
                          : 'your volunteer',
                      requestType: request.requestType,
                    ),
                  ),
                ).then((_) => _refreshRequests());
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
    return '${date.day}/${date.month}/${date.year} '
        '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
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