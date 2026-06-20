import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_nav.dart';
import 'driver_change_password_screen.dart';
import 'driver_edit_contact_screen.dart';
import 'driver_ui.dart';

/// Driver account and status (Profile tab).
class DriverProfileTab extends StatefulWidget {
  const DriverProfileTab({super.key, required this.driverId, this.onSignOut});

  final String driverId;
  final VoidCallback? onSignOut;

  @override
  State<DriverProfileTab> createState() => _DriverProfileTabState();
}

class _DriverProfileTabState extends State<DriverProfileTab> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _driver;
  String? _clinicName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final driver = await _client
          .from('drivers')
          .select('name, email, phone_number, ic_number, status, base_clinic_id')
          .eq('id', widget.driverId)
          .maybeSingle();
      String? clinicName;
      final clinicId = driver?['base_clinic_id']?.toString();
      if (clinicId != null && clinicId.isNotEmpty) {
        final clinic = await _client.from('clinics').select('name').eq('id', clinicId).maybeSingle();
        clinicName = clinic?['name']?.toString();
      }
      if (!mounted) return;
      setState(() {
        _driver = driver != null ? Map<String, dynamic>.from(driver) : null;
        _clinicName = clinicName;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChangePassword() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const DriverChangePasswordScreen()),
    );
  }

  Future<void> _openEditContact() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DriverEditContactScreen(
          driverId: widget.driverId,
          initialPhone: _driver?['phone_number']?.toString(),
          initialIc: _driver?['ic_number']?.toString(),
        ),
      ),
    );
    if (saved == true) await _load();
  }

  String _contactValue(String? raw) {
    final v = raw?.trim();
    return (v != null && v.isNotEmpty) ? v : 'Not set — tap Edit contact';
  }

  bool _isUnset(String? raw) {
    final v = raw?.trim();
    return v == null || v.isEmpty;
  }

  Future<void> _signOut() async {
    if (widget.onSignOut != null) {
      widget.onSignOut!();
      return;
    }
    await _client.auth.signOut();
    rootNavigatorKey.currentState?.pushNamedAndRemoveUntil('/roles', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final authEmail = _client.auth.currentUser?.email;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [DriverUi.primaryBlue, DriverUi.darkBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  child: const Icon(Icons.person, size: 44, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  _driver?['name']?.toString() ?? 'Driver',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusLabel(_driver?['status']),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: DriverUi.primaryBlue))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                    children: [
                      _infoCard('Account', [
                        _row('Email', _driver?['email']?.toString() ?? authEmail ?? '—'),
                        _row('Phone', _contactValue(_driver?['phone_number']?.toString()), muted: _isUnset(_driver?['phone_number']?.toString())),
                        _row('IC no.', _contactValue(_driver?['ic_number']?.toString()), muted: _isUnset(_driver?['ic_number']?.toString())),
                      ]),
                      const SizedBox(height: 14),
                      _infoCard('Clinic', [
                        _row('Base clinic', _clinicName ?? 'Not linked'),
                      ]),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: _openEditContact,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit contact details'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          foregroundColor: DriverUi.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _openChangePassword,
                        icon: const Icon(Icons.lock_reset_outlined),
                        label: const Text('Change password'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          foregroundColor: DriverUi.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh profile'),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _signOut,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(dynamic status) {
    final s = (status ?? 'Offline').toString();
    switch (s) {
      case 'Available':
        return 'Online — available for dispatch';
      case 'Busy':
        return 'On mission';
      default:
        return 'Offline';
    }
  }

  Widget _infoCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.06, color: Colors.blueGrey),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool muted = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: muted ? Colors.blueGrey : const Color(0xFF1E293B),
                fontStyle: muted ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
