import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'theme/app_palette.dart';

/// Combined Overview + Statistics dashboard for the admin portal.
class AdminOverviewPage extends StatefulWidget {
  final void Function(String pageKey) onNavigate;

  const AdminOverviewPage({super.key, required this.onNavigate});

  @override
  State<AdminOverviewPage> createState() => _AdminOverviewPageState();
}

class _AdminOverviewPageState extends State<AdminOverviewPage> {
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  String? _errorMessage;
  String _adminName = 'Admin';

  // Stat cards
  int _totalVolunteers = 0;
  int _verifiedVolunteers = 0;
  int _blindUsers = 0;
  int _reportsMade = 0;

  // Rating overview
  double _overallAverageRating = 0.0;
  int _totalRatings = 0;
  Map<int, int> _ratingDistribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

  // Volunteer status
  int _pendingCount = 0;
  int _approvedCount = 0;
  int _rejectedCount = 0;

  // Top performers
  List<Map<String, dynamic>> _topPerformers = [];

  // Live location: most recent active help request with coordinates
  Map<String, dynamic>? _liveRequest;

  // Location history: request counts for each of the last 7 days
  List<int> _requestCountsByDay = List.filled(7, 0);
  List<String> _dayLabels = [];

  @override
  void initState() {
    super.initState();
    _loadAdminName();
    _loadDashboardData();
  }

  Future<void> _loadAdminName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await _firestore.collection('admins').doc(user.uid).get();
      final name = doc.data()?['name'] as String?;
      if (mounted) {
        setState(() {
          _adminName = (name != null && name.isNotEmpty)
              ? name
              : (user.email?.split('@').first ?? 'Admin');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _adminName = user.email?.split('@').first ?? 'Admin');
      }
    }
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // ── Volunteers ──
      final volunteerSnapshot = await _firestore.collection('volunteers').get();
      final volunteers = volunteerSnapshot.docs;
      _totalVolunteers = volunteers.length;

      final ratingDist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
      double totalRatingSum = 0.0;
      int totalRatings = 0;
      int pending = 0, approved = 0, rejected = 0;
      final performers = <Map<String, dynamic>>[];

      for (var doc in volunteers) {
        final data = doc.data();
        final status = (data['status'] ?? 'pending').toString().toLowerCase();

        if (status == 'pending') {
          pending++;
        } else if (status == 'approved') {
          approved++;
        } else if (status == 'rejected') {
          rejected++;
        }

        String volunteerName = data['name'] ?? 'Unknown';
        if (volunteerName == 'Unknown' || volunteerName.isEmpty) {
          try {
            final uid = data['uid'] ?? doc.id;
            final userDoc = await _firestore.collection('users').doc(uid).get();
            if (userDoc.exists) {
              volunteerName = userDoc.data()?['name'] ?? 'Unknown';
            }
          } catch (_) {}
        }

        dynamic avgRatingValue = data['averageRating'] ?? 0.0;
        double avgRating = avgRatingValue is int
            ? avgRatingValue.toDouble()
            : (avgRatingValue as double? ?? 0.0);

        dynamic totalRatingValue = data['totalRatings'] ?? 0;
        int totalRating = totalRatingValue is int
            ? totalRatingValue
            : (totalRatingValue as double? ?? 0).toInt();

        if (totalRating > 0) {
          totalRatings += totalRating;
          totalRatingSum += avgRating * totalRating;
          performers.add({
            'uid': data['uid'] ?? doc.id,
            'name': volunteerName,
            'avgRating': avgRating,
            'totalRatings': totalRating,
          });
        }
      }

      _pendingCount = pending;
      _approvedCount = approved;
      _rejectedCount = rejected;
      _verifiedVolunteers = approved;

      performers.sort((a, b) {
        final ratingA = a['avgRating'] as double;
        final ratingB = b['avgRating'] as double;
        if (ratingA != ratingB) return ratingB.compareTo(ratingA);
        return (b['totalRatings'] as int).compareTo(a['totalRatings'] as int);
      });
      _topPerformers = performers.length > 5 ? performers.sublist(0, 5) : performers;

      // ── Blind users ──
      final blindUsersSnap = await _firestore
          .collection('users')
          .where('userType', isEqualTo: 'blind')
          .get();
      _blindUsers = blindUsersSnap.docs.length;

      // ── Reports made ──
      final reportsSnap = await _firestore.collection('reports').get();
      _reportsMade = reportsSnap.docs.length;

      // ── Rating distribution (from completed help_requests) ──
      final ratingSnapshot = await _firestore
          .collection('help_requests')
          .where('rating', isGreaterThan: 0)
          .get();
      for (var doc in ratingSnapshot.docs) {
        final data = doc.data();
        dynamic ratingValue = data['rating'] ?? 0;
        int rating = ratingValue is int ? ratingValue : (ratingValue as double).toInt();
        if (rating >= 1 && rating <= 5) {
          ratingDist[rating] = (ratingDist[rating] ?? 0) + 1;
        }
      }
      _ratingDistribution = ratingDist;
      _overallAverageRating = totalRatings > 0 ? totalRatingSum / totalRatings : 0.0;
      _totalRatings = totalRatings;

      // ── Live location: most recent active request with coordinates ──
      // Sorted client-side (rather than orderBy in the query) so this
      // doesn't require a Firestore composite index.
      final activeSnapshot = await _firestore
          .collection('help_requests')
          .where('status', whereIn: ['pending', 'accepted', 'in_progress'])
          .get();
      final activeDocsWithLocation = activeSnapshot.docs
          .where((doc) =>
              doc.data()['latitude'] != null && doc.data()['longitude'] != null)
          .toList()
        ..sort((a, b) {
          final tsA = a.data()['createdAt'] as Timestamp?;
          final tsB = b.data()['createdAt'] as Timestamp?;
          if (tsA == null || tsB == null) return 0;
          return tsB.compareTo(tsA);
        });
      _liveRequest =
          activeDocsWithLocation.isNotEmpty ? activeDocsWithLocation.first.data() : null;

      // ── Location history: request counts per day for the last 7 days ──
      final now = DateTime.now();
      final weekStart = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6));
      final weekSnapshot = await _firestore
          .collection('help_requests')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
          .get();
      final counts = List.filled(7, 0);
      final labels = <String>[];
      for (int i = 0; i < 7; i++) {
        final day = weekStart.add(Duration(days: i));
        labels.add(_weekdayShort(day));
      }
      for (final doc in weekSnapshot.docs) {
        final createdAt = doc.data()['createdAt'] as Timestamp?;
        if (createdAt == null) continue;
        final date = createdAt.toDate();
        final dayIndex = DateTime(date.year, date.month, date.day)
            .difference(weekStart)
            .inDays;
        if (dayIndex >= 0 && dayIndex < 7) counts[dayIndex]++;
      }
      _requestCountsByDay = counts;
      _dayLabels = labels;

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _weekdayShort(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kPinkBright));
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: kRedAccent),
            const SizedBox(height: 16),
            Text('Error loading dashboard: $_errorMessage',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDashboardData,
              style: ElevatedButton.styleFrom(
                  backgroundColor: kPinkBright, foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Container(
      color: kNavyDeep,
      child: RefreshIndicator(
        onRefresh: _loadDashboardData,
        color: kPinkBright,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 800;
            return SingleChildScrollView(
              padding: EdgeInsets.all(isWide ? 24 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(isWide),
                  const SizedBox(height: 20),
                  _buildStatCardsRow(),
                  const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 800;
                  final left = Column(
                    children: [
                      _buildLiveLocationCard(),
                      const SizedBox(height: 20),
                      _buildLocationHistoryCard(),
                    ],
                  );
                  final right = Column(
                    children: [
                      _buildRatingOverviewCard(),
                      const SizedBox(height: 20),
                      _buildVolunteerStatusCard(),
                      const SizedBox(height: 20),
                      _buildTopPerformersCard(),
                    ],
                  );
                  if (!isWide) {
                    return Column(children: [left, const SizedBox(height: 20), right]);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: 20),
                      Expanded(child: right),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              _buildQuickActions(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------

  Widget _buildHeader(bool isWide) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$greeting,',
                  style: const TextStyle(fontSize: 14, color: Colors.white60)),
              Text(_adminName,
                  style: TextStyle(
                      fontSize: isWide ? 30 : 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              const Text('Welcome back to BlindFriend Admin Portal',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => widget.onNavigate('verification'),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: const Icon(Icons.notifications_outlined, color: Colors.white70),
              ),
              if (_pendingCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    decoration: const BoxDecoration(
                        color: kRedAccent, shape: BoxShape.circle),
                    child: Text(
                      '$_pendingCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (isWide) ...[
          const SizedBox(width: 16),
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: kAccentGradient),
            child: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_adminName,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const Text('Admin', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STAT CARDS
  // ---------------------------------------------------------------------------

  Widget _buildStatCardsRow() {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 800;
      final cards = [
        _statCard(
          icon: Icons.people,
          iconColor: kBlueAccent,
          label: 'Total Volunteers',
          value: '$_totalVolunteers',
          subtitle: '$_totalVolunteers active',
          subtitleColor: kTealAccent,
        ),
        _statCard(
          icon: Icons.verified,
          iconColor: kTealAccent,
          label: 'Verified Volunteers',
          value: '$_verifiedVolunteers',
          subtitle: _totalVolunteers > 0
              ? '${(_verifiedVolunteers / _totalVolunteers * 100).toStringAsFixed(1)}% of total'
              : '0% of total',
          subtitleColor: Colors.white60,
        ),
        _statCard(
          icon: Icons.accessibility_new,
          iconColor: kAmberAccent,
          label: 'Blind Users',
          value: '$_blindUsers',
          subtitle: 'Active users',
          subtitleColor: Colors.white60,
        ),
        _statCard(
          icon: Icons.flag_outlined,
          iconColor: kRedAccent,
          label: 'Reports Made',
          value: '$_reportsMade',
          subtitle: _reportsMade > 0 ? '$_reportsMade total' : 'No new reports',
          subtitleColor: _reportsMade > 0 ? kRedAccent : Colors.white38,
        ),
      ];

      if (!isWide) {
        return Column(
          children: cards
              .map((c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: c))
              .toList(),
        );
      }
      return Row(
        children: cards
            .map((c) => Expanded(
                child: Padding(padding: const EdgeInsets.only(right: 12), child: c)))
            .toList(),
      );
    });
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String subtitle,
    required Color subtitleColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 14),
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.white60)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: subtitleColor)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LIVE LOCATION
  // ---------------------------------------------------------------------------

  Widget _buildLiveLocationCard() {
    final hasLocation = _liveRequest != null;
    final lat = hasLocation ? (_liveRequest!['latitude'] as num).toDouble() : 0.0;
    final lng = hasLocation ? (_liveRequest!['longitude'] as num).toDouble() : 0.0;
    final locationLabel = hasLocation
        ? (_liveRequest!['location']?.toString() ?? 'Unknown location')
        : 'No active requests right now';

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: kPurpleAccent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Live Location',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              if (hasLocation)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kTealAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: kTealAccent),
                      SizedBox(width: 6),
                      Text('Live', style: TextStyle(color: kTealAccent, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Current Location',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
          const SizedBox(height: 2),
          Text(locationLabel,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: hasLocation
                  ? Stack(
                      children: [
                        FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(lat, lng),
                            initialZoom: 15,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName:
                                  'com.example.flutter_blindfriend',
                            ),
                            MarkerLayer(markers: [
                              Marker(
                                point: LatLng(lat, lng),
                                width: 50,
                                height: 50,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.location_on,
                                        color: kPinkBright, size: 36),
                                  ],
                                ),
                              ),
                            ]),
                          ],
                        ),
                        const Positioned(
                          left: 10,
                          bottom: 10,
                          child: _MapLabel('You are here'),
                        ),
                      ],
                    )
                  : Container(
                      color: Colors.white.withValues(alpha: 0.03),
                      child: const Center(
                        child: Text('No active requests with a location yet',
                            style: TextStyle(color: Colors.white38)),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _infoChip(Icons.gps_fixed, 'Status',
                    hasLocation ? (_liveRequest!['status'] ?? '—') : '—'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _infoChip(Icons.access_time, 'Updated',
                    hasLocation ? 'Just now' : '—'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _infoChip(Icons.category, 'Type',
                    hasLocation ? (_liveRequest!['requestType'] ?? '—') : '—'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 13, color: Colors.white38),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white38)),
          ]),
          const SizedBox(height: 2),
          Text(value.toString(),
              style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOCATION HISTORY (request volume over the last 7 days)
  // ---------------------------------------------------------------------------

  Widget _buildLocationHistoryCard() {
    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: kBlueAccent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Request Activity',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              const Text('This Week',
                  style: TextStyle(fontSize: 12, color: Colors.white60)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Help requests received per day',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(
              painter: _LineChartPainter(
                values: _requestCountsByDay.map((e) => e.toDouble()).toList(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: _dayLabels
                .map((l) => Expanded(
                      child: Text(l,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: Colors.white38)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RATING OVERVIEW
  // ---------------------------------------------------------------------------

  Widget _buildRatingOverviewCard() {
    final existingRatings = _ratingDistribution.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final maxCount =
        existingRatings.fold(0, (a, b) => a > b.value ? a : b.value);

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.star, color: kAmberAccent, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Volunteer Rating Overview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Average Rating',
                        style: TextStyle(fontSize: 12, color: Colors.white38)),
                    Text(
                      _totalRatings > 0 ? _overallAverageRating.toStringAsFixed(1) : '—',
                      style: const TextStyle(
                          fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Row(
                      children: List.generate(5, (i) {
                        final filled = i < _overallAverageRating.round();
                        return Icon(filled ? Icons.star : Icons.star_border,
                            size: 16, color: kAmberAccent);
                      }),
                    ),
                    const SizedBox(height: 4),
                    Text('Based on $_totalRatings ratings',
                        style: const TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  children: [1, 2, 3, 4, 5].reversed.map((rating) {
                    final count = _ratingDistribution[rating] ?? 0;
                    final percentage = maxCount > 0 ? count / maxCount : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 26,
                            child: Text('$rating★',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white70)),
                          ),
                          Expanded(
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: percentage,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: kTealAccent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 24,
                            child: Text('$count',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white60)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VOLUNTEER STATUS DONUT
  // ---------------------------------------------------------------------------

  Widget _buildVolunteerStatusCard() {
    final total = _pendingCount + _approvedCount + _rejectedCount;
    final segments = <_DonutSegment>[
      _DonutSegment('Approved', _approvedCount, kTealAccent),
      _DonutSegment('Pending', _pendingCount, kAmberAccent),
      _DonutSegment('Rejected', _rejectedCount, kRedAccent),
    ];

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart, color: kPurpleAccent, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Volunteer Status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(120, 120),
                      painter: _DonutChartPainter(segments: segments, total: total),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$total',
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const Text('Total',
                            style: TextStyle(fontSize: 11, color: Colors.white38)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: segments.map((s) {
                    final pct = total > 0 ? s.value / total * 100 : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration:
                                BoxDecoration(color: s.color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text('${s.value}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(s.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ),
                          Text('${pct.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TOP PERFORMERS
  // ---------------------------------------------------------------------------

  Widget _buildTopPerformersCard() {
    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, color: kAmberAccent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Top Performing Volunteers',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => widget.onNavigate('volunteers'),
                child: const Text('View All',
                    style: TextStyle(fontSize: 12, color: kBlueAccent)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_topPerformers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('No volunteers with ratings yet',
                    style: TextStyle(color: Colors.white60)),
              ),
            )
          else
            ..._topPerformers.map((v) {
              final name = (v['name'] ?? 'Unknown').toString();
              final rating = v['avgRating'] as double? ?? 0.0;
              final helps = v['totalRatings'] as int? ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: kPurpleAccent.withValues(alpha: 0.25),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const Icon(Icons.star, size: 14, color: kAmberAccent),
                    const SizedBox(width: 2),
                    Text(rating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kPurpleAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$helps help${helps == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 10, color: kPurpleAccent)),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // QUICK ACTIONS
  // ---------------------------------------------------------------------------

  Widget _buildQuickActions() {
    final actions = [
      (Icons.assignment_turned_in, 'Accept Requests', kPurpleAccent, 'verification'),
      (Icons.search, 'Find Volunteers', kTealAccent, 'volunteers'),
      (Icons.flag_outlined, 'View Reports', kRedAccent, 'reports'),
      (Icons.manage_accounts, 'Manage Users', kBlueAccent, 'users'),
      (Icons.description_outlined, 'Generate Report', kAmberAccent, null),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt, color: kPinkBright, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text('Quick Actions',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            final children = actions.map((a) {
              final (icon, label, color, pageKey) = a;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GestureDetector(
                    onTap: () {
                      if (pageKey != null) {
                        widget.onNavigate(pageKey);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Report generation coming soon.')),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          const SizedBox(height: 8),
                          Text(label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList();

            if (isWide) return Row(children: children);
            return Wrap(
              children: actions.map((a) {
                final (icon, label, color, pageKey) = a;
                return SizedBox(
                  width: 110,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: GestureDetector(
                      onTap: () {
                        if (pageKey != null) {
                          widget.onNavigate(pageKey);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Report generation coming soon.')),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  shape: BoxShape.circle),
                              child: Icon(icon, color: color, size: 20),
                            ),
                            const SizedBox(height: 8),
                            Text(label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SHARED CARD SHELL
  // ---------------------------------------------------------------------------

  Widget _cardShell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _MapLabel extends StatelessWidget {
  final String text;
  const _MapLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kNavyDeep.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.my_location, size: 12, color: kBlueAccent),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 11, color: Colors.white)),
        ],
      ),
    );
  }
}

class _DonutSegment {
  final String label;
  final int value;
  final Color color;
  _DonutSegment(this.label, this.value, this.color);
}

class _DonutChartPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  final int total;

  _DonutChartPainter({required this.segments, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final strokeWidth = 16.0;

    final backgroundPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, backgroundPaint);

    if (total == 0) return;

    double startAngle = -math.pi / 2;
    for (final segment in segments) {
      if (segment.value == 0) continue;
      final sweepAngle = (segment.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.segments != segments || oldDelegate.total != total;
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;

  _LineChartPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.reduce(math.max);
    final effectiveMax = maxValue <= 0 ? 1.0 : maxValue;
    final stepX = values.length > 1 ? size.width / (values.length - 1) : size.width;

    final points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = stepX * i;
      final y = size.height - (values[i] / effectiveMax) * (size.height - 16) - 8;
      points.add(Offset(x, y));
    }

    // Gradient fill under the line
    final fillPath = ui.Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          kPurpleAccent.withValues(alpha: 0.35),
          kPurpleAccent.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePath = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }
    final linePaint = Paint()
      ..color = kPurpleAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // Dots
    final dotPaint = Paint()..color = kPinkBright;
    for (final p in points) {
      canvas.drawCircle(p, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}
