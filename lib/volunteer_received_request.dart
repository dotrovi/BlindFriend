import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HelpRequest {
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

  HelpRequest({
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
  });

  factory HelpRequest.fromMap(String id, Map<String, dynamic> map) {
    return HelpRequest(
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
    );
  }
}

class VolunteerReceivedRequestsScreen extends StatefulWidget {
  const VolunteerReceivedRequestsScreen({super.key});

  @override
  State<VolunteerReceivedRequestsScreen> createState() =>
      _VolunteerReceivedRequestsScreenState();
}

class _VolunteerReceivedRequestsScreenState
    extends State<VolunteerReceivedRequestsScreen> {
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  String _filterStatus = 'all';
  bool _isLoading = true;
  List<HelpRequest> _matchedRequests = [];
  String? _errorMessage;

  // Volunteer's profile
  Map<String, dynamic>? _volunteerProfile;
  List<String> _volunteerSpecialties = [];
  String _volunteerLanguage = 'english';

  // Language display names mapping
  final Map<String, String> _languageNames = {
    'english': 'English 🇺🇸',
    'spanish': 'Spanish 🇪🇸',
    'mandarin': 'Mandarin 🇨🇳',
    'french': 'French 🇫🇷',
    'german': 'German 🇩🇪',
    'korean': 'Korean 🇰🇷',
  };

  @override
  void initState() {
    super.initState();
    _loadVolunteerProfile();
  }

  Future<void> _loadVolunteerProfile() async {
    final volunteerId = auth.currentUser?.uid;
    if (volunteerId == null) return;

    try {
      // Get volunteer profile from Firestore
      final volunteerDoc = await firestore
          .collection('volunteers')
          .doc(volunteerId)
          .get();

      if (volunteerDoc.exists) {
        final data = volunteerDoc.data() as Map<String, dynamic>;
        _volunteerProfile = data;
        _volunteerSpecialties = List<String>.from(
          data['specialties'] ?? [],
        ).map((s) => s.toString().toLowerCase()).toList();

        _volunteerLanguage =
            data['language']?.toString().toLowerCase() ?? 'english';

        print('✅ Volunteer loaded - Specialties: $_volunteerSpecialties');
        print('✅ Volunteer Language: $_volunteerLanguage');

        await _loadMatchingRequests();
      } else {
        setState(() {
          _errorMessage = 'Volunteer profile not found. Please contact admin.';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading volunteer profile: $e');
      setState(() {
        _errorMessage = 'Error loading profile: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMatchingRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final volunteerId = auth.currentUser?.uid;
      if (volunteerId == null) {
        throw Exception('Volunteer not logged in');
      }

      final querySnapshot = await firestore.collection('help_requests').get();

      print('🔵 Total requests found: ${querySnapshot.docs.length}');
      print('🔵 Volunteer specialties: $_volunteerSpecialties');
      print('🔵 Volunteer language: $_volunteerLanguage');

      List<HelpRequest> allRequests = [];
      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] ?? 'pending';

        if (status == 'cancelled') continue;
        if (status == 'completed' && data['volunteerId'] != volunteerId)
          continue;

        final request = HelpRequest.fromMap(doc.id, data);
        allRequests.add(request);
      }

      allRequests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final matched = _filterMatchingRequests(allRequests, volunteerId);

      setState(() {
        _matchedRequests = matched;
        _isLoading = false;
      });

      print('🔵 Matched requests count: ${_matchedRequests.length}');
    } catch (e, stackTrace) {
      print('🔴 Error loading requests: $e');
      print('🔴 Stack trace: $stackTrace');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  List<HelpRequest> _filterMatchingRequests(
    List<HelpRequest> requests,
    String volunteerId,
  ) {
    return requests.where((request) {
      // Always show requests assigned to this volunteer
      if (request.volunteerId == volunteerId) {
        return true;
      }

      // For pending requests, apply matching criteria
      if (request.status == 'pending') {
        // 1. Check specialty match
        final matchesSpecialty = _volunteerSpecialties.contains(
          request.requestType.toLowerCase(),
        );

        if (!matchesSpecialty) {
          print(
            '❌ Request ${request.id} - Specialty mismatch: ${request.requestType} not in $_volunteerSpecialties',
          );
          return false;
        }

        // 2. Check language match
        final requestLanguage =
            request.preferredLanguage?.toLowerCase() ?? 'english';
        final matchesLanguage = requestLanguage == _volunteerLanguage;

        if (!matchesLanguage) {
          print(
            '❌ Request ${request.id} - Language mismatch: $requestLanguage vs $_volunteerLanguage',
          );
          return false;
        }

        print('✅ Request ${request.id} - MATCHES!');
        return true;
      }

      return false;
    }).toList();
  }

  Future<void> _refreshRequests() async {
    await _loadVolunteerProfile();
  }

  List<HelpRequest> get _filteredByStatus {
    if (_filterStatus == 'all') return _matchedRequests;
    return _matchedRequests
        .where((request) => request.status == _filterStatus)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help Requests'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          // Volunteer's language indicator
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.language, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  _languageNames[_volunteerLanguage] ?? _volunteerLanguage,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ],
            ),
          ),
          // Specialty indicator
          if (_volunteerSpecialties.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    _volunteerSpecialties.take(2).join(', '),
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ],
              ),
            ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshRequests,
            color: Colors.white,
          ),
          // Filter dropdown
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: DropdownButton<String>(
              value: _filterStatus,
              dropdownColor: Colors.white,
              underline: const SizedBox(),
              icon: const Icon(Icons.filter_list, color: Colors.white),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'accepted', child: Text('Accepted')),
                DropdownMenuItem(
                  value: 'in_progress',
                  child: Text('In Progress'),
                ),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
              ],
              onChanged: (value) {
                setState(() {
                  _filterStatus = value ?? 'all';
                });
              },
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshRequests,
        child: _buildContent(),
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
            Text('Finding matching requests...'),
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
              'Error',
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
              onPressed: _loadVolunteerProfile,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    final requests = _filteredByStatus;

    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No matching help requests',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'You only see requests that match:\n'
              '• Specialties: ${_volunteerSpecialties.isEmpty ? 'None set' : _volunteerSpecialties.join(', ')}\n'
              '• Language: ${_languageNames[_volunteerLanguage] ?? _volunteerLanguage}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshRequests,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final request = requests[index];
        return _buildRequestCard(request);
      },
    );
  }

  Widget _buildRequestCard(HelpRequest request) {
    final matchesSpecialty = _volunteerSpecialties.contains(
      request.requestType,
    );
    final requestLanguage = request.preferredLanguage ?? 'english';
    final matchesLanguage = requestLanguage == _volunteerLanguage;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: matchesSpecialty && matchesLanguage && request.status == 'pending'
            ? BorderSide(color: Colors.green.shade400, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _showRequestActions(request),
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
                      color: _getStatusColor(request.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getStatusIcon(request.status),
                      color: _getStatusColor(request.status),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              request.requestType.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (matchesSpecialty &&
                                matchesLanguage &&
                                request.status == 'pending')
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Perfect Match',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          'From: ${request.blindUserName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(request.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      request.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(request.status),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                request.description,
                style: const TextStyle(fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      request.location,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.phone, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    request.blindUserPhone,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Language preference badge
              if (request.preferredLanguage != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.language,
                        size: 12,
                        color: Colors.deepPurple.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Prefers: ${_languageNames[request.preferredLanguage] ?? request.preferredLanguage}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.deepPurple.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                _formatDate(request.createdAt),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRequestActions(HelpRequest request) async {
    final volunteer = auth.currentUser;
    if (volunteer == null) return;

    String volunteerName = _volunteerProfile?['name'] ?? 'Volunteer';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Help Request Details',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple.shade700,
                ),
              ),
              const SizedBox(height: 16),
              _detailRow('From:', request.blindUserName),
              _detailRow('Phone:', request.blindUserPhone),
              _detailRow('Type:', request.requestType),
              _detailRow('Location:', request.location),
              _detailRow('Description:', request.description),
              if (request.preferredLanguage != null)
                _detailRow(
                  'Language:',
                  _languageNames[request.preferredLanguage] ??
                      request.preferredLanguage!,
                ),
              const Divider(height: 24),
              const Text(
                'Actions',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              if (request.status == 'pending')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _acceptRequest(
                        request,
                        volunteer.uid,
                        volunteerName,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Accept Request'),
                  ),
                ),
              if (request.status == 'accepted')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _startHelp(request);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Mark as In Progress'),
                  ),
                ),
              if (request.status == 'in_progress')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _completeHelp(request);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Mark as Completed'),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _acceptRequest(
    HelpRequest request,
    String volunteerId,
    String volunteerName,
  ) async {
    try {
      await firestore.collection('help_requests').doc(request.id).update({
        'status': 'accepted',
        'volunteerId': volunteerId,
        'volunteerName': volunteerName,
        'acceptedAt': Timestamp.now(),
      });

      await _loadMatchingRequests();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request accepted successfully')),
        );
      }
    } catch (e) {
      print('Error accepting request: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _startHelp(HelpRequest request) async {
    try {
      await firestore.collection('help_requests').doc(request.id).update({
        'status': 'in_progress',
      });

      await _loadMatchingRequests();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Help marked as in progress')),
        );
      }
    } catch (e) {
      print('Error starting help: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _completeHelp(HelpRequest request) async {
    try {
      await firestore.collection('help_requests').doc(request.id).update({
        'status': 'completed',
        'completedAt': Timestamp.now(),
      });

      await _loadMatchingRequests();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Help completed! Good job!')),
        );
      }
    } catch (e) {
      print('Error completing help: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'in_progress':
        return Colors.cyan;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.pending;
      case 'accepted':
        return Icons.check_circle;
      case 'in_progress':
        return Icons.hourglass_empty;
      case 'completed':
        return Icons.done_all;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
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
      ),
    );
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
