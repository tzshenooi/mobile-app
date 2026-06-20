import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'patient_home_address_screen.dart';
import 'patient_home_address_service.dart';
import 'patient_settings_screen.dart';
import 'patient_ui.dart';

/// App version shown on profile (keep in sync with pubspec.yaml).
const String kPatientAppVersionLabel = '1.0.0+1 version';

class PatientProfileTab extends StatefulWidget {
  const PatientProfileTab({super.key, required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  State<PatientProfileTab> createState() => _PatientProfileTabState();
}

class _PatientProfileTabState extends State<PatientProfileTab> {
  String? _homeSummary;
  bool _homeLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHome();
  }

  Future<void> _loadHome() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _homeLoading = false);
      return;
    }
    try {
      final home = await PatientHomeAddressService.load(Supabase.instance.client, uid);
      if (!mounted) return;
      setState(() {
        _homeSummary = home?.address;
        _homeLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _homeLoading = false);
    }
  }

  Future<void> _openHomeAddress() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const PatientHomeAddressScreen()),
    );
    if (saved == true) await _loadHome();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PatientSettingsScreen()),
    );
  }

  static String _displayName(User? user) {
    final meta = user?.userMetadata?['name']?.toString().trim();
    if (meta != null && meta.isNotEmpty) return meta.toUpperCase();
    final email = user?.email ?? '';
    final local = email.split('@').first;
    return local.replaceAll(RegExp(r'[._]+'), ' ').trim().toUpperCase();
  }

  void _showAccountSheet(BuildContext context, User? user) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.paddingOf(ctx).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _sheetRow('Name', _displayName(user)),
            _sheetRow('Email', user?.email ?? '—'),
            _sheetRow('User ID', user?.id ?? '—'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(backgroundColor: PatientUi.accentRed),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = _displayName(user);
    final email = user?.email ?? '—';

    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Center(
              child: Text(
                'Profile',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey.shade300,
                    child: Icon(Icons.person, size: 32, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _ProfileMenuTile(
              icon: Icons.home_outlined,
              title: 'Home address',
              subtitle: _homeLoading
                  ? 'Loading…'
                  : (_homeSummary?.isNotEmpty == true
                      ? _homeSummary!
                      : 'Add your home for clinic send-home routing'),
              onTap: _openHomeAddress,
            ),
            _ProfileMenuTile(
              icon: Icons.person_outline,
              title: 'My Profile',
              subtitle: 'Manage your account information',
              onTap: () => _showAccountSheet(context, user),
            ),
            _ProfileMenuTile(
              icon: Icons.settings_outlined,
              title: 'Settings',
              subtitle: 'Account and privacy',
              onTap: _openSettings,
            ),
            const SizedBox(height: 20),
            Material(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: widget.onSignOut,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: PatientUi.accentRed, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Log Out',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: PatientUi.accentRed,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: PatientUi.accentRed),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                kPatientAppVersionLabel,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 24, color: const Color(0xFF6B7280)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
