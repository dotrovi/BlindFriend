import 'package:cloud_firestore/cloud_firestore.dart';

class AdminService {
  final _firestore = FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------------------

  // Returns a live stream of all volunteers with status == 'pending'
  Stream<QuerySnapshot> getPendingVolunteers() {
    return _firestore
        .collection('volunteers')
        .where('isVerified', isEqualTo: false)
        .snapshots();
  }

  // Fetches name and email from the users collection as a fallback
  // Used when the volunteers doc is missing those fields
  Future<Map<String, dynamic>?> getUserInfo(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.exists ? doc.data() : null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // APPROVE
  // ---------------------------------------------------------------------------

  Future<void> approveVolunteer({
    required String uid,
    required String volunteerName,
    required String volunteerEmail,
  }) async {
    try {
      final batch = _firestore.batch();

      // 1. Update volunteer status
      batch.update(_firestore.collection('volunteers').doc(uid), {
        'status': 'approved',
        'isVerified': true,
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      // 2. Update user document
      batch.update(_firestore.collection('users').doc(uid), {
        'isVerified': true,
      });

      // 3. In-app notification
      batch.set(
        _firestore.collection('notifications').doc(uid).collection('messages').doc(),
        {
          'title': 'Application Approved!',
          'body': 'Congratulations $volunteerName! Your application has been approved.',
          'type': 'approval',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      // 4. Email queue — picked up by Cloud Function to send email
      batch.set(
        _firestore.collection('emailQueue').doc(),
        {
          'to': volunteerEmail,
          'subject': 'BlindFriend - Your application has been approved!',
          'body': 'Hi $volunteerName, your volunteer application has been approved. Welcome to the team!',
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();
    } catch (e) {
      print('Approve volunteer error: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // REJECT
  // ---------------------------------------------------------------------------

  Future<void> rejectVolunteer({
    required String uid,
    required String volunteerName,
    required String volunteerEmail,
    String reason = 'Your application did not meet our current requirements.',
  }) async {
    try {
      final batch = _firestore.batch();

      // 1. Update volunteer status
      batch.update(_firestore.collection('volunteers').doc(uid), {
        'status': 'rejected',
        'isVerified': false,
        'rejectionReason': reason,
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      // 2. In-app notification
      batch.set(
        _firestore.collection('notifications').doc(uid).collection('messages').doc(),
        {
          'title': 'Application Update',
          'body': 'Hi $volunteerName, your application was not approved. $reason',
          'type': 'rejection',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      // 3. Email queue
      batch.set(
        _firestore.collection('emailQueue').doc(),
        {
          'to': volunteerEmail,
          'subject': 'BlindFriend - Application Status Update',
          'body': 'Hi $volunteerName, your application was not approved. $reason',
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();
    } catch (e) {
      print('Reject volunteer error: $e');
      rethrow;
    }
  }
}