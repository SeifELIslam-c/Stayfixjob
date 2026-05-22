import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'services/app_env.dart';
import 'screens/app_launch_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/device_lock_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppEnv.load();
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    // Firebase already initialized (hot restart) or config error — safe to continue.
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final initialScreen = FirebaseAuth.instance.currentUser == null
        ? const AuthScreen()
        : const DeviceLockGate(child: HomeScreen(requireAuth: false));

    return MaterialApp(
      title: 'Hotel Lux Profile',
      debugShowCheckedModeBanner: false,
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
