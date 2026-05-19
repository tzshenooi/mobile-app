import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_role_service.dart';

/// Patient sign-in / sign-up — layout matches clinic patient login mock (red shield, white card).
class PatientAuthScreen extends StatefulWidget {
  const PatientAuthScreen({super.key, required this.onBackToRoles});

  final VoidCallback onBackToRoles;

  @override
  State<PatientAuthScreen> createState() => _PatientAuthScreenState();
}

class _PatientAuthScreenState extends State<PatientAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registerMode = false;
  bool _loading = false;

  /// Matches main app scaffold / mock red.
  static const Color _brandRed = Color(0xFFE74C3C);

  /// Screen & field backgrounds like the mock.
  static const Color _screenGray = Color(0xFFF2F4F7);
  static const Color _fieldFill = Color(0xFFEBEEF4);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _password.text;
    if (email.isEmpty || pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter email and password (≥6 characters).')));
      return;
    }

    setState(() => _loading = true);
    try {
      if (_registerMode) {
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: pass,
          data: const {'role': 'patient'},
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check your inbox if verification is enabled, then sign in.')),
        );
      } else {
        final client = Supabase.instance.client;
        await client.auth.signInWithPassword(email: email, password: pass);
        final user = client.auth.currentUser;
        if (user == null) return;

        final denied = await AuthRoleService.patientAccessDeniedReason(client, user);
        if (denied != null && mounted) {
          await client.auth.signOut();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(denied)));
          return;
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _fieldDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 15),
      prefixIcon: Icon(icon, color: Colors.grey.shade700, size: 22),
      filled: true,
      fillColor: _fieldFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: _screenGray,
      appBar: AppBar(
        // Same color as scaffold so there is no 'extra white slab' seam under the toolbar
        // (Driver login uses one tone for app bar + body for the same reason).
        backgroundColor: _screenGray,
        foregroundColor: accent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: widget.onBackToRoles,
        ),
        title: Text(
          'Patient',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: accent),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PatientLogoBadge(red: _brandRed),
              const SizedBox(height: 28),
              Material(
                color: Colors.white,
                elevation: 2,
                shadowColor: Colors.black.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                              Text(
                                _registerMode ? 'Patient Register' : 'Patient Login',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _registerMode ? 'Create an account to request help.' : 'Request an ambulance, anywhere.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 14, height: 1.4, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 28),
                              TextField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(fontSize: 15),
                                decoration: _fieldDecoration('Email Address', Icons.mail_outline_rounded),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _password,
                                obscureText: true,
                                style: const TextStyle(fontSize: 15),
                                decoration: _fieldDecoration('Password', Icons.lock_outline_rounded),
                              ),
                              const SizedBox(height: 26),
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _brandRed,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: _loading ? null : _submit,
                                  child: _loading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                                        )
                                      : Text(
                                          _registerMode ? 'REGISTER' : 'SIGN IN',
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.5),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Align(
                                alignment: Alignment.center,
                                child: TextButton(
                                  onPressed: () => setState(() => _registerMode = !_registerMode),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _brandRed,
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: Text(
                                    _registerMode ? 'Already registered? Sign in' : 'New patient? Register here',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Red rounded square — white shield with red medical cross (mock branding).
class _PatientLogoBadge extends StatelessWidget {
  const _PatientLogoBadge({required this.red});

  final Color red;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: red,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: red.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 8)),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.shield_rounded, color: Colors.white, size: 58),
            SizedBox(
              width: 24,
              height: 24,
              child: CustomPaint(painter: _CrossPainter(color: red)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple plus-shaped cross centered on shield.
class _CrossPainter extends CustomPainter {
  _CrossPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = min(size.shortestSide * 0.22, 4.0);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final vLen = size.height * 0.72;
    final hLen = size.width * 0.72;

    final p = Paint()..color = color..strokeWidth = stroke..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(cx, cy - vLen / 2), Offset(cx, cy + vLen / 2), p);
    canvas.drawLine(Offset(cx - hLen / 2, cy), Offset(cx + hLen / 2, cy), p);
  }

  @override
  bool shouldRepaint(covariant _CrossPainter oldDelegate) => oldDelegate.color != color;
}
