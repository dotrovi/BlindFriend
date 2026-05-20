import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  bool _isLoading = true;
  List<HelpRequestModel> _requests = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRequests();
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

      print('🔵 Loading requests for user: $userId');

      // Query without orderBy first to avoid index requirement
      final querySnapshot = await firestore
          .collection('help_requests')
          .where('blindUserId', isEqualTo: userId)
          .get();

      print('🔵 Found ${querySnapshot.docs.length} requests');

      // Sort manually in Dart instead of using orderBy
      final requests = querySnapshot.docs.map((doc) {
        return HelpRequestModel.fromMap(
          doc.id,
          doc.data() as Map<String, dynamic>,
        );
      }).toList();

      // Sort by createdAt descending (newest first)
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      print('🔴 Error loading requests: $e');
      print('🔴 Stack trace: $stackTrace');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshRequests() async {
    await _loadRequests();
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
            icon: const Icon(Icons.refresh),
            onPressed: _refreshRequests,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshRequests,
        child: _buildContent(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pop(context); // Go back to send request
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

    if (_requests.isEmpty) {
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
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final request = _requests[index];
        return _buildRequestCard(request);
      },
    );
  }

  Widget _buildRequestCard(HelpRequestModel request) {
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
      case 'cancelled':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showRequestDetails(request),
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
                        Text(
                          request.requestType.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _formatDate(request.createdAt),
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
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      request.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
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
              // Add after the location row, before the volunteer name section
              const SizedBox(height: 8),
              if (request.preferredLanguage != null)
                Row(
                  children: [
                    Icon(
                      Icons.language,
                      size: 14,
                      color: Colors.deepPurple.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Preferred Language: ${_getLanguageDisplay(request.preferredLanguage!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.deepPurple.shade600,
                      ),
                    ),
                  ],
                ),
              if (request.volunteerName != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.person, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      'Volunteer: ${request.volunteerName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              // Status indicator
              _buildStatusIndicator(request.status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(String status) {
    Color color;
    String message;

    switch (status) {
      case 'pending':
        color = Colors.orange;
        message = '⏳ Waiting for a volunteer to accept...';
        break;
      case 'accepted':
        color = Colors.blue;
        message =
            '✓ A volunteer has accepted your request! They will contact you soon.';
        break;
      case 'in_progress':
        color = Colors.cyan;
        message = '🔄 Volunteer is on their way to help you.';
        break;
      case 'completed':
        color = Colors.green;
        message = '✅ Request completed. Thank you for using BlindFriend!';
        break;
      case 'cancelled':
        color = Colors.red;
        message = '❌ This request was cancelled.';
        break;
      default:
        color = Colors.grey;
        message = 'Status unknown';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  void _showRequestDetails(HelpRequestModel request) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
              if (request.volunteerName != null) ...[
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
          if (request.status == 'pending' || request.status == 'accepted')
            TextButton(
              onPressed: () => _cancelRequest(request),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancel Request'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelRequest(HelpRequestModel request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request'),
        content: const Text(
          'Are you sure you want to cancel this help request?',
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

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Request cancelled')));
          Navigator.pop(context); // Close dialog
          _loadRequests(); // Refresh list
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

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
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
