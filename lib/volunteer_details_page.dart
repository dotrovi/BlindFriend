import 'package:flutter/material.dart';
import 'package:flutter_blindfriend/services/firebase_service.dart';

class VolunteerDetailsPage extends StatefulWidget {
  final String name;
  final String email;
  final String password;
  final String uid;

  const VolunteerDetailsPage({
    super.key,
    required this.name,
    required this.email,
    required this.password,
    required this.uid,
  });

  @override
  State<VolunteerDetailsPage> createState() => _VolunteerDetailsPageState();
}

class _VolunteerDetailsPageState extends State<VolunteerDetailsPage> {
  final _idCardController = TextEditingController();
  final _phoneController = TextEditingController();

  // Languages
  String? _selectedLanguage;
  final List<String> _languages = [
    'English',
    'Spanish',
    'Mandarin',
    'French',
    'German',
    'Korean',
  ];

  // Specialties
  final List<String> _allSpecialties = [
    'Shopping',
    'Navigation',
    'Reading',
    'Tech Support',
    'Emergency Assistance',
    'Medical Support',
    'Transportation',
  ];
  final List<String> _selectedSpecialties = [];

  // Availability - Dropdown
  String? _selectedAvailability;
  final List<String> _availabilityOptions = [
    'Weekdays',
    'Weekends',
    'Anytime',
    'Emergency Only',
  ];

  void _speak(String message) {
    print('🔊 TTS: $message');
  }

  void _submit() async {
    // Validation checks
    if (_idCardController.text.isEmpty) {
      _speak('Please enter your ID card number');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your ID card number')),
      );
      return;
    }
    if (_phoneController.text.isEmpty) {
      _speak('Please enter your phone number');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your phone number')),
      );
      return;
    }
    if (_selectedLanguage == null) {
      _speak('Please select a language');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a language')));
      return;
    }
    if (_selectedSpecialties.isEmpty) {
      _speak('Please select at least one specialty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one specialty')),
      );
      return;
    }
    if (_selectedAvailability == null) {
      _speak('Please select your availability');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your availability')),
      );
      return;
    }

    _speak('Submitting for verification');

    // ✅ Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // ✅ Create FirebaseService instance
    final FirebaseService _firebaseService = FirebaseService();

    // ✅ SAVE TO FIRESTORE
    bool saved = await _firebaseService.saveVolunteerDetails(
      uid: widget.uid,
      idCardNumber: _idCardController.text,
      phoneNumber: _phoneController.text,
      language: _selectedLanguage!,
      specialties: _selectedSpecialties,
      availability: _selectedAvailability!,
    );

    // ✅ Close loading
    if (mounted) Navigator.pop(context);

    if (saved) {
      _speak('Volunteer details saved successfully!');

      // ✅ Navigate to completion page
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => VolunteerCompletePage(
              name: widget.name,
              email: widget.email,
              languages: [_selectedLanguage!],
              specialties: _selectedSpecialties,
              availability: _selectedAvailability!,
            ),
          ),
        );
      }
    } else {
      _speak('Failed to save. Please try again.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),

              // Title
              const Center(
                child: Text(
                  'Volunteer Registration',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              const Center(
                child: Text(
                  'Complete your profile to start helping others',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 28),

              // ===== IDENTITY VERIFICATION =====
              const Text(
                'Identity Verification',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'Identity Card Number',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _idCardController,
                decoration: InputDecoration(
                  hintText: 'Enter your ID card number',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Required for volunteer verification and background check',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              const Text(
                'Phone Number',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'Enter your phone number',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 20),

              // Privacy Notice
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.privacy_tip, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Privacy Notice: Your identity information will be used solely for volunteer verification.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ===== LANGUAGES - 3 columns =====
              const Text(
                'Languages You Speak',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 6),

              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.8,
                ),
                itemCount: _languages.length,
                itemBuilder: (context, index) {
                  final language = _languages[index];
                  final isSelected = _selectedLanguage == language;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedLanguage = isSelected ? null : language;
                      });
                      if (!isSelected) _speak('Selected $language');
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected
                              ? Colors.purple
                              : Colors.grey.shade300,
                          width: 1.2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: isSelected
                            ? Colors.purple.shade50
                            : Colors.white,
                      ),
                      child: Center(
                        child: Text(
                          language,
                          style: TextStyle(
                            fontSize: 13,
                            color: isSelected ? Colors.purple : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),

              // ===== SPECIALTIES - 2 columns =====
              const Text(
                'Your Specialties',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Select areas where you can provide assistance',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),

              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 3.0,
                ),
                itemCount: _allSpecialties.length,
                itemBuilder: (context, index) {
                  final specialty = _allSpecialties[index];
                  final isSelected = _selectedSpecialties.contains(specialty);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedSpecialties.remove(specialty);
                          _speak('Deselected $specialty');
                        } else {
                          _selectedSpecialties.add(specialty);
                          _speak('Selected $specialty');
                        }
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected
                              ? Colors.purple
                              : Colors.grey.shade300,
                          width: 1.2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: isSelected
                            ? Colors.purple.shade50
                            : Colors.white,
                      ),
                      child: Center(
                        child: Text(
                          specialty,
                          style: TextStyle(
                            fontSize: 13,
                            color: isSelected ? Colors.purple : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),

              // ===== AVAILABILITY - DROPDOWN =====
              const Text(
                'Availability',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedAvailability,
                    hint: const Text(
                      'Select availability',
                      style: TextStyle(color: Colors.grey),
                    ),
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down),
                    elevation: 16,
                    style: const TextStyle(color: Colors.black, fontSize: 14),
                    onChanged: (String? value) {
                      setState(() {
                        _selectedAvailability = value;
                      });
                      _speak('Selected $value');
                    },
                    items: _availabilityOptions.map((String option) {
                      return DropdownMenuItem<String>(
                        value: option,
                        child: Text(option),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ===== COMPLETE REGISTRATION BUTTON =====
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                  child: const Text('Complete Registration'),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Submit for verification',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 32),

              // ===== WHAT'S NEXT =====
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "What's Next?",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStep(
                      '1',
                      "We'll verify your identity (usually instant)",
                    ),
                    _buildStep(
                      '2',
                      'Background check will be processed (1-2 days)',
                    ),
                    _buildStep(
                      '3',
                      "You'll receive training materials via email",
                    ),
                    _buildStep('4', 'Complete a short online training course'),
                    _buildStep('5', 'Start helping people in your community!'),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.purple,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

// Completion Page
class VolunteerCompletePage extends StatelessWidget {
  final String name;
  final String email;
  final List<String> languages;
  final List<String> specialties;
  final String availability;

  const VolunteerCompletePage({
    super.key,
    required this.name,
    required this.email,
    required this.languages,
    required this.specialties,
    required this.availability,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.check_circle, size: 70, color: Colors.green),
              const SizedBox(height: 20),
              const Text(
                'Welcome, Volunteer!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Your account has been verified and activated.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Thank you for joining the BlindFriend community.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profile Summary',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildRow('Name:', name),
                    const SizedBox(height: 6),
                    _buildRow('Languages:', languages.join(', ')),
                    const SizedBox(height: 6),
                    _buildRow('Specialties:', specialties.join(', ')),
                    const SizedBox(height: 6),
                    _buildRow('Availability:', availability),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/',
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Go to Dashboard'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 85,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
