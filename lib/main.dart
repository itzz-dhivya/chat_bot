import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models/user_model.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/notification_service.dart';
import 'services/user_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize notification service
  try {
    final notificationService = NotificationService();
    await notificationService.initialize();
  } catch (e) {
    debugPrint("Notification init error: $e");
  }

  // Get and register FCM token
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      debugPrint("=================================");
      debugPrint("FCM TOKEN: $token");
      debugPrint("=================================");
      await UserService().updateFcmToken(token);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      debugPrint("NEW FCM TOKEN: $newToken");
      UserService().updateFcmToken(newToken);
    });
  } catch (e) {
    debugPrint("FCM token error: $e");
  }

  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'ChatApp',
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF5B50E6), // Royal Indigo
        scaffoldBackgroundColor: const Color(0xFFF4F6FC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B50E6),
          primary: const Color(0xFF5B50E6),
          secondary: const Color(0xFF7C3AED), // Electric Violet
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFF5B50E6),
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// Determines whether to navigate to HomeScreen or LoginScreen based on user profile state
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final UserService _userService = UserService();
  bool _isChecking = true;
  bool _hasProfile = false;

  @override
  void initState() {
    super.initState();
    _checkUserProfile();
  }

  Future<void> _checkUserProfile() async {
    try {
      await _userService.ensureUserLoggedIn();
      final UserModel? profile = await _userService.getCurrentUserProfile();

      if (mounted) {
        setState(() {
          _hasProfile = profile != null &&
              profile.name.trim().isNotEmpty &&
              profile.phoneNumber.trim().isNotEmpty;
          _isChecking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasProfile = false;
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return Scaffold(
        backgroundColor: const Color(0xFF5B50E6),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.chat_bubble_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'ChatApp',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.8,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasProfile) {
      return HomeScreen(navigatorKey: navigatorKey);
    } else {
      return LoginScreen(navigatorKey: navigatorKey);
    }
  }
}