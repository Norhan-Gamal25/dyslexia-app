import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VerbixApp());
}

class VerbixApp extends StatelessWidget {
  const VerbixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verbix',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}