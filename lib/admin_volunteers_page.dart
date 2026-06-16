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
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _volunteers = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadVolunteers();
  }

  String _safeString(dynamic value) {
    if (value == null) return 'N/A';
    if (value is String) return value;
    if (value is List) return value.join(', ');
    if (value is Map) return value.toString();
    return value.toString();
  }

  String _getLocationAddress(Map<String, dynamic> data) {
    if (data['locationAddress'] != null && data['locationAddress'].toString().isNotEmpty) {
      return data['locationAddress'].toString();
    }
    if (data['location'] is String && data['location'].toString().isNotEmpty) {
      return data['location'].toString();
    }
    return 'N/A';
  }

  Future<void> _loadVolunteers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final volunteerSnapshot = await firestore.collection('volunteers').get();
      final List<Map<String, dynamic>> volunteers = [];

      if (volunteerSnapshot.docs.isEmpty) {
        setState(() {
          _volunteers = [];
          _isLoading = false;
        });
        return;
      }

      for (var doc in volunteerSnapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          String uid = data['uid'] ?? doc.id;
          
          DocumentSnapshot userDoc;
          try {
            userDoc = await firestore.collection('users').doc(uid).get();
          } catch (e) {
            userDoc = await firestore.collection('users').doc(doc.id).get();
          }
          
          final userData = userDoc.exists ? (userDoc.data() as Map<String, dynamic>? ?? {}) : {};
          
          final specialties = data['specialties'];
          String specialtiesStr = 'N/A';
          if (specialties is List) {
            specialtiesStr = specialties.map((e) => e.toString()).join(', ');
          } else if (specialties is String) {
            specialtiesStr = specialties;
          }
          
          volunteers.add({
            'docId': doc.id,
            'uid': uid,
            'name': _safeString(userData['name'] ?? data['name']),
            'email': _safeString(userData['email'] ?? data['email']),
            'phoneNumber': _safeString(data['phoneNumber']),
            'language': _safeString(data['language']),
            'specialtiesStr': specialtiesStr,
            'specialties': specialties is List ? specialties : [],
            'availability': _safeString(data['availability']),
            'status': _safeString(data['status']),
            'submittedAt': data['submittedAt'],
            'reviewedAt': data['reviewedAt'],
            'averageRating': (data['averageRating'] ?? 0.0).toDouble(),
            'totalRatings': (data['totalRatings'] ?? 0),
            'locationAddress': _getLocationAddress(data),
          });
        } catch (e) {
          print('Error processing volunteer ${doc.id}: $e');
          final data = doc.data() as Map<String, dynamic>;
          
          final specialties = data['specialties'];
          String specialtiesStr = 'N/A';
          if (specialties is List) {
            specialtiesStr = specialties.map((e) => e.toString()).join(', ');
          } else if (specialties is String) {
            specialtiesStr = specialties;
          }
          
          volunteers.add({
            'docId': doc.id,
            'uid': _safeString(data['uid']),
            'name': _safeString(data['name']),
            'email': _safeString(data['email']),
            'phoneNumber': _safeString(data['phoneNumber']),
            'language': _safeString(data['language']),
            'specialtiesStr': specialtiesStr,
            'specialties': specialties is List ? specialties : [],
            'availability': _safeString(data['availability']),
            'status': _safeString(data['status']),
            'submittedAt': data['submittedAt'],
            'reviewedAt': data['reviewedAt'],
            'averageRating': (data['averageRating'] ?? 0.0).toDouble(),
            'totalRatings': (data['totalRatings'] ?? 0),
            'locationAddress': _getLocationAddress(data),
          });
        }
      }

      setState(() {
        _volunteers = volunteers;
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
      color: const Color(0xFFF8F9FA),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchBar(),
                  const SizedBox(height: 12),
                  _buildFilters(),
                  const SizedBox(height: 12),
                  _buildTable(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade700, Colors.amber.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.volunteer_activism, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Volunteers Management',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                Text(
                  'View and manage volunteer applications',
                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            onPressed: _loadVolunteers,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search volunteers...',
          hintStyle: const TextStyle(fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Colors.amber, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // Language Filter
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  value: _selectedLanguage,
                  decoration: InputDecoration(
                    labelText: 'Language',
                    labelStyle: const TextStyle(color: Colors.amber, fontSize: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Colors.amber, width: 1.5),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'english', child: Text('English', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'spanish', child: Text('Spanish', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'mandarin', child: Text('Mandarin', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'french', child: Text('French', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'german', child: Text('German', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'korean', child: Text('Korean', style: TextStyle(fontSize: 11))),
                  ],
                  onChanged: (value) => setState(() => _selectedLanguage = value ?? 'all'),
                ),
              ),
              // Specialty Filter
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  value: _selectedSpecialty,
                  decoration: InputDecoration(
                    labelText: 'Specialty',
                    labelStyle: const TextStyle(color: Colors.amber, fontSize: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Colors.amber, width: 1.5),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'shopping', child: Text('Shopping', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'navigation', child: Text('Navigation', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'reading', child: Text('Reading', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'tech support', child: Text('Tech Support', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'emergency assistance', child: Text('Emergency', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'medical support', child: Text('Medical', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'transportation', child: Text('Transport', style: TextStyle(fontSize: 11))),
                  ],
                  onChanged: (value) => setState(() => _selectedSpecialty = value ?? 'all'),
                ),
              ),
              // Availability Filter
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  value: _selectedAvailability,
                  decoration: InputDecoration(
                    labelText: 'Availability',
                    labelStyle: const TextStyle(color: Colors.amber, fontSize: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Colors.amber, width: 1.5),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'weekends', child: Text('Weekends', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'weekdays', child: Text('Weekdays', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'anytime', child: Text('Anytime', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'emergency only', child: Text('Emergency', style: TextStyle(fontSize: 11))),
                  ],
                  onChanged: (value) => setState(() => _selectedAvailability = value ?? 'all'),
                ),
              ),
              // Status Filter
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  value: _filterStatus,
                  decoration: InputDecoration(
                    labelText: 'Status',
                    labelStyle: const TextStyle(color: Colors.amber, fontSize: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Colors.amber, width: 1.5),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'pending', child: Text('Pending', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'approved', child: Text('Approved', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejected', style: TextStyle(fontSize: 11))),
                  ],
                  onChanged: (value) => setState(() => _filterStatus = value ?? 'all'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
                icon: const Icon(Icons.clear_all, size: 14),
                label: const Text('Clear', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue.shade700, 
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading volunteers...', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 40, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text('Error: $_errorMessage', style: TextStyle(fontSize: 14, color: Colors.red.shade700)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadVolunteers,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_volunteers.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            _buildTableHeader(),
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('No volunteers found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('Volunteer registrations will appear here', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ✅ FIXED FILTERS - Case insensitive
    var filteredVolunteers = List<Map<String, dynamic>>.from(_volunteers);

    // Search filter
    if (_searchQuery.isNotEmpty) {
      filteredVolunteers = filteredVolunteers.where((data) {
        final name = (data['name'] ?? '').toLowerCase();
        final email = (data['email'] ?? '').toLowerCase();
        final phone = (data['phoneNumber'] ?? '').toLowerCase();
        final uid = (data['uid'] ?? '').toLowerCase();
        final address = (data['locationAddress'] ?? '').toLowerCase();
        return name.contains(_searchQuery) ||
            email.contains(_searchQuery) ||
            phone.contains(_searchQuery) ||
            uid.contains(_searchQuery) ||
            address.contains(_searchQuery);
      }).toList();
    }

    // ✅ Status filter - case insensitive
    if (_filterStatus != 'all') {
      filteredVolunteers = filteredVolunteers.where((data) {
        final status = (data['status'] ?? '').toLowerCase();
        return status == _filterStatus.toLowerCase();
      }).toList();
    }

    // ✅ Language filter - case insensitive
    if (_selectedLanguage != 'all') {
      filteredVolunteers = filteredVolunteers.where((data) {
        final language = (data['language'] ?? '').toLowerCase();
        return language == _selectedLanguage.toLowerCase();
      }).toList();
    }

    // ✅ Availability filter - case insensitive
    if (_selectedAvailability != 'all') {
      filteredVolunteers = filteredVolunteers.where((data) {
        final availability = (data['availability'] ?? '').toLowerCase();
        return availability == _selectedAvailability.toLowerCase();
      }).toList();
    }

    // ✅ Specialty filter - case insensitive
    if (_selectedSpecialty != 'all') {
      filteredVolunteers = filteredVolunteers.where((data) {
        final specialties = data['specialties'] as List? ?? [];
        final specialtyList = specialties.map((e) => e.toString().toLowerCase()).toList();
        return specialtyList.contains(_selectedSpecialty.toLowerCase());
      }).toList();
    }

    // Sort
    if (filteredVolunteers.isNotEmpty) {
      filteredVolunteers.sort((a, b) {
        int comparison = 0;

        if (_sortBy == 'submittedAt') {
          final dateA = _getDateTimeFromTimestamp(a['submittedAt']);
          final dateB = _getDateTimeFromTimestamp(b['submittedAt']);
          comparison = dateA.compareTo(dateB);
        } else if (_sortBy == 'name') {
          final nameA = (a['name'] ?? '').toLowerCase();
          final nameB = (b['name'] ?? '').toLowerCase();
          comparison = nameA.compareTo(nameB);
        } else if (_sortBy == 'rating') {
          final ratingA = (a['averageRating'] ?? 0.0).toDouble();
          final ratingB = (b['averageRating'] ?? 0.0).toDouble();
          comparison = ratingA.compareTo(ratingB);
        }

        return _sortAscending ? comparison : -comparison;
      });
    }

    if (filteredVolunteers.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            _buildTableHeader(),
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('No matching volunteers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('Try adjusting your search or filters', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildTableHeader(),
          ...filteredVolunteers.asMap().entries.map((entry) {
            final index = entry.key;
            final data = entry.value;
            final isEven = index % 2 == 0;

            return Container(
              color: isEven ? Colors.white : Colors.grey.shade50,
              child: InkWell(
                onTap: () => _showVolunteerDetails(context, data['docId'], data),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['name'] ?? 'Unknown',
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                            ),
                            Text(
                              data['language'] ?? '',
                              style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['email'] ?? 'N/A',
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              data['phoneNumber'] ?? 'N/A',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          data['locationAddress'] ?? 'N/A',
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: _statusBadge(data['status'] ?? 'pending'),
                      ),
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: _ratingDisplay(
                            (data['averageRating'] ?? 0.0).toDouble(),
                            data['totalRatings'] ?? 0,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          _formatDate(data['submittedAt']),
                          style: const TextStyle(fontSize: 10),
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
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey.shade50, Colors.grey.shade100],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
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
                  if (_sortBy == 'name') ...[
                    const SizedBox(width: 2),
                    Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: Colors.grey.shade600),
                  ],
                ],
              ),
            ),
          ),
          Expanded(flex: 2, child: _headerCell('Contact')),
          Expanded(flex: 2, child: _headerCell('Address')),
          Expanded(flex: 1, child: _headerCell('Status')),
          Expanded(
            flex: 1,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  if (_sortBy == 'rating') {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortBy = 'rating';
                    _sortAscending = false;
                  }
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _headerCell('Rating'),
                  if (_sortBy == 'rating') ...[
                    const SizedBox(width: 2),
                    Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: Colors.grey.shade600),
                  ],
                ],
              ),
            ),
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
                    const SizedBox(width: 2),
                    Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: Colors.grey.shade600),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10, color: Colors.grey),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        displayText,
        textAlign: TextAlign.center,
        style: TextStyle(color: textColor, fontSize: 8, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _ratingDisplay(double averageRating, int totalRatings) {
    if (totalRatings == 0) {
      return Text('No ratings', style: TextStyle(fontSize: 8, color: Colors.grey.shade400));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, color: Colors.amber, size: 10),
            const SizedBox(width: 1),
            Text(averageRating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9)),
          ],
        ),
        Text('($totalRatings)', style: TextStyle(fontSize: 7, color: Colors.grey.shade500)),
      ],
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

  void _showVolunteerDetails(BuildContext context, String volunteerId, Map<String, dynamic> data) {
    final specialties = data['specialtiesStr'] ?? 'N/A';
    final status = data['status'] ?? 'pending';
    final avgRating = (data['averageRating'] ?? 0.0).toDouble();
    final totalRatings = data['totalRatings'] ?? 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.person, size: 22),
            const SizedBox(width: 8),
            const Text('Volunteer Details', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailCard('Personal', [
                  _detailRow('Name:', data['name'] ?? 'N/A'),
                  _detailRow('Email:', data['email'] ?? 'N/A'),
                  _detailRow('Phone:', data['phoneNumber'] ?? 'N/A'),
                  _detailRow('Address:', data['locationAddress'] ?? 'N/A'),
                ]),
                const SizedBox(height: 8),
                _buildDetailCard('Volunteer', [
                  _detailRow('Language:', data['language'] ?? 'N/A'),
                  _detailRow('Availability:', data['availability'] ?? 'N/A'),
                  _detailRow('Specialties:', specialties),
                  _detailRow('Status:', _capitalize(status)),
                ]),
                const SizedBox(height: 8),
                _buildDetailCard('Rating', [
                  _detailRow('Average:', avgRating > 0 ? avgRating.toStringAsFixed(1) : 'No ratings'),
                  _detailRow('Total:', totalRatings > 0 ? totalRatings.toString() : '0'),
                  if (totalRatings > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: List.generate(5, (index) {
                          if (index < avgRating.floor()) {
                            return const Icon(Icons.star, color: Colors.amber, size: 16);
                          } else if (index < avgRating && avgRating - index >= 0.5) {
                            return const Icon(Icons.star_half, color: Colors.amber, size: 16);
                          } else {
                            return const Icon(Icons.star_border, color: Colors.amber, size: 16);
                          }
                        }),
                      ),
                    ),
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
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
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
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.black87)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}