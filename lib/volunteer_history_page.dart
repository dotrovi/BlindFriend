import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'volunteer_received_request.dart';

// ── Shared palette ─────────────────────────────────────────────────
const Color _kNavyDeep = Color(0xFF120A2E);
const Color _kNavyMid = Color(0xFF1E1147);
const Color _kPurple = Color(0xFF3B1E78);
const Color _kPinkBright = Color(0xFFFF5FD2);
const Color _kBlueAccent = Color(0xFF4A90E2);
const Color _kCardFill = Color(0xFF241A45);

class VolunteerHistoryPage extends StatefulWidget {
  const VolunteerHistoryPage({super.key});

  @override
  State<VolunteerHistoryPage> createState() => _VolunteerHistoryPageState();
}

class _VolunteerHistoryPageState extends State<VolunteerHistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  List<HelpRequest> _completedRequests = [];
  List<HelpRequest> _declinedRequests = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _volunteerId;

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
    _tabController = TabController(length: 2, vsync: this);
    _volunteerId = auth.currentUser?.uid;
    _loadHistory();
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final volunteerId = _volunteerId;
      if (volunteerId == null) throw Exception('Not logged in');

      final completedSnap = await firestore
          .collection('help_requests')
          .where('volunteerId', isEqualTo: volunteerId)
          .where('status', isEqualTo: 'completed')
          .get();

      final declinedSnap = await firestore
          .collection('help_requests')
          .where('declinedBy', arrayContains: volunteerId)
          .get();

      final completed = completedSnap.docs
          .map((d) => HelpRequest.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => (b.completedAt ?? b.createdAt)
            .compareTo(a.completedAt ?? a.createdAt));

      final declined = declinedSnap.docs
          .map((d) => HelpRequest.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _completedRequests = completed;
        _declinedRequests = declined;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kNavyDeep,
      child: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: _isLoading
                ? _buildLoading()
                : _errorMessage != null
                    ? _buildError()
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildRequestList(_completedRequests, _HistoryType.completed),
                          _buildRequestList(_declinedRequests, _HistoryType.declined),
                        ],
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
          const Icon(Icons.history_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'My History',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          GestureDetector(
            onTap: _loadHistory,
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

  Widget _buildTabBar() {
    return Container(
      color: _kNavyMid,
      child: TabBar(
        controller: _tabController,
        indicatorColor: _kPinkBright,
        labelColor: _kPinkBright,
        unselectedLabelColor: Colors.white.withOpacity(0.5),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        tabs: [
          _tab(Icons.done_all_rounded, 'Completed', _completedRequests.length, const Color(0xFF6EE7B7)),
          _tab(Icons.cancel_outlined, 'Declined', _declinedRequests.length, Colors.redAccent),
        ],
      ),
    );
  }

  Tab _tab(IconData icon, String label, int count, Color color) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text('$label ($count)'),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _kPinkBright),
          const SizedBox(height: 16),
          Text('Loading history...', style: TextStyle(color: Colors.white.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildError() {
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
              onPressed: _loadHistory,
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

  Widget _buildRequestList(List<HelpRequest> requests, _HistoryType type) {
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
                  color: type.color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(type.icon, size: 56, color: type.color.withOpacity(0.5)),
              ),
              const SizedBox(height: 20),
              Text(
                type.emptyTitle,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                type.emptySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6)),
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
      itemBuilder: (context, index) => _buildHistoryCard(requests[index], type),
    );
  }

  Widget _buildHistoryCard(HelpRequest request, _HistoryType type) {
    final myReason = type == _HistoryType.declined
        ? request.declineReasons[_volunteerId ?? '']
        : null;

    return GestureDetector(
      onTap: () => _showRequestDetail(request, type),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent bar
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: type.color,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                  ),
                ),
              ),
              // Main card body
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _kCardFill,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: type.color.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(color: Colors.white),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: type.color.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(type.icon, color: type.color, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      request.requestType.toUpperCase(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      request.blindUserName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _statusBadge(type.label, type.color),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            request.description,
                            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (myReason != null && myReason.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.comment_outlined, size: 13, color: Colors.redAccent),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      myReason,
                                      style: TextStyle(fontSize: 12, color: Colors.redAccent),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _cardChip(Icons.location_on_rounded, request.location, Colors.white60),
                                const SizedBox(width: 8),
                                if (request.preferredLanguage != null)
                                  _cardChip(
                                    Icons.language_rounded,
                                    _languageNames[request.preferredLanguage] ?? request.preferredLanguage!,
                                    _kBlueAccent,
                                  ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDate(_dateForType(request, type)),
                                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4)),
                                ),
                              ],
                            ),
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

  Timestamp _dateForType(HelpRequest r, _HistoryType type) {
    switch (type) {
      case _HistoryType.completed:
        return r.completedAt ?? r.createdAt;
      case _HistoryType.declined:
        return r.createdAt;
    }
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
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

  void _showRequestDetail(HelpRequest request, _HistoryType type) {
    final myReason = type == _HistoryType.declined
        ? request.declineReasons[_volunteerId ?? '']
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: _kNavyMid,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [type.color, type.color.withOpacity(0.7)],
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
                        child: Icon(type.icon, color: Colors.white, size: 22),
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
                              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      _statusBadge(type.label, Colors.white.withOpacity(0.9)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _detailRow(Icons.person_rounded, 'Name', request.blindUserName),
                      _detailRow(Icons.phone_rounded, 'Phone', request.blindUserPhone),
                      _detailRow(Icons.category_rounded, 'Type', request.requestType),
                      _detailRow(Icons.location_on_rounded, 'Location', request.location),
                      _detailRow(Icons.description_rounded, 'Description', request.description),
                      if (request.preferredLanguage != null)
                        _detailRow(Icons.language_rounded, 'Language',
                            _languageNames[request.preferredLanguage] ?? request.preferredLanguage!),
                      _detailRow(Icons.access_time_rounded, 'Requested', _formatDate(request.createdAt)),
                      if (type == _HistoryType.completed && request.completedAt != null)
                        _detailRow(Icons.done_all_rounded, 'Completed', _formatDate(request.completedAt!)),
                      if (myReason != null && myReason.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.comment_outlined, size: 15, color: Colors.redAccent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Your decline reason',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      myReason,
                                      style: TextStyle(fontSize: 13, color: Colors.redAccent),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} '
        '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

enum _HistoryType {
  completed,
  declined;

  Color get color {
    switch (this) {
      case _HistoryType.completed:
        return const Color(0xFF6EE7B7);
      case _HistoryType.declined:
        return Colors.redAccent;
    }
  }

  IconData get icon {
    switch (this) {
      case _HistoryType.completed:
        return Icons.done_all_rounded;
      case _HistoryType.declined:
        return Icons.cancel_outlined;
    }
  }

  String get label {
    switch (this) {
      case _HistoryType.completed:
        return 'COMPLETED';
      case _HistoryType.declined:
        return 'DECLINED';
    }
  }

  String get emptyTitle {
    switch (this) {
      case _HistoryType.completed:
        return 'No completed requests yet';
      case _HistoryType.declined:
        return 'No declined requests';
    }
  }

  String get emptySubtitle {
    switch (this) {
      case _HistoryType.completed:
        return 'Help requests you complete will appear here.';
      case _HistoryType.declined:
        return 'Requests you decline will appear here.';
    }
  }
}