import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'login_page.dart';
import 'volunteer_profile_page.dart';
import 'volunteer_received_request.dart';
import 'services/firebase_service.dart';
import 'volunteer_training_page.dart';

class VolunteerHomePage extends StatefulWidget {
  final String userName;
  const VolunteerHomePage({super.key, required this.userName});

  @override
  State<VolunteerHomePage> createState() => _VolunteerHomePageState();
}

class _VolunteerHomePageState extends State<VolunteerHomePage> {
  int _selectedIndex = 0;

  // Location & availability
  final FirebaseService _firebaseService = FirebaseService();
  bool _isAvailable = true;
  bool _isUpdatingLocation = false;
  bool _isTogglingAvailability = false;
  String _locationText = 'Not set';
  DateTime? _locationLastUpdated;
  late StreamSubscription<QuerySnapshot> _helpRequestsSubscription;

  // Stats
  int _pendingCount = 0;
  int _acceptedCount = 0;
  int _completedCount = 0;
  bool _isLoadingStats = true;
  // Training progress state
  int _trainingProgress = 0;


  // Volunteer matching data (for counting pending requests)
  List<String> _volunteerSpecialties = [];
  List<String> _volunteerLanguages = ['english'];

  // Profile data for profile tab
  String _profilePhone = '';
  List<String> _profileLanguages = [];
  List<String> _profileSpecialties = [];
  String _profileAvailability = '';

  static const _emerald = Color(0xFF059669);
  static const _emeraldDark = Color(0xFF047857);
  static const _emeraldLight = Color(0xFFD1FAE5);
  static const _mintBg = Color(0xFFF0FDF4);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  String _trainingSubtitle() {
    if (_trainingProgress >= 4) return 'Training complete ✓';
    if (_trainingProgress == 0) return 'Start your induction training';
    return '$_trainingProgress of 4 chapters complete';
  }
  

  @override
  void initState() {
    super.initState();
    _loadVolunteerData();
    _setupRealtimeStats();
  }

  void _setupRealtimeStats() {
    final uid = _uid;
    if (uid == null) return;

    _helpRequestsSubscription = FirebaseFirestore.instance
        .collection('help_requests')
        .snapshots()
        .listen((snapshot) {
          _updateStatsFromSnapshot(snapshot);
        });
  }

void _updateStatsFromSnapshot(QuerySnapshot snapshot) {
  final uid = _uid;
  if (uid == null) return;

  int pending = 0;
  int accepted = 0;
  int completed = 0;

  for (var doc in snapshot.docs) {
    final data = doc.data() as Map<String, dynamic>;
    final rawStatus = data['status'] ?? '';
    final status = rawStatus.toString().toLowerCase();

    // Get volunteer ID
    final volunteerField = data['volunteerId'] ?? 
                           data['volunteer'] ?? 
                           data['assignedVolunteerId'];
    String? volunteerIdStr;
    if (volunteerField is DocumentReference) {
      volunteerIdStr = volunteerField.id;
    } else if (volunteerField != null) {
      volunteerIdStr = volunteerField.toString();
    }

    // Check if request is assigned to this volunteer
    final isAssignedToMe = volunteerIdStr == uid;
    
    // Count accepted/in_progress requests assigned to this volunteer
    if (status == 'accepted' || status == 'assigned' || status == 'in_progress') {
      if (isAssignedToMe) {
        accepted++;
      }
    } 
    else if (status == 'completed' || status == 'done' || status == 'finished') {
      if (isAssignedToMe) {
        completed++;
      }
    }
    else if (status == 'pending' || status == 'awaiting' || status == 'requested') {
      // IMPORTANT: Only count if NOT assigned to anyone yet
      final isUnassigned = volunteerIdStr == null || volunteerIdStr.isEmpty;
      
      if (isUnassigned) {
        final requestType = (data['requestType'] ?? '').toString().toLowerCase();
        final requestLanguage = (data['preferredLanguage'] ?? 'english').toString().toLowerCase();
        
        final matchesSpecialty = _volunteerSpecialties.contains(requestType);
        final matchesLanguage = _volunteerLanguages.contains(requestLanguage);
        
        // Count if BOTH specialty AND language match
        if (matchesSpecialty && matchesLanguage) {
          pending++;
        }
      }
    }
  }

  if (mounted) {
    setState(() {
      _pendingCount = pending;
      _acceptedCount = accepted;
      _completedCount = completed;
      _isLoadingStats = false;
    });
  }
}


  @override
  void dispose() {
    _helpRequestsSubscription.cancel();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────

  Future<void> _loadVolunteerData() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('volunteers')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data == null || !mounted) return;

      final geoPoint = data['location'] as GeoPoint?;
      final updatedAt = data['locationUpdatedAt'] as Timestamp?;
      final savedAddress = data['locationAddress'] as String?;
      // Load training progress
      final progress = data['trainingProgress'] as Map<String, dynamic>? ?? {};
      _trainingProgress = progress.values.where((v) => v == true).length;

      // Load volunteer specialties and languages for stats matching
      _volunteerSpecialties = List<String>.from(
        data['specialties'] ?? [],
      ).map((s) => s.toString().toLowerCase()).toList();

      final rawLang = data['language'];
      if (rawLang is List) {
        _volunteerLanguages = List<String>.from(
          rawLang,
        ).map((s) => s.toString().toLowerCase()).toList();
      } else if (rawLang is String && rawLang.isNotEmpty) {
        _volunteerLanguages = [rawLang.toLowerCase()];
      } else {
        _volunteerLanguages = ['english'];
      }
      

      setState(() {
        _isAvailable = data['isAvailable'] ?? true;
        _profilePhone = data['phoneNumber'] ?? '';
        if (rawLang is List) {
          _profileLanguages = List<String>.from(rawLang);
        } else if (rawLang is String && rawLang.isNotEmpty) {
          _profileLanguages = [rawLang];
        } else {
          _profileLanguages = [];
        }
        _profileSpecialties = List<String>.from(data['specialties'] ?? []);
        _profileAvailability = data['availability'] ?? '';
        if (savedAddress != null && savedAddress.isNotEmpty) {
          _locationText = savedAddress;
        } else if (geoPoint != null) {
          _locationText =
              '${geoPoint.latitude.toStringAsFixed(5)}, ${geoPoint.longitude.toStringAsFixed(5)}';
        }
        _locationLastUpdated = updatedAt?.toDate();
      });

  
    } catch (_) {}
  }

  Future<void> _updateLocation() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _isUpdatingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                permission == LocationPermission.deniedForever
                    ? 'Location permission permanently denied. Please enable in Settings.'
                    : 'Location permission denied.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final address = await _reverseGeocode(
        position.latitude,
        position.longitude,
      );

      final success = await _firebaseService.updateVolunteerLocation(
        uid: uid,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (success) {
        await FirebaseFirestore.instance
            .collection('volunteers')
            .doc(uid)
            .update({'locationAddress': address});
      }

      if (!mounted) return;
      if (success) {
        setState(() {
          _locationText = address;
          _locationLastUpdated = DateTime.now();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save location. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not get location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingLocation = false);
    }
  }

  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=$lat&lon=$lng&zoom=14&addressdetails=1',
      );
      final response = await http
          .get(
            url,
            headers: {'User-Agent': 'BlindFriend/1.0', 'Accept-Language': 'en'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>? ?? {};
        final parts = <String>[];
        for (final key in [
          'suburb',
          'village',
          'town',
          'city_district',
          'city',
          'county',
          'state',
          'country',
        ]) {
          final val = addr[key] as String?;
          if (val != null && val.isNotEmpty && !parts.contains(val)) {
            parts.add(val);
          }
          if (parts.length >= 3) break;
        }
        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (_) {}
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  Future<void> _toggleAvailability() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _isTogglingAvailability = true);
    final newValue = !_isAvailable;
    final success = await _firebaseService.updateVolunteerAvailability(
      uid: uid,
      isAvailable: newValue,
    );
    if (!mounted) return;
    if (success) {
      setState(() => _isAvailable = newValue);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update availability. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
    setState(() => _isTogglingAvailability = false);
  }

  String _formatLastUpdated() {
    if (_locationLastUpdated == null) return 'Never updated';
    final diff = DateTime.now().difference(_locationLastUpdated!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _mintBg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                _buildHomePage(),
                const VolunteerReceivedRequestsScreen(),
                _buildProfilePage(),
              ],
            ),
          ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BlindFriend',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _isAvailable
                                ? const Color(0xFF6EE7B7)
                                : Colors.grey.shade400,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _isAvailable ? 'Available' : 'Unavailable',
                          style: const TextStyle(
                            color: Color(0xFFBBF7D0),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        widget.userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        'Volunteer',
                        style: TextStyle(
                          color: Color(0xFFBBF7D0),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      }
                    },
                    icon: Icon(
                      Icons.logout,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    const navItems = [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.handshake_outlined, 'label': 'Requests'},
      {'icon': Icons.person_rounded, 'label': 'Profile'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: List.generate(navItems.length, (i) {
              final isSelected = _selectedIndex == i;
              final icon = navItems[i]['icon'] as IconData;
              final label = navItems[i]['label'] as String;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _emerald.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          color: isSelected ? _emerald : Colors.grey.shade400,
                          size: 24,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected ? _emerald : Colors.grey.shade500,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ── Home tab ──────────────────────────────────────────────────────────

  Widget _buildHomePage() {
    return RefreshIndicator(
      onRefresh: () async {
        final snapshot = await FirebaseFirestore.instance
            .collection('help_requests')
            .get();
        _updateStatsFromSnapshot(snapshot);
        await _loadVolunteerData();
      },
      color: _emerald,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          children: [
            _buildWelcomeBanner(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildAvailabilityCard()),
                const SizedBox(width: 12),
                Expanded(child: _buildLocationMiniCard()),
              ],
            ),
            const SizedBox(height: 16),
            _buildLocationFullCard(),
            const SizedBox(height: 16),
            _buildStatsRow(),
            const SizedBox(height: 16),
            _buildQuickActions(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _emerald.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good day,',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isAvailable
                            ? const Color(0xFF6EE7B7)
                            : Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isAvailable
                          ? 'Available for help requests'
                          : 'Not accepting requests',
                      style: const TextStyle(
                        color: Color(0xFFBBF7D0),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.volunteer_activism_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isAvailable
              ? _emerald.withValues(alpha: 0.3)
              : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _isAvailable
                ? _emerald.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isAvailable ? _emeraldLight : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _isAvailable
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_tethering_off_rounded,
                  color: _isAvailable ? _emerald : Colors.grey.shade500,
                  size: 18,
                ),
              ),
              const Spacer(),
              _isTogglingAvailability
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : GestureDetector(
                      onTap: _toggleAvailability,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 40,
                        height: 22,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: _isAvailable ? _emerald : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 250),
                          alignment: _isAvailable
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _isAvailable ? 'Available' : 'Unavailable',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: _isAvailable ? _emeraldDark : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _isAvailable ? 'Accepting requests' : 'Not accepting',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationMiniCard() {
    final hasLocation = _locationText != 'Not set';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasLocation
              ? const Color(0xFF7C3AED).withValues(alpha: 0.25)
              : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasLocation
                      ? const Color(0xFFEDE9FE)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasLocation
                      ? Icons.location_on_rounded
                      : Icons.location_off_rounded,
                  color: hasLocation
                      ? const Color(0xFF7C3AED)
                      : Colors.grey.shade500,
                  size: 18,
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: hasLocation
                      ? const Color(0xFF7C3AED)
                      : Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Location',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            _formatLastUpdated(),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationFullCard() {
    final hasLocation = _locationText != 'Not set';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.my_location_rounded,
                color: Color(0xFF7C3AED),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Your Location',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              _isUpdatingLocation
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : GestureDetector(
                      onTap: _updateLocation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFF9F67FA)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.gps_fixed_rounded,
                              color: Colors.white,
                              size: 13,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Update GPS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: hasLocation
                  ? const Color(0xFFEDE9FE)
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  hasLocation
                      ? Icons.location_on_rounded
                      : Icons.location_searching_rounded,
                  color: hasLocation
                      ? const Color(0xFF7C3AED)
                      : Colors.grey.shade400,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _locationText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: hasLocation
                          ? const Color(0xFF5B21B6)
                          : Colors.grey.shade500,
                    ),
                  ),
                ),
                if (hasLocation)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: Color(0xFF059669),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Shared',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (!hasLocation) ...[
            const SizedBox(height: 8),
            Text(
              'Tap "Update GPS" to share your location with nearby blind users.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    if (_isLoadingStats) {
      return Row(
        children: [
          _buildStatItem(
            'Pending',
            '...',
            Icons.pending_actions_rounded,
            Colors.orange,
          ),
          const SizedBox(width: 10),
          _buildStatItem(
            'Accepted',
            '...',
            Icons.check_circle_outline_rounded,
            Colors.blue,
          ),
          const SizedBox(width: 10),
          _buildStatItem('Done', '...', Icons.verified_rounded, _emerald),
        ],
      );
    }

    return Row(
      children: [
        _buildStatItem(
          'Pending',
          _pendingCount.toString(),
          Icons.pending_actions_rounded,
          Colors.orange,
        ),
        const SizedBox(width: 10),
        _buildStatItem(
          'Accepted',
          _acceptedCount.toString(),
          Icons.check_circle_outline_rounded,
          Colors.blue,
        ),
        const SizedBox(width: 10),
        _buildStatItem(
          'Done',
          _completedCount.toString(),
          Icons.verified_rounded,
          _emerald,
        ),
      ],
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 14),
          _buildActionTile(
            icon: Icons.handshake_outlined,
            iconColor: Colors.blue.shade600,
            iconBg: Colors.blue.shade50,
            title: 'View Help Requests',
            subtitle: 'See requests from blind users',
            onTap: () => setState(() => _selectedIndex = 1),
          ),
          const SizedBox(height: 10),
          _buildActionTile(
            icon: Icons.person_rounded,
            iconColor: _emerald,
            iconBg: _emeraldLight,
            title: 'My Profile',
            subtitle: 'Update your information',
            onTap: () => setState(() => _selectedIndex = 2),
          ),
          _buildActionTile(
            icon: Icons.school_rounded,
            iconColor: const Color(0xFFF59E0B),
            iconBg: const Color(0xFFFFFBEB),
            title: 'Induction Training',
            subtitle: _trainingSubtitle(),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const VolunteerTrainingPage(),
                ),
              );
              _loadVolunteerData(); // refresh after training
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ── Profile tab ───────────────────────────────────────────────────────

  Widget _buildProfilePage() {
    final user = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF047857), Color(0xFF10B981)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Text(
                      widget.userName.isNotEmpty
                          ? widget.userName[0].toUpperCase()
                          : 'V',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  user?.email ?? 'No email',
                  style: const TextStyle(
                    color: Color(0xFFBBF7D0),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Volunteer',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                _profileInfoCard(
                  title: 'CONTACT',
                  accentColor: Colors.blue.shade600,
                  icon: Icons.phone_rounded,
                  children: [
                    _profileInfoRow(
                      Icons.phone_outlined,
                      'Phone',
                      _profilePhone.isEmpty ? '—' : _profilePhone,
                    ),
                  ],
                ),
                _profileInfoCard(
                  title: 'LANGUAGE',
                  accentColor: const Color(0xFF7C3AED),
                  icon: Icons.language_rounded,
                  children: [
                    _profileInfoRow(
                      Icons.translate_rounded,
                      'Speaks',
                      _profileLanguages.isEmpty
                          ? '—'
                          : _profileLanguages.join(', '),
                    ),
                  ],
                ),
                _profileInfoCard(
                  title: 'SPECIALTIES',
                  accentColor: Colors.orange.shade700,
                  icon: Icons.star_rounded,
                  children: [
                    if (_profileSpecialties.isEmpty)
                      const Text(
                        '—',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _profileSpecialties
                            .map(
                              (s) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.orange.shade400,
                                      Colors.orange.shade600,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  s,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
                _profileInfoCard(
                  title: 'AVAILABILITY',
                  accentColor: Colors.teal.shade600,
                  icon: Icons.schedule_rounded,
                  children: [
                    _profileInfoRow(
                      Icons.access_time_rounded,
                      'Schedule',
                      _profileAvailability.isEmpty ? '—' : _profileAvailability,
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const VolunteerProfilePage(),
                  ),
                );
                _loadVolunteerData();
                final snapshot = await FirebaseFirestore.instance
                    .collection('help_requests')
                    .get();
                _updateStatsFromSnapshot(snapshot);
              },
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Edit Profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _emerald,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileInfoCard({
    required String title,
    required Color accentColor,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accentColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _profileInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: _emerald, size: 17),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }
}
