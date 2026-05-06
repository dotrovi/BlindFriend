import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Register User
  Future<User?> registerUser({
    required String email,
    required String password,
    required String name,
    required String userType,
  }) async {
    try {
      print("STEP A: Creating auth user");

      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      print("STEP B: Auth user created");

      await userCredential.user?.updateDisplayName(name);

      print("STEP C: Display name updated");

      await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'uid': userCredential.user!.uid,
        'name': name,
        'email': email,
        'userType': userType,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print("STEP D: Firestore user document saved");

      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      print("Firebase Auth Error: ${e.code}");

      throw Exception(
        e.message ?? "Authentication failed",
      );
    } on FirebaseException catch (e) {
      print("Firestore Error: ${e.code}");

      throw Exception(
        e.message ?? "Database error",
      );
    } catch (e) {
      print("Registration error: $e");
      throw Exception("Registration failed");
    }
  }

  // Login User
  Future<User?> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential userCredential =
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return userCredential.user;
    } catch (e) {
      print("Login error: $e");
      return null;
    }
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
        'isVerified': false,
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