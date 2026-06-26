import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'theme/app_palette.dart';

const double _kWideBreakpoint = 700;

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
  String _selectedLocation = 'all';

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
    if (data['locationAddress'] != null &&
        data['locationAddress'].toString().isNotEmpty) {
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
          final data = doc.data();
          String uid = data['uid'] ?? doc.id;

          DocumentSnapshot userDoc;
          try {
            userDoc = await firestore.collection('users').doc(uid).get();
          } catch (e) {
            userDoc = await firestore.collection('users').doc(doc.id).get();
          }

          final userData = userDoc.exists
              ? (userDoc.data() as Map<String, dynamic>? ?? {})
              : {};

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
          debugPrint('Error processing volunteer ${doc.id}: $e');
          final data = doc.data();

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

  List<String> _getUniqueLocations() {
    final locations = <String>{};
    for (var volunteer in _volunteers) {
      final address = (volunteer['locationAddress'] ?? '').toString();
      if (address.isNotEmpty && address != 'N/A') {
        final parts = address.split(',');
        if (parts.isNotEmpty) {
          final location = parts[0].trim();
          if (location.isNotEmpty) {
            locations.add(location);
          }
        }
      }
    }
    return locations.toList()..sort();
  }

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
              _buildHeader(isWide),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    isWide ? 32 : 16, 
                    isWide ? 24 : 16, 
                    isWide ? 32 : 16, 
                    isWide ? 32 : 16
                  ),
                  children: [
                    _buildSearchBar(),
                    const SizedBox(height: 16),
                    _buildFilters(),
                    const SizedBox(height: 16),
                    _buildTable(isWide),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool isWide) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isWide ? 32 : 16, 
        isWide ? 32 : 20, 
        isWide ? 32 : 16, 
        0
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Volunteers Management',
                  style: TextStyle(
                    fontSize: isWide ? 28 : 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'View and manage volunteer listings and performance profiles',
                  style: TextStyle(fontSize: 14, color: Colors.white60),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
              onPressed: _loadVolunteers,
              tooltip: 'Refresh Data',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCardFill.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search by name, email, phone number, location, uid...',
          hintStyle: const TextStyle(fontSize: 13, color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          filled: true,
          fillColor: Colors.white.withOpacity(0.04),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kPinkBright, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      ),
    );
  }

  InputDecoration _dropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: kPinkBright, fontSize: 11, fontWeight: FontWeight.w500),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kPinkBright, width: 1.5)),
      filled: true,
      fillColor: Colors.white.withOpacity(0.04),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  Widget _buildFilters() {
    return Container(
      decoration: BoxDecoration(
        color: kCardFill.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<String>(
                    value: _selectedLanguage,
                    isExpanded: true,
                    dropdownColor: kNavyMid,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: _dropdownDecoration('Language'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Languages')),
                      DropdownMenuItem(value: 'english', child: Text('English')),
                      DropdownMenuItem(value: 'spanish', child: Text('Spanish')),
                      DropdownMenuItem(value: 'mandarin', child: Text('Mandarin')),
                      DropdownMenuItem(value: 'french', child: Text('French')),
                      DropdownMenuItem(value: 'german', child: Text('German')),
                      DropdownMenuItem(value: 'korean', child: Text('Korean')),
                    ],
                    onChanged: (value) => setState(() => _selectedLanguage = value ?? 'all'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    value: _selectedSpecialty,
                    isExpanded: true,
                    dropdownColor: kNavyMid,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: _dropdownDecoration('Specialty'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Specialties')),
                      DropdownMenuItem(value: 'shopping', child: Text('Shopping')),
                      DropdownMenuItem(value: 'navigation', child: Text('Navigation')),
                      DropdownMenuItem(value: 'reading', child: Text('Reading')),
                      DropdownMenuItem(value: 'tech support', child: Text('Tech Support')),
                      DropdownMenuItem(value: 'emergency assistance', child: Text('Emergency')),
                      DropdownMenuItem(value: 'medical support', child: Text('Medical')),
                      DropdownMenuItem(value: 'transportation', child: Text('Transport')),
                    ],
                    onChanged: (value) => setState(() => _selectedSpecialty = value ?? 'all'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    value: _selectedAvailability,
                    isExpanded: true,
                    dropdownColor: kNavyMid,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: _dropdownDecoration('Availability'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Availability')),
                      DropdownMenuItem(value: 'weekends', child: Text('Weekends')),
                      DropdownMenuItem(value: 'weekdays', child: Text('Weekdays')),
                      DropdownMenuItem(value: 'anytime', child: Text('Anytime')),
                      DropdownMenuItem(value: 'emergency only', child: Text('Emergency Only')),
                    ],
                    onChanged: (value) => setState(() => _selectedAvailability = value ?? 'all'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<String>(
                    value: _filterStatus,
                    isExpanded: true,
                    dropdownColor: kNavyMid,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: _dropdownDecoration('Status'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Status')),
                      DropdownMenuItem(value: 'pending', child: Text('Pending')),
                      DropdownMenuItem(value: 'approved', child: Text('Approved')),
                      DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                    ],
                    onChanged: (value) => setState(() => _filterStatus = value ?? 'all'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    value: _selectedLocation,
                    isExpanded: true,
                    dropdownColor: kNavyMid,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: _dropdownDecoration('Location'),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Locations')),
                      ..._getUniqueLocations().map((location) =>
                          DropdownMenuItem(value: location, child: Text(location))),
                    ],
                    onChanged: (value) => setState(() => _selectedLocation = value ?? 'all'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _filterStatus = 'all';
                    _selectedLanguage = 'all';
                    _selectedSpecialty = 'all';
                    _selectedAvailability = 'all';
                    _selectedLocation = 'all';
                    _searchQuery = '';
                  });
                },
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear All Filters', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                style: TextButton.styleFrom(
                  foregroundColor: kBlueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTable(bool isWide) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(color: kPinkBright),
              SizedBox(height: 16),
              Text('Loading volunteer records...',
                  style: TextStyle(fontSize: 14, color: Colors.white60)),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.error_outline, size: 44, color: kRedAccent),
              const SizedBox(height: 12),
              Text('Error Loading Data: $_errorMessage',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: kRedAccent)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadVolunteers,
                icon: const Icon(Icons.replay, size: 16),
                label: const Text('Retry Execution'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPinkBright,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    var filteredVolunteers = List<Map<String, dynamic>>.from(_volunteers);

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

    if (_filterStatus != 'all') {
      filteredVolunteers = filteredVolunteers.where((data) => (data['status'] ?? '').toLowerCase() == _filterStatus.toLowerCase()).toList();
    }

    if (_selectedLanguage != 'all') {
      filteredVolunteers = filteredVolunteers.where((data) => (data['language'] ?? '').toLowerCase() == _selectedLanguage.toLowerCase()).toList();
    }

    if (_selectedAvailability != 'all') {
      filteredVolunteers = filteredVolunteers.where((data) => (data['availability'] ?? '').toLowerCase() == _selectedAvailability.toLowerCase()).toList();
    }

    if (_selectedSpecialty != 'all') {
      filteredVolunteers = filteredVolunteers.where((data) {
        final specialties = data['specialties'] as List? ?? [];
        final specialtyList = specialties.map((e) => e.toString().toLowerCase()).toList();
        return specialtyList.contains(_selectedSpecialty.toLowerCase());
      }).toList();
    }

    if (_selectedLocation != 'all') {
      filteredVolunteers = filteredVolunteers.where((data) {
        final address = (data['locationAddress'] ?? '').toString();
        if (address.isEmpty || address == 'N/A') return false;
        final parts = address.split(',');
        if (parts.isEmpty) return false;
        final location = parts[0].trim();
        return location.toLowerCase() == _selectedLocation.toLowerCase();
      }).toList();
    }

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
        width: double.infinity,
        decoration: BoxDecoration(
          color: kCardFill.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          children: [
            if (isWide) _buildTableHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 44, color: Colors.white.withOpacity(0.25)),
                  const SizedBox(height: 16),
                  const Text(
                    'No volunteers matched metrics',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Adjust current dropdown selections or check back later.',
                    style: TextStyle(fontSize: 13, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (!isWide) {
      return Column(
        children: filteredVolunteers.map((data) => _buildMobileCard(data)).toList(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: kCardFill.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          _buildTableHeader(),
          ...filteredVolunteers.asMap().entries.map((entry) {
            final index = entry.key;
            final data = entry.value;
            final isEven = index % 2 == 0;

            return Container(
              decoration: BoxDecoration(
                color: isEven ? Colors.transparent : Colors.white.withOpacity(0.02),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: InkWell(
                onTap: () => _showVolunteerDetails(context, data['docId'], data),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['name'] ?? 'Unknown',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              data['language'] ?? '',
                              style: const TextStyle(fontSize: 11, color: Colors.white38),
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
                              style: const TextStyle(fontSize: 13, color: Colors.white70),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              data['phoneNumber'] ?? 'N/A',
                              style: const TextStyle(fontSize: 11, color: Colors.white38),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          data['locationAddress'] ?? 'N/A',
                          style: const TextStyle(fontSize: 13, color: Colors.white70),
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
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
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

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: InkWell(
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
                    const SizedBox(width: 4),
                    Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: kPinkBright),
                  ],
                ],
              ),
            ),
          ),
          Expanded(flex: 2, child: _headerCell('Contact Info')),
          Expanded(flex: 2, child: _headerCell('Location Area')),
          Expanded(flex: 1, child: _headerCell('System Status')),
          Expanded(
            flex: 1,
            child: InkWell(
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
                  _headerCell('Rating Score'),
                  if (_sortBy == 'rating') ...[
                    const SizedBox(width: 4),
                    Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: kPinkBright),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: InkWell(
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
                    Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: kPinkBright),
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
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white60),
    );
  }

  Widget _buildMobileCard(Map<String, dynamic> data) {
    final name = data['name'] ?? 'Unknown';
    final email = data['email'] ?? 'N/A';
    final phone = data['phoneNumber'] ?? 'N/A';
    final address = data['locationAddress'] ?? 'N/A';
    final status = data['status'] ?? 'pending';
    final avgRating = (data['averageRating'] ?? 0.0).toDouble();
    final totalRatings = data['totalRatings'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kCardFill.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showVolunteerDetails(context, data['docId'], data),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _statusBadge(status),
                ],
              ),
              const SizedBox(height: 8),
              if (email != 'N/A')
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.email_outlined, size: 14, color: Colors.white38),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(email, style: const TextStyle(fontSize: 13, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              if (phone != 'N/A')
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 14, color: Colors.white38),
                      const SizedBox(width: 6),
                      Text(phone, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                    ],
                  ),
                ),
              if (address != 'N/A')
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: Colors.white38),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(address, style: const TextStyle(fontSize: 13, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.white.withOpacity(0.06)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ratingDisplay(avgRating, totalRatings),
                  Text(
                    'Enrolled: ${_formatDate(data['submittedAt'])}',
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'approved':
        color = kTealAccent;
        break;
      case 'rejected':
        color = kRedAccent;
        break;
      default:
        color = kAmberAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5),
      ),
    );
  }

  Widget _ratingDisplay(double averageRating, int totalRatings) {
    if (totalRatings == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('Unrated', style: TextStyle(fontSize: 11, color: Colors.white38)),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, color: kAmberAccent, size: 16),
        const SizedBox(width: 2),
        Text(
          averageRating.toStringAsFixed(1),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
        ),
        const SizedBox(width: 2),
        Text('($totalRatings reviews)', style: const TextStyle(fontSize: 11, color: Colors.white38)),
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
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  void _showVolunteerDetails(BuildContext context, String volunteerId, Map<String, dynamic> data) {
    final isWide = MediaQuery.of(context).size.width >= _kWideBreakpoint;
    
    if (isWide) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: kNavyMid,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildDetailsShellLayout(ctx, data),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: kNavyMid,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).padding.bottom + 16),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.82),
            child: _buildDetailsShellLayout(ctx, data),
          ),
        ),
      );
    }
  }

  Widget _buildDetailsShellLayout(BuildContext ctx, Map<String, dynamic> data) {
    final specialties = data['specialtiesStr'] ?? 'N/A';
    final status = data['status'] ?? 'pending';
    final avgRating = (data['averageRating'] ?? 0.0).toDouble();
    final totalRatings = data['totalRatings'] ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            const Icon(Icons.account_circle_outlined, size: 22, color: kPinkBright),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Volunteer Enrolment Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: () => Navigator.pop(ctx),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        Divider(height: 24, color: Colors.white.withOpacity(0.08)),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                _buildDetailCard('Personal & Core Profile', [
                  _detailRow('Name:', data['name'] ?? 'N/A'),
                  _detailRow('Email ID:', data['email'] ?? 'N/A'),
                  _detailRow('Contact No:', data['phoneNumber'] ?? 'N/A'),
                  _detailRow('Home Address:', data['locationAddress'] ?? 'N/A'),
                ]),
                const SizedBox(height: 12),
                _buildDetailCard('Operational Logistics', [
                  _detailRow('Languages:', data['language'] ?? 'N/A'),
                  _detailRow('Availability:', data['availability'] ?? 'N/A'),
                  _detailRow('Specialties:', specialties),
                  _detailRow('Status Flag:', _capitalize(status)),
                ]),
                const SizedBox(height: 12),
                _buildDetailCard('Performance Audit Summary', [
                  _detailRow('Avg Rating:', totalRatings > 0 ? '${avgRating.toStringAsFixed(1)} / 5.0' : 'No aggregate metrics yet'),
                  _detailRow('Total Volume:', '$totalRatings evaluation records'),
                  if (totalRatings > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(5, (index) {
                        if (index < avgRating.floor()) {
                          return const Icon(Icons.star_rounded, color: kAmberAccent, size: 20);
                        } else if (index < avgRating && avgRating - index >= 0.5) {
                          return const Icon(Icons.star_half_rounded, color: kAmberAccent, size: 20);
                        } else {
                          return const Icon(Icons.star_border_rounded, color: kAmberAccent, size: 20);
                        }
                      }),
                    ),
                  ]
                ]),
              ],
            ),
          ),
        ),
        Divider(height: 24, color: Colors.white.withOpacity(0.08)),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withOpacity(0.12)),
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Close Sheet', style: TextStyle(fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white38),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.25),
            ),
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