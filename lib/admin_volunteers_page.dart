import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminVolunteersPage extends StatefulWidget {
  const AdminVolunteersPage({super.key});

  @override
  State<AdminVolunteersPage> createState() => _AdminVolunteersPageState();
}

class _AdminVolunteersPageState extends State<AdminVolunteersPage> {
  final firestore = FirebaseFirestore.instance;

  String _searchQuery = '';
  String _filterStatus = 'all';
  String _selectedLanguage = 'all';
  String _selectedSpecialty = 'all';
  String _selectedAvailability = 'all';
  String _sortBy = 'submittedAt';
  bool _sortAscending = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Volunteers Management',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'View and manage volunteer applications',
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),

                // Search bar
                TextField(
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search volunteers by UID or phone number...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                /// FILTERS
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              // Language filter
                              SizedBox(
                                width: (constraints.maxWidth - 48) / 4,
                                child: DropdownButtonFormField<String>(
                                  value: _selectedLanguage,
                                  decoration: InputDecoration(
                                    labelText: 'Language',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text('All Languages'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'english',
                                      child: Text('English'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'spanish',
                                      child: Text('Spanish'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'mandarin',
                                      child: Text('Mandarin'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'french',
                                      child: Text('French'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'german',
                                      child: Text('German'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'korean',
                                      child: Text('Korean'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedLanguage = value ?? 'all';
                                    });
                                  },
                                ),
                              ),

                              // Specialty filter
                              SizedBox(
                                width: (constraints.maxWidth - 48) / 4,
                                child: DropdownButtonFormField<String>(
                                  value: _selectedSpecialty,
                                  decoration: InputDecoration(
                                    labelText: 'Specialty',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text('All Specialties'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'shopping',
                                      child: Text('Shopping'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'navigation',
                                      child: Text('Navigation'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'reading',
                                      child: Text('Reading'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'tech support',
                                      child: Text('Tech Support'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'emergency assistance',
                                      child: Text('Emergency Assistance'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'medical support',
                                      child: Text('Medical Support'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'transportation',
                                      child: Text('Transportation'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedSpecialty = value ?? 'all';
                                    });
                                  },
                                ),
                              ),

                              // Availability filter
                              SizedBox(
                                width: (constraints.maxWidth - 48) / 4,
                                child: DropdownButtonFormField<String>(
                                  value: _selectedAvailability,
                                  decoration: InputDecoration(
                                    labelText: 'Availability',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text('All Availability'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'weekends',
                                      child: Text('Weekends'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'weekdays',
                                      child: Text('Weekdays'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'anytime',
                                      child: Text('Anytime'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'emergency only',
                                      child: Text('Emergency Only'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedAvailability = value ?? 'all';
                                    });
                                  },
                                ),
                              ),

                              // Status filter
                              SizedBox(
                                width: (constraints.maxWidth - 48) / 4,
                                child: DropdownButtonFormField<String>(
                                  value: _filterStatus,
                                  decoration: InputDecoration(
                                    labelText: 'Status',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text('All Status'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'pending',
                                      child: Text('Pending'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'approved',
                                      child: Text('Approved'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'rejected',
                                      child: Text('Rejected'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _filterStatus = value ?? 'all';
                                    });
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _filterStatus = 'all';
                                _selectedLanguage = 'all';
                                _selectedSpecialty = 'all';
                                _selectedAvailability = 'all';
                                _searchQuery = '';
                              });
                            },
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: const Text('Clear All Filters'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                /// TABLE
                FutureBuilder<QuerySnapshot>(
                  future: firestore.collection('volunteers').get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    final docs = snapshot.data?.docs ?? [];

                    var filteredDocs = docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;

                      final uid = (data['uid'] ?? '').toString().toLowerCase();
                      final phone = (data['phoneNumber'] ?? '')
                          .toString()
                          .toLowerCase();
                      final matchesSearch =
                          _searchQuery.isEmpty ||
                          uid.contains(_searchQuery) ||
                          phone.contains(_searchQuery);

                      final status = (data['status'] ?? '')
                          .toString()
                          .toLowerCase();
                      final matchesStatus =
                          _filterStatus == 'all' || status == _filterStatus;

                      final language = (data['language'] ?? '')
                          .toString()
                          .toLowerCase();
                      final matchesLanguage =
                          _selectedLanguage == 'all' ||
                          language == _selectedLanguage;

                      final availability = (data['availability'] ?? '')
                          .toString()
                          .toLowerCase();
                      final matchesAvailability =
                          _selectedAvailability == 'all' ||
                          availability == _selectedAvailability;

                      final specialties =
                          (data['specialties'] as List<dynamic>? ?? [])
                              .map((e) => e.toString().toLowerCase())
                              .toList();
                      final matchesSpecialty =
                          _selectedSpecialty == 'all' ||
                          specialties.contains(_selectedSpecialty);

                      return matchesSearch &&
                          matchesStatus &&
                          matchesLanguage &&
                          matchesAvailability &&
                          matchesSpecialty;
                    }).toList();

                    filteredDocs.sort((a, b) {
                      final dataA = a.data() as Map<String, dynamic>;
                      final dataB = b.data() as Map<String, dynamic>;

                      int comparison = 0;

                      if (_sortBy == 'submittedAt') {
                        final dateA = _getDateTimeFromTimestamp(
                          dataA['submittedAt'],
                        );
                        final dateB = _getDateTimeFromTimestamp(
                          dataB['submittedAt'],
                        );
                        comparison = dateA.compareTo(dateB);
                      } else if (_sortBy == 'availability') {
                        final availabilityA = (dataA['availability'] ?? '')
                            .toString();
                        final availabilityB = (dataB['availability'] ?? '')
                            .toString();
                        comparison = availabilityA.compareTo(availabilityB);
                      } else if (_sortBy == 'uid') {
                        final uidA = (dataA['uid'] ?? '')
                            .toString()
                            .toLowerCase();
                        final uidB = (dataB['uid'] ?? '')
                            .toString()
                            .toLowerCase();
                        comparison = uidA.compareTo(uidB);
                      }

                      return _sortAscending ? comparison : -comparison;
                    });

                    if (filteredDocs.isEmpty) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(12),
                                    ),
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: _headerCell('UID'),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: _headerCell('Phone'),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: _headerCell('Language'),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: _headerCell('Specialties'),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: _headerCell('Availability'),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: _headerCell('Status'),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: _headerCell('Submitted'),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(48),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.people_outline,
                                        size: 48,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'No volunteers found',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (_searchQuery.isNotEmpty ||
                                          _filterStatus != 'all' ||
                                          _selectedLanguage != 'all' ||
                                          _selectedSpecialty != 'all' ||
                                          _selectedAvailability != 'all')
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Text(
                                            'Try adjusting your search or filters',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                          /// HEADER
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        if (_sortBy == 'uid') {
                                          _sortAscending = !_sortAscending;
                                        } else {
                                          _sortBy = 'uid';
                                          _sortAscending = true;
                                        }
                                      });
                                    },
                                    child: Row(
                                      children: [
                                        _headerCell('UID'),
                                        if (_sortBy == 'uid') ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            _sortAscending
                                                ? Icons.arrow_upward
                                                : Icons.arrow_downward,
                                            size: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(flex: 1, child: _headerCell('Phone')),
                                Expanded(
                                  flex: 1,
                                  child: _headerCell('Language'),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: _headerCell('Specialties'),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        if (_sortBy == 'availability') {
                                          _sortAscending = !_sortAscending;
                                        } else {
                                          _sortBy = 'availability';
                                          _sortAscending = true;
                                        }
                                      });
                                    },
                                    child: Row(
                                      children: [
                                        _headerCell('Availability'),
                                        if (_sortBy == 'availability') ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            _sortAscending
                                                ? Icons.arrow_upward
                                                : Icons.arrow_downward,
                                            size: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(child: _headerCell('Status')),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        if (_sortBy == 'submittedAt') {
                                          _sortAscending = !_sortAscending;
                                        } else {
                                          _sortBy = 'submittedAt';
                                          _sortAscending = false;
                                        }
                                      });
                                    },
                                    child: Row(
                                      children: [
                                        _headerCell('Submitted'),
                                        if (_sortBy == 'submittedAt') ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            _sortAscending
                                                ? Icons.arrow_upward
                                                : Icons.arrow_downward,
                                            size: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          /// DATA ROWS
                          ...filteredDocs.asMap().entries.map((entry) {
                            final index = entry.key;
                            final doc = entry.value;
                            final data = doc.data() as Map<String, dynamic>;
                            final isEven = index % 2 == 0;

                            return Container(
                              color: isEven
                                  ? Colors.white
                                  : Colors.grey.shade50,
                              child: InkWell(
                                onTap: () {
                                  _showVolunteerDetails(context, doc.id, data);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: _dataCell(data['uid'] ?? 'N/A'),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: _dataCell(
                                          data['phoneNumber'] ?? 'N/A',
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: _dataCell(
                                          data['language'] ?? 'N/A',
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: _dataCell(
                                          (data['specialties'] as List?)?.join(
                                                ', ',
                                              ) ??
                                              'N/A',
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: _dataCell(
                                          data['availability'] ?? 'N/A',
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: _statusBadge(
                                            data['status'] ?? 'pending',
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: _dataCell(
                                          _formatDate(data['submittedAt']),
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
        ),
      ],
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
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14),
    );
  }

  Widget _statusBadge(String status) {
    Color backgroundColor;
    Color textColor;
    String displayText;

    switch (status.toLowerCase()) {
      case 'approved':
        backgroundColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        displayText = 'Approved';
        break;
      case 'rejected':
        backgroundColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        displayText = 'Rejected';
        break;
      default:
        backgroundColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        displayText = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        displayText,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
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
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  void _showVolunteerDetails(
    BuildContext context,
    String volunteerId,
    Map<String, dynamic> data,
  ) {
    final specialties = (data['specialties'] as List?)?.join(', ') ?? 'N/A';
    final status = data['status'] ?? 'pending';
    final verified = data['isVerified'] == true ? 'Yes' : 'No';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.person, size: 28),
            const SizedBox(width: 12),
            const Text('Volunteer Details'),
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
                  _detailRow('UID:', data['uid'] ?? 'N/A'),
                  _detailRow('Phone Number:', data['phoneNumber'] ?? 'N/A'),
                  _detailRow('ID Card Number:', data['idCardNumber'] ?? 'N/A'),
                  _detailRow('Verified:', verified),
                ]),
                const SizedBox(height: 16),
                _buildDetailCard('Volunteer Information', [
                  _detailRow('Language:', data['language'] ?? 'N/A'),
                  _detailRow('Availability:', data['availability'] ?? 'N/A'),
                  _detailRow('Specialties:', specialties),
                  _detailRow('Status:', _capitalize(status)),
                  _detailRow('Rejected Reason:', _capitalize(data['rejectionReason'] ?? 'N/A')),
                ]),
                const SizedBox(height: 16),
                _buildDetailCard('Timestamps', [
                  _detailRow('Submitted At:', _formatDate(data['submittedAt'])),
                  _detailRow('Reviewed At:', _formatDate(data['reviewedAt'])),
                ]),
              ],
            ),
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

  Widget _buildDetailCard(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}
