import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'driver_ui.dart';

class DriverChangePasswordScreen extends StatefulWidget {
  const DriverChangePasswordScreen({super.key});

  @override
  State<DriverChangePasswordScreen> createState() => _DriverChangePasswordScreenState();
}

class _DriverChangePasswordScreenState extends State<DriverChangePasswordScreen> {
  final _client = Supabase.instance.client;
  final _current = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _current.dispose();
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('invalid login') || msg.contains('invalid_credentials')) {
      return 'Current password is incorrect.';
    }
    if (msg.contains('same_password') || msg.contains('should be different')) {
      return 'New password must be different from your current password.';
    }
    if (msg.contains('weak') || msg.contains('at least')) {
      return 'Choose a stronger password (at least 6 characters).';
    }
    return '$e';
  }

  Future<void> _save() async {
    final email = _client.auth.currentUser?.email?.trim();
    if (email == null || email.isEmpty) {
      _showMessage('No signed-in account found.');
      return;
    }

    final current = _current.text;
    final next = _newPassword.text;
    final confirm = _confirm.text;

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      _showMessage('Fill in all password fields.');
      return;
    }
    if (next.length < 6) {
      _showMessage('New password must be at least 6 characters.');
      return;
    }
    if (next != confirm) {
      _showMessage('New password and confirmation do not match.');
      return;
    }
    if (current == next) {
      _showMessage('New password must be different from your current password.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _client.auth.signInWithPassword(email: email, password: current);
      await _client.auth.updateUser(UserAttributes(password: next));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showMessage(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  InputDecoration _fieldDecoration(String label, {required bool obscure, required VoidCallback onToggle}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      suffixIcon: IconButton(
        onPressed: onToggle,
        icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverUi.bgGray,
      appBar: AppBar(
        title: const Text('Change password'),
        backgroundColor: DriverUi.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            'Enter your current password, then choose a new one. '
            'You will stay signed in after the change.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _current,
            obscureText: !_showCurrent,
            autofillHints: const [AutofillHints.password],
            decoration: _fieldDecoration(
              'Current password',
              obscure: !_showCurrent,
              onToggle: () => setState(() => _showCurrent = !_showCurrent),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _newPassword,
            obscureText: !_showNew,
            autofillHints: const [AutofillHints.newPassword],
            decoration: _fieldDecoration(
              'New password',
              obscure: !_showNew,
              onToggle: () => setState(() => _showNew = !_showNew),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirm,
            obscureText: !_showConfirm,
            autofillHints: const [AutofillHints.newPassword],
            decoration: _fieldDecoration(
              'Confirm new password',
              obscure: !_showConfirm,
              onToggle: () => setState(() => _showConfirm = !_showConfirm),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: DriverUi.primaryBlue,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                  )
                : const Text('Update password', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
