import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  // Filter: 'all', 'pending', 'reviewed', 'resolved'
  String _selectedFilter = 'all';

  // Maps the raw reportType id to a readable label
  String _formatReportType(String reportType) {
    switch (reportType) {
      case 'no_show':
        return 'No Show';
      case 'inappropriate_behaviour':
        return 'Inappropriate Behaviour';
      case 'did_not_complete':
        return 'Did Not Complete Task';
      case 'other':
        return 'Other';
      default:
        return reportType;
    }
  }

  // Returns a colour for each status badge
  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange.shade700;
      case 'reviewed':
        return Colors.blue.shade700;
      case 'resolved':
        return Colors.green.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  Color _statusBgColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange.shade50;
      case 'reviewed':
        return Colors.blue.shade50;
      case 'resolved':
        return Colors.green.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  // Returns a colour for each report type badge
  Color _reportTypeColor(String reportType) {
    switch (reportType) {
      case 'no_show':
        return Colors.red.shade700;
      case 'inappropriate_behaviour':
        return Colors.deepPurple.shade700;
      case 'did_not_complete':
        return Colors.amber.shade800;
      case 'other':
        return Colors.blueGrey.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  // Updates the status field of a report document in Firestore
  Future<void> _updateStatus(String docId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(docId)
          .update({'status': newStatus});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to "$newStatus".'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update status. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Shows a bottom sheet so the admin can pick a new status
  void _showStatusPicker(String docId, String currentStatus) {
    final statuses = ['pending', 'reviewed', 'resolved'];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Update Report Status',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...statuses.map((status) {
                final isCurrentStatus = status == currentStatus;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 6,
                    backgroundColor: _statusColor(status),
                  ),
                  title: Text(
                    status[0].toUpperCase() + status.substring(1),
                    style: TextStyle(
                      fontWeight:
                          isCurrentStatus ? FontWeight.bold : FontWeight.normal,
                      color: isCurrentStatus
                          ? _statusColor(status)
                          : Colors.black87,
                    ),
                  ),
                  trailing: isCurrentStatus
                      ? Icon(Icons.check, color: _statusColor(status))
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    if (!isCurrentStatus) {
                      _updateStatus(docId, status);
                    }
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // No Scaffold or AppBar here — this widget sits inside AdminDashboardPage
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Page header ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reports',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Reports submitted by blind users against volunteers',
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              // ── Filter bar ──
              _buildFilterBar(),
            ],
          ),
        ),
        // ── Reports list ──
        Expanded(child: _buildReportsList()),
      ],
    );
  }

  Widget _buildFilterBar() {
    final filters = ['all', 'pending', 'reviewed', 'resolved'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8, bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.red.shade700 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color:
                      isSelected ? Colors.red.shade700 : Colors.grey.shade300,
                ),
              ),
              child: Text(
                filter[0].toUpperCase() + filter.substring(1),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReportsList() {
    // Build the Firestore query based on the selected filter
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('reports')
        .orderBy('createdAt', descending: true);

    if (_selectedFilter != 'all') {
      query = query.where('status', isEqualTo: _selectedFilter);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        // Still loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Error from Firestore
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading reports.\n${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        // No reports found
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.flag_outlined,
                    size: 60, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  _selectedFilter == 'all'
                      ? 'No reports submitted yet.'
                      : 'No $_selectedFilter reports.',
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildReportCard(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildReportCard(String docId, Map<String, dynamic> data) {
    final volunteerName = data['volunteerName'] ?? 'Unknown Volunteer';
    final reportType = data['reportType'] ?? '';
    final requestType = data['requestType'] ?? '';
    final description = data['description'] ?? '';
    final status = data['status'] ?? 'pending';
    final createdAt = data['createdAt'] as Timestamp?;

    // Format the date nicely
    String formattedDate = 'Date unknown';
    if (createdAt != null) {
      final dt = createdAt.toDate();
      formattedDate =
          '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: volunteer name + status badge ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.person_outline,
                    size: 18, color: Colors.black54),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Volunteer: $volunteerName',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                // Status badge — tap to change status
                GestureDetector(
                  onTap: () => _showStatusPicker(docId, status),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusBgColor(status),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _statusColor(status)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          status[0].toUpperCase() + status.substring(1),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _statusColor(status),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.expand_more,
                            size: 14, color: _statusColor(status)),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // ── Report type ──
            Row(
              children: [
                Icon(Icons.flag_rounded,
                    size: 16, color: _reportTypeColor(reportType)),
                const SizedBox(width: 6),
                Text(
                  'Reason: ',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _reportTypeColor(reportType).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _formatReportType(reportType),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _reportTypeColor(reportType),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Request type ──
            Row(
              children: [
                Icon(Icons.help_outline, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  'Request type: $requestType',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ),

            // ── Description (only show if not empty) ──
            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  '"$description"',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 10),

            // ── Date ──
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  formattedDate,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
