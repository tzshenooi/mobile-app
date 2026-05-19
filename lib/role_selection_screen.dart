import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'modules/auth/driver_auth_shell.dart';
import 'modules/patient/patient_auth_shell.dart';

/// First screen — user picks driver vs patient flow (same app, separate Supabase checks).
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  static const Color _driverBlue = Color(0xFF2563EB);
  static const Color _patientRed = Color(0xFFE74C3C);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 28),
              Text(
                'Smart Ambulance',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'Sign in as',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
              const SizedBox(height: 36),
              _RoleCard(
                icon: Icons.health_and_safety_rounded,
                title: 'I need help',
                subtitle: 'Request an ambulance.',
                accent: _patientRed,
                iconBackground: const Color(0xFFFCE8E6),
                onTap: () => _openPatient(context),
              ),
              const SizedBox(height: 14),
              _RoleCard(
                icon: Icons.local_hospital_rounded,
                title: "I'm a driver",
                subtitle: 'Dispatcher & dispatch portal.',
                accent: _driverBlue,
                iconBackground: const Color(0xFFE3EDFF),
                onTap: () => _openDriver(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDriver(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (shellCtx) => DriverAuthShell(
          onBackToRoles: () {
            Navigator.of(shellCtx).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const RoleSelectionScreen()),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openPatient(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (shellCtx) => PatientAuthShell(
          onBackToRoles: () {
            Navigator.of(shellCtx).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const RoleSelectionScreen()),
            );
          },
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.iconBackground,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color iconBackground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1.5,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}
