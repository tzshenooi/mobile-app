import 'package:flutter/material.dart';
import 'dart:convert'; // Helper for handling JSON data
import 'package:http/http.dart' as http; // Helper for making network calls
import '../driver/driver_home.dart'; // Import your driver dashboard

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
    });

    // IMPORTANT: This connects to your Python backend.
    // Use '10.0.2.2' if you are using the standard Android Emulator.
    // If you are using a physical phone, change this to your PC's IP address (e.g., 192.168.0.x)
    const String apiUrl = "http://10.0.2.2:5000/login";

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": _emailController.text,
          "password": _passwordController.text,
        }),
      );

      print("Server Response: ${response.body}"); // Print response to console for debugging

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        // SUCCESS: Login worked! Go to Driver Home.
        if (mounted) {
           Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DriverHomeScreen()),
          );
        }
      } else {
        // FAIL: Login failed (Wrong password or email)
        _showError(data['message'] ?? "Login failed");
      }
    } catch (e) {
      // ERROR: Couldn't connect to server
      print("Error: $e");
      _showError("Connection error. Is 'python app.py' running?");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Smart Ambulance Login")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_hospital, size: 80, color: Colors.red),
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _handleLogin,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Login"),
                  ),
          ],
        ),
      ),
    );
  }
}