import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'dart:io' show Platform;
import 'login_page.dart';
import 'register_page.dart';
import 'firebase_options.dart';
import 'admin_login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize Firebase using FlutterFire
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("✅ Firebase initialized successfully!");
  } catch (e) {
    print("❌ Firebase initialization error: $e");
  }
  
  runApp(const BlindFriendApp());
}

class BlindFriendApp extends StatelessWidget {
  const BlindFriendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlindFriend',
      theme: ThemeData(
        primarySwatch: Colors.purple,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/admin': (context) {
          final isDesktop = !kIsWeb &&
              (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
          return isDesktop
              ? const AdminLoginPage()
              : const Scaffold(
                  body: Center(child: Text('Admin portal is desktop only.')),
                );
        },
      },
      debugShowCheckedModeBanner: false,
    );
  }
}