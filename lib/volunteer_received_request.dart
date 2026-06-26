import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Shared palette ─────────────────────────────────────────────────
const Color _kNavyDeep = Color(0xFF120A2E);
const Color _kNavyMid = Color(0xFF1E1147);
const Color _kPurple = Color(0xFF3B1E78);
const Color _kPinkBright = Color(0xFFFF5FD2);
const Color _kBlueAccent = Color(0xFF4A90E2);
const Color _kCardFill = Color(0xFF241A45);

const LinearGradient _kAccentGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_kPinkBright, Color(0xFF9B59B6), _kBlueAccent],
);

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
  Map<String, String> declineReasons;
  double? latitude;
  double? longitude;

  bool get hasLocation => latitude != null && longitude != null;

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
    this.declineReasons = const {},
    this.latitude,
    this.longitude,
  });

  factory HelpRequest.fromMap(String id, Map<String, dynamic> map) {
    final rawReasons = map['declineReasons'];
    final parsedReasons = <String, String>{};
    if (rawReasons is Map) {
      rawReasons.forEach((k, v) => parsedReasons[k.toString()] = v.toString());
    }
    return HelpRequest(
      id: id,
      blindUserId: map['blindUserId'] ?? '',
      blindUserName: map['blindUserName'] ?? '',
      blindUserPhone: map['blindUserPhone'] ?? map['phoneNumber'] ?? 'Not set',
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
      declineReasons: parsedReasons,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
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
          _errorMessage = 'Volunteer profile not found. Please contact admin.';
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

      final querySnapshot = await firestore.collection('help_requests').get();

      List<HelpRequest> allRequests = [];
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final status = data['status'] ?? 'pending';
        if (status == 'cancelled') continue;
        if (status != 'pending' && data['volunteerId'] != volunteerId) {
          continue;
        }
        final declinedBy = List<String>.from(data['declinedBy'] ?? []);
        if (status == 'pending' && declinedBy.contains(volunteerId)) continue;
        allRequests.add(HelpRequest.fromMap(doc.id, data));
      }

      allRequests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _matchedRequests = allRequests;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshRequests() async {
    await _loadVolunteerProfile();
  }

  List<HelpRequest> get _filteredByStatus {
    if (_filterStatus == 'all') return _matchedRequests;
    return _matchedRequests.where((r) => r.status == _filterStatus).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kNavyDeep,
      child: Column(
        children: [
          _buildHeader(),
          _buildFilterChips(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshRequests,
              color: _kPinkBright,
              backgroundColor: _kNavyMid,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kPurple, _kNavyMid, _kNavyDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Row(
        children: [
          const Icon(Icons.handshake_outlined, color: Colors.white, size: 22),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language_rounded, size: 13, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    _volunteerLanguages
                        .map((l) => _languageNames[l] ?? l)
                        .join(', '),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
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
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
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
      color: _kNavyMid,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final val = f['value']!;
            final label = f['label']!;
            final isSelected = _filterStatus == val;
            final color = val == 'all' ? _kPinkBright : _getStatusColor(val);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filterStatus = val),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected ? color : color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? color : color.withOpacity(0.4),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
                  const CircularProgressIndicator(color: _kPinkBright),
                  const SizedBox(height: 16),
                  Text(
                    'Finding matching requests...',
                    style: TextStyle(color: Colors.white.withOpacity(0.6)),
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
                  color: Colors.red.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded, size: 52, color: Colors.redAccent),
              ),
              const SizedBox(height: 16),
              const Text(
                'Something went wrong',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6)),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadVolunteerProfile,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPinkBright,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  color: _kPinkBright.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.inbox_rounded, size: 56, color: _kPinkBright.withOpacity(0.5)),
              ),
              const SizedBox(height: 20),
              const Text(
                'No requests found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'There are no help requests to show right now.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6)),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _refreshRequests,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPinkBright,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _buildRequestCard(HelpRequest request) {
    final statusColor = _getStatusColor(request.status);
    final isMatch = _volunteerSpecialties.contains(request.requestType.toLowerCase()) &&
        _volunteerLanguages.contains(request.preferredLanguage?.toLowerCase() ?? 'english') &&
        request.status == 'pending';

    return GestureDetector(
      onTap: () => _showRequestActions(request),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _kCardFill,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.12),
                    ),
                  ),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(color: Colors.white),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _getStatusIcon(request.status),
                                  color: statusColor,
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
                                        Flexible(
                                          child: Text(
                                            request.requestType.toUpperCase(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Colors.white,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isMatch) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              gradient: _kAccentGradient,
                                              borderRadius: BorderRadius.circular(6),
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
                                    const SizedBox(height: 4),
                                    Text(
                                      request.blindUserName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.white70,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              _buildStatusBadge(request.status, statusColor),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (request.description.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                request.description,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          _cardChip(
                            Icons.location_on_rounded,
                            request.location,
                            Colors.white70,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (request.preferredLanguage != null)
                                _cardChip(
                                  Icons.language_rounded,
                                  _languageNames[request.preferredLanguage] ?? request.preferredLanguage!,
                                  _kBlueAccent,
                                ),
                              const Spacer(),
                              Text(
                                _formatDate(request.createdAt),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
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
        const SizedBox(width: 4),
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
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: _kNavyMid,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [statusColor, statusColor.withOpacity(0.7)],
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
                                  color: Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_getStatusIcon(request.status), color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      request.requestType.toUpperCase(),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    Text(
                                      'From: ${request.blindUserName}',
                                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              _buildStatusBadge(request.status, Colors.white.withOpacity(0.9)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        _detailRow(Icons.person_rounded, 'Name', request.blindUserName),
                        
// ── PHONE NUMBER (cleaned UI) ──
FutureBuilder<DocumentSnapshot>(
  future: firestore.collection('users').doc(request.blindUserId).get(),
  builder: (context, snapshot) {
    String activePhone = 'Loading...';
    if (snapshot.hasData && snapshot.data!.exists) {
      final userData = snapshot.data!.data() as Map<String, dynamic>?;
      activePhone = userData?['phoneNumber'] ?? userData?['phone'] ?? 'Not set';
    } else if (snapshot.hasError) {
      activePhone = 'Error loading number';
    } else if (snapshot.connectionState == ConnectionState.done) {
      activePhone = request.blindUserPhone;
    }

    final bool canCall = activePhone != 'Not set' && activePhone != 'Loading...' && activePhone != 'Error loading number';
    final bool showCallPrompt = canCall && (request.status == 'accepted' || request.status == 'in_progress');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: showCallPrompt ? Colors.green.shade900.withOpacity(0.3) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: showCallPrompt ? Colors.greenAccent.withOpacity(0.4) : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.phone_rounded, size: 18, color: showCallPrompt ? Colors.greenAccent : _kPinkBright),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phone',
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5)),
                ),
                const SizedBox(height: 2),
                Text(
                  activePhone,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: canCall ? Colors.white : Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          if (canCall) ...[
            if (showCallPrompt)
              // When call is appropriate, a filled call button
              Material(
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _callNumber(activePhone),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone_in_talk_rounded, size: 16, color: Colors.white),
                        SizedBox(width: 4),
                        Text('Call', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              )
            else
              // Otherwise just a call icon to keep it compact
              IconButton(
                icon: Icon(Icons.phone_forwarded_rounded, size: 20, color: _kPinkBright),
                onPressed: () => _callNumber(activePhone),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ],
      ),
    );
  },
),
                        
                        _detailRow(Icons.category_rounded, 'Type', request.requestType),
                        _detailRow(Icons.location_on_rounded, 'Location', request.location),
                        _detailRow(Icons.description_rounded, 'Description', request.description),
                        if (request.preferredLanguage != null)
                          _detailRow(Icons.language_rounded, 'Language',
                              _languageNames[request.preferredLanguage] ?? request.preferredLanguage!),
                        if (request.hasLocation) ...[
                          const SizedBox(height: 8),
                          _buildLocationPreview(request),
                        ],
                        const SizedBox(height: 8),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 12),
                        
                        if (request.status == 'pending') ...[
                          _actionButton(
                            label: 'Accept Request',
                            icon: Icons.check_circle_outline_rounded,
                            color: const Color(0xFF6EE7B7),
                            onTap: () async {
                              Navigator.pop(context);
                              await _acceptRequest(request, volunteer.uid, volunteerName);
                            },
                          ),
                          _actionButton(
                            label: 'Decline Request',
                            icon: Icons.cancel_outlined,
                            color: Colors.redAccent,
                            onTap: () async {
                              Navigator.pop(context);
                              await _declineRequest(request, volunteer.uid);
                            },
                          ),
                        ],
                        if (request.status == 'accepted')
                          _actionButton(
                            label: 'Mark as In Progress',
                            icon: Icons.hourglass_top_rounded,
                            color: Colors.blue.shade400,
                            onTap: () async {
                              Navigator.pop(context);
                              await _startHelp(request);
                            },
                          ),
                        if (request.status == 'in_progress')
                          _actionButton(
                            label: 'Mark as Completed',
                            icon: Icons.done_all_rounded,
                            color: const Color(0xFF6EE7B7),
                            onTap: () async {
                              Navigator.pop(context);
                              await _completeHelp(request);
                            },
                          ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.white.withOpacity(0.3)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Close', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _callNumber(String phoneNumber) async {
    if (phoneNumber.isEmpty || phoneNumber == 'Not set') return;
    final uri = Uri(scheme: 'tel', path: phoneNumber.trim());
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start a call to $phoneNumber')),
        );
      }
    }
  }

  Widget _buildLocationPreview(HelpRequest request) {
    final point = LatLng(request.latitude!, request.longitude!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 160,
        width: double.infinity,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 16.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.flutter_blindfriend',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: _kPinkBright,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: _kNavyDeep.withOpacity(0.85),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => launchUrl(Uri.parse(
                      'https://www.openstreetmap.org/?mlat=${point.latitude}&mlon=${point.longitude}#map=18/${point.latitude}/${point.longitude}')),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text('Open in Maps', style: TextStyle(fontSize: 12, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          Icon(icon, size: 16, color: _kPinkBright),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white70),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptRequest(HelpRequest request, String volunteerId, String volunteerName) async {
    try {
      final batch = firestore.batch();
      batch.update(firestore.collection('help_requests').doc(request.id), {
        'status': 'accepted',
        'volunteerId': volunteerId,
        'volunteerName': volunteerName,
        'acceptedAt': Timestamp.now(),
      });
      batch.set(
          firestore
              .collection('notifications')
              .doc(request.blindUserId)
              .collection('messages')
              .doc(),
          {
            'title': 'Request Accepted!',
            'body': 'Good news! $volunteerName has accepted your ${request.requestType} request.',
            'type': 'request_accepted',
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Request accepted successfully'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      await _loadMatchingRequests();
    }
  }

  Future<void> _startHelp(HelpRequest request) async {
    try {
      await firestore.collection('help_requests').doc(request.id).update({'status': 'in_progress'});
      await _loadMatchingRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Help marked as in progress')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
          backgroundColor: Colors.green,
        ));
        _showRateReminderDialog(request);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showRateReminderDialog(HelpRequest request) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kNavyMid,
        title: const Text('Remind Blind User?', style: TextStyle(color: Colors.white)),
        content: Text('Would you like to remind ${request.blindUserName} to rate your help?',
            style: TextStyle(color: Colors.white.withOpacity(0.8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Reminder sent to ${request.blindUserName}')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: _kPinkBright),
            child: const Text('Send Reminder'),
          ),
        ],
      ),
    );
  }

  Future<void> _declineRequest(HelpRequest request, String volunteerId) async {
    final reason = await _showDeclineReasonSheet();
    if (reason == null) return;

    try {
      final batch = firestore.batch();
      final Map<String, dynamic> updateData = {
        'declinedBy': FieldValue.arrayUnion([volunteerId]),
      };
      if (reason.isNotEmpty) {
        updateData['declineReasons.$volunteerId'] = reason;
      }
      batch.update(firestore.collection('help_requests').doc(request.id), updateData);
      batch.set(
          firestore
              .collection('notifications')
              .doc(request.blindUserId)
              .collection('messages')
              .doc(),
          {
            'title': 'Request Update',
            'body':
                'A volunteer was unable to accept your ${request.requestType} request. We are still searching for another volunteer.',
            'type': 'request_declined',
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
      await batch.commit();
      await _loadMatchingRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(reason.isEmpty ? 'Request declined' : 'Request declined: $reason'),
            backgroundColor: Colors.red.shade600));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<String?> _showDeclineReasonSheet() async {
    String? selectedQuickReason;
    final customController = TextEditingController();

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          const quickReasons = [
            'Too far away',
            'Not available now',
            'Outside my specialty',
            'Already occupied',
          ];

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: _kNavyMid,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Decline Request',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                            Text('Select or type an optional reason',
                                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: quickReasons.map((r) {
                        final isSelected = selectedQuickReason == r;
                        return GestureDetector(
                          onTap: () => setSheetState(() {
                            selectedQuickReason = isSelected ? null : r;
                            if (!isSelected) customController.clear();
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.redAccent : Colors.red.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? Colors.redAccent : Colors.red.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              r,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: isSelected ? Colors.white : Colors.redAccent,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: TextField(
                      controller: customController,
                      onChanged: (v) {
                        if (v.isNotEmpty) {
                          setSheetState(() => selectedQuickReason = null);
                        }
                      },
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Or type a custom reason (optional)...',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.3)),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      maxLines: 2,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.white.withOpacity(0.3)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final reason = selectedQuickReason ?? customController.text.trim();
                              Navigator.pop(ctx, reason);
                            },
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Decline'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    customController.dispose();
    return result;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange.shade600;
      case 'accepted':
        return Colors.blue.shade400;
      case 'in_progress':
        return Colors.cyan.shade600;
      case 'completed':
        return const Color(0xFF6EE7B7);
      case 'cancelled':
        return Colors.redAccent;
      default:
        return Colors.white60;
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