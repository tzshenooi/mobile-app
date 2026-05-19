import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_role_service.dart';
import 'patient_auth_screen.dart';
import 'patient_home_screen.dart';

/// Patient flow: signed-in user must not be a driver account.
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
        return _PatientGate(userId: session.user.id, onBackToRoles: onBackToRoles);
      },
    );
  }
}

class _PatientGate extends StatelessWidget {
  const _PatientGate({required this.userId, required this.onBackToRoles});

  final String userId;
  final VoidCallback onBackToRoles;

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return FutureBuilder<String?>(
      future: () async {
        final user = client.auth.currentUser;
        if (user == null || user.id != userId) return 'Sign in again.';
        return AuthRoleService.patientAccessDeniedReason(client, user);
      }(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final denied = snap.data;
        if (denied != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await client.auth.signOut();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(denied)));
            }
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        return const PatientHomeScreen();
      },
    );
  }
}
