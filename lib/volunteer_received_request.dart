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

  Map<String, dynamic>? _volunteerProfile;
  List<String> _volunteerSpecialties = [];
  List<String> _volunteerLanguages = ['english'];

  final Map<String, String> _languageNames = {
    'english': 'English',
    'spanish': 'Spanish',
    'mandarin': 'Mandarin',
    'french': 'French',
    'german': 'German',
    'korean': 'Korean',
  };

  static const _emerald = Color(0xFF059669);
  static const _emeraldDark = Color(0xFF047857);

  @override
  void initState() {
    super.initState();
    _loadVolunteerProfile();
  }

  Future<void> _loadVolunteerProfile() async {
    final volunteerId = auth.currentUser?.uid;
    if (volunteerId == null) return;

    try {
      final volunteerDoc =
          await firestore.collection('volunteers').doc(volunteerId).get();

      if (volunteerDoc.exists) {
        final data = volunteerDoc.data() as Map<String, dynamic>;
        _volunteerProfile = data;
        _volunteerSpecialties = List<String>.from(data['specialties'] ?? [])
            .map((s) => s.toString().toLowerCase())
            .toList();
        final rawLang = data['language'];
        if (rawLang is List) {
          _volunteerLanguages = List<String>.from(rawLang)
              .map((s) => s.toString().toLowerCase())
              .toList();
        } else if (rawLang is String && rawLang.isNotEmpty) {
          _volunteerLanguages = [rawLang.toLowerCase()];
        } else {
          _volunteerLanguages = ['english'];
        }

        await _loadMatchingRequests();
      } else {
        setState(() {
          _errorMessage =
              'Volunteer profile not found. Please contact admin.';
          _isLoading = false;
        });
      }
    } catch (e) {
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
      if (volunteerId == null) throw Exception('Volunteer not logged in');

      final querySnapshot =
          await firestore.collection('help_requests').get();

      List<HelpRequest> allRequests = [];
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final status = data['status'] ?? 'pending';
        if (status == 'cancelled') continue;
        if (status == 'completed' && data['volunteerId'] != volunteerId) {
          continue;
        }
        allRequests.add(HelpRequest.fromMap(doc.id, data));
      }

      allRequests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _matchedRequests =
            _filterMatchingRequests(allRequests, volunteerId);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  List<HelpRequest> _filterMatchingRequests(
      List<HelpRequest> requests, String volunteerId) {
    return requests.where((request) {
      if (request.volunteerId == volunteerId) return true;
      if (request.status == 'pending') {
        final matchesSpecialty = _volunteerSpecialties
            .contains(request.requestType.toLowerCase());
        if (!matchesSpecialty) return false;
        final requestLanguage =
            request.preferredLanguage?.toLowerCase() ?? 'english';
        return _volunteerLanguages.contains(requestLanguage);
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
        .where((r) => r.status == _filterStatus)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildFilterChips(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshRequests,
            color: _emerald,
            child: _buildContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_emeraldDark, _emerald],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Row(
        children: [
          const Icon(Icons.handshake_outlined,
              color: Colors.white, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Help Requests',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_volunteerSpecialties.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language_rounded,
                      size: 13, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    _volunteerLanguages
                        .map((l) => _languageNames[l] ?? l)
                        .join(', '),
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _refreshRequests,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.refresh_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    const filters = [
      {'value': 'all', 'label': 'All'},
      {'value': 'pending', 'label': 'Pending'},
      {'value': 'accepted', 'label': 'Accepted'},
      {'value': 'in_progress', 'label': 'In Progress'},
      {'value': 'completed', 'label': 'Completed'},
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final val = f['value']!;
            final label = f['label']!;
            final isSelected = _filterStatus == val;
            final color = val == 'all'
                ? _emerald
                : _getStatusColor(val);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filterStatus = val),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color
                        : color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? color
                          : color.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected ? Colors.white : color,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 300,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _emerald),
                  const SizedBox(height: 16),
                  Text(
                    'Finding matching requests...',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.error_outline_rounded,
                    size: 52, color: Colors.red.shade400),
              ),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadVolunteerProfile,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _emerald,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      );
    }

    final requests = _filteredByStatus;

    if (requests.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _emerald.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.inbox_rounded,
                    size: 56, color: _emerald.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 20),
              const Text(
                'No requests found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _emerald.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    _emptyStateRow(
                      Icons.star_outline_rounded,
                      'Specialties',
                      _volunteerSpecialties.isEmpty
                          ? 'None set'
                          : _volunteerSpecialties.join(', '),
                    ),
                    const SizedBox(height: 8),
                    _emptyStateRow(
                      Icons.language_rounded,
                      'Language',
                      _volunteerLanguages
                          .map((l) => _languageNames[l] ?? l)
                          .join(', '),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _refreshRequests,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _emerald,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        return _buildRequestCard(requests[index]);
      },
    );
  }

  Widget _emptyStateRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _emerald),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
                fontSize: 13, color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(HelpRequest request) {
    final statusColor = _getStatusColor(request.status);
    final isMatch = _volunteerSpecialties
            .contains(request.requestType.toLowerCase()) &&
        _volunteerLanguages.contains(
            request.preferredLanguage?.toLowerCase() ?? 'english') &&
        request.status == 'pending';

    return GestureDetector(
      onTap: () => _showRequestActions(request),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border(
            left: BorderSide(color: statusColor, width: 5),
          ),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getStatusIcon(request.status),
                      color: statusColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                request.requestType.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isMatch) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF059669),
                                      Color(0xFF10B981)
                                    ],
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Match',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          request.blindUserName,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(request.status, statusColor),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                request.description,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Flexible(
                    child: _cardChip(Icons.location_on_rounded,
                        request.location, Colors.grey.shade600),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: _cardChip(Icons.phone_rounded,
                        request.blindUserPhone, Colors.grey.shade600),
                  ),
                ],
              ),
              if (request.preferredLanguage != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    _cardChip(
                      Icons.language_rounded,
                      _languageNames[request.preferredLanguage] ??
                          request.preferredLanguage!,
                      const Color(0xFF7C3AED),
                    ),
                    const Spacer(),
                    Text(
                      _formatDate(request.createdAt),
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatDate(request.createdAt),
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade400),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _cardChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _showRequestActions(HelpRequest request) {
    final volunteer = auth.currentUser;
    if (volunteer == null) return;
    final volunteerName = _volunteerProfile?['name'] ?? 'Volunteer';
    final statusColor = _getStatusColor(request.status);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Gradient header
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      statusColor,
                      statusColor.withValues(alpha: 0.7)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getStatusIcon(request.status),
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.requestType.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'From: ${request.blindUserName}',
                            style: TextStyle(
                              color:
                                  Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildStatusBadge(
                        request.status, Colors.white.withValues(alpha: 0.9)),
                  ],
                ),
              ),
              // Details
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _detailRow(
                        Icons.person_rounded, 'Name', request.blindUserName),
                    _detailRow(
                        Icons.phone_rounded, 'Phone', request.blindUserPhone),
                    _detailRow(Icons.category_rounded, 'Type',
                        request.requestType),
                    _detailRow(
                        Icons.location_on_rounded, 'Location', request.location),
                    _detailRow(Icons.description_rounded, 'Description',
                        request.description),
                    if (request.preferredLanguage != null)
                      _detailRow(
                        Icons.language_rounded,
                        'Language',
                        _languageNames[request.preferredLanguage] ??
                            request.preferredLanguage!,
                      ),
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    // Action buttons
                    if (request.status == 'pending')
                      _actionButton(
                        label: 'Accept Request',
                        icon: Icons.check_circle_outline_rounded,
                        color: _emerald,
                        onTap: () async {
                          Navigator.pop(context);
                          await _acceptRequest(
                              request, volunteer.uid, volunteerName);
                        },
                      ),
                    if (request.status == 'accepted')
                      _actionButton(
                        label: 'Mark as In Progress',
                        icon: Icons.hourglass_top_rounded,
                        color: Colors.blue.shade600,
                        onTap: () async {
                          Navigator.pop(context);
                          await _startHelp(request);
                        },
                      ),
                    if (request.status == 'in_progress')
                      _actionButton(
                        label: 'Mark as Completed',
                        icon: Icons.done_all_rounded,
                        color: _emerald,
                        onTap: () async {
                          Navigator.pop(context);
                          await _completeHelp(request);
                        },
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _emerald),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptRequest(
      HelpRequest request, String volunteerId, String volunteerName) async {
    try {
      await firestore.collection('help_requests').doc(request.id).update({
        'status': 'accepted',
        'volunteerId': volunteerId,
        'volunteerName': volunteerName,
        'acceptedAt': Timestamp.now(),
      });
      await _loadMatchingRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Request accepted successfully'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _startHelp(HelpRequest request) async {
    try {
      await firestore
          .collection('help_requests')
          .doc(request.id)
          .update({'status': 'in_progress'});
      await _loadMatchingRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Help marked as in progress')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Help completed! Good job!'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange.shade600;
      case 'accepted':
        return Colors.blue.shade600;
      case 'in_progress':
        return Colors.cyan.shade700;
      case 'completed':
        return _emerald;
      case 'cancelled':
        return Colors.red.shade600;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.pending_rounded;
      case 'accepted':
        return Icons.check_circle_outline_rounded;
      case 'in_progress':
        return Icons.hourglass_top_rounded;
      case 'completed':
        return Icons.done_all_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} '
        '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
