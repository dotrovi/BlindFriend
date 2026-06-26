import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'theme/app_palette.dart';

const double _kWideBreakpoint = 700;

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final firestore = FirebaseFirestore.instance;
  String _searchQuery = '';
  String _sortBy = 'name'; // 'name' or 'createdAt'
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kNavyDeep,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _kWideBreakpoint;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isWide ? 32 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with gradient
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: kAccentGradient,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.people,
                                  color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Users Management',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: isWide ? 26 : 20,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'View and manage blind users',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white
                                            .withValues(alpha: 0.8)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isWide ? 32 : 20),

                      // Search bar
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: kCardFill.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: TextField(
                          onChanged: (value) => setState(
                              () => _searchQuery = value.toLowerCase()),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search users by name or email...',
                            hintStyle: const TextStyle(color: Colors.white38),
                            prefixIcon: const Icon(Icons.search,
                                color: Colors.white54),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close,
                                        color: Colors.white54),
                                    onPressed: () =>
                                        setState(() => _searchQuery = ''),
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color:
                                      Colors.white.withValues(alpha: 0.15)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color:
                                      Colors.white.withValues(alpha: 0.15)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: kPinkBright, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Sort controls
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kCardFill.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            const Text(
                              'Sort by:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white70),
                            ),
                            _sortChip('Name', 'name'),
                            _sortChip('Join Date', 'createdAt'),
                            IconButton(
                              icon: Icon(
                                  _sortAscending
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  color: Colors.white70),
                              tooltip:
                                  _sortAscending ? 'Ascending' : 'Descending',
                              onPressed: () {
                                setState(() {
                                  _sortAscending = !_sortAscending;
                                });
                              },
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(8),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Users list/table
                      FutureBuilder<QuerySnapshot>(
                        future: firestore
                            .collection('users')
                            .where('userType', isEqualTo: 'blind')
                            .get(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator(
                                    color: kPinkBright));
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text('Error: ${snapshot.error}',
                                  style:
                                      const TextStyle(color: kRedAccent)),
                            );
                          }

                          final docs = snapshot.data?.docs ?? [];

                          var filteredDocs = docs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final name = (data['name'] ?? '')
                                .toString()
                                .toLowerCase();
                            final email = (data['email'] ?? '')
                                .toString()
                                .toLowerCase();
                            return name.contains(_searchQuery) ||
                                email.contains(_searchQuery);
                          }).toList();

                          filteredDocs.sort((a, b) {
                            final dataA = a.data() as Map<String, dynamic>;
                            final dataB = b.data() as Map<String, dynamic>;

                            int comparison = 0;

                            if (_sortBy == 'name') {
                              final nameA = (dataA['name'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              final nameB = (dataB['name'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              comparison = nameA.compareTo(nameB);
                            } else if (_sortBy == 'createdAt') {
                              final dateA = _getDateTimeFromTimestamp(
                                  dataA['createdAt']);
                              final dateB = _getDateTimeFromTimestamp(
                                  dataB['createdAt']);
                              comparison = dateA.compareTo(dateB);
                            }

                            return _sortAscending ? comparison : -comparison;
                          });

                          if (filteredDocs.isEmpty) {
                            return _buildEmptyState(isWide);
                          }

                          return isWide
                              ? _buildDesktopTable(filteredDocs)
                              : _buildMobileCards(filteredDocs);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isWide) {
    return Container(
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_outline,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'No users found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            if (_searchQuery.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Try adjusting your search',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white60,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DESKTOP TABLE (wide screens)
  // ---------------------------------------------------------------------------

  Widget _buildDesktopTable(List<QueryDocumentSnapshot> filteredDocs) {
    return Container(
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12)),
              border: Border(
                  bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08))),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_sortBy == 'name') {
                          _sortAscending = !_sortAscending;
                        } else {
                          _sortBy = 'name';
                          _sortAscending = true;
                        }
                      });
                    },
                    child: Row(
                      children: [
                        _headerCell('Name'),
                        const SizedBox(width: 4),
                        if (_sortBy == 'name')
                          Icon(
                            _sortAscending
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 14,
                            color: Colors.white60,
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _headerCell('Email'),
                ),
                Expanded(
                  flex: 1,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_sortBy == 'createdAt') {
                          _sortAscending = !_sortAscending;
                        } else {
                          _sortBy = 'createdAt';
                          _sortAscending = false; // Most recent first
                        }
                      });
                    },
                    child: Row(
                      children: [
                        _headerCell('Join Date'),
                        const SizedBox(width: 4),
                        if (_sortBy == 'createdAt')
                          Icon(
                            _sortAscending
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 14,
                            color: Colors.white60,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Data rows
          ...filteredDocs.asMap().entries.map((entry) {
            final index = entry.key;
            final doc = entry.value;
            final data = doc.data() as Map<String, dynamic>;
            final isEven = index % 2 == 0;

            return Container(
              color: isEven
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.03),
              child: InkWell(
                onTap: () => _showUserDetails(context, doc.id, data),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _dataCell(
                          '${data['name'] ?? 'N/A'} ${data['lastName'] ?? ''}',
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: _dataCell(data['email'] ?? 'N/A'),
                      ),
                      Expanded(
                        flex: 1,
                        child: _dataCell(
                          _formatDate(data['createdAt']),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE CARD LIST (narrow screens)
  // ---------------------------------------------------------------------------

  Widget _buildMobileCards(List<QueryDocumentSnapshot> filteredDocs) {
    return Column(
      children: filteredDocs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final name = '${data['name'] ?? 'N/A'} ${data['lastName'] ?? ''}';
        final email = data['email'] ?? 'N/A';
        final joinDate = _formatDate(data['createdAt']);

        return GestureDetector(
          onTap: () => _showUserDetails(context, doc.id, data),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kCardFill.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: kPinkBright.withValues(alpha: 0.2),
                  child: Text(
                    name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: kPinkBright, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.trim(),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 11, color: Colors.white38),
                          const SizedBox(width: 4),
                          Text(
                            'Joined $joinDate',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white38),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: Colors.white38),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _sortChip(String label, String sortValue) {
    final isSelected = _sortBy == sortValue;
    return GestureDetector(
      onTap: () {
        setState(() {
          _sortBy = sortValue;
          // Default: name ascending, date descending (newest first)
          _sortAscending = sortValue == 'name';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kPinkBright : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? kPinkBright : Colors.white.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check, size: 14, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: Colors.white60,
      ),
    );
  }

  Widget _dataCell(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, color: Colors.white),
      overflow: TextOverflow.ellipsis,
    );
  }

  DateTime _getDateTimeFromTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime(1970);
    try {
      return (timestamp as Timestamp).toDate();
    } catch (e) {
      return DateTime(1970);
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      final date = (timestamp as Timestamp).toDate();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'N/A';
    }
  }

  void _showUserDetails(
      BuildContext context, String userId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kNavyMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.person, size: 28, color: kPinkBright),
            SizedBox(width: 12),
            Text('User Details', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailCard('Personal Information', [
                  _detailRow('Name:',
                      '${data['name'] ?? 'N/A'} ${data['lastName'] ?? ''}'),
                  _detailRow('Email:', data['email'] ?? 'N/A'),
                  _detailRow('User Type:', data['userType'] ?? 'N/A'),
                ]),
                const SizedBox(height: 16),
                _buildDetailCard('Account Information', [
                  _detailRow('Join Date:', _formatDate(data['createdAt'])),
                  _detailRow('User ID:', data['uid'] ?? 'N/A'),
                ]),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: kBlueAccent),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
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
}
