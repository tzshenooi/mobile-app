import 'package:flutter/material.dart';
import 'modules/auth/login_screen.dart'; // Import the login screen

void main() {
  runApp(const SmartAmbulanceApp());
}

class SmartAmbulanceApp extends StatelessWidget {
  const SmartAmbulanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Ambulance Driver',
      theme: ThemeData(
        // Using Red as the primary color for emergency context
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      // Define the first screen the user sees
      home: const LoginScreen(),
    );
  }
}