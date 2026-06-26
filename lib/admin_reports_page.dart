import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'theme/app_palette.dart';

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
        return kAmberAccent;
      case 'reviewed':
        return kBlueAccent;
      case 'resolved':
        return kTealAccent;
      default:
        return Colors.white60;
    }
  }

  // Returns a colour for each report type badge
  Color _reportTypeColor(String reportType) {
    switch (reportType) {
      case 'no_show':
        return kRedAccent;
      case 'inappropriate_behaviour':
        return kPurpleAccent;
      case 'did_not_complete':
        return kAmberAccent;
      case 'other':
        return kBlueAccent;
      default:
        return Colors.white60;
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
            backgroundColor: kTealAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update status. Please try again.'),
            backgroundColor: kRedAccent,
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
      backgroundColor: kNavyMid,
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
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
                          : Colors.white70,
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
    return Container(
      color: kNavyDeep,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          final horizontalPadding = isWide ? 32.0 : 16.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Page header ──
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                    horizontalPadding, isWide ? 32 : 20, horizontalPadding, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reports',
                      style: TextStyle(
                        fontSize: isWide ? 28 : 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Reports submitted by blind users against volunteers',
                      style: TextStyle(fontSize: 13, color: Colors.white60),
                    ),
                    const SizedBox(height: 16),
                    // ── Filter bar ──
                    _buildFilterBar(),
                  ],
                ),
              ),
              // ── Reports list ──
              Expanded(child: _buildReportsList(horizontalPadding)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterBar() {
    final filters = ['all', 'pending', 'reviewed', 'resolved'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
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
                color: isSelected
                    ? kRedAccent
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? kRedAccent
                      : Colors.white.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                filter[0].toUpperCase() + filter.substring(1),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
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

  Widget _buildReportsList(double horizontalPadding) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('reports')
        .orderBy('createdAt', descending: true);

    if (_selectedFilter != 'all') {
      query = query.where('status', isEqualTo: _selectedFilter);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: kPinkBright),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading reports.\n${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: kRedAccent),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.flag_outlined,
                    size: 60, color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text(
                  _selectedFilter == 'all'
                      ? 'No reports submitted yet.'
                      : 'No $_selectedFilter reports.',
                  style: const TextStyle(fontSize: 15, color: Colors.white60),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
              horizontalPadding, 8, horizontalPadding, horizontalPadding),
          physics: const AlwaysScrollableScrollPhysics(),
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

    String formattedDate = 'Date unknown';
    if (createdAt != null) {
      final dt = createdAt.toDate();
      formattedDate =
          '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return LayoutBuilder(
      builder: (context, cardConstraints) {
        // If the single card space drops below 340px, stack badge under name cleanly
        final isCompactCard = cardConstraints.maxWidth < 340;

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: kCardFill.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top section: Volunteer Header & Status Badge ──
                if (isCompactCard)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 18, color: Colors.white54),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              volunteerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildStatusBadge(docId, status),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.person_outline, size: 18, color: Colors.white54),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Volunteer: $volunteerName',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(docId, status),
                    ],
                  ),

                const SizedBox(height: 12),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                const SizedBox(height: 12),

                // ── Reason Badge row ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.flag_rounded, size: 16, color: _reportTypeColor(reportType)),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Reason: ',
                      style: TextStyle(fontSize: 13, color: Colors.white60),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _reportTypeColor(reportType).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _formatReportType(reportType),
                            maxLines: 2, // Wraps neatly if string is long on narrow screens
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _reportTypeColor(reportType),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // ── Request details row ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(Icons.help_outline, size: 16, color: Colors.white38),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Request type: $requestType',
                        maxLines: 2,
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ),
                  ],
                ),

                // ── User's description ──
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Text(
                      '"$description"',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        fontStyle: FontStyle.italic,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // ── Date stamp ──
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text(
                      formattedDate,
                      style: const TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(String docId, String status) {
    return GestureDetector(
      onTap: () => _showStatusPicker(docId, status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _statusColor(status).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _statusColor(status).withValues(alpha: 0.4)),
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
            Icon(Icons.expand_more, size: 14, color: _statusColor(status)),
          ],
        ),
      ),
    );
  }
}