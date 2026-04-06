import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'register_screen.dart'; // Make sure this path is correct
import '../driver/driver_home.dart'; // Make sure this path is correct

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  final Color primaryBlue = const Color(0xFF1E40AF);
  final Color bgGray = const Color(0xFFF8FAFC);

  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar("Please enter both email and password.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (response.user != null && mounted) {
        // Navigate to Driver Home on success
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DriverHome()),
        );
      }
    } catch (e) {
      if (mounted) _showSnackBar("Login Failed: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red[800], behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLogo(),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
                ),
                child: Column(
                  children: [
                    const Text("Driver Login", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                    const SizedBox(height: 10),
                    const Text("Smart Ambulance Dispatch", style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 25),
                    _buildInputField(_emailController, "Email Address", Icons.mail_outline),
                    _buildInputField(_passwordController, "Password", Icons.lock_outline, isPass: true),
                    const SizedBox(height: 25),
                    _buildActionButton("Sign In", _handleLogin, isLoading: _isLoading),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RegisterScreen()),
                        );
                      },
                      child: Text("Don't have an account? Register here", style: TextStyle(color: primaryBlue)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 🎨 UI HELPERS ---

  Widget _buildLogo() => Container(
    width: 80, height: 80,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [primaryBlue, const Color(0xFF1E3A8A)]),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Icon(Icons.shield, color: Colors.white, size: 40),
  );

  Widget _buildInputField(TextEditingController ctrl, String hint, IconData icon, {bool isPass = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: TextField(
      controller: ctrl,
      obscureText: isPass,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 18),
        hintText: hint,
        filled: true,
        fillColor: bgGray,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.transparent)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: primaryBlue)),
      ),
    ),
  );

  Widget _buildActionButton(String text, VoidCallback onPressed, {bool isLoading = false}) => SizedBox(
    width: double.infinity,
    height: 55,
    child: ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
      child: isLoading 
        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
        : Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
    ),
  );
}