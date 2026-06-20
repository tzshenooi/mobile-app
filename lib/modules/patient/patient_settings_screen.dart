import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_nav.dart';
import 'patient_account_service.dart';
import 'patient_ui.dart';

class PatientSettingsScreen extends StatefulWidget {
  const PatientSettingsScreen({super.key});

  @override
  State<PatientSettingsScreen> createState() => _PatientSettingsScreenState();
}

class _PatientSettingsScreenState extends State<PatientSettingsScreen> {
  final _client = Supabase.instance.client;
  bool _deleting = false;

  Future<void> _confirmDeleteAccount() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently removes your account, home address, and incident reports. '
          'Active ambulance missions may still show anonymised records at the clinic.\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: PatientUi.accentRed),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    setState(() => _deleting = true);
    try {
      await PatientAccountService.deleteOwnAccount(_client);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$e\nIf this mentions a missing function, run patient_delete_account.sql in Supabase.',
          ),
        ),
      );
      setState(() => _deleting = false);
      return;
    }

    try {
      await _client.auth.signOut();
    } catch (_) {
      // Session may already be invalid after user deletion.
    }

    if (!mounted) return;
    rootNavigatorKey.currentState?.pushNamedAndRemoveUntil('/roles', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: PatientUi.accentRed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            'Account',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _deleting ? null : _confirmDeleteAccount,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.delete_forever_outlined, color: PatientUi.accentRed, size: 24),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Delete account',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: PatientUi.accentRed,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Permanently remove your patient account and saved data.',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                    if (_deleting)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: PatientUi.accentRed),
                      )
                    else
                      Icon(Icons.chevron_right, color: PatientUi.accentRed.withValues(alpha: 0.7)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
