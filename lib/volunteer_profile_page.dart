import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firebase_service.dart';
import 'volunteer_rating_summary.dart';

// Add this new class for feedback items
class FeedbackItem {
  final String id;
  final String blindUserName;
  final int rating;
  final String comment;
  final DateTime createdAt;
  final String requestType;

  FeedbackItem({
    required this.id,
    required this.blindUserName,
    required this.rating,
    required this.comment,
    required this.createdAt,
    required this.requestType,
  });

  factory FeedbackItem.fromMap(String id, Map<String, dynamic> map) {
    return FeedbackItem(
      id: id,
      blindUserName: map['blindUserName'] ?? 'Anonymous',
      rating: map['rating'] ?? 0,
      comment: map['comment'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      requestType: map['requestType'] ?? 'help',
    );
  }
}

// Update the main VolunteerProfilePage class
class VolunteerProfilePage extends StatefulWidget {
  const VolunteerProfilePage({super.key});

  @override
  State<VolunteerProfilePage> createState() => _VolunteerProfilePageState();
}

class _VolunteerProfilePageState extends State<VolunteerProfilePage>
    with SingleTickerProviderStateMixin {
  final FirebaseService _firebaseService = FirebaseService();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  final List<String> _languages = [
    'English',
    'Spanish',
    'Mandarin',
    'French',
    'German',
    'Korean',
  ];
  final List<String> _allSpecialties = [
    'Shopping',
    'Navigation',
    'Reading',
    'Tech Support',
    'Emergency Assistance',
    'Medical Support',
    'Transportation',
  ];
  final List<String> _availabilityOptions = [
    'Weekdays',
    'Weekends',
    'Anytime',
    'Emergency Only',
  ];

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  bool _isLoadingFeedback = true;

  String _name = '';
  String _email = '';
  String _phone = '';
  List<String> _languageList = [];
  List<String> _specialties = [];
  String _availability = '';

  List<String> _editLanguages = [];
  List<String> _editSpecialties = [];
  String? _editAvailability;

  // Rating data
  double _averageRating = 0.0;
  int _totalRatings = 0;
  List<FeedbackItem> _feedbacks = [];
  int _selectedTabIndex =
      0; // 0 = rating summary, 1 = all feedback, 2 = by rating

  late TabController _tabController;

  static const _emerald = Color(0xFF059669);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadProfile();
    _loadRatingsAndFeedback();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final volDoc = await FirebaseFirestore.instance
          .collection('volunteers')
          .doc(user.uid)
          .get();

      final userData = userDoc.data() ?? {};
      final volData = volDoc.data() ?? {};

      setState(() {
        _name = userData['name'] ?? '';
        _email = userData['email'] ?? user.email ?? '';
        _phone = volData['phoneNumber'] ?? '';
        final rawLang = volData['language'];
        if (rawLang is List) {
          _languageList = List<String>.from(rawLang);
        } else if (rawLang is String && rawLang.isNotEmpty) {
          _languageList = [rawLang];
        } else {
          _languageList = [];
        }
        _specialties = List<String>.from(volData['specialties'] ?? []);
        _availability = volData['availability'] ?? '';
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRatingsAndFeedback() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingFeedback = true;
    });

    try {
      // Get volunteer data
      final volDoc = await FirebaseFirestore.instance
          .collection('volunteers')
          .doc(user.uid)
          .get();

      if (volDoc.exists) {
        final data = volDoc.data()!;
        setState(() {
          _averageRating = (data['averageRating'] ?? 0.0).toDouble();
          _totalRatings = data['totalRatings'] ?? 0;
        });
      }

      // Get all feedback (ratings) from help_requests
      final feedbackSnapshot = await FirebaseFirestore.instance
          .collection('help_requests')
          .where('volunteerId', isEqualTo: user.uid)
          .where('rating', isGreaterThanOrEqualTo: 1)
          .orderBy('ratedAt', descending: true)
          .get();

      final feedbacks = <FeedbackItem>[];
      for (var doc in feedbackSnapshot.docs) {
        final data = doc.data();
        feedbacks.add(FeedbackItem(
          id: doc.id,
          blindUserName: data['blindUserName'] ?? 'Anonymous',
          rating: data['rating'] ?? 0,
          comment: data['feedbackComment'] ?? '',
          createdAt:
              (data['ratedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          requestType: data['requestType'] ?? 'help',
        ));
      }

      setState(() {
        _feedbacks = feedbacks;
        _isLoadingFeedback = false;
      });
    } catch (e) {
      debugPrint('Error loading feedback: $e');
      setState(() {
        _isLoadingFeedback = false;
      });
    }
  }

  List<FeedbackItem> get _filteredFeedbacksByRating {
    if (_selectedTabIndex == 2) {
      // Show by rating breakdown
      return _feedbacks;
    }
    return _feedbacks;
  }

  Map<int, int> get _ratingDistribution {
    final distribution = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final feedback in _feedbacks) {
      distribution[feedback.rating] = (distribution[feedback.rating] ?? 0) + 1;
    }
    return distribution;
  }

  void _startEditing() {
    _nameController.text = _name;
    _phoneController.text = _phone;
    _editLanguages = List<String>.from(_languageList);
    _editSpecialties = List<String>.from(_specialties);
    _editAvailability = _availability.isEmpty ? null : _availability;
    setState(() => _isEditing = true);
  }

  void _cancelEditing() {
    setState(() => _isEditing = false);
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      _showError('Please enter your name.');
      return;
    }
    if (phone.isEmpty) {
      _showError('Please enter your phone number.');
      return;
    }
    if (_editLanguages.isEmpty) {
      _showError('Please select at least one language.');
      return;
    }
    if (_editSpecialties.isEmpty) {
      _showError('Please select at least one specialty.');
      return;
    }
    if (_editAvailability == null) {
      _showError('Please select your availability.');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isSaving = true);
    final success = await _firebaseService.updateVolunteerProfile(
      uid: uid,
      name: name,
      phoneNumber: phone,
      languages: _editLanguages,
      specialties: _editSpecialties,
      availability: _editAvailability!,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      setState(() {
        _name = name;
        _phone = phone;
        _languageList = List<String>.from(_editLanguages);
        _specialties = List<String>.from(_editSpecialties);
        _availability = _editAvailability!;
        _isEditing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      _showError('Failed to save. Please try again.');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDF4),
      body: _isLoading
          ? Column(
              children: [
                _buildGradientBar(context, showAvatar: false),
                const Expanded(
                    child: Center(child: CircularProgressIndicator())),
              ],
            )
          : _isEditing
              ? Column(
                  children: [
                    _buildGradientBar(context, showAvatar: false),
                    Expanded(child: _buildEditForm()),
                  ],
                )
              : _buildViewScroll(context),
    );
  }

  // Gradient bar with rating badge
  Widget _buildGradientBar(BuildContext context, {required bool showAvatar}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white),
                onPressed:
                    _isEditing ? _cancelEditing : () => Navigator.pop(context),
              ),
              Expanded(
                child: Row(
                  children: [
                    // Compact rating badge
                    if (!_isEditing && uid != null && _totalRatings > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              _averageRating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '($_totalRatings)',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      _isEditing ? 'Edit Profile' : 'My Profile',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isEditing)
                TextButton.icon(
                  onPressed: _startEditing,
                  icon: const Icon(Icons.edit_rounded,
                      size: 16, color: Colors.white),
                  label: const Text('Edit',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                ),
              if (_isEditing)
                _isSaving
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        ),
                      )
                    : TextButton(
                        onPressed: _saveProfile,
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
            ],
          ),
        ),
      ),
    );
  }

  // View mode with tabs for ratings and feedback
  Widget _buildViewScroll(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final volunteerId = user?.uid ?? '';
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildViewHeader(context),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              children: [
                // Rating and Feedback Section Header
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rate_rounded,
                          color: Colors.amber, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Ratings & Feedback',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_totalRatings > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _emerald.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$_totalRatings reviews',
                            style: TextStyle(
                              fontSize: 12,
                              color: _emerald,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Tab Bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
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
                      TabBar(
                        controller: _tabController,
                        onTap: (index) {
                          setState(() {
                            _selectedTabIndex = index;
                          });
                        },
                        indicatorColor: _emerald,
                        labelColor: _emerald,
                        unselectedLabelColor: Colors.grey.shade600,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        tabs: const [
                          Tab(text: 'Summary'),
                          Tab(text: 'All Feedback'),
                          Tab(text: 'By Rating'),
                        ],
                      ),
                      SizedBox(
                        height: _selectedTabIndex == 2 ? 400 : 350,
                        child: IndexedStack(
                          index: _selectedTabIndex,
                          children: [
                            // Summary Tab
                            _buildRatingSummaryTab(volunteerId),

                            // All Feedback Tab
                            _buildAllFeedbackTab(),

                            // By Rating Tab
                            _buildRatingBreakdownTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Profile Information Cards
                _buildInfoCard(
                  title: 'ACCOUNT',
                  accentColor: _emerald,
                  icon: Icons.person_rounded,
                  children: [
                    _InfoRow(
                        icon: Icons.badge_outlined,
                        label: 'Name',
                        value: _name.isEmpty ? '—' : _name),
                    const Divider(height: 20),
                    _InfoRow(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: _email.isEmpty ? '—' : _email),
                  ],
                ),
                _buildInfoCard(
                  title: 'CONTACT',
                  accentColor: Colors.blue.shade600,
                  icon: Icons.phone_rounded,
                  children: [
                    _InfoRow(
                        icon: Icons.phone_outlined,
                        label: 'Phone',
                        value: _phone.isEmpty ? '—' : _phone),
                  ],
                ),
                _buildInfoCard(
                  title: 'LANGUAGE',
                  accentColor: const Color(0xFF7C3AED),
                  icon: Icons.language_rounded,
                  children: [
                    _InfoRow(
                        icon: Icons.translate_rounded,
                        label: 'Language',
                        value: _languageList.isEmpty
                            ? '—'
                            : _languageList.join(', ')),
                  ],
                ),
                _buildInfoCard(
                  title: 'SPECIALTIES',
                  accentColor: Colors.orange.shade700,
                  icon: Icons.star_rounded,
                  children: [
                    if (_specialties.isEmpty)
                      const Text('—',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _specialties
                            .map((s) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
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
                                ))
                            .toList(),
                      ),
                  ],
                ),
                _buildInfoCard(
                  title: 'AVAILABILITY',
                  accentColor: Colors.teal.shade600,
                  icon: Icons.schedule_rounded,
                  children: [
                    _InfoRow(
                        icon: Icons.access_time_rounded,
                        label: 'Schedule',
                        value: _availability.isEmpty ? '—' : _availability),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Rating Summary Tab
  Widget _buildRatingSummaryTab(String volunteerId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Large rating display
          if (_totalRatings > 0) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _averageRating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: List.generate(5, (index) {
                              if (index < _averageRating.floor()) {
                                return const Icon(Icons.star,
                                    color: Colors.amber, size: 24);
                              } else if (index < _averageRating &&
                                  _averageRating - index >= 0.5) {
                                return const Icon(Icons.star_half,
                                    color: Colors.amber, size: 24);
                              } else {
                                return const Icon(Icons.star_border,
                                    color: Colors.amber, size: 24);
                              }
                            }),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Based on $_totalRatings ratings',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.star_outline,
                      size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    'No ratings yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ratings will appear after you complete help requests',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // All Feedback Tab
  Widget _buildAllFeedbackTab() {
    if (_isLoadingFeedback) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_feedbacks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.comment_outlined,
                  size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'No feedback yet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Feedback from blind users will appear here',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _feedbacks.length,
      itemBuilder: (context, index) {
        final feedback = _feedbacks[index];
        return _buildFeedbackCard(feedback);
      },
    );
  }

  // Rating Breakdown Tab
  Widget _buildRatingBreakdownTab() {
    if (_isLoadingFeedback) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final distribution = _ratingDistribution;
    final total = _feedbacks.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (int rating = 5; rating >= 1; rating--)
            _buildRatingBar(rating, distribution[rating] ?? 0, total),
          const SizedBox(height: 16),
          if (_feedbacks.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap on any rating in the "All Feedback" tab to see detailed comments',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRatingBar(int rating, int count, int total) {
    final percentage = total > 0 ? (count / total) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Row(
              children: [
                Text('$rating',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Icon(Icons.star, size: 14, color: Colors.amber),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  rating >= 4
                      ? Colors.green.shade600
                      : rating == 3
                          ? Colors.orange.shade600
                          : Colors.red.shade600,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 45,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackCard(FeedbackItem feedback) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    feedback.blindUserName.isNotEmpty
                        ? feedback.blindUserName[0].toUpperCase()
                        : 'U',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.amber.shade800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feedback.blindUserName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: List.generate(5, (index) {
                        return Icon(
                          index < feedback.rating
                              ? Icons.star
                              : Icons.star_border,
                          size: 16,
                          color: Colors.amber,
                        );
                      }),
                    ),
                  ],
                ),
              ),
              Text(
                _formatDate(feedback.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          if (feedback.comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                feedback.comment,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Request: ${feedback.requestType}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: CircleAvatar(
                radius: 44,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(
                  _name.isNotEmpty ? _name[0].toUpperCase() : 'V',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _name.isNotEmpty ? _name : 'Volunteer',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.verified_rounded, color: Colors.white, size: 13),
                  SizedBox(width: 5),
                  Text('Volunteer',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required Color accentColor,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
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
                Icon(icon, color: accentColor, size: 15),
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
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  // Edit form remains the same as before
  Widget _buildEditForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormSection(
            label: 'Name',
            icon: Icons.badge_outlined,
            child: _textField(_nameController, 'Your full name'),
          ),
          const SizedBox(height: 16),
          _buildFormSection(
            label: 'Email',
            icon: Icons.email_outlined,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline,
                      size: 16, color: Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Text(_email,
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                ],
              ),
            ),
            note: 'Email cannot be changed.',
          ),
          const SizedBox(height: 16),
          _buildFormSection(
            label: 'Phone Number',
            icon: Icons.phone_outlined,
            child: _textField(_phoneController, 'Your phone number',
                type: TextInputType.phone),
          ),
          const SizedBox(height: 20),
          _buildFormSection(
            label: 'Language You Speak',
            icon: Icons.language_rounded,
            child: _buildLanguageGrid(),
          ),
          const SizedBox(height: 20),
          _buildFormSection(
            label: 'Specialties',
            icon: Icons.star_outline_rounded,
            note: 'Select areas where you can assist',
            child: _buildSpecialtiesGrid(),
          ),
          const SizedBox(height: 20),
          _buildFormSection(
            label: 'Availability',
            icon: Icons.schedule_rounded,
            child: _buildAvailabilityDropdown(),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF047857), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _emerald.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text(
                      'Save Changes',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: _cancelEditing,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormSection({
    required String label,
    required IconData icon,
    required Widget child,
    String? note,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ],
    );
  }

  Widget _textField(TextEditingController controller, String hint,
      {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _emerald, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      ),
    );
  }

  Widget _buildLanguageGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.6,
      ),
      itemCount: _languages.length,
      itemBuilder: (context, index) {
        final lang = _languages[index];
        final isSelected = _editLanguages.contains(lang);
        return GestureDetector(
          onTap: () => setState(() {
            if (isSelected) {
              _editLanguages.remove(lang);
            } else {
              _editLanguages.add(lang);
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF9F67FA)],
                    )
                  : null,
              color: isSelected ? null : Colors.white,
              border: Border.all(
                color:
                    isSelected ? const Color(0xFF7C3AED) : Colors.grey.shade300,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                lang,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpecialtiesGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.8,
      ),
      itemCount: _allSpecialties.length,
      itemBuilder: (context, index) {
        final specialty = _allSpecialties[index];
        final isSelected = _editSpecialties.contains(specialty);
        return GestureDetector(
          onTap: () => setState(() {
            if (isSelected) {
              _editSpecialties.remove(specialty);
            } else {
              _editSpecialties.add(specialty);
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        Colors.orange.shade500,
                        Colors.orange.shade700,
                      ],
                    )
                  : null,
              color: isSelected ? null : Colors.white,
              border: Border.all(
                color:
                    isSelected ? Colors.orange.shade400 : Colors.grey.shade300,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected) ...[
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      specialty,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvailabilityDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _editAvailability,
          hint: Text('Select availability',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          style: const TextStyle(color: Colors.black87, fontSize: 14),
          onChanged: (value) => setState(() => _editAvailability = value),
          items: _availabilityOptions
              .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
              .toList(),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// Info Row widget
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF059669), size: 18),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 1),
            Text(value,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}
