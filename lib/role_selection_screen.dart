import 'package:flutter/material.dart';

import 'modules/auth/driver_auth_shell.dart';
import 'modules/patient/patient_auth_shell.dart';

/// First screen — user picks driver vs patient flow (same app, separate Supabase checks).
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                'Smart Ambulance',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Who is using this device?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
              ),
              const Spacer(),
              _RoleCard(
                icon: Icons.local_hospital_rounded,
                title: 'Ambulance driver',
                subtitle: 'Receive dispatches, navigation, and mission photos.',
                color: accent,
                onTap: () {
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
                },
              ),
              const SizedBox(height: 16),
              _RoleCard(
                icon: Icons.health_and_safety_outlined,
                title: 'Patient / bystander',
                subtitle: 'Report a medical emergency or call your clinic from the app.',
                color: const Color(0xFFC62828),
                onTap: () {
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
                },
              ),
              const Spacer(),
              Text(
                'Use the correct role so your account is checked against the right profile.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
              ),
            ],
          ),
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
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
