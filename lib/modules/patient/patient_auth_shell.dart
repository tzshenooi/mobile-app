import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'patient_auth_screen.dart';
import 'patient_home_screen.dart';

/// Patient flow: any signed-in user can open patient home (no `drivers` profile required).
class PatientAuthShell extends StatelessWidget {
  const PatientAuthShell({super.key, required this.onBackToRoles});

  final VoidCallback onBackToRoles;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;
        if (session == null) {
          return PatientAuthScreen(onBackToRoles: onBackToRoles);
        }
        return const PatientHomeScreen();
      },
    );
  }
}
