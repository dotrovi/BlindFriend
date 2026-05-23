import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firebase_service.dart';

class VolunteerProfilePage extends StatefulWidget {
  const VolunteerProfilePage({super.key});

  @override
  State<VolunteerProfilePage> createState() => _VolunteerProfilePageState();
}

class _VolunteerProfilePageState extends State<VolunteerProfilePage> {
  final FirebaseService _firebaseService = FirebaseService();

  // Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Options
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

  // State
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;

  // Profile data (view mode)
  String _name = '';
  String _email = '';
  String _phone = '';
  String _language = '';
  List<String> _specialties = [];
  String _availability = '';

  // Edit mode selections
  String? _editLanguage;
  List<String> _editSpecialties = [];
  String? _editAvailability;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
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
        _language = volData['language'] ?? '';
        _specialties = List<String>.from(volData['specialties'] ?? []);
        _availability = volData['availability'] ?? '';
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _startEditing() {
    _nameController.text = _name;
    _phoneController.text = _phone;
    _editLanguage = _language.isEmpty ? null : _language;
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
    if (_editLanguage == null) {
      _showError('Please select a language.');
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
      language: _editLanguage!,
      specialties: _editSpecialties,
      availability: _editAvailability!,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      setState(() {
        _name = name;
        _phone = phone;
        _language = _editLanguage!;
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
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: _isEditing ? _cancelEditing : () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing ? 'Edit Profile' : 'My Profile',
          style: const TextStyle(color: Colors.black),
        ),
        actions: [
          if (!_isLoading && !_isEditing)
            TextButton.icon(
              onPressed: _startEditing,
              icon: const Icon(Icons.edit, size: 18, color: Colors.green),
              label: const Text('Edit',
                  style: TextStyle(color: Colors.green, fontSize: 15)),
            ),
          if (_isEditing)
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: _saveProfile,
                    child: const Text('Save',
                        style: TextStyle(
                            color: Colors.green,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                  ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isEditing
              ? _buildEditForm()
              : _buildViewMode(),
    );
  }

  // ── View mode ────────────────────────────────────────────────────────────
  Widget _buildViewMode() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Avatar
          CircleAvatar(
            radius: 48,
            backgroundColor: Colors.green.shade100,
            child: Text(
              _name.isNotEmpty ? _name[0].toUpperCase() : 'V',
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Volunteer',
              style: TextStyle(
                  color: Colors.green.shade700, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 24),

          // Account info
          _buildCard('Account Information', [
            _InfoRow(icon: Icons.person, label: 'Name', value: _name),
            const Divider(),
            _InfoRow(icon: Icons.email, label: 'Email', value: _email),
          ]),
          const SizedBox(height: 12),

          // Contact
          _buildCard('Contact', [
            _InfoRow(
                icon: Icons.phone,
                label: 'Phone',
                value: _phone.isEmpty ? '—' : _phone),
          ]),
          const SizedBox(height: 12),

          // Languages
          _buildCard('Language', [
            _InfoRow(
                icon: Icons.language,
                label: 'Language',
                value: _language.isEmpty ? '—' : _language),
          ]),
          const SizedBox(height: 12),

          // Specialties
          _buildCard('Specialties', [
            if (_specialties.isEmpty)
              const Text('—',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _specialties
                    .map((s) => Chip(
                          label: Text(s,
                              style: const TextStyle(fontSize: 12)),
                          backgroundColor: Colors.purple.shade50,
                          labelStyle:
                              TextStyle(color: Colors.purple.shade700),
                          side: BorderSide(color: Colors.purple.shade200),
                          padding: EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
          ]),
          const SizedBox(height: 12),

          // Availability
          _buildCard('Availability', [
            _InfoRow(
                icon: Icons.schedule,
                label: 'Availability',
                value: _availability.isEmpty ? '—' : _availability),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  // ── Edit form ─────────────────────────────────────────────────────────────
  Widget _buildEditForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name
          _sectionLabel('Name'),
          _textField(_nameController, 'Your name'),
          const SizedBox(height: 16),

          // Email (read-only)
          _sectionLabel('Email'),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_email,
                style:
                    TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Email cannot be changed.',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
          const SizedBox(height: 16),

          // Phone
          _sectionLabel('Phone Number'),
          _textField(_phoneController, 'Your phone number',
              type: TextInputType.phone),
          const SizedBox(height: 24),

          // Language
          _sectionLabel('Language You Speak'),
          _buildLanguageGrid(),
          const SizedBox(height: 24),

          // Specialties
          _sectionLabel('Specialties'),
          const Text('Select areas where you can provide assistance',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          _buildSpecialtiesGrid(),
          const SizedBox(height: 24),

          // Availability
          _sectionLabel('Availability'),
          _buildAvailabilityDropdown(),
          const SizedBox(height: 32),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Save Changes'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _cancelEditing,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600)),
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
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
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
        childAspectRatio: 2.8,
      ),
      itemCount: _languages.length,
      itemBuilder: (context, index) {
        final lang = _languages[index];
        final isSelected = _editLanguage == lang;
        return GestureDetector(
          onTap: () =>
              setState(() => _editLanguage = isSelected ? null : lang),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? Colors.purple : Colors.grey.shade300,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(8),
              color: isSelected ? Colors.purple.shade50 : Colors.white,
            ),
            child: Center(
              child: Text(lang,
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        isSelected ? Colors.purple : Colors.black87,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  )),
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
        childAspectRatio: 3.0,
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
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? Colors.purple : Colors.grey.shade300,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(8),
              color: isSelected ? Colors.purple.shade50 : Colors.white,
            ),
            child: Center(
              child: Text(specialty,
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        isSelected ? Colors.purple : Colors.black87,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  )),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvailabilityDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _editAvailability,
          hint: Text('Select availability',
              style: TextStyle(color: Colors.grey.shade400)),
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down),
          style: const TextStyle(color: Colors.black, fontSize: 14),
          onChanged: (value) =>
              setState(() => _editAvailability = value),
          items: _availabilityOptions
              .map((opt) =>
                  DropdownMenuItem(value: opt, child: Text(opt)))
              .toList(),
        ),
      ),
    );
  }
}

// ── Shared info row widget ─────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 12)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}
