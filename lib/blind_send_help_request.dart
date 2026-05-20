import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BlindSendHelpRequestScreen extends StatefulWidget {
  const BlindSendHelpRequestScreen({super.key});

  @override
  State<BlindSendHelpRequestScreen> createState() =>
      _BlindSendHelpRequestScreenState();
}

class _BlindSendHelpRequestScreenState
    extends State<BlindSendHelpRequestScreen> {
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  String _selectedRequestType = 'shopping';  // ✅ lowercase
  String _selectedLanguage = 'english';      // ✅ lowercase
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  final Map<String, IconData> _requestTypes = {
    'shopping': Icons.shopping_cart,      // ✅ all lowercase
    'navigation': Icons.navigation,
    'reading': Icons.menu_book,
    'tech support': Icons.computer,
    'emergency': Icons.emergency,
    'medical': Icons.local_hospital,
    'transportation': Icons.directions_car,
  };

  final Map<String, String> _languages = {
    'english': 'English 🇺🇸',    // ✅ lowercase keys
    'spanish': 'Spanish 🇪🇸',
    'mandarin': 'Mandarin 🇨🇳',
    'french': 'French 🇫🇷',
    'german': 'German 🇩🇪',
    'korean': 'Korean 🇰🇷',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Help'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (same as before)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurple.shade700,
                    Colors.deepPurple.shade500
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.help_outline,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Need Assistance?',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Our volunteers are ready to help you',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Error message if any
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _errorMessage = null),
                      child: Icon(Icons.close, color: Colors.red.shade700),
                    ),
                  ],
                ),
              ),

            // Request Type
            const Text(
              'Type of Help Needed',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.5,
              children: _requestTypes.entries.map((entry) {
                return _buildRequestTypeCard(
                  entry.key,
                  entry.value,
                  _selectedRequestType == entry.key,
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Preferred Language Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.language, color: Colors.deepPurple.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Preferred Language',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.deepPurple.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select your preferred language for volunteer communication',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.deepPurple.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _languages.entries.map((entry) {
                      final isSelected = _selectedLanguage == entry.key;
                      return FilterChip(
                        selected: isSelected,
                        label: Text(entry.value),
                        onSelected: (selected) {
                          setState(() {
                            _selectedLanguage = entry.key;
                          });
                        },
                        backgroundColor: Colors.white,
                        selectedColor: Colors.deepPurple.shade100,
                        checkmarkColor: Colors.deepPurple,
                        showCheckmark: true,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Description
            const Text(
              'Describe your request',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'e.g., I need help finding the cereal aisle...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 16),

            // Location
            const Text(
              'Your Location',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _locationController,
              decoration: InputDecoration(
                hintText: 'e.g., Giant Supermarket, KLCC',
                prefixIcon: const Icon(Icons.location_on),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitHelpRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Send Help Request',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestTypeCard(
      String type, IconData icon, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedRequestType = type;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepPurple.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.deepPurple : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.deepPurple : Colors.grey.shade600,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              type.toUpperCase(),
              style: TextStyle(
                color:
                    isSelected ? Colors.deepPurple : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitHelpRequest() async {
    setState(() => _errorMessage = null);

    if (_descriptionController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please describe your request');
      return;
    }

    if (_locationController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please provide your location');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      final userDoc = await firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) throw Exception('User document not found');

      final userData = userDoc.data() as Map<String, dynamic>;
      final userName = '${userData['name'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
      final userPhone = userData['phone'] ?? 'N/A';

      final helpRequestData = {
        'blindUserId': user.uid,
        'blindUserName': userName.isEmpty ? 'User' : userName,
        'blindUserPhone': userPhone,
        'volunteerId': null,
        'volunteerName': null,
        'requestType': _selectedRequestType.toLowerCase(), // ✅ ensure lowercase
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'preferredLanguage': _selectedLanguage.toLowerCase(), // ✅ ensure lowercase
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'acceptedAt': null,
        'completedAt': null,
        'cancelledAt': null,
        'notes': null,
      };

      await firestore.collection('help_requests').add(helpRequestData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Help request sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to send request. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}