import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/app_launch_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/app_env.dart';
import 'services/app_notification_service.dart';
import 'widgets/device_lock_gate.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppEnv.load();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Firebase may already be initialized after hot restart.
  }

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _notificationsBootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_notificationsBootstrapped) return;
    _notificationsBootstrapped = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeNotifications());
    });
  }

  Future<void> _initializeNotifications() async {
    try {
      await AppNotificationService.initialize(navigatorKey: appNavigatorKey);
    } catch (error, stackTrace) {
      debugPrint('Notification initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialScreen = FirebaseAuth.instance.currentUser == null
        ? const AuthScreen()
        : const DeviceLockGate(child: HomeScreen(requireAuth: false));

    return MaterialApp(
      title: 'Stayfix Job',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: AppLaunchScreen(nextScreen: initialScreen),
    );
  }
}
