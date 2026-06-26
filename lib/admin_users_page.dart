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
            children: [
              // ── Header & Controls Section ──
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 32 : 16, 
                  isWide ? 32 : 16, 
                  isWide ? 32 : 16, 
                  0
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Gradient Card Header
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
                            child: const Icon(Icons.people, color: Colors.white, size: 28),
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
                                      color: Colors.white.withValues(alpha: 0.8)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isWide ? 24 : 16),

                    // Search Input
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kCardFill.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: TextField(
                        onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search users by name or email...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                          prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                                  onPressed: () => setState(() => _searchQuery = ''),
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: kPinkBright, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Sort Layout
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: kCardFill.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Sort:',
                            style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  _sortChip('Name', 'name'),
                                  const SizedBox(width: 8),
                                  _sortChip('Join Date', 'createdAt'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            height: 24,
                            width: 1,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          IconButton(
                            icon: Icon(
                                _sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                color: kPinkBright,
                                size: 20),
                            tooltip: _sortAscending ? 'Ascending' : 'Descending',
                            onPressed: () => setState(() => _sortAscending = !_sortAscending),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // ── Dynamic Dynamic List Content ──
              Expanded(
                child: FutureBuilder<QuerySnapshot>(
                  future: firestore.collection('users').where('userType', isEqualTo: 'blind').get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: kPinkBright));
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Error: ${snapshot.error}', style: const TextStyle(color: kRedAccent)),
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];

                    var filteredDocs = docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final name = (data['name'] ?? '').toString().toLowerCase();
                      final email = (data['email'] ?? '').toString().toLowerCase();
                      return name.contains(_searchQuery) || email.contains(_searchQuery);
                    }).toList();

                    filteredDocs.sort((a, b) {
                      final dataA = a.data() as Map<String, dynamic>;
                      final dataB = b.data() as Map<String, dynamic>;

                      int comparison = 0;

                      if (_sortBy == 'name') {
                        final nameA = (dataA['name'] ?? '').toString().toLowerCase();
                        final nameB = (dataB['name'] ?? '').toString().toLowerCase();
                        comparison = nameA.compareTo(nameB);
                      } else if (_sortBy == 'createdAt') {
                        final dateA = _getDateTimeFromTimestamp(dataA['createdAt']);
                        final dateB = _getDateTimeFromTimestamp(dataB['createdAt']);
                        comparison = dateA.compareTo(dateB);
                      }

                      return _sortAscending ? comparison : -comparison;
                    });

                    if (filteredDocs.isEmpty) {
                      return Padding(
                        padding: EdgeInsets.all(isWide ? 32 : 16),
                        child: _buildEmptyState(),
                      );
                    }

                    return isWide ? _buildDesktopTable(filteredDocs) : _buildMobileCards(filteredDocs);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_rounded, size: 48, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            const Text(
              'No users found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
            ),
            if (_searchQuery.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Try adjusting your search query',
                  style: TextStyle(fontSize: 13, color: Colors.white60),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DESKTOP VIEWPORT
  // ---------------------------------------------------------------------------

  Widget _buildDesktopTable(List<QueryDocumentSnapshot> filteredDocs) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      children: [
        Container(
          decoration: BoxDecoration(
            color: kCardFill.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _headerCell('Name'),
                    ),
                    Expanded(
                      flex: 2,
                      child: _headerCell('Email'),
                    ),
                    Expanded(
                      flex: 1,
                      child: _headerCell('Join Date'),
                    ),
                  ],
                ),
              ),
              ...filteredDocs.asMap().entries.map((entry) {
                final index = entry.key;
                final doc = entry.value;
                final data = doc.data() as Map<String, dynamic>;
                final isEven = index % 2 == 0;

                return Container(
                  color: isEven ? Colors.transparent : Colors.white.withValues(alpha: 0.03),
                  child: InkWell(
                    onTap: () => _showUserDetailShell(context, doc.id, data, isWide: true),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: _dataCell('${data['name'] ?? 'N/A'} ${data['lastName'] ?? ''}'),
                          ),
                          Expanded(
                            flex: 2,
                            child: _dataCell(data['email'] ?? 'N/A'),
                          ),
                          Expanded(
                            flex: 1,
                            child: _dataCell(_formatDate(data['createdAt'])),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE VIEWPORT
  // ---------------------------------------------------------------------------

  Widget _buildMobileCards(List<QueryDocumentSnapshot> filteredDocs) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: filteredDocs.length,
      itemBuilder: (context, index) {
        final doc = filteredDocs[index];
        final data = doc.data() as Map<String, dynamic>;
        final name = '${data['name'] ?? 'N/A'} ${data['lastName'] ?? ''}';
        final email = data['email'] ?? 'N/A';
        final joinDate = _formatDate(data['createdAt']);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: kCardFill.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showUserDetailShell(context, doc.id, data, isWide: false),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: kPinkBright.withValues(alpha: 0.15),
                    child: Text(
                      name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
                      style: const TextStyle(color: kPinkBright, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.trim(),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: const TextStyle(fontSize: 12, color: Colors.white60),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 10, color: Colors.white38),
                            const SizedBox(width: 4),
                            Text(
                              'Joined $joinDate',
                              style: const TextStyle(fontSize: 11, color: Colors.white38),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white38),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sortChip(String label, String sortValue) {
    final isSelected = _sortBy == sortValue;
    return GestureDetector(
      onTap: () {
        setState(() {
          _sortBy = sortValue;
          _sortAscending = sortValue == 'name';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? kPinkBright.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? kPinkBright : Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? kPinkBright : Colors.white70,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white60),
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

  // ---------------------------------------------------------------------------
  // INTERACTIVE SHEET & DIALOG DISPLAY
  // ---------------------------------------------------------------------------

  void _showUserDetailShell(BuildContext context, String userId, Map<String, dynamic> data, {required bool isWide}) {
    if (isWide) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: kNavyMid,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.person_rounded, size: 24, color: kPinkBright),
              SizedBox(width: 12),
              Text('User Details', style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: Container(
            width: 420,
            child: _buildDetailsContent(data),
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
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: kNavyMid,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.person_rounded, size: 22, color: kPinkBright),
                  SizedBox(width: 8),
                  Text(
                    'User Details',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDetailsContent(data),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildDetailsContent(Map<String, dynamic> data) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDetailCard('Personal Information', [
          _detailRow('Name:', '${data['name'] ?? 'N/A'} ${data['lastName'] ?? ''}'),
          _detailRow('Email:', data['email'] ?? 'N/A'),
          _detailRow('User Type:', (data['userType'] ?? 'N/A').toString().toUpperCase()),
        ]),
        const SizedBox(height: 12),
        _buildDetailCard('Account Information', [
          _detailRow('Join Date:', _formatDate(data['createdAt'])),
          _detailRow('User ID:', data['uid'] ?? 'N/A'),
        ]),
      ],
    );
  }

  Widget _buildDetailCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white70),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Fallback stack variant if user IDs or emails would trigger overflow boundaries
          final useVerticalStack = constraints.maxWidth < 280;
          
          if (useVerticalStack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: Colors.white38),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 85,
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.white38),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.2),
                ),
              ),
            ],
          );
        }
      ),
    );
  }
}