import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_role_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onBackToRoles});

  final VoidCallback onBackToRoles;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  final Color primaryBlue = const Color(0xFF1E40AF);
  final Color bgGray = const Color(0xFFF8FAFC);

  String _friendlyAuthError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('invalid login') || msg.contains('invalid_credentials')) {
      return 'Wrong email or password.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Confirm your email first (check inbox), or ask your clinic to register you with email already confirmed.';
    }
    if (msg.contains('network') || msg.contains('socket')) {
      return 'Network error. Check internet and try again.';
    }
    return 'Login failed: $e';
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar('Please enter both email and password.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = response.user;
      if (user == null) {
        _showSnackBar('Login failed. No user returned.');
        return;
      }

      final client = Supabase.instance.client;
      final denied = await AuthRoleService.driverAccessDeniedReason(client, user);
      if (denied != null) {
        await client.auth.signOut();
        if (mounted) _showSnackBar(denied);
        return;
      }
    } catch (e) {
      if (mounted) _showSnackBar(_friendlyAuthError(e));
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
      appBar: AppBar(
        backgroundColor: bgGray,
        foregroundColor: primaryBlue,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: widget.onBackToRoles),
        title: const Text('Driver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
      ),
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
                    const Text('Driver Login', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                    const SizedBox(height: 10),
                    const Text('Smart Ambulance Dispatch', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 8),
                    const Text(
                      'Use the email and password your clinic gave you after they add you as a driver.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 25),
                    _buildInputField(_emailController, 'Email Address', Icons.mail_outline),
                    _buildInputField(_passwordController, 'Password', Icons.lock_outline, isPass: true),
                    const SizedBox(height: 25),
                    _buildActionButton('Sign In', _handleLogin, isLoading: _isLoading),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() => Container(
        width: 80,
        height: 80,
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
            enabledBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.transparent)),
            focusedBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: primaryBlue)),
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
