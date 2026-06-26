import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'theme/app_palette.dart';

/// Optimized Combined Overview + Statistics dashboard for mobile & web.
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

  // Live location
  Map<String, dynamic>? _liveRequest;

  // Location history
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
    if (!mounted) return;
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

      // ── Rating distribution ──
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

      // ── Live location ──
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

      // ── Location history ──
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
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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

    return Scaffold(
      backgroundColor: kNavyDeep,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboardData,
          color: kPinkBright,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(isWide ? 24 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(isWide),
                    const SizedBox(height: 24),
                    _buildStatCardsRow(isWide),
                    const SizedBox(height: 20),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _buildLiveLocationCard(),
                                const SizedBox(height: 20),
                                _buildLocationHistoryCard(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              children: [
                                _buildRatingOverviewCard(),
                                const SizedBox(height: 20),
                                _buildVolunteerStatusCard(),
                                const SizedBox(height: 20),
                                _buildTopPerformersCard(),
                              ],
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          _buildLiveLocationCard(),
                          const SizedBox(height: 20),
                          _buildLocationHistoryCard(),
                          const SizedBox(height: 20),
                          _buildRatingOverviewCard(),
                          const SizedBox(height: 20),
                          _buildVolunteerStatusCard(),
                          const SizedBox(height: 20),
                          _buildTopPerformersCard(),
                        ],
                      ),
                    const SizedBox(height: 20),
                    _buildQuickActions(isWide),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader(bool isWide) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$greeting,', style: const TextStyle(fontSize: 14, color: Colors.white60)),
              Text(_adminName,
                  style: TextStyle(
                      fontSize: isWide ? 30 : 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              const Text('BlindFriend Admin Portal',
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
                    decoration: const BoxDecoration(color: kRedAccent, shape: BoxShape.circle),
                    child: Text(
                      '$_pendingCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STAT CARDS (Now handles mobile grids beautifully)
  // ---------------------------------------------------------------------------
  Widget _buildStatCardsRow(bool isWide) {
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
        label: 'Verified Users',
        value: '$_verifiedVolunteers',
        subtitle: _totalVolunteers > 0
            ? '${(_verifiedVolunteers / _totalVolunteers * 100).toStringAsFixed(1)}% verified'
            : '0% total',
        subtitleColor: Colors.white60,
      ),
      _statCard(
        icon: Icons.accessibility_new,
        iconColor: kAmberAccent,
        label: 'Blind Users',
        value: '$_blindUsers',
        subtitle: 'Active accounts',
        subtitleColor: Colors.white60,
      ),
      _statCard(
        icon: Icons.flag_outlined,
        iconColor: kRedAccent,
        label: 'Reports Made',
        value: '$_reportsMade',
        subtitle: _reportsMade > 0 ? 'Action needed' : 'Clean history',
        subtitleColor: _reportsMade > 0 ? kRedAccent : Colors.white38,
      ),
    ];

    if (!isWide) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
        children: cards,
      );
    }

    return Row(
      children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: c))).toList(),
    );
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          Text(subtitle, style: TextStyle(fontSize: 11, color: subtitleColor), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final locationLabel = hasLocation ? (_liveRequest!['location']?.toString() ?? 'Unknown location') : 'No active requests';

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: kPurpleAccent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Live Location', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              if (hasLocation)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: kTealAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, size: 6, color: kTealAccent),
                      SizedBox(width: 4),
                      Text('Live', style: TextStyle(color: kTealAccent, fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(locationLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: hasLocation
                  ? Stack(
                      children: [
                        FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(lat, lng),
                            initialZoom: 14,
                            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.flutter_blindfriend',
                            ),
                            MarkerLayer(markers: [
                              Marker(
                                point: LatLng(lat, lng),
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.location_on, color: kPinkBright, size: 32),
                              ),
                            ]),
                          ],
                        ),
                      ],
                    )
                  : Container(
                      color: Colors.white.withValues(alpha: 0.03),
                      child: const Center(child: Text('No active map points', style: TextStyle(color: Colors.white38))),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _infoChip(Icons.gps_fixed, 'Status', hasLocation ? (_liveRequest!['status'] ?? '—') : '—')),
              const SizedBox(width: 6),
              Expanded(child: _infoChip(Icons.category, 'Type', hasLocation ? (_liveRequest!['requestType'] ?? '—') : '—')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white38),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
                Text(value.toString(), style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOCATION HISTORY
  // ---------------------------------------------------------------------------
  Widget _buildLocationHistoryCard() {
    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.show_chart, color: kBlueAccent, size: 20),
              SizedBox(width: 8),
              Text('Request Activity', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(
              painter: _LineChartPainter(values: _requestCountsByDay.map((e) => e.toDouble()).toList()),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: _dayLabels
                .map((l) => Expanded(
                      child: Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: Colors.white38)),
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
    final maxCount = _ratingDistribution.values.fold(0, (a, b) => a > b ? a : b);

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.star, color: kAmberAccent, size: 20),
              SizedBox(width: 8),
              Text('Rating Overview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_totalRatings > 0 ? _overallAverageRating.toStringAsFixed(1) : '—',
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
                  Row(
                    children: List.generate(5, (i) => Icon(i < _overallAverageRating.round() ? Icons.star : Icons.star_border, size: 12, color: kAmberAccent)),
                  ),
                  const SizedBox(height: 4),
                  Text('$_totalRatings ratings', style: const TextStyle(fontSize: 10, color: Colors.white38)),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [1, 2, 3, 4, 5].reversed.map((rating) {
                    final count = _ratingDistribution[rating] ?? 0;
                    final percentage = maxCount > 0 ? count / maxCount : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Text('$rating★', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(3)),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: percentage,
                                child: Container(decoration: BoxDecoration(color: kTealAccent, borderRadius: BorderRadius.circular(3))),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(width: 16, child: Text('$count', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: Colors.white60))),
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
              Text('Volunteer Onboarding Status', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(90, 90),
                      painter: _DonutChartPainter(segments: segments, total: total),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$total', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const Text('Total', style: TextStyle(fontSize: 10, color: Colors.white38)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: segments.map((s) {
                    final pct = total > 0 ? s.value / total * 100 : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text('${s.value}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(width: 4),
                          Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                          Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.emoji_events, color: kAmberAccent, size: 20),
                  SizedBox(width: 8),
                  Text('Top Volunteers', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              GestureDetector(
                onTap: () => widget.onNavigate('volunteers'),
                child: const Text('View All', style: TextStyle(fontSize: 12, color: kBlueAccent)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_topPerformers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: Text('No active ratings yet', style: TextStyle(color: Colors.white38))),
            )
          else
            ..._topPerformers.map((v) {
              final name = (v['name'] ?? 'Unknown').toString();
              final rating = v['avgRating'] as double? ?? 0.0;
              final helps = v['totalRatings'] as int? ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: kPurpleAccent.withValues(alpha: 0.25),
                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.star, size: 12, color: kAmberAccent),
                    const SizedBox(width: 2),
                    Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: kPurpleAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text('$helps done', style: const TextStyle(fontSize: 9, color: kPurpleAccent)),
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
  // QUICK ACTIONS (Clean mobile grid arrangement)
  // ---------------------------------------------------------------------------
  Widget _buildQuickActions(bool isWide) {
    final actions = [
      (Icons.assignment_turned_in, 'Verify', kPurpleAccent, 'verification'),
      (Icons.search, 'Find', kTealAccent, 'volunteers'),
      (Icons.flag_outlined, 'Reports', kRedAccent, 'reports'),
      (Icons.manage_accounts, 'Users', kBlueAccent, 'users'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
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
              Text('Quick Actions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: isWide ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: isWide ? 1.5 : 2.1,
            children: actions.map((a) {
              final (icon, label, color, pageKey) = a;
              return GestureDetector(
                onTap: () => widget.onNavigate(pageKey),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: Icon(icon, color: color, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _cardShell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
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
