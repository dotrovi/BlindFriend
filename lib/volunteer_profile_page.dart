import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firebase_service.dart';

// ── Dark theme colours ──────────────────────────────────────────
const Color _kNavyDeep = Color(0xFF120A2E);
const Color _kNavyMid = Color(0xFF1E1147);
const Color _kPurple = Color(0xFF3B1E78);
const Color _kPinkBright = Color(0xFFFF5FD2);
const Color _kBlueAccent = Color(0xFF4A90E2);
const Color _kCardFill = Color(0xFF241A45);

const LinearGradient _kAccentGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_kPinkBright, Color(0xFF9B59B6), _kBlueAccent],
);

// ── Feedback model ───────────────────────────────────────────────
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

// ── Main Profile Page ────────────────────────────────────────────
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
    'English', 'Spanish', 'Mandarin', 'French', 'German', 'Korean',
  ];
  final List<String> _allSpecialties = [
    'Shopping', 'Navigation', 'Reading', 'Tech Support',
    'Emergency Assistance', 'Medical Support', 'Transportation',
  ];
  final List<String> _availabilityOptions = [
    'Weekdays', 'Weekends', 'Anytime', 'Emergency Only',
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

  double _averageRating = 0.0;
  int _totalRatings = 0;
  List<FeedbackItem> _feedbacks = [];
  int _selectedTabIndex = 0;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // FIX: Changed length from 3 to 2
    _tabController = TabController(length: 2, vsync: this);
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

    setState(() => _isLoadingFeedback = true);

    try {
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

      final feedbackSnapshot = await FirebaseFirestore.instance
          .collection('help_requests')
          .where('volunteerId', isEqualTo: user.uid)
          .get();

      final feedbacks = <FeedbackItem>[];
      for (var doc in feedbackSnapshot.docs) {
        final data = doc.data();
        final rating = data['rating'] ?? 0;
        final comment = data['feedbackComment'] ?? data['comment'] ?? '';
        final blindUserName = data['blindUserName'] ?? data['blindName'] ?? 'Anonymous';
        final requestType = data['requestType'] ?? data['type'] ?? 'help';
        final ratedAt = data['ratedAt'] ?? data['createdAt'] ?? data['timestamp'];
        
        if (rating > 0) {
          DateTime? date;
          if (ratedAt is Timestamp) {
            date = ratedAt.toDate();
          } else if (ratedAt != null) {
            date = DateTime.now();
          }
          
          feedbacks.add(FeedbackItem(
            id: doc.id,
            blindUserName: blindUserName.toString(),
            rating: rating is int ? rating : (rating as num).toInt(),
            comment: comment.toString(),
            createdAt: date ?? DateTime.now(),
            requestType: requestType.toString(),
          ));
        }
      }
      
      feedbacks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _feedbacks = feedbacks;
        _isLoadingFeedback = false;
      });
      
      debugPrint('✅ Loaded ${feedbacks.length} feedbacks from ${feedbackSnapshot.docs.length} requests');
      
    } catch (e) {
      debugPrint('❌ Error loading feedback: $e');
      setState(() {
        _isLoadingFeedback = false;
        _feedbacks = [];
      });
    }
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
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kNavyDeep,
      appBar: AppBar(
        backgroundColor: _kNavyMid,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing ? 'Edit Profile' : 'My Profile',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (_isEditing)
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _saveProfile,
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        color: _kPinkBright,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  )
          else
            TextButton.icon(
              onPressed: _startEditing,
              icon: const Icon(Icons.edit_rounded, size: 16, color: _kPinkBright),
              label: const Text(
                'Edit',
                style: TextStyle(color: _kPinkBright, fontSize: 14),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _kPinkBright),
            )
          : _isEditing
              ? _buildEditForm()
              : _buildViewContent(),
    );
  }

  // ── Edit Form ─────────────────────────────────────────────────────
  Widget _buildEditForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
                color: Colors.white.withOpacity(0.05),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Colors.white.withOpacity(0.4)),
                  const SizedBox(width: 8),
                  Text(
                    _email,
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
                  ),
                ],
              ),
            ),
            note: 'Email cannot be changed.',
          ),
          const SizedBox(height: 16),
          _buildFormSection(
            label: 'Phone Number',
            icon: Icons.phone_outlined,
            child: _textField(_phoneController, 'Your phone number', type: TextInputType.phone),
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
          GestureDetector(
            onTap: _isSaving ? null : _saveProfile,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: _kAccentGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _kPinkBright.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
                side: BorderSide(color: Colors.white.withOpacity(0.3)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 15, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── View Content ──────────────────────────────────────────────────
  Widget _buildViewContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        children: [
          // Profile Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_kPurple, _kNavyMid, _kNavyDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    gradient: _kAccentGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _kPinkBright.withOpacity(0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: Colors.transparent,
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
                const SizedBox(height: 12),
                Text(
                  _name.isNotEmpty ? _name : 'Volunteer',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded, color: Colors.white, size: 13),
                      SizedBox(width: 5),
                      Text(
                        'Volunteer',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                // Ratings & Feedback Section
                Row(
                  children: [
                    const Icon(Icons.star_rate_rounded, color: Color(0xFFFFD700), size: 22),
                    const SizedBox(width: 8),
                    const Text(
                      'Ratings & Feedback',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (_totalRatings > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kPinkBright.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$_totalRatings reviews',
                          style: TextStyle(
                            fontSize: 12,
                            color: _kPinkBright,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Tab Bar Container
                Container(
                  decoration: BoxDecoration(
                    color: _kCardFill.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Column(
                    children: [
                      TabBar(
                        controller: _tabController,
                        onTap: (index) => setState(() => _selectedTabIndex = index),
                        indicatorColor: _kPinkBright,
                        labelColor: _kPinkBright,
                        unselectedLabelColor: Colors.white.withOpacity(0.5),
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        // FIX: Removed 'All Feedback' tab literal item
                        tabs: const [
                          Tab(text: 'Summary'),
                          Tab(text: 'Feeback'),
                        ],
                      ),
                      // FIX: Replaced IndexedStack with direct dynamic layout conditional expression
                      _selectedTabIndex == 0
                          ? _buildRatingSummaryTab()
                          : _buildRatingBreakdownTab(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Rating Summary Tab ────────────────────────────────────────────
  Widget _buildRatingSummaryTab() {
    // FIX: Removed inner SingleChildScrollView to fix layout constraints
    return Padding(
      padding: const EdgeInsets.all(16),
      child: _totalRatings > 0
          ? Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _averageRating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(5, (i) => Icon(
                          i < _averageRating.floor()
                              ? Icons.star
                              : (i < _averageRating && _averageRating - i >= 0.5)
                                  ? Icons.star_half
                                  : Icons.star_border,
                          color: const Color(0xFFFFD700),
                          size: 24,
                        )),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Based on $_totalRatings ratings',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Icon(Icons.star_outline, size: 48, color: Colors.white.withOpacity(0.3)),
                const SizedBox(height: 12),
                Text(
                  'No ratings yet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ratings will appear after you complete help requests',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }

  // ── Rating Breakdown Tab ──────────────────────────────────────────
  Widget _buildRatingBreakdownTab() {
    if (_isLoadingFeedback) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: _kPinkBright),
        ),
      );
    }
    
    final dist = _ratingDistribution;
    final total = _feedbacks.length;
    
    // FIX: Removed inner SingleChildScrollView to fix nested layout constraints
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int r = 5; r >= 1; r--)
            _buildRatingBar(r, dist[r] ?? 0, total),
          
          const SizedBox(height: 20),
          
          if (_feedbacks.isNotEmpty) ...[
            const Text(
              'Reviews by Rating',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            for (int r = 5; r >= 1; r--) ...[
              if ((dist[r] ?? 0) > 0) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(
                        '$r',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      const Icon(Icons.star, size: 14, color: Color(0xFFFFD700)),
                      const SizedBox(width: 8),
                      Text(
                        '(${dist[r]})',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ..._feedbacks
                    .where((fb) => fb.rating == r)
                    .map((fb) => _buildFeedbackCard(fb)),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRatingBar(int rating, int count, int total) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Row(
              children: [
                Text(
                  '$rating',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Icon(Icons.star, size: 14, color: Color(0xFFFFD700)),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  rating >= 4
                      ? const Color(0xFF66BB6A)
                      : rating == 3
                          ? const Color(0xFFFFA726)
                          : const Color(0xFFEF5350),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 45,
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ── Feedback Card ─────────────────────────────────────────────────
  Widget _buildFeedbackCard(FeedbackItem fb) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCardFill.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                  gradient: _kAccentGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    fb.blindUserName.isNotEmpty ? fb.blindUserName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
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
                      fb.blindUserName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: List.generate(5, (i) => Icon(
                        i < fb.rating ? Icons.star : Icons.star_border,
                        size: 16,
                        color: const Color(0xFFFFD700),
                      )),
                    ),
                  ],
                ),
              ),
              Text(
                '${fb.createdAt.day}/${fb.createdAt.month}/${fb.createdAt.year}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
          if (fb.comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                fb.comment,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.7),
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Request: ${fb.requestType}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helper Widgets ────────────────────────────────────────────────
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
        color: _kCardFill.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: accentColor, width: 4),
          top: BorderSide(color: Colors.white.withOpacity(0.08)),
          right: BorderSide(color: Colors.white.withOpacity(0.08)),
          bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
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

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _kPinkBright, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
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
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(
            note,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _textField(
    TextEditingController controller,
    String hint, {
    TextInputType type = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kPinkBright, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              gradient: isSelected ? _kAccentGradient : null,
              color: isSelected ? null : Colors.white.withOpacity(0.05),
              border: Border.all(
                color: isSelected
                    ? _kPinkBright.withOpacity(0.6)
                    : Colors.white.withOpacity(0.15),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: _kPinkBright.withOpacity(0.3),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                lang,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? Colors.white : Colors.white70,
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
              gradient: isSelected ? _kAccentGradient : null,
              color: isSelected ? null : Colors.white.withOpacity(0.05),
              border: Border.all(
                color: isSelected
                    ? _kPinkBright.withOpacity(0.6)
                    : Colors.white.withOpacity(0.15),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: _kPinkBright.withOpacity(0.3),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected) ...[
                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      specialty,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _editAvailability,
          hint: Text(
            'Select availability',
            style: TextStyle(color: Colors.white.withOpacity(0.4)),
          ),
          isExpanded: true,
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            color: Colors.white.withOpacity(0.6),
          ),
          dropdownColor: _kCardFill,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: (value) => setState(() => _editAvailability = value),
          items: _availabilityOptions
              .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
              .toList(),
        ),
      ),
    );
  }
}