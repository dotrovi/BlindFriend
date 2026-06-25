import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

// ---------------------------------------------------------------------------
// DATA — Training content, quizzes, structure
// ---------------------------------------------------------------------------

class _Chapter {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String article;
  final String youtubeVideoId;
  final List<_Question> quiz;

  const _Chapter({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.article,
    required this.youtubeVideoId,
    required this.quiz,
  });
}

class _Question {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const _Question({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

const _chapters = [
  _Chapter(
    id: 'chapter1',
    title: 'Understanding Visual Impairment',
    subtitle: 'Learn what it means to live with vision loss',
    icon: Icons.visibility_off_rounded,
    color: Color(0xFF3B82F6),
    youtubeVideoId: 'dQw4w9WgXcQ', // swap with real video
    article: '''
Visual impairment affects over 2.2 billion people worldwide. It ranges from partial sight loss to complete blindness, and the experience is unique to every individual.

**Types of Visual Impairment**

Low vision refers to significant visual impairment that cannot be corrected with glasses or surgery. People with low vision may still perceive light, shapes, or colours but cannot see clearly enough for daily tasks. Total blindness means no light perception at all.

Conditions that cause visual impairment include glaucoma, cataracts, diabetic retinopathy, age-related macular degeneration, and retinitis pigmentosa. Each affects vision differently — some affect central vision, others peripheral vision.

**Daily Life and Independence**

Most people with visual impairment live independently and lead full, active lives. They use tools such as white canes, guide dogs, screen readers, and braille to navigate the world. Many use smartphones with voice assistants for communication, navigation, and information access.

It is important to understand that blindness does not affect intelligence, capability, or personality. Blind individuals are experts in their own needs and preferences. As a volunteer, your role is to assist — not to take over.

**Common Misconceptions**

A common misconception is that all blind people see only darkness. In reality, many perceive light, shadows, and colour to varying degrees. Another misconception is that speaking loudly helps — it does not. Speak at a normal volume and pace.

Never assume someone needs help. Always ask first. If your offer is declined, accept that gracefully. Respect autonomy above all else.

**Emotional Awareness**

Vision loss can be emotionally complex. Some individuals were born without sight; others lost it gradually or suddenly. Each person's relationship with their impairment is different. Avoid pity, excessive sympathy, or treating someone as less capable. Treat blind individuals as you would anyone else — with dignity and respect.
''',
    quiz: [
      _Question(
        question:
            'How many people worldwide are affected by visual impairment?',
        options: [
          'Over 500 million',
          'Over 2.2 billion',
          'Over 100 million',
          'Over 1 billion',
        ],
        correctIndex: 1,
        explanation:
            'According to the World Health Organization, over 2.2 billion people have visual impairment globally.',
      ),
      _Question(
        question:
            'What should you do if a blind person declines your offer of help?',
        options: [
          'Insist because they may need it',
          'Ask a third person to help them',
          'Accept it gracefully and respect their decision',
          'Follow them to make sure they are safe',
        ],
        correctIndex: 2,
        explanation:
            'Respecting autonomy is fundamental. Always accept when someone declines help — they know their own needs.',
      ),
      _Question(
        question:
            'Which of the following is a common misconception about blindness?',
        options: [
          'Blind people can use smartphones',
          'All blind people see only complete darkness',
          'Blind people can live independently',
          'White canes help with navigation',
        ],
        correctIndex: 1,
        explanation:
            'Many people with visual impairment can perceive light, shadows, or colours. Total darkness is not universal.',
      ),
      _Question(
        question:
            'How should you adjust your speaking volume when assisting a blind person?',
        options: [
          'Speak much louder so they can hear clearly',
          'Whisper to avoid startling them',
          'Speak at your normal volume and pace',
          'Only speak when spoken to',
        ],
        correctIndex: 2,
        explanation:
            'Visual impairment does not affect hearing. Speak normally — raising your voice is unnecessary and can be condescending.',
      ),
    ],
  ),
  _Chapter(
    id: 'chapter2',
    title: 'Communication & Guiding Skills',
    subtitle: 'How to communicate and physically guide someone safely',
    icon: Icons.people_alt_rounded,
    color: Color(0xFF059669),
    youtubeVideoId: 'dQw4w9WgXcQ', // swap with sighted guide technique video
    article: '''
Effective communication and safe guiding are the two most practical skills a volunteer can develop. Done well, they build trust and ensure safety.

**Communication Principles**

Always introduce yourself when approaching a blind person. Say your name and your role. For example: "Hi, I'm Ahmad, a BlindFriend volunteer. Can I help you?"

Use specific, directional language. Instead of "over there", say "two metres to your left" or "straight ahead about five steps". Vague spatial words like "here", "there", and "that" are not useful without visual context.

It is perfectly acceptable to use words like "see", "look", and "watch" in conversation. Blind individuals use these words too — avoiding them can make conversations awkward and unnatural.

When you are leaving someone, always tell them. Never walk away silently. Say "I'm stepping away now — I'll be back in two minutes."

**The Sighted Guide Technique**

The sighted guide technique is the safest way to physically assist a blind person. Here is how it works:

1. Offer your arm — do not grab theirs. Say "Would you like to take my arm?" Offer your elbow, not your hand.
2. Let the person hold your arm just above the elbow. They will follow your body movements naturally.
3. Walk at a comfortable, steady pace — slightly slower than normal.
4. Narrate upcoming changes: "There are three steps going down", "We are approaching a door that opens toward us", "There is a kerb here."
5. When approaching a seat, place the person's hand on the back of the chair and let them sit themselves.

**Navigating Obstacles and Narrow Spaces**

When approaching a narrow space, move your guiding arm behind your back. The person will move behind you and follow single-file. Once through, return your arm to the normal position.

For stairs, pause before the first step and say whether they go up or down. Let the person find the handrail themselves or offer to guide their hand to it. Move one step ahead of them throughout.

**Asking Before Acting**

The golden rule is always ask before touching or guiding. Never grab someone's arm, hand, or belongings without warning. A sudden unexpected touch can be startling and disorienting.
''',
    quiz: [
      _Question(
        question:
            'When offering to guide a blind person, what is the correct approach?',
        options: [
          'Grab their hand and lead them',
          'Push them gently from behind',
          'Offer your elbow for them to hold',
          'Hold their shoulder and steer them',
        ],
        correctIndex: 2,
        explanation:
            'The sighted guide technique requires you to offer your elbow. The person holds just above it and follows your body movements naturally.',
      ),
      _Question(
        question: 'How should you describe directions to a blind person?',
        options: [
          'Use words like "over there" and "this way"',
          'Use specific directional language like "two metres to your left"',
          'Point and say "that direction"',
          'Use hand signals',
        ],
        correctIndex: 1,
        explanation:
            'Specific directional language is essential. Vague spatial terms have no meaning without visual context.',
      ),
      _Question(
        question:
            'What should you do when approaching a narrow passage while guiding?',
        options: [
          'Ask the person to wait while you check',
          'Move your guiding arm behind your back so they follow single-file',
          'Hold their hand and walk side by side',
          'Stop and find another route',
        ],
        correctIndex: 1,
        explanation:
            'Moving your arm behind your back signals the person to move behind you and walk single-file through the narrow space.',
      ),
      _Question(
        question:
            'Is it appropriate to use words like "see" and "look" when talking to a blind person?',
        options: [
          'No, always avoid those words as they are offensive',
          'Only if the person has some remaining vision',
          'Yes, blind individuals use these words too',
          'Only in formal situations',
        ],
        correctIndex: 2,
        explanation:
            'These words are part of everyday language and are used naturally by blind individuals themselves. Avoiding them creates unnecessary awkwardness.',
      ),
      _Question(
        question:
            'What must you always do before walking away from someone you are assisting?',
        options: [
          'Make sure they are sitting down first',
          'Tell them you are leaving and when you will return',
          'Ask a nearby person to watch them',
          'Nothing — they will notice on their own',
        ],
        correctIndex: 1,
        explanation:
            'Always verbally announce when you are stepping away. Never leave silently — it can disorient the person.',
      ),
    ],
  ),
  _Chapter(
    id: 'chapter3',
    title: 'Safety & Emergency Protocols',
    subtitle: 'Keeping blind users safe in difficult situations',
    icon: Icons.health_and_safety_rounded,
    color: Color(0xFFEF4444),
    youtubeVideoId: 'dQw4w9WgXcQ', // swap with emergency assistance video
    article: '''
Emergencies and safety situations require calm, clear, and immediate action. As a volunteer, knowing how to respond can make a critical difference.

**Staying Calm and Clear**

In any emergency, your first responsibility is to remain calm. A panicked volunteer creates additional confusion. Speak in a steady, clear voice. Give simple, direct instructions: "There is an exit to your right. Take my arm."

Blind individuals are often experienced in handling emergencies — they may have rehearsed evacuation routes or know their environment well. Do not assume helplessness.

**Fire and Evacuation**

In a fire or evacuation situation:
1. Alert the person calmly: "There is a fire alarm. We need to leave now."
2. Use the sighted guide technique. Do not use lifts — use stairs.
3. Narrate every step: "We are at the stairwell. Steps going down. Handrail on your right."
4. Do not leave the person alone unless absolutely unavoidable. If you must leave, ensure they are with another person or in a safe, known location.
5. Alert emergency services that a blind person requires assistance.

**Medical Situations**

If a blind person appears unwell or injured:
1. Identify yourself and ask how you can help.
2. Do not move them unless there is immediate danger.
3. Call emergency services if needed.
4. Stay with them and provide reassurance until help arrives.
5. Describe what is happening around them so they are not disoriented.

**Getting Lost or Disoriented**

If someone becomes disoriented in an unfamiliar area:
1. Speak calmly: "You are safe. I am here with you."
2. Help them identify a landmark or familiar reference point.
3. Use the BlindFriend app to check their location and find their destination.
4. Do not rush them — disorientation can be frightening and takes a moment to resolve.

**Personal Safety as a Volunteer**

Your safety matters too. Do not place yourself in danger. If a situation feels unsafe, call for help rather than acting alone. Trust your instincts. You are a companion and assistant — not a first responder.

**Boundaries and Professionalism**

Maintain professional boundaries at all times. Do not share personal contact details unless through the app. Do not make medical decisions for someone. Do not enter private spaces without explicit invitation. Respect privacy and dignity in all situations.
''',
    quiz: [
      _Question(
        question: 'In a fire evacuation, which of the following is correct?',
        options: [
          'Use the lift for speed',
          'Leave immediately without the person if they are slow',
          'Use stairs and narrate every step',
          'Wait for the fire brigade before moving',
        ],
        correctIndex: 2,
        explanation:
            'Always use stairs in evacuations — never lifts. Narrate every step to keep the person informed and safe.',
      ),
      _Question(
        question:
            'What is your first responsibility in any emergency situation?',
        options: [
          'Call the emergency services immediately',
          'Remain calm and speak in a clear, steady voice',
          'Find the nearest exit yourself first',
          'Ask bystanders for help',
        ],
        correctIndex: 1,
        explanation:
            'Remaining calm is essential. A panicked volunteer creates confusion. Calm, clear communication is your most valuable tool.',
      ),
      _Question(
        question:
            'If someone appears disoriented, what should your first words be?',
        options: [
          '"Where are you trying to go?"',
          '"You are safe. I am here with you."',
          '"Stay here and do not move."',
          '"Let me call someone to help."',
        ],
        correctIndex: 1,
        explanation:
            'Reassurance comes first. Disorientation can be frightening — establishing safety and presence immediately helps the person calm down.',
      ),
      _Question(
        question:
            'As a volunteer, what should you do if a situation feels personally unsafe?',
        options: [
          'Push through it — the blind person needs you',
          'Call for help rather than acting alone',
          'Leave the scene quickly',
          'Ask the blind person what to do',
        ],
        correctIndex: 1,
        explanation:
            'Your safety matters. You are an assistant, not a first responder. Call for help rather than putting yourself in danger.',
      ),
    ],
  ),
  _Chapter(
    id: 'chapter4',
    title: 'Final Assessment',
    subtitle: 'Demonstrate what you have learned',
    icon: Icons.emoji_events_rounded,
    color: Color(0xFFF59E0B),
    youtubeVideoId: '',
    article: '',
    quiz: [
      _Question(
        question: 'A blind user declines your help. What do you do?',
        options: [
          'Insist and follow them to make sure they are safe',
          'Accept gracefully and respect their decision',
          'Contact their family',
          'Report it in the app',
        ],
        correctIndex: 1,
        explanation:
            'Autonomy and respect are fundamental. Always accept when help is declined.',
      ),
      _Question(
        question: 'You are guiding someone down stairs. What is correct?',
        options: [
          'Walk behind them and hold their shoulders',
          'Hold their hand and walk side by side',
          'Walk one step ahead, narrate the steps, offer the handrail',
          'Ask them to hold the wall and follow slowly',
        ],
        correctIndex: 2,
        explanation:
            'Walk one step ahead using the sighted guide technique. Always narrate and offer the handrail.',
      ),
      _Question(
        question:
            'What should you always do before walking away from someone you are assisting?',
        options: [
          'Make sure they are seated',
          'Tell them you are leaving',
          'Ask a nearby stranger to watch them',
          'Nothing — they will sense it',
        ],
        correctIndex: 1,
        explanation:
            'Always announce when you are stepping away. Never leave silently.',
      ),
      _Question(
        question: 'In a fire evacuation, you should:',
        options: [
          'Use the lift for speed',
          'Leave them if they slow you down',
          'Use stairs and narrate every step',
          'Wait until the alarm stops',
        ],
        correctIndex: 2,
        explanation:
            'Always use stairs and narrate the entire route during evacuation.',
      ),
      _Question(
        question:
            'Which phrase is best when a blind person becomes disoriented?',
        options: [
          '"Where are you going?"',
          '"You are safe. I am here with you."',
          '"Stay still and do not move."',
          '"I will find someone to help."',
        ],
        correctIndex: 1,
        explanation:
            'Immediate reassurance is the priority. Establish safety and presence first.',
      ),
    ],
  ),
];

// ---------------------------------------------------------------------------
// MAIN PAGE
// ---------------------------------------------------------------------------

class VolunteerTrainingPage extends StatefulWidget {
  const VolunteerTrainingPage({super.key});

  @override
  State<VolunteerTrainingPage> createState() => _VolunteerTrainingPageState();
}

class _VolunteerTrainingPageState extends State<VolunteerTrainingPage> {
  static const _emerald = Color(0xFF059669);
  static const _emeraldDark = Color(0xFF047857);

  Map<String, bool> _completedChapters = {};
  bool _isLoading = true;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _loadProgress();
  }

  // ---------------------------------------------------------------------------
  // FIRESTORE
  // ---------------------------------------------------------------------------

  Future<void> _loadProgress() async {
    if (_uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('volunteers')
          .doc(_uid)
          .get();
      final data = doc.data();
      if (data != null && mounted) {
        final progress =
            data['trainingProgress'] as Map<String, dynamic>? ?? {};
        setState(() {
          _completedChapters = {
            for (final c in _chapters) c.id: progress[c.id] == true,
          };
          _isLoading = false;
        });
      } else {
        setState(() {
          _completedChapters = {for (final c in _chapters) c.id: false};
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Load progress error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markChapterComplete(String chapterId) async {
    if (_uid == null) return;
    setState(() => _completedChapters[chapterId] = true);

    final allDone = _chapters.every((c) => _completedChapters[c.id] == true);

    await FirebaseFirestore.instance.collection('volunteers').doc(_uid).update({
      'trainingProgress.$chapterId': true,
      if (allDone) 'trainingCompleted': true,
      if (allDone) 'trainingCompletedAt': FieldValue.serverTimestamp(),
    });

    if (allDone && mounted) {
      await _showCertificateScreen();
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  bool _isChapterUnlocked(int index) {
    if (index == 0) return true;
    return _completedChapters[_chapters[index - 1].id] == true;
  }

  int get _completedCount => _completedChapters.values.where((v) => v).length;

  bool get _allCompleted => _completedCount == _chapters.length;

  // ---------------------------------------------------------------------------
  // CERTIFICATE
  // ---------------------------------------------------------------------------

  Future<void> _showCertificateScreen() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CertificatePage(
          volunteerName:
              FirebaseAuth.instance.currentUser?.displayName ?? 'Volunteer',
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDF4),
      appBar: AppBar(
        title: const Text(
          'Volunteer Training',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: _emeraldDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _emerald),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProgressHeader(),
                  const SizedBox(height: 24),
                  if (_allCompleted) ...[
                    _buildCompletionBanner(),
                    const SizedBox(height: 24),
                  ],
                  const Text(
                    'Chapters',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(
                    _chapters.length,
                    (i) => _buildChapterCard(i),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildProgressHeader() {
    final progress = _completedCount / _chapters.length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _emerald.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Induction Training',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$_completedCount of ${_chapters.length} chapters complete',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionBanner() {
    return GestureDetector(
      onTap: _showCertificateScreen,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF59E0B), width: 2),
        ),
        child: Row(
          children: [
            const Icon(Icons.emoji_events_rounded,
                color: Color(0xFFF59E0B), size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Training Complete! 🎉',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to view and download your certificate',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: Color(0xFFF59E0B)),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterCard(int index) {
    final chapter = _chapters[index];
    final isCompleted = _completedChapters[chapter.id] == true;
    final isUnlocked = _isChapterUnlocked(index);
    final isFinal = index == _chapters.length - 1;

    return GestureDetector(
      onTap: isUnlocked
          ? () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _ChapterPage(
                    chapter: chapter,
                    isCompleted: isCompleted,
                    isFinalChapter: isFinal,
                    onComplete: () => _markChapterComplete(chapter.id),
                  ),
                ),
              );
              await _loadProgress();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isUnlocked ? Colors.white : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isCompleted
                ? _emerald.withValues(alpha: 0.5)
                : isUnlocked
                    ? chapter.color.withValues(alpha: 0.3)
                    : Colors.grey.shade200,
            width: 1.5,
          ),
          boxShadow: isUnlocked
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Chapter icon / status
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isCompleted
                    ? _emerald.withValues(alpha: 0.1)
                    : isUnlocked
                        ? chapter.color.withValues(alpha: 0.1)
                        : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isCompleted
                    ? Icons.check_circle_rounded
                    : isUnlocked
                        ? chapter.icon
                        : Icons.lock_rounded,
                color: isCompleted
                    ? _emerald
                    : isUnlocked
                        ? chapter.color
                        : Colors.grey.shade400,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),

            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Chapter ${index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              isUnlocked ? chapter.color : Colors.grey.shade400,
                        ),
                      ),
                      if (isCompleted) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _emerald.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 10,
                              color: _emerald,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    chapter.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isUnlocked ? Colors.black87 : Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chapter.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),

            Icon(
              isUnlocked ? Icons.arrow_forward_ios_rounded : Icons.lock_rounded,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CHAPTER PAGE — article + video + quiz
// ---------------------------------------------------------------------------

class _ChapterPage extends StatefulWidget {
  final _Chapter chapter;
  final bool isCompleted;
  final bool isFinalChapter;
  final VoidCallback onComplete;

  const _ChapterPage({
    required this.chapter,
    required this.isCompleted,
    required this.isFinalChapter,
    required this.onComplete,
  });

  @override
  State<_ChapterPage> createState() => _ChapterPageState();
}

class _ChapterPageState extends State<_ChapterPage> {
  // Tracks which section the user is on: 'article', 'video', 'quiz'
  String _section = 'article';
  YoutubePlayerController? _ytController;

  @override
  void initState() {
    super.initState();
    if (widget.chapter.youtubeVideoId.isNotEmpty) {
      _ytController = YoutubePlayerController(
        initialVideoId: widget.chapter.youtubeVideoId,
        flags: const YoutubePlayerFlags(autoPlay: false),
      );
    }
    // Final chapter has no article or video — go straight to quiz
    if (widget.chapter.id == 'chapter4') {
      _section = 'quiz';
    }
  }

  @override
  void dispose() {
    _ytController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDF4),
      appBar: AppBar(
        title: Text(
          widget.chapter.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: widget.chapter.color,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _section == 'article'
            ? _ArticleSection(
                key: const ValueKey('article'),
                chapter: widget.chapter,
                onNext: () => setState(() => _section = 'video'),
              )
            : _section == 'video'
                ? _VideoSection(
                    key: const ValueKey('video'),
                    controller: _ytController!,
                    chapter: widget.chapter,
                    onNext: () => setState(() => _section = 'quiz'),
                  )
                : _QuizSection(
                    key: const ValueKey('quiz'),
                    chapter: widget.chapter,
                    isAlreadyCompleted: widget.isCompleted,
                    isFinalChapter: widget.isFinalChapter,
                    onComplete: () {
                      widget.onComplete();
                      Navigator.pop(context);
                    },
                  ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ARTICLE SECTION
// ---------------------------------------------------------------------------

class _ArticleSection extends StatelessWidget {
  final _Chapter chapter;
  final VoidCallback onNext;

  const _ArticleSection(
      {super.key, required this.chapter, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: chapter.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: chapter.color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.article_rounded, color: chapter.color, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Reading Material',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Article content — parse **bold** markdown
          ..._parseArticle(chapter.article),

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.play_circle_rounded, size: 20),
              label: const Text('Watch Video'),
              style: ElevatedButton.styleFrom(
                backgroundColor: chapter.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: onNext,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // Parses **bold** markdown into RichText widgets
  List<Widget> _parseArticle(String text) {
    final lines = text.trim().split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 12));
        continue;
      }

      // Bold heading
      if (line.startsWith('**') && line.endsWith('**')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            line.replaceAll('**', ''),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ));
        continue;
      }

      // Numbered list
      if (RegExp(r'^\d+\.').hasMatch(line.trim())) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Text(
            line.trim(),
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
        ));
        continue;
      }

      // Normal paragraph
      widgets.add(Text(
        line.trim(),
        style: const TextStyle(
          fontSize: 14,
          height: 1.7,
          color: Colors.black87,
        ),
      ));
    }

    return widgets;
  }
}

// ---------------------------------------------------------------------------
// VIDEO SECTION
// ---------------------------------------------------------------------------

class _VideoSection extends StatelessWidget {
  final YoutubePlayerController controller;
  final _Chapter chapter;
  final VoidCallback onNext;

  const _VideoSection({
    super.key,
    required this.controller,
    required this.chapter,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: chapter.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: chapter.color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.play_circle_rounded, color: chapter.color, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Watch & Learn',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // YouTube player
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: YoutubePlayer(
              controller: controller,
              showVideoProgressIndicator: true,
              progressIndicatorColor: chapter.color,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Watch the video above, then proceed to the quiz when you are ready.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.quiz_rounded, size: 20),
              label: const Text('Take the Quiz'),
              style: ElevatedButton.styleFrom(
                backgroundColor: chapter.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: onNext,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QUIZ SECTION
// ---------------------------------------------------------------------------

class _QuizSection extends StatefulWidget {
  final _Chapter chapter;
  final bool isAlreadyCompleted;
  final bool isFinalChapter;
  final VoidCallback onComplete;

  const _QuizSection({
    super.key,
    required this.chapter,
    required this.isAlreadyCompleted,
    required this.isFinalChapter,
    required this.onComplete,
  });

  @override
  State<_QuizSection> createState() => _QuizSectionState();
}

class _QuizSectionState extends State<_QuizSection> {
  int _currentQuestion = 0;
  int? _selectedAnswer;
  bool _answered = false;
  int _correctCount = 0;
  bool _quizCompleted = false;

  _Question get _question => widget.chapter.quiz[_currentQuestion];

  void _selectAnswer(int index) {
    if (_answered) return;
    setState(() {
      _selectedAnswer = index;
      _answered = true;
      if (index == _question.correctIndex) _correctCount++;
    });
  }

  void _nextQuestion() {
    if (_currentQuestion < widget.chapter.quiz.length - 1) {
      setState(() {
        _currentQuestion++;
        _selectedAnswer = null;
        _answered = false;
      });
    } else {
      setState(() => _quizCompleted = true);
    }
  }

  bool get _passed =>
      _correctCount >= (widget.chapter.quiz.length * 0.75).ceil();

  void _retake() {
    setState(() {
      _currentQuestion = 0;
      _selectedAnswer = null;
      _answered = false;
      _correctCount = 0;
      _quizCompleted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_quizCompleted) return _buildResults();
    return _buildQuestion();
  }

  Widget _buildQuestion() {
    final total = widget.chapter.quiz.length;
    final progress = (_currentQuestion + 1) / total;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress
          Row(
            children: [
              Text(
                'Question ${_currentQuestion + 1} of $total',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '$_correctCount correct',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF059669),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(widget.chapter.color),
            ),
          ),
          const SizedBox(height: 24),

          // Question card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              _question.question,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Options
          ...List.generate(
            _question.options.length,
            (i) => _buildOption(i),
          ),

          // Explanation
          if (_answered) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _selectedAnswer == _question.correctIndex
                    ? const Color(0xFFD1FAE5)
                    : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedAnswer == _question.correctIndex
                      ? const Color(0xFF059669)
                      : const Color(0xFFEF4444),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _selectedAnswer == _question.correctIndex
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: _selectedAnswer == _question.correctIndex
                            ? const Color(0xFF059669)
                            : const Color(0xFFEF4444),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _selectedAnswer == _question.correctIndex
                            ? 'Correct!'
                            : 'Incorrect',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _selectedAnswer == _question.correctIndex
                              ? const Color(0xFF059669)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _question.explanation,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _nextQuestion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.chapter.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _currentQuestion < widget.chapter.quiz.length - 1
                      ? 'Next Question'
                      : 'See Results',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildOption(int index) {
    Color bgColor = Colors.white;
    Color borderColor = Colors.grey.shade300;
    Color textColor = Colors.black87;
    IconData? icon;

    if (_answered) {
      if (index == _question.correctIndex) {
        bgColor = const Color(0xFFD1FAE5);
        borderColor = const Color(0xFF059669);
        textColor = const Color(0xFF065F46);
        icon = Icons.check_circle_rounded;
      } else if (index == _selectedAnswer) {
        bgColor = const Color(0xFFFEE2E2);
        borderColor = const Color(0xFFEF4444);
        textColor = const Color(0xFF991B1B);
        icon = Icons.cancel_rounded;
      }
    } else if (_selectedAnswer == index) {
      borderColor = widget.chapter.color;
      bgColor = widget.chapter.color.withValues(alpha: 0.05);
    }

    return GestureDetector(
      onTap: () => _selectAnswer(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _answered && index == _question.correctIndex
                    ? const Color(0xFF059669)
                    : _answered && index == _selectedAnswer
                        ? const Color(0xFFEF4444)
                        : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: icon != null
                    ? Icon(icon, color: Colors.white, size: 16)
                    : Text(
                        String.fromCharCode(65 + index),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _question.options[index],
                style: TextStyle(
                  fontSize: 14,
                  color: textColor,
                  fontWeight: _answered && index == _question.correctIndex
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final total = widget.chapter.quiz.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Score circle
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: _passed
                        ? const Color(0xFFD1FAE5)
                        : const Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$_correctCount/$total',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: _passed
                            ? const Color(0xFF059669)
                            : const Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _passed ? 'Chapter Complete! 🎉' : 'Not Quite There',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _passed
                      ? 'You scored $_correctCount out of $total. '
                          '${widget.isFinalChapter ? 'You have completed the full training!' : 'The next chapter is now unlocked.'}'
                      : 'You need to score at least ${(total * 0.75).ceil()} out of $total to pass. Please review the material and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),

                if (_passed) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(
                        widget.isFinalChapter
                            ? Icons.emoji_events_rounded
                            : Icons.arrow_forward_rounded,
                        size: 20,
                      ),
                      label: Text(
                        widget.isFinalChapter ? 'Get Certificate' : 'Continue',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: widget.onComplete,
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Retake Quiz'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.chapter.color,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: _retake,
                    ),
                  ),
                ],

                if (widget.isAlreadyCompleted && !_passed) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: widget.onComplete,
                    child: const Text('Skip (already completed)'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CERTIFICATE PAGE
// ---------------------------------------------------------------------------

class _CertificatePage extends StatelessWidget {
  final String volunteerName;

  const _CertificatePage({required this.volunteerName});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.now();
    final dateStr =
        '${date.day.toString().padLeft(2, '0')} / ${date.month.toString().padLeft(2, '0')} / ${date.year}';

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBEB),
      appBar: AppBar(
        title: const Text('Your Certificate'),
        backgroundColor: const Color(0xFFF59E0B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildCertificateCard(volunteerName, dateStr),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.download_rounded, size: 20),
                label: const Text('Download PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => _downloadPdf(context, volunteerName, dateStr),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text('Done'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF59E0B),
                  side: const BorderSide(color: Color(0xFFF59E0B)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificateCard(String name, String date) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF59E0B), width: 3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            color: Color(0xFFF59E0B),
            size: 56,
          ),
          const SizedBox(height: 16),
          const Text(
            'BlindFriend',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF047857),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Certificate of Completion',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 24),
          Container(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 24),
          const Text(
            'This certifies that',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'has successfully completed the\nBlindFriend Volunteer Induction Training',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 24),
          Container(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                date,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _downloadPdf(
      BuildContext context, String name, String date) async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: const PdfColor.fromInt(0xFFF59E0B),
                  width: 4,
                ),
                borderRadius: pw.BorderRadius.circular(16),
              ),
              padding: const pw.EdgeInsets.all(48),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'BlindFriend',
                    style: pw.TextStyle(
                      fontSize: 36,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF047857),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Certificate of Completion',
                    style: pw.TextStyle(
                      fontSize: 18,
                      color: const PdfColor.fromInt(0xFF6B7280),
                    ),
                  ),
                  pw.SizedBox(height: 48),
                  pw.Divider(color: const PdfColor.fromInt(0xFFE5E7EB)),
                  pw.SizedBox(height: 48),
                  pw.Text(
                    'This certifies that',
                    style: pw.TextStyle(
                      fontSize: 14,
                      color: const PdfColor.fromInt(0xFF6B7280),
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Text(
                    name,
                    style: pw.TextStyle(
                      fontSize: 32,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 24),
                  pw.Text(
                    'has successfully completed the',
                    style: const pw.TextStyle(fontSize: 14),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'BlindFriend Volunteer Induction Training',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF047857),
                    ),
                  ),
                  pw.SizedBox(height: 48),
                  pw.Divider(color: const PdfColor.fromInt(0xFFE5E7EB)),
                  pw.SizedBox(height: 24),
                  pw.Text(
                    'Date: $date',
                    style: const pw.TextStyle(fontSize: 13),
                  ),
                ],
              ),
            );
          },
        ),
      );

      final Uint8List bytes = await pdf.save();

      // For mobile (Android & iOS)
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: 'BlindFriend_Certificate_$name.pdf',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Certificate downloaded!'),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
