import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'modules/auth/login_screen.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 👇 KEEP YOUR KEYS HERE! 
  // (Do not delete your actual keys if you already pasted them)
  await Supabase.initialize(
    url: 'https://yvzylhestgcygwsjbaut.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl2enlsaGVzdGdjeWd3c2piYXV0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjMxMDMsImV4cCI6MjA4MzU5OTEwM30.BAHSq367fKLk9gi0HHQ5vQcHezd9zDVhjrErBdADeoo',
  );

  runApp(const MyApp());
}

// Global variable to access the database anywhere
final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Ambulance',
      
      // 👇 THEME UPDATE: Restoring the Red Design
      theme: ThemeData(
        // Primary Color: Ambulance Red
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE74C3C), 
          primary: const Color(0xFFE74C3C),
        ),
        
        // Background Color: Light Grey (easier on eyes)
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        
        // App Bar Theme (Red Header, White Text)
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFE74C3C),
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 0,
        ),
        
        // Button Theme (Rounded & Red)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE74C3C),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        
        useMaterial3: true,
      ),
      
      home: const LoginScreen(),
    );
  }
}