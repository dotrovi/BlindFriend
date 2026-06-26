import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'services/admin_service.dart';
import 'theme/app_palette.dart';

const double _kWideBreakpoint = 700;

class PendingVerificationsPage extends StatefulWidget {
  const PendingVerificationsPage({super.key});

  @override
  State<PendingVerificationsPage> createState() =>
      _PendingVerificationsPageState();
}

class _PendingVerificationsPageState extends State<PendingVerificationsPage> {
  final _adminService = AdminService();

  // Helper method to safely convert any value to String
  String _safeString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is List) return value.map((e) => e.toString()).join(', ');
    if (value is Map) return value.toString();
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kNavyDeep,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _kWideBreakpoint;
          return SingleChildScrollView(
            padding: EdgeInsets.all(isWide ? 32 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending Verifications',
                  style: TextStyle(
                    fontSize: isWide ? 28 : 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Review and approve volunteer applications',
                  style: TextStyle(fontSize: 15, color: Colors.white60),
                ),
                SizedBox(height: isWide ? 28 : 20),
                _buildStatsRow(isWide),
                SizedBox(height: isWide ? 28 : 20),
                _buildTable(isWide),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STATS ROW
  // ---------------------------------------------------------------------------

  Widget _buildStatsRow(bool isWide) {
    return StreamBuilder<QuerySnapshot>(
      stream: _adminService.getPendingVolunteers(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final total = docs.length;
        final readyCount = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['backgroundCheck'] == 'passed' &&
              data['trainingCompleted'] == true;
        }).length;

        final cards = [
          _statCard(
            icon: Icons.hourglass_empty,
            iconColor: kAmberAccent,
            label: 'Pending Applications',
            value: '$total',
          ),
          _statCard(
            icon: Icons.check_circle_outline,
            iconColor: kTealAccent,
            label: 'Ready to Approve',
            value: '$readyCount',
          ),
          _statCard(
            icon: Icons.search,
            iconColor: kPurpleAccent,
            label: 'Needs Review',
            value: '${total - readyCount}',
          ),
        ];

        if (!isWide) {
          return Column(
            children: cards
                .map((c) =>
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: c))
                .toList(),
          );
        }

        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 16),
            Expanded(child: cards[1]),
            const SizedBox(width: 16),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 13, color: Colors.white60),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
  // TABLE / LIST
  // ---------------------------------------------------------------------------

  Widget _buildTable(bool isWide) {
    return Container(
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (desktop only)
          if (isWide)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: const Row(
                children: [
                  Expanded(flex: 3, child: _HeaderCell('Applicant')),
                  Expanded(flex: 3, child: _HeaderCell('Contact')),
                  Expanded(flex: 2, child: _HeaderCell('Applied')),
                  Expanded(flex: 3, child: _HeaderCell('Qualifications')),
                ],
              ),
            ),

          // Body
          StreamBuilder<QuerySnapshot>(
            stream: _adminService.getPendingVolunteers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(
                      child: CircularProgressIndicator(color: kPinkBright)),
                );
              }

              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(
                    child: Text(
                      'Could not load data. Please try again.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 64),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined,
                            size: 48, color: Colors.white.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        const Text(
                          'No volunteers pending approval',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'New volunteer applications will appear here.',
                          style: TextStyle(fontSize: 13, color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _VolunteerRow(
                    uid: doc.id,
                    data: data,
                    adminService: _adminService,
                    isWide: isWide,
                    onTap: (enrichedData) => _showDetailsDialog(enrichedData),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DETAILS POPUP
  // ---------------------------------------------------------------------------

  void _showDetailsDialog(Map<String, dynamic> data) {
    final uid = data['uid'] ?? '';
    final name = _safeString(data['name']);
    final email = _safeString(data['email']);
    final phone = _safeString(data['phoneNumber']);
    final idCard = _safeString(data['idCardNumber']);
    final language = _safeString(data['language']);

    // Safely handle specialties - could be List or String
    List<String> specialties = [];
    final specialtiesData = data['specialties'];
    if (specialtiesData is List) {
      specialties = specialtiesData.map((e) => e.toString()).toList();
    } else if (specialtiesData is String) {
      specialties = [specialtiesData];
    } else if (specialtiesData != null) {
      specialties = [specialtiesData.toString()];
    }

    final availability = _safeString(data['availability']);
    final backgroundCheck = _safeString(data['backgroundCheck'] ?? 'pending');
    final trainingDone = data['trainingCompleted'] == true;
    final submittedAt = data['submittedAt'] as Timestamp?;

    final dateStr = submittedAt != null
        ? '${submittedAt.toDate().day.toString().padLeft(2, '0')}/'
            '${submittedAt.toDate().month.toString().padLeft(2, '0')}/'
            '${submittedAt.toDate().year}'
        : 'N/A';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        backgroundColor: kNavyMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Volunteer Details',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                Divider(height: 20, color: Colors.white.withValues(alpha: 0.08)),

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailCard('Personal Information', [
                          _detailRow('Name:', name.isNotEmpty ? name : '—'),
                          _detailRow('Email:', email.isNotEmpty ? email : '—'),
                          _detailRow('Phone:', phone.isNotEmpty ? phone : '—'),
                          _detailRow(
                              'IC Number:', idCard.isNotEmpty ? idCard : '—'),
                          _detailRow('Applied:', dateStr),
                        ]),
                        const SizedBox(height: 12),
                        _buildDetailCard('Verification Status', [
                          _statusRow(
                            label: 'Background Check',
                            passed: backgroundCheck == 'passed',
                            text: backgroundCheck == 'passed'
                                ? 'Passed'
                                : 'Pending',
                          ),
                          const SizedBox(height: 4),
                          _statusRow(
                            label: 'Training Status',
                            passed: trainingDone,
                            text: trainingDone ? 'Completed' : 'Incomplete',
                          ),
                        ]),
                        const SizedBox(height: 12),
                        _buildDetailCard('Volunteer Information', [
                          _detailRow('Language:',
                              language.isNotEmpty ? language : '—'),
                          _detailRow('Availability:',
                              availability.isNotEmpty ? availability : '—'),
                          _detailRow(
                              'Specialties:',
                              specialties.isNotEmpty
                                  ? specialties.join(', ')
                                  : 'None'),
                        ]),
                      ],
                    ),
                  ),
                ),

                Divider(height: 20, color: Colors.white.withValues(alpha: 0.08)),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kTealAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showApproveDialog(uid, name, email);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Reject'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kRedAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showRejectDialog(uid, name, email);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD DETAIL CARD
  // ---------------------------------------------------------------------------

  Widget _buildDetailCard(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DETAIL ROW
  // ---------------------------------------------------------------------------

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STATUS ROW
  // ---------------------------------------------------------------------------

  Widget _statusRow({
    required String label,
    required bool passed,
    required String text,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white70),
          ),
        ),
        Icon(
          passed ? Icons.check_circle : Icons.schedule,
          size: 16,
          color: passed ? kTealAccent : kAmberAccent,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: passed ? kTealAccent : kAmberAccent,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // APPROVE DIALOG
  // ---------------------------------------------------------------------------

  void _showApproveDialog(String uid, String name, String email) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kNavyMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Approve Application', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to approve $name as a volunteer?\n\nThey will be notified by in-app message and email.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: Colors.white60),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kTealAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _adminService.approveVolunteer(
                uid: uid,
                volunteerName: name,
                volunteerEmail: email,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$name has been approved!'),
                    backgroundColor: kTealAccent,
                  ),
                );
              }
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // REJECT DIALOG
  // ---------------------------------------------------------------------------

  void _showRejectDialog(String uid, String name, String email) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kNavyMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Application', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Reject $name's application?",
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            const Text('Reason (optional):',
                style: TextStyle(fontSize: 13, color: Colors.white60)),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. Incomplete documents...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: Colors.white60),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kRedAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _adminService.rejectVolunteer(
                uid: uid,
                volunteerName: name,
                volunteerEmail: email,
                reason: reasonController.text.trim().isNotEmpty
                    ? reasonController.text.trim()
                    : 'Your application did not meet our current requirements.',
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("$name's application has been rejected."),
                    backgroundColor: kRedAccent,
                  ),
                );
              }
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VOLUNTEER ROW
// Separate widget so each row handles its own fallback fetch independently.
// Renders as a flex-column table row on wide screens, or a stacked card on
// narrow ones.
// ---------------------------------------------------------------------------

class _VolunteerRow extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> data;
  final AdminService adminService;
  final bool isWide;
  final Function(Map<String, dynamic> enrichedData) onTap;

  const _VolunteerRow({
    required this.uid,
    required this.data,
    required this.adminService,
    required this.isWide,
    required this.onTap,
  });

  @override
  State<_VolunteerRow> createState() => _VolunteerRowState();
}

class _VolunteerRowState extends State<_VolunteerRow> {
  late Map<String, dynamic> _data;
  bool _loading = true;

  // Helper function to safely get string value
  String _safeString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is List) return value.join(', ');
    return value.toString();
  }

  @override
  void initState() {
    super.initState();
    _data = {...widget.data, 'uid': widget.uid};
    _fetchMissingInfo();
  }

  Future<void> _fetchMissingInfo() async {
    final nameIsMissing = (_data['name'] ?? '').toString().isEmpty;
    final emailIsMissing = (_data['email'] ?? '').toString().isEmpty;

    if (nameIsMissing || emailIsMissing) {
      final userInfo = await widget.adminService.getUserInfo(widget.uid);
      if (userInfo != null && mounted) {
        setState(() {
          if (nameIsMissing) _data['name'] = userInfo['name'] ?? '';
          if (emailIsMissing) _data['email'] = userInfo['email'] ?? '';
        });
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: kPinkBright),
          ),
        ),
      );
    }

    return widget.isWide ? _buildWideRow() : _buildMobileCard();
  }

  Widget _buildWideRow() {
    final name = _safeString(_data['name']);
    final email = _safeString(_data['email']);
    final phone = _safeString(_data['phoneNumber']);
    final language = _safeString(_data['language']);
    final submittedAt = _data['submittedAt'] as Timestamp?;
    final backgroundCheck = _safeString(_data['backgroundCheck'] ?? 'pending');
    final trainingDone = _data['trainingCompleted'] == true;

    final dateStr = submittedAt != null
        ? '${submittedAt.toDate().day.toString().padLeft(2, '0')}/'
            '${submittedAt.toDate().month.toString().padLeft(2, '0')}/'
            '${submittedAt.toDate().year}'
        : 'N/A';

    final daysAgo = submittedAt != null
        ? DateTime.now().difference(submittedAt.toDate()).inDays
        : 0;

    return InkWell(
      onTap: () => widget.onTap(_data),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
        ),
        child: Row(
          children: [
            // Applicant
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isNotEmpty ? name : 'Unknown',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                  Text(
                    language.isNotEmpty ? language : '—',
                    style: const TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                ],
              ),
            ),

            // Contact
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.email_outlined, size: 13, color: Colors.white38),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        email.isNotEmpty ? email : '—',
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.phone_outlined, size: 13, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text(
                      phone.isNotEmpty ? phone : '—',
                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ]),
                ],
              ),
            ),

            // Applied
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateStr, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  Text(
                    '$daysAgo day${daysAgo == 1 ? '' : 's'} ago',
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
            ),

            // Qualifications
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _qualBadge(
                    label: backgroundCheck == 'passed'
                        ? 'Background Passed'
                        : 'Background Pending',
                    passed: backgroundCheck == 'passed',
                  ),
                  const SizedBox(height: 4),
                  _qualBadge(
                    label:
                        trainingDone ? 'Training Done' : 'Training Incomplete',
                    passed: trainingDone,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCard() {
    final name = _safeString(_data['name']);
    final email = _safeString(_data['email']);
    final phone = _safeString(_data['phoneNumber']);
    final language = _safeString(_data['language']);
    final submittedAt = _data['submittedAt'] as Timestamp?;
    final backgroundCheck = _safeString(_data['backgroundCheck'] ?? 'pending');
    final trainingDone = _data['trainingCompleted'] == true;

    final dateStr = submittedAt != null
        ? '${submittedAt.toDate().day.toString().padLeft(2, '0')}/'
            '${submittedAt.toDate().month.toString().padLeft(2, '0')}/'
            '${submittedAt.toDate().year}'
        : 'N/A';

    return InkWell(
      onTap: () => widget.onTap(_data),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name.isNotEmpty ? name : 'Unknown',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(dateStr,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white38)),
              ],
            ),
            if (language.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(language,
                  style: const TextStyle(fontSize: 12, color: Colors.white38)),
            ],
            const SizedBox(height: 8),
            if (email.isNotEmpty)
              Row(children: [
                const Icon(Icons.email_outlined,
                    size: 13, color: Colors.white38),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    email,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.phone_outlined,
                    size: 13, color: Colors.white38),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white70)),
                ),
              ]),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _qualBadge(
                  label: backgroundCheck == 'passed'
                      ? 'Background Passed'
                      : 'Background Pending',
                  passed: backgroundCheck == 'passed',
                ),
                _qualBadge(
                  label: trainingDone ? 'Training Done' : 'Training Incomplete',
                  passed: trainingDone,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _qualBadge({required String label, required bool passed}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          passed ? Icons.check_circle : Icons.schedule,
          size: 13,
          color: passed ? kTealAccent : kAmberAccent,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: passed ? kTealAccent : kAmberAccent,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// HEADER CELL
// ---------------------------------------------------------------------------

class _HeaderCell extends StatelessWidget {
  final String label;
  const _HeaderCell(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white60),
    );
  }
}
