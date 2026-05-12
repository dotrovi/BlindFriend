import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Register User with Email Verification
  Future<User?> registerUser({
    required String email,
    required String password,
    required String name,
    required String userType,
  }) async {
    try {
      print("STEP A: Creating auth user");

      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      print("STEP B: Auth user created");

      // Update display name
      await userCredential.user?.updateDisplayName(name);
      print("STEP C: Display name updated");

      // ✅ SEND EMAIL VERIFICATION (NEW)
      await userCredential.user?.sendEmailVerification();
      print("STEP C.5: Verification email sent to $email");

      // Save to Firestore with email verification status
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'name': name,
        'email': email,
        'userType': userType,
        'isEmailVerified': false,  // ✅ Track verification status
        'createdAt': FieldValue.serverTimestamp(),
      });

      print("STEP D: Firestore user document saved");

      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      print("Firebase Auth Error: ${e.code}");
      throw Exception(e.code);
    } on FirebaseException catch (e) {
      print("Firestore Error: ${e.code}");
      throw Exception(e.code);
    } catch (e) {
      print("Registration error: $e");
      throw Exception("registration-failed");
    }
  }

  // Login User with Email Verification Check
  Future<User?> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      print("Login error: ${e.code}");
      return null;
    }
  }

  // ✅ NEW: Resend Verification Email
  Future<bool> resendVerificationEmail() async {
    try {
      User? user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        print("Verification email resent");
        return true;
      }
      return false;
    } catch (e) {
      print("Resend email error: $e");
      return false;
    }
  }

  // ✅ NEW: Check if email is verified
  Future<bool> isEmailVerified() async {
    User? user = _auth.currentUser;
    if (user != null) {
      await user.reload(); // Refresh user data
      return user.emailVerified;
    }
    return false;
  }

  // Save Volunteer Details
  Future<bool> saveVolunteerDetails({
    required String uid,
    required String idCardNumber,
    required String phoneNumber,
    required String language,
    required List<String> specialties,
    required String availability,
  }) async {
    try {
      await _firestore.collection('volunteers').doc(uid).set({
        'uid': uid,
        'idCardNumber': idCardNumber,
        'phoneNumber': phoneNumber,
        'language': language,
        'specialties': specialties,
        'availability': availability,
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print("Save volunteer details error: $e");
      return false;
    }
  }

  User? getCurrentUser() {
    return _auth.currentUser;
  }

  Future<void> logout() async {
    await _auth.signOut();
  }
}