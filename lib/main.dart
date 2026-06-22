import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'login_page.dart';
import 'register_page.dart';
import 'firebase_options.dart';
import 'admin_login_page.dart';
import 'admin_dashboard_page.dart';
import 'blind_home_page.dart';
import 'services/accessibility_settings.dart';
import 'services/notification_service.dart';

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

  await AccessibilitySettings.instance.load();

  runApp(const BlindFriendApp());
}

class BlindFriendApp extends StatefulWidget {
  const BlindFriendApp({super.key});

  @override
  State<BlindFriendApp> createState() => _BlindFriendAppState();
}

class _BlindFriendAppState extends State<BlindFriendApp> {
  final AccessibilitySettings _settings = AccessibilitySettings.instance;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    NotificationService().initialize(_navigatorKey);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
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
        '/admin': (context) => const AdminLoginPage(),
        '/admin-dashboard': (context) => const AdminDashboardPage(),
        '/blind-home': (context) => const BlindHomePage(userName: 'User'),
      },
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Keep the wrapper widget tree shape constant across settings
        // changes (only vary the matrix values) - swapping ColorFiltered
        // in and out here would reset the app's entire navigation stack.
        const contrast = 2.2;
        const translate = (1 - contrast) / 2 * 255;
        final matrix = _settings.highContrastEnabled
            ? const <double>[
                contrast, 0, 0, 0, translate,
                0, contrast, 0, 0, translate,
                0, 0, contrast, 0, translate,
                0, 0, 0, 1, 0,
              ]
            : const <double>[
                1, 0, 0, 0, 0,
                0, 1, 0, 0, 0,
                0, 0, 1, 0, 0,
                0, 0, 0, 1, 0,
              ];
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(_settings.fontScale),
          ),
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(matrix),
            child: child!,
          ),
        );
      },
    );
  }
}