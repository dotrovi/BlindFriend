import 'package:flutter/material.dart';
import 'login_page.dart';

void main() {
  runApp(const BlindFriendApp());
}

class BlindFriendApp extends StatelessWidget {
  const BlindFriendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlindFriend',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      home: const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}