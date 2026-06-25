import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminStatisticsPage extends StatefulWidget {
  const AdminStatisticsPage({super.key});

  @override
  State<AdminStatisticsPage> createState() => _AdminStatisticsPageState();
}

class _AdminStatisticsPageState extends State<AdminStatisticsPage> {
  final firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  String? _errorMessage;

  // Statistics data
  int _totalVolunteers = 0;
  int _totalCompletedRequests = 0;
  double _overallAverageRating = 0.0;
  int _totalRatings = 0;

  // Rating distribution
  Map<int, int> _ratingDistribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

  // Top performers
  List<Map<String, dynamic>> _topPerformers = [];

  // Status breakdown
  int _pendingCount = 0;
  int _approvedCount = 0;
  int _rejectedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get all volunteers
      final volunteerSnapshot = await firestore.collection('volunteers').get();
      final volunteers = volunteerSnapshot.docs;
      _totalVolunteers = volunteers.length;

      // Initialize rating distribution
      final ratingDist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
      double totalRatingSum = 0.0;
      int totalRatings = 0;

      // Count statuses
      int pending = 0, approved = 0, rejected = 0;

      // Collect volunteers with ratings for top performers
      final performers = <Map<String, dynamic>>[];

      for (var doc in volunteers) {
        final data = doc.data();
        final status = (data['status'] ?? 'pending').toString().toLowerCase();

        // Count statuses
        if (status == 'pending') {
          pending++;
        } else if (status == 'approved')
          approved++;
        else if (status == 'rejected') rejected++;

        // ✅ Get name from data or use Unknown
        String volunteerName = data['name'] ?? 'Unknown';

        // Try to get name from users collection if not available
        if (volunteerName == 'Unknown' || volunteerName.isEmpty) {
          try {
            final uid = data['uid'] ?? doc.id;
            final userDoc = await firestore.collection('users').doc(uid).get();
            if (userDoc.exists) {
              final userData = userDoc.data();
              volunteerName = userData?['name'] ?? 'Unknown';
            }
          } catch (_) {}
        }

        // Get rating data
        dynamic avgRatingValue = data['averageRating'] ?? 0.0;
        double avgRating = 0.0;
        if (avgRatingValue is int) {
          avgRating = avgRatingValue.toDouble();
        } else if (avgRatingValue is double) {
          avgRating = avgRatingValue;
        }

        dynamic totalRatingValue = data['totalRatings'] ?? 0;
        int totalRating = 0;
        if (totalRatingValue is int) {
          totalRating = totalRatingValue;
        } else if (totalRatingValue is double) {
          totalRating = totalRatingValue.toInt();
        }

        if (totalRating > 0) {
          totalRatings = totalRatings + totalRating;
          totalRatingSum = totalRatingSum + (avgRating * totalRating);

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

      // Get completed requests count
      final completedSnapshot = await firestore
          .collection('help_requests')
          .where('status', isEqualTo: 'completed')
          .get();
      _totalCompletedRequests = completedSnapshot.docs.length;

      // Calculate average rating
      _overallAverageRating =
          totalRatings > 0 ? totalRatingSum / totalRatings : 0.0;
      _totalRatings = totalRatings;

      // Get exact rating distribution from help_requests
      final ratingSnapshot = await firestore
          .collection('help_requests')
          .where('rating', isGreaterThan: 0)
          .get();

      for (var doc in ratingSnapshot.docs) {
        final data = doc.data();

        dynamic ratingValue = data['rating'] ?? 0;
        int rating = 0;

        if (ratingValue is int) {
          rating = ratingValue;
        } else if (ratingValue is double) {
          rating = ratingValue.toInt();
        }

        if (rating >= 1 && rating <= 5) {
          ratingDist[rating] = (ratingDist[rating] ?? 0) + 1;
        }
      }
      _ratingDistribution = ratingDist;

      // Sort performers by average rating (highest first)
      performers.sort((a, b) {
        final ratingA = a['avgRating'] as double;
        final ratingB = b['avgRating'] as double;
        if (ratingA != ratingB) return ratingB.compareTo(ratingA);
        return (b['totalRatings'] as int).compareTo(a['totalRatings'] as int);
      });

      // Get top 10 performers
      if (performers.length > 10) {
        _topPerformers = performers.sublist(0, 10);
      } else {
        _topPerformers = performers;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading statistics: $e');
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorWidget()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildStatsCards(),
                            const SizedBox(height: 16),
                            _buildRatingDistribution(),
                            const SizedBox(height: 16),
                            _buildStatusBreakdown(),
                            const SizedBox(height: 16),
                            _buildTopPerformers(),
                            const SizedBox(height: 24),
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
          colors: [Colors.purple.shade700, Colors.purple.shade500],
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
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.analytics, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Volunteer Statistics',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
                Text(
                  'Overview of volunteer performance and ratings',
                  style: TextStyle(
                      fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            onPressed: _loadStatistics,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
          const SizedBox(height: 16),
          Text('Error loading statistics: $_errorMessage'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadStatistics,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            icon: Icons.people,
            iconColor: Colors.blue,
            label: 'Total Volunteers',
            value: _totalVolunteers.toString(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            icon: Icons.star,
            iconColor: Colors.amber,
            label: 'Avg Rating',
            value: _totalRatings > 0
                ? _overallAverageRating.toStringAsFixed(1)
                : 'N/A',
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingDistribution() {
    final existingRatings = _ratingDistribution.entries
        .where((entry) => entry.value > 0)
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    final total = _ratingDistribution.values.fold(0, (a, b) => a + b);

    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text('No ratings yet'),
        ),
      );
    }

    final maxCount =
        existingRatings.fold(0, (a, b) => a > b.value ? a : b.value);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart, size: 18, color: Colors.purple),
              SizedBox(width: 8),
              Text(
                'Rating Distribution',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...existingRatings.map((entry) {
            final rating = entry.key;
            final count = entry.value;
            final percentage = maxCount > 0 ? count / maxCount : 0.0;

            Color barColor;
            if (rating == 5) {
              barColor = Colors.green.shade600;
            } else if (rating == 4) {
              barColor = Colors.blue.shade600;
            } else if (rating == 3) {
              barColor = Colors.orange.shade600;
            } else if (rating == 2) {
              barColor = Colors.deepOrange.shade600;
            } else {
              barColor = Colors.red.shade600;
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Row(
                      children: [
                        Text('$rating',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        const Icon(Icons.star, size: 12, color: Colors.amber),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Align(
                        alignment: Alignment
                            .centerLeft, // ✅ FIX: Bar starts from the left
                        child: FractionallySizedBox(
                          widthFactor: percentage,
                          child: Container(
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 45,
                    child: Text(
                      count.toString(),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Text(
            'Total ratings: $total',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBreakdown() {
    final total = _totalVolunteers;
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart, size: 18, color: Colors.purple),
              SizedBox(width: 8),
              Text(
                'Volunteer Status Breakdown',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statusBadge('Pending', _pendingCount, Colors.orange, total),
              const SizedBox(width: 8),
              _statusBadge('Approved', _approvedCount, Colors.green, total),
              const SizedBox(width: 8),
              _statusBadge('Rejected', _rejectedCount, Colors.red, total),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      if (_pendingCount > 0)
                        Flexible(
                          flex: _pendingCount,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(4),
                                bottomLeft: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      if (_approvedCount > 0)
                        Flexible(
                          flex: _approvedCount,
                          child: Container(
                            color: Colors.green,
                          ),
                        ),
                      if (_rejectedCount > 0)
                        Flexible(
                          flex: _rejectedCount,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(4),
                                bottomRight: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String label, int count, Color color, int total) {
    final percentage = total > 0 ? (count / total * 100) : 0.0;
    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
          Text(
            '${percentage.toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildTopPerformers() {
    if (_topPerformers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text('No volunteers with ratings yet'),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events, size: 18, color: Colors.amber),
              SizedBox(width: 8),
              Text(
                'Top Performing Volunteers',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_topPerformers.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No volunteers with ratings yet'),
              ),
            )
          else
            ..._topPerformers.asMap().entries.map((entry) {
              final index = entry.key;
              final volunteer = entry.value;
              final isFirst = index == 0;
              final isSecond = index == 1;
              final isThird = index == 2;

              String medal;
              if (isFirst) {
                medal = '🥇';
              } else if (isSecond) {
                medal = '🥈';
              } else if (isThird) {
                medal = '🥉';
              } else {
                medal = '${index + 1}.';
              }

              final name = volunteer['name'] ?? 'Unknown';
              final avgRating = volunteer['avgRating'] as double? ?? 0.0;
              final totalRatings = volunteer['totalRatings'] as int? ?? 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isFirst ? Colors.amber.shade50 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        isFirst ? Colors.amber.shade300 : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(
                        medal,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          avgRating.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$totalRatings ratings',
                            style: TextStyle(
                                fontSize: 9, color: Colors.purple.shade700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
