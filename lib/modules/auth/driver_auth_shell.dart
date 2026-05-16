import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../driver/driver_home.dart';
import 'driver_profile_service.dart';
import 'login_screen.dart';

/// Driver flow: session + valid `drivers` row → [DriverHome], else [LoginScreen].
class DriverAuthShell extends StatelessWidget {
  const DriverAuthShell({super.key, required this.onBackToRoles});

  final VoidCallback onBackToRoles;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;
        if (session == null) {
          return LoginScreen(onBackToRoles: onBackToRoles);
        }
        return _DriverGate(userId: session.user.id, onBackToRoles: onBackToRoles);
      },
    );
  }
}

class _DriverGate extends StatelessWidget {
  const _DriverGate({required this.userId, required this.onBackToRoles});

  final String userId;
  final VoidCallback onBackToRoles;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: DriverProfileService.loadOrCreate(Supabase.instance.client, userId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load driver profile: ${snap.error}', textAlign: TextAlign.center),
              ),
            ),
          );
        }
        if (snap.data == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await Supabase.instance.client.auth.signOut();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('This login is not a driver account. Choose Patient, or register as a driver.'),
                ),
              );
            }
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        return const DriverHome();
      },
    );
  }
}
