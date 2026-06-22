import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../blind_track_help_request.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  StreamSubscription? _authSubscription;
  StreamSubscription? _notificationSubscription;
  bool _isDialogShowing = false;

  // Use a GlobalKey to get a valid context for showing dialogs.
  // This should be set in main.dart
  GlobalKey<NavigatorState>? navigatorKey;

  void initialize(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
    _authSubscription?.cancel();
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user != null) {
        _listenForNotifications(user.uid);
        _setupPushNotifications(user.uid);
      } else {
        _notificationSubscription?.cancel();
      }
    });
  }

  void _listenForNotifications(String userId) {
    _notificationSubscription?.cancel();
    _notificationSubscription = _firestore
        .collection('notifications')
        .doc(userId)
        .collection('messages')
        .where('read', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      // Only show the very latest unread notification to avoid spamming dialogs.
      // The listener will fire again for the next one after this is read.
      if (snapshot.docs.isNotEmpty) {
        _showNotificationDialog(snapshot.docs.first);
      }
    });
  }

  void _showNotificationDialog(DocumentSnapshot doc) {
    if (_isDialogShowing) return;
    final context = navigatorKey?.currentContext;
    if (context == null) return;

    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] as String? ?? 'Notification';
    final body = data['body'] as String? ?? 'You have a new message.';
    _isDialogShowing = true;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () {
              // Mark as read and close
              doc.reference.update({'read': true});
              Navigator.pop(dialogContext);
            },
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              // Mark as read, close, and navigate
              doc.reference.update({'read': true});
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BlindTrackRequestsScreen(),
                ),
              );
            },
            child: const Text('View Request'),
          ),
        ],
      ),
    ).then((_) {
      // Ensure it's marked as read even if the dialog is dismissed
      // by tapping outside.
      doc.reference.get().then((snapshot) {
        _isDialogShowing = false;
        if (snapshot.exists && snapshot.data() != null) {
          final currentData = snapshot.data() as Map<String, dynamic>;
          if (currentData['read'] == false) {
            doc.reference.update({'read': true});
          }
        }
      });
    });
  }

  Future<void> _setupPushNotifications(String userId) async {
    final messaging = FirebaseMessaging.instance;

    // Request permission for iOS and web
    await messaging.requestPermission();

    // Get the token and save it to the user's document
    try {
      final token = await messaging.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(userId).update({
          'fcmToken': token,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error getting or saving FCM token: $e');
    }

    // TODO: Handle foreground messages if needed (e.g., show a custom toast)
  }

  void dispose() {
    _authSubscription?.cancel();
    _notificationSubscription?.cancel();
  }
}