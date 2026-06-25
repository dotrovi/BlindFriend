import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'login_page.dart';
import 'volunteer_profile_page.dart';
import 'volunteer_received_request.dart';
import 'volunteer_history_page.dart';
import 'services/firebase_service.dart';
import 'volunteer_training_page.dart';
import 'services/notification_service.dart';

// ── Shared palette from login page ─────────────────────────────────────────
const Color _kNavyDeep = Color(0xFF120A2E);
const Color _kNavyMid = Color(0xFF1E1147);
const Color _kPurple = Color(0xFF3B1E78);
const Color _kPinkBright = Color(0xFFFF5FD2);
const Color _kBlueAccent = Color(0xFF4A90E2);
const Color _kCardFill = Color(0xFF241A45);

const LinearGradient _kSkyGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [_kNavyDeep, _kNavyMid, _kPurple],
);

const LinearGradient _kAccentGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_kPinkBright, Color(0xFF9B59B6), _kBlueAccent],
);

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
  double? _currentLat;
  double? _currentLng;
  late StreamSubscription<QuerySnapshot> _helpRequestsSubscription;

  // Stats
  int _pendingCount = 0;
  int _acceptedCount = 0;
  int _completedCount = 0;
  int _declinedCount = 0;
  bool _isLoadingStats = true;
  int _trainingProgress = 0;

  // Volunteer matching data
  List<String> _volunteerSpecialties = [];
  List<String> _volunteerLanguages = ['english'];

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

    bool isFirstLoad = true;

    _helpRequestsSubscription = FirebaseFirestore.instance
        .collection('help_requests')
        .snapshots()
        .listen((snapshot) {
      _updateStatsFromSnapshot(snapshot);

      if (isFirstLoad) {
        isFirstLoad = false;
        return;
      }

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final status = (data['status'] ?? '').toString().toLowerCase();
          final volunteerId = data['volunteerId'];

          if (status == 'pending' &&
              (volunteerId == null || volunteerId.toString().isEmpty)) {
            final requestType = (data['requestType'] ?? 'help').toString();
            final blindUserName =
                (data['blindUserName'] ?? 'A blind user').toString();
            final location = (data['location'] ?? 'nearby').toString();

            NotificationService().showHelpRequestNotification(
              blindUserName: blindUserName,
              requestType: requestType,
              location: location,
            );
          }
        }
      }
    });
  }

  void _updateStatsFromSnapshot(QuerySnapshot snapshot) {
    final uid = _uid;
    if (uid == null) return;

    int pending = 0;
    int accepted = 0;
    int completed = 0;
    int declined = 0;

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final rawStatus = data['status'] ?? '';
      final status = rawStatus.toString().toLowerCase();

      final volunteerField = data['volunteerId'] ??
          data['volunteer'] ??
          data['assignedVolunteerId'];
      String? volunteerIdStr;
      if (volunteerField is DocumentReference) {
        volunteerIdStr = volunteerField.id;
      } else if (volunteerField != null) {
        volunteerIdStr = volunteerField.toString();
      }

      final isAssignedToMe = volunteerIdStr == uid;
      final declinedBy = List<String>.from(data['declinedBy'] ?? []);
      if (declinedBy.contains(uid)) declined++;

      if (status == 'accepted' ||
          status == 'assigned' ||
          status == 'in_progress') {
        if (isAssignedToMe) accepted++;
      } else if (status == 'completed' ||
          status == 'done' ||
          status == 'finished') {
        if (isAssignedToMe) completed++;
      } else if (status == 'pending' ||
          status == 'awaiting' ||
          status == 'requested') {
        final isUnassigned = volunteerIdStr == null || volunteerIdStr.isEmpty;
        if (isUnassigned) {
          final requestType =
              (data['requestType'] ?? '').toString().toLowerCase();
          final requestLanguage =
              (data['preferredLanguage'] ?? 'english').toString().toLowerCase();
          if (_volunteerSpecialties.contains(requestType) &&
              _volunteerLanguages.contains(requestLanguage)) {
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
        _declinedCount = declined;
        _isLoadingStats = false;
      });
    }
  }

  @override
  void dispose() {
    _helpRequestsSubscription.cancel();
    super.dispose();
  }

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
      final progress = data['trainingProgress'] as Map<String, dynamic>? ?? {};
      _trainingProgress = progress.values.where((v) => v == true).length;

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
        if (savedAddress != null && savedAddress.isNotEmpty) {
          _locationText = savedAddress;
        } else if (geoPoint != null) {
          _locationText =
              '${geoPoint.latitude.toStringAsFixed(5)}, ${geoPoint.longitude.toStringAsFixed(5)}';
        }
        _locationLastUpdated = updatedAt?.toDate();

        if (geoPoint != null) {
          _currentLat = geoPoint.latitude;
          _currentLng = geoPoint.longitude;
        }
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
          _currentLat = position.latitude;
          _currentLng = position.longitude;
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

  Future<Map<String, dynamic>> _getVolunteerRatingData() async {
    final uid = _uid;
    if (uid == null) return {'averageRating': 0.0, 'totalRatings': 0};

    try {
      final doc = await FirebaseFirestore.instance
          .collection('volunteers')
          .doc(uid)
          .get();
      final data = doc.data();
      return {
        'averageRating': (data?['averageRating'] ?? 0.0).toDouble(),
        'totalRatings': data?['totalRatings'] ?? 0,
      };
    } catch (e) {
      return {'averageRating': 0.0, 'totalRatings': 0};
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kNavyDeep,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                _buildHomePage(),
                const VolunteerReceivedRequestsScreen(),
                const VolunteerHistoryPage(),
                const SizedBox.shrink(),
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
          colors: [_kPurple, _kNavyMid, _kNavyDeep],
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
                    const Row(
                      children: [
                        Text(
                          'Blind',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Friend',
                          style: TextStyle(
                            color: _kPinkBright,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _isAvailable
                                ? const Color(0xFF6EE7B7)
                                : Colors.grey.shade600,
                            shape: BoxShape.circle,
                            boxShadow: _isAvailable
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF6EE7B7)
                                          .withOpacity(0.6),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _isAvailable ? 'Available' : 'Unavailable',
                          style: TextStyle(
                            color: _isAvailable
                                ? const Color(0xFF6EE7B7)
                                : Colors.grey.shade500,
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
                          color: _kPinkBright,
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
                      color: Colors.white.withOpacity(0.85),
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
      {'icon': Icons.history_rounded, 'label': 'History'},
      {'icon': Icons.person_rounded, 'label': 'Profile'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: _kNavyMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
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
                  onTap: () {
                    if (i == 3) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VolunteerProfilePage(),
                        ),
                      ).then((_) {
                        _loadVolunteerData();
                        FirebaseFirestore.instance
                            .collection('help_requests')
                            .get()
                            .then((snapshot) {
                          _updateStatsFromSnapshot(snapshot);
                        });
                      });
                    } else {
                      setState(() => _selectedIndex = i);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _kPinkBright.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          color: isSelected
                              ? _kPinkBright
                              : Colors.grey.shade500,
                          size: 24,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? _kPinkBright
                                : Colors.grey.shade600,
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

  Widget _buildHomePage() {
    return RefreshIndicator(
      onRefresh: () async {
        final snapshot = await FirebaseFirestore.instance
            .collection('help_requests')
            .get();
        _updateStatsFromSnapshot(snapshot);
        await _loadVolunteerData();
      },
      color: _kPinkBright,
      backgroundColor: _kNavyMid,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _buildMapSection(),
            _buildActionGrid(),
            const SizedBox(height: 12),
            _buildFeedbackPreview(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSection() {
    final screenHeight = MediaQuery.of(context).size.height;
    final mapHeight = screenHeight * 0.42;

    return Container(
      height: mapHeight,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: _kPinkBright.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            if (_currentLat != null && _currentLng != null)
              FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(_currentLat!, _currentLng!),
                  initialZoom: 15.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.blindfriend.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(_currentLat!, _currentLng!),
                        width: 40,
                        height: 40,
                        child: _buildLocationMarker(),
                      ),
                    ],
                  ),
                ],
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _kBlueAccent.withOpacity(0.2),
                      _kCardFill,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: 48,
                        color: Colors.white.withOpacity(0.4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No location set',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap "Update GPS" below',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 12,
              left: 12,
              child: _buildMapBadge(
                icon: Icons.star_rounded,
                label: _buildRatingBadgeLabel(),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                ),
              ),
            ),
            if (_pendingCount > 0)
              Positioned(
                top: 12,
                right: 12,
                child: _buildMapBadge(
                  icon: Icons.notifications_active_rounded,
                  label: Text(
                    '$_pendingCount pending',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.deepOrange],
                  ),
                  showPulse: true,
                ),
              ),
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: _kPinkBright, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _locationText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingBadgeLabel() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getVolunteerRatingData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          );
        }
        if (snapshot.hasData && snapshot.data!['totalRatings'] > 0) {
          final avg =
              (snapshot.data!['averageRating'] as double).toStringAsFixed(1);
          return Text(
            avg,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          );
        }
        return const Text(
          'New',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        );
      },
    );
  }

  Widget _buildMapBadge({
    required IconData icon,
    required Widget label,
    required LinearGradient gradient,
    bool showPulse = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (gradient.colors.first).withOpacity(0.5),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          label,
          if (showPulse) ...[
            const SizedBox(width: 6),
            _PulsingDot(),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationMarker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: _kAccentGradient,
            boxShadow: [
              BoxShadow(
                color: _kPinkBright.withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.circle, size: 12, color: Colors.white),
        ),
        Container(
          width: 2,
          height: 16,
          color: Colors.white.withOpacity(0.8),
        ),
      ],
    );
  }

  Widget _buildActionGrid() {
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = 16.0;
    final spacing = 12.0;
    final squareSize = (screenWidth - padding * 2 - spacing) / 2;

    final actions = [
      {
        'icon': Icons.gps_fixed_rounded,
        'label': 'Update\nGPS',
        'color': const Color(0xFF4A90E2),
        'onTap': _isUpdatingLocation ? null : _updateLocation,
      },
      {
        'icon': _isAvailable
            ? Icons.toggle_on_rounded
            : Icons.toggle_off_rounded,
        'label': _isAvailable ? 'Online' : 'Offline',
        'color': _isAvailable ? const Color(0xFF6EE7B7) : Colors.grey,
        'onTap': _isTogglingAvailability ? null : _toggleAvailability,
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: actions.map((action) {
              final label = action['label'] as String;
              final icon = action['icon'] as IconData;
              final color = action['color'] as Color;
              final onTap = action['onTap'] as VoidCallback?;

              final isLoading = (label.contains('GPS') && _isUpdatingLocation) ||
                  (label.contains('Online') && _isTogglingAvailability) ||
                  (label.contains('Offline') && _isTogglingAvailability);

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: action == actions.first ? spacing / 2 : 0,
                    left: action == actions.last ? spacing / 2 : 0,
                  ),
                  child: GestureDetector(
                    onTap: isLoading ? null : onTap,
                    child: Container(
                      height: squareSize,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _kCardFill.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isLoading)
                            const SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: _kPinkBright,
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    color.withOpacity(0.2),
                                    color.withOpacity(0.05),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: color.withOpacity(0.4),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withOpacity(0.3),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Icon(icon, color: color, size: 28),
                            ),
                          const SizedBox(height: 10),
                          Flexible(
                            child: Text(
                              label.split('\n')[0],
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (label.contains('\n')) ...[
                            const SizedBox(height: 2),
                            Flexible(
                              child: Text(
                                label.split('\n')[1],
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 10,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _buildTrainingCard(),
        ],
      ),
    );
  }

  Widget _buildTrainingCard() {
    final trainingSubtitle = _trainingSubtitle();
    final isComplete = _trainingProgress >= 4;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VolunteerTrainingPage()),
        );
        _loadVolunteerData();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isComplete
                ? [
                    const Color(0xFF6EE7B7).withOpacity(0.15),
                    _kCardFill.withOpacity(0.7)
                  ]
                : [
                    const Color(0xFFF59E0B).withOpacity(0.15),
                    _kCardFill.withOpacity(0.7)
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isComplete
                ? const Color(0xFF6EE7B7).withOpacity(0.3)
                : const Color(0xFFF59E0B).withOpacity(0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: isComplete
                  ? const Color(0xFF6EE7B7).withOpacity(0.15)
                  : const Color(0xFFF59E0B).withOpacity(0.15),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isComplete
                      ? [const Color(0xFF6EE7B7), const Color(0xFF34D399)]
                      : [const Color(0xFFF59E0B), const Color(0xFFF97316)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: isComplete
                        ? const Color(0xFF6EE7B7).withOpacity(0.4)
                        : const Color(0xFFF59E0B).withOpacity(0.4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                isComplete ? Icons.verified_rounded : Icons.school_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Induction Training',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trainingSubtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _trainingProgress / 4,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isComplete
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFFF59E0B),
                      ),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackPreview() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getIndividualFeedback(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError ||
            snapshot.data == null ||
            snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final feedback = snapshot.data!.first;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kCardFill.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: _kAccentGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      (feedback['blindUserName'] as String).isNotEmpty
                          ? (feedback['blindUserName'] as String)[0]
                              .toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            i < (feedback['rating'] as int)
                                ? Icons.star
                                : Icons.star_border,
                            size: 14,
                            color: const Color(0xFFFFD700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (feedback['comment'] as String).isNotEmpty
                            ? feedback['comment'] as String
                            : 'No comment',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getIndividualFeedback() async {
    final uid = _uid;
    if (uid == null) return [];

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('help_requests')
          .where('volunteerId', isEqualTo: uid)
          .get();

      final feedbacks = <Map<String, dynamic>>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final rating = data['rating'] ?? 0;
        if (rating > 0) {
          feedbacks.add({
            'rating': rating,
            'comment': data['feedbackComment'] ?? '',
            'blindUserName': data['blindUserName'] ?? 'Anonymous',
            'requestType': data['requestType'] ?? 'help',
            'ratedAt': data['ratedAt'] as Timestamp?,
          });
        }
      }
      feedbacks.sort((a, b) {
        final aDate = a['ratedAt'] as Timestamp?;
        final bDate = b['ratedAt'] as Timestamp?;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.toDate().compareTo(aDate.toDate());
      });
      return feedbacks;
    } catch (e) {
      return [];
    }
  }
}

// ── Pulsing dot widget ────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  @override
  __PulsingDotState createState() => __PulsingDotState();
}

class __PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.6, end: 1.0).animate(_controller),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
      ),
    );
  }
}