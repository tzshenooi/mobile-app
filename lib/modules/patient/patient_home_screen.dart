import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_nav.dart';
import '../../widgets/slide_to_confirm.dart';
import 'ambulance_tracking_screen.dart';
import 'patient_mission_loader.dart';
import 'patient_mission_progress.dart';
import 'patient_ui.dart';
import 'patient_clinic_contact.dart';
import 'patient_profile_tab.dart';
import 'report_incident_screen.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  int _idx = 0;
  PatientClinicContact? _clinic;
  bool _clinicLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClinic();
  }

  Future<void> _loadClinic() async {
    final contact = await PatientClinicContact.load();
    if (!mounted) return;
    setState(() {
      _clinic = contact;
      _clinicLoading = false;
    });
  }

  String get _greetingName {
    final email = Supabase.instance.client.auth.currentUser?.email ?? 'there';
    return email.split('@').first;
  }

  Future<void> _dialClinic() async {
    final contact = _clinic ?? await PatientClinicContact.load();
    if (!contact.hasPhone) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Clinic phone is not set yet. Ask your clinic to add it in Supabase (clinics.phone) '
            'or build the app with --dart-define=CLINIC_PHONE=…',
          ),
        ),
      );
      return;
    }
    final digits = contact.phone!.replaceAll(RegExp(r'[^\d+]+'), '');
    final uri = Uri.parse('tel:$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _signOutToRoles() async {
    await Supabase.instance.client.auth.signOut();
    rootNavigatorKey.currentState?.pushNamedAndRemoveUntil('/roles', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _PatientHomeTab(
        greetingName: _greetingName,
        clinic: _clinic,
        clinicLoading: _clinicLoading,
        onCall: _dialClinic,
      ),
      const _MyPatientReportsTab(),
      PatientProfileTab(onSignOut: _signOutToRoles),
    ];

    return Scaffold(
      body: pages[_idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        indicatorColor: PatientUi.accentRed.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Report',
          ),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _PatientHomeTab extends StatelessWidget {
  const _PatientHomeTab({
    required this.greetingName,
    required this.clinic,
    required this.clinicLoading,
    required this.onCall,
  });

  final String greetingName;
  final PatientClinicContact? clinic;
  final bool clinicLoading;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () {}, child: const Text('EN')),
            ),
            Text('Hello, $greetingName', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Quick access to emergency assistance.',
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 24),
            SlideToConfirm(
              label: clinicLoading ? 'Slide to call clinic' : 'Slide to call ${clinic?.name ?? 'clinic'}',
              icon: Icons.local_hospital_rounded,
              subtitle: clinicLoading
                  ? 'Loading clinic number…'
                  : (clinic?.hasPhone == true
                      ? 'Speak to ${clinic!.name} dispatch.'
                      : 'Clinic number not configured — contact your clinic.'),
              trackColor: PatientUi.accentRed,
              onConfirmed: onCall,
            ),
            const SizedBox(height: 22),
            SlideToConfirm(
              label: 'Slide to send report',
              icon: Icons.description_outlined,
              subtitle: 'Open the form: map pin, category, details.',
              trackColor: PatientUi.accentRed.withValues(alpha: 0.85),
              onConfirmed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const ReportIncidentScreen()),
                );
              },
            ),
            const Spacer(),
            Text(
              'Need an ambulance on scene? Use Send report below.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyPatientReportsTab extends StatefulWidget {
  const _MyPatientReportsTab();

  @override
  State<_MyPatientReportsTab> createState() => _MyPatientReportsTabState();
}

class _MyPatientReportsTabState extends State<_MyPatientReportsTab> {
  Future<List<({Map<String, dynamic> report, Map<String, dynamic>? booking, Map<String, dynamic>? driver})>>?
      _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    setState(() {
      _future = uid == null
          ? Future.value([])
          : _loadReports(client, uid);
    });
  }

  Future<List<({Map<String, dynamic> report, Map<String, dynamic>? booking, Map<String, dynamic>? driver})>>
      _loadReports(SupabaseClient client, String uid) async {
    final rows = await client
        .from('patient_reports')
        .select('id, incident_category, created_at, status')
        .eq('reporter_user_id', uid)
        .order('created_at', ascending: false)
        .limit(50);
    final reports = List<Map<String, dynamic>>.from(rows as List);
    final out = <({Map<String, dynamic> report, Map<String, dynamic>? booking, Map<String, dynamic>? driver})>[];
    for (final r in reports) {
      final id = r['id']?.toString();
      if (id == null) continue;
      try {
        final mission = await PatientMissionLoader.load(
          client: client,
          patientReportId: id,
          userId: uid,
        );
        out.add((report: mission.report, booking: mission.booking, driver: mission.driver));
      } catch (_) {
        out.add((report: r, booking: null, driver: null));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('My reports', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: FutureBuilder<
                List<({Map<String, dynamic> report, Map<String, dynamic>? booking, Map<String, dynamic>? driver})>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snap.data ?? [];
                if (rows.isEmpty) {
                  return const Center(child: Text('No reports yet.'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _future;
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      final r = row.report;
                      final progress = PatientMissionProgress.build(
                        booking: row.booking,
                        driver: row.driver,
                      );
                      final reportId = r['id']?.toString() ?? '';
                      final canTrack = reportId.isNotEmpty;

                      return Card(
                        child: ListTile(
                          title: Text('${r['incident_category']}'),
                          subtitle: Text(
                            '${progress.statusLabel}\n${progress.etaLabel}',
                            style: const TextStyle(height: 1.35),
                          ),
                          isThreeLine: true,
                          trailing: canTrack
                              ? Icon(Icons.chevron_right, color: PatientUi.accentRed.withValues(alpha: 0.8))
                              : null,
                          onTap: canTrack
                              ? () {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) => AmbulanceTrackingScreen(patientReportId: reportId),
                                    ),
                                  );
                                }
                              : null,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

