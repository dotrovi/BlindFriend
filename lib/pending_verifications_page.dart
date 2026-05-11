import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'services/admin_service.dart';

class PendingVerificationsPage extends StatefulWidget {
  const PendingVerificationsPage({super.key});

  @override
  State<PendingVerificationsPage> createState() =>
      _PendingVerificationsPageState();
}

class _PendingVerificationsPageState extends State<PendingVerificationsPage> {
  final _adminService = AdminService();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pending Verifications',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Review and approve volunteer applications',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 28),
          _buildStatsRow(),
          const SizedBox(height: 28),
          _buildTable(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STATS ROW
  // ---------------------------------------------------------------------------

  Widget _buildStatsRow() {
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

        return Row(
          children: [
            Expanded(
              child: _statCard(
                icon: Icons.hourglass_empty,
                iconColor: Colors.orange,
                label: 'Pending Applications',
                value: '$total',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _statCard(
                icon: Icons.check_circle_outline,
                iconColor: Colors.green,
                label: 'Ready to Approve',
                value: '$readyCount',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _statCard(
                icon: Icons.search,
                iconColor: Colors.deepPurple,
                label: 'Needs Review',
                value: '${total - readyCount}',
              ),
            ),
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TABLE
  // ---------------------------------------------------------------------------

  Widget _buildTable() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
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
                  child: Center(child: CircularProgressIndicator(color: Colors.deepPurple)),
                );
              }

              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: Text(
                      'Could not load data. Please try again.',
                      style: TextStyle(color: Colors.grey.shade600),
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
                            size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        const Text(
                          'No volunteers pending approval',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'New volunteer applications will appear here.',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500),
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
    final name = data['name'] ?? '';
    final email = data['email'] ?? '';
    final phone = data['phoneNumber'] ?? '';
    final idCard = data['idCardNumber'] ?? '';
    final language = data['language'] ?? '';
    final specialties = List<String>.from(data['specialties'] ?? []);
    final availability = data['availability'] ?? '';
    final backgroundCheck = data['backgroundCheck'] ?? 'pending';
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
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Application Details',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Scrollable content
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('Applicant Information'),
                        const SizedBox(height: 10),
                        _infoRow('Name', name.isNotEmpty ? name : '—'),
                        _infoRow('Email', email.isNotEmpty ? email : '—'),
                        _infoRow('Phone', phone.isNotEmpty ? phone : '—'),
                        _infoRow('IC Number', idCard.isNotEmpty ? idCard : '—'),
                        _infoRow('Applied', dateStr),
                        const SizedBox(height: 20),

                        _sectionTitle('Verification Status'),
                        const SizedBox(height: 10),
                        _statusRow(
                          label: 'Background Check',
                          passed: backgroundCheck == 'passed',
                          text: backgroundCheck == 'passed' ? 'Passed' : 'Pending',
                        ),
                        const SizedBox(height: 6),
                        _statusRow(
                          label: 'Training Status',
                          passed: trainingDone,
                          text: trainingDone ? 'Completed' : 'Incomplete',
                        ),
                        const SizedBox(height: 20),

                        _sectionTitle('Language'),
                        const SizedBox(height: 8),
                        language.isNotEmpty
                            ? _chip(language)
                            : Text('Not specified',
                                style: TextStyle(color: Colors.grey.shade500)),
                        const SizedBox(height: 20),

                        _sectionTitle('Specialties'),
                        const SizedBox(height: 8),
                        specialties.isEmpty
                            ? Text('None listed',
                                style: TextStyle(color: Colors.grey.shade500))
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: specialties.map((s) => _chip(s)).toList(),
                              ),
                        const SizedBox(height: 20),

                        _sectionTitle('Availability'),
                        const SizedBox(height: 8),
                        _chip(availability.isNotEmpty ? availability : 'Not set'),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 28),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
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
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
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
  // APPROVE DIALOG
  // ---------------------------------------------------------------------------

  void _showApproveDialog(String uid, String name, String email) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Approve Application'),
        content: Text(
          'Are you sure you want to approve $name as a volunteer?\n\nThey will be notified by in-app message and email.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                    backgroundColor: Colors.green,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Application'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Reject $name's application?"),
            const SizedBox(height: 16),
            const Text('Reason (optional):',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'e.g. Incomplete documents...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                    backgroundColor: Colors.red,
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

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _statusRow({
    required String label,
    required bool passed,
    required String text,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text('$label:', style: const TextStyle(fontSize: 14)),
        ),
        Icon(
          passed ? Icons.check_circle : Icons.schedule,
          size: 16,
          color: passed ? Colors.green : Colors.orange,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: passed ? Colors.green.shade700 : Colors.orange.shade700,
          ),
        ),
      ],
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, color: Colors.deepPurple.shade700),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VOLUNTEER ROW
// Separate widget so each row handles its own fallback fetch independently
// ---------------------------------------------------------------------------

class _VolunteerRow extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> data;
  final AdminService adminService;
  final Function(Map<String, dynamic> enrichedData) onTap;

  const _VolunteerRow({
    required this.uid,
    required this.data,
    required this.adminService,
    required this.onTap,
  });

  @override
  State<_VolunteerRow> createState() => _VolunteerRowState();
}

class _VolunteerRowState extends State<_VolunteerRow> {
  late Map<String, dynamic> _data;
  bool _loading = true;

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
    final name = _data['name'] ?? '';
    final email = _data['email'] ?? '';
    final phone = _data['phoneNumber'] ?? '';
    final submittedAt = _data['submittedAt'] as Timestamp?;
    final backgroundCheck = _data['backgroundCheck'] ?? 'pending';
    final trainingDone = _data['trainingCompleted'] == true;

    final dateStr = submittedAt != null
        ? '${submittedAt.toDate().day.toString().padLeft(2, '0')}/'
            '${submittedAt.toDate().month.toString().padLeft(2, '0')}/'
            '${submittedAt.toDate().year}'
        : 'N/A';

    final daysAgo = submittedAt != null
        ? DateTime.now().difference(submittedAt.toDate()).inDays
        : 0;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => widget.onTap(_data),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
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
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    _data['language'] ?? '—',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
                    Icon(Icons.email_outlined, size: 13, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        email.isNotEmpty ? email : '—',
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.phone_outlined, size: 13, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(
                      phone.isNotEmpty ? phone : '—',
                      style: const TextStyle(fontSize: 13),
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
                  Text(dateStr, style: const TextStyle(fontSize: 13)),
                  Text(
                    '$daysAgo day${daysAgo == 1 ? '' : 's'} ago',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
                    label: trainingDone ? 'Training Done' : 'Training Incomplete',
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

  Widget _qualBadge({required String label, required bool passed}) {
    return Row(
      children: [
        Icon(
          passed ? Icons.check_circle : Icons.schedule,
          size: 13,
          color: passed ? Colors.green : Colors.orange,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: passed ? Colors.green.shade700 : Colors.orange.shade700,
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
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    );
  }
}