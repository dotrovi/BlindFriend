import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final firestore = FirebaseFirestore.instance;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Text(
              'Users Management',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'View and manage blind users',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),

            // Search bar
            TextField(
              onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search users by name or email...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),

            // Users table
            FutureBuilder<QuerySnapshot>(
              future: firestore.collection('users').where('userType', isEqualTo: 'blind').get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red)),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                final filteredDocs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  return name.contains(_searchQuery) || email.contains(_searchQuery);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_outline, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text('No users found',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      // Header row
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(12)),
                          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
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
                              child: _headerCell('Phone'),
                            ),
                            Expanded(
                              flex: 1,
                              child: _headerCell('Join Date'),
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
                          color: isEven ? Colors.white : Colors.grey.shade50,
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
                                    child: _dataCell(data['phone'] ?? 'N/A'),
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
                      }).toList(),
                    ],
                  ),
                );
              },
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
        color: Colors.grey,
      ),
    );
  }

  Widget _dataCell(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14),
      overflow: TextOverflow.ellipsis,
    );
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

  void _showUserDetails(BuildContext context, String userId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('User Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Name:', data['name'] ?? 'N/A'),
              _detailRow('Email:', data['email'] ?? 'N/A'),
              _detailRow('Phone:', data['phone'] ?? 'N/A'),
              _detailRow('User Type:', data['userType'] ?? 'N/A'),
              _detailRow('Join Date:', _formatDate(data['createdAt'])),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }
}
