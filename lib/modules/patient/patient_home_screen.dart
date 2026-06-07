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
import 'advance_booking_screen.dart';
import 'patient_mission_record_sheet.dart';
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
            'Clinic phone is not set yet. Ask your clinic to add their contact number when registering or in portal Settings.',
          ),
        ),
      );
      return;
    }

    final digits = contact.phone!.replaceAll(RegExp(r'[^\d+]+'), '');
    final uri = Uri.parse('tel:$digits');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open phone dialer for ${contact.phone}.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not call clinic: $e')),
      );
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
            const SizedBox(height: 16),
            SlideToConfirm(
              label: clinicLoading ? 'Slide to call clinic' : 'Slide to call ${clinic?.name ?? 'clinic'}',
              icon: Icons.local_hospital_rounded,
              subtitle: clinicLoading ? '' : (clinic?.hasPhone == true ? '' : 'No clinic number'),
              trackColor: PatientUi.accentRed,
              onConfirmed: onCall,
            ),
            const SizedBox(height: 22),
            SlideToConfirm(
              label: 'Slide to send report',
              icon: Icons.description_outlined,
              subtitle: '',
              trackColor: PatientUi.accentRed.withValues(alpha: 0.85),
              onConfirmed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const ReportIncidentScreen()),
                );
              },
            ),
            const SizedBox(height: 22),
            SlideToConfirm(
              label: 'Schedule bedridden transport',
              icon: Icons.event_available_outlined,
              subtitle: '',
              trackColor: const Color(0xFF5C6BC0),
              onConfirmed: () {
                Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(builder: (_) => const AdvanceBookingScreen()),
                );
              },
            ),
            const Spacer(),
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
  Future<
      ({
        List<({Map<String, dynamic> report, Map<String, dynamic>? booking, Map<String, dynamic>? driver})> reports,
        List<Map<String, dynamic>> scheduled,
      })>? _future;

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
          ? Future.value((reports: <({Map<String, dynamic> report, Map<String, dynamic>? booking, Map<String, dynamic>? driver})>[], scheduled: <Map<String, dynamic>>[]))
          : _loadAll(client, uid);
    });
  }

  Future<({List<({Map<String, dynamic> report, Map<String, dynamic>? booking, Map<String, dynamic>? driver})> reports, List<Map<String, dynamic>> scheduled})>
      _loadAll(SupabaseClient client, String uid) async {
    final reports = await _loadReports(client, uid);
    final scheduledRows = await client
        .from('bookings')
        .select('id, patient_name, scheduled_at, status, location, is_bedridden, created_at')
        .eq('reporter_user_id', uid)
        .eq('status', 'Scheduled')
        .order('scheduled_at', ascending: true);
    final scheduled = List<Map<String, dynamic>>.from(scheduledRows as List);
    return (reports: reports, scheduled: scheduled);
  }

  Future<void> _cancelScheduled(String bookingId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: const Text('Your clinic will no longer see this scheduled transport.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel booking')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client
          .from('bookings')
          .update({'status': 'Cancelled'})
          .eq('id', bookingId)
          .eq('status', 'Scheduled');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking cancelled.')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _formatScheduled(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      final h = d.hour.toString().padLeft(2, '0');
      final m = d.minute.toString().padLeft(2, '0');
      return '${d.day}/${d.month}/${d.year} $h:$m';
    } catch (_) {
      return iso;
    }
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
                ({
                  List<({Map<String, dynamic> report, Map<String, dynamic>? booking, Map<String, dynamic>? driver})>
                      reports,
                  List<Map<String, dynamic>> scheduled,
                })>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snap.data;
                final rows = data?.reports ?? [];
                final scheduled = data?.scheduled ?? [];
                if (rows.isEmpty && scheduled.isEmpty) {
                  return const Center(child: Text('No reports yet.'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _future;
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (scheduled.isNotEmpty) ...[
                        const Text('Scheduled transport', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ...scheduled.map((b) {
                          final id = b['id']?.toString() ?? '';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(b['patient_name']?.toString() ?? 'Transport'),
                              subtitle: Text(
                                '${_formatScheduled(b['scheduled_at']?.toString())}\n${b['location'] ?? ''}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              isThreeLine: true,
                              trailing: id.isEmpty
                                  ? null
                                  : TextButton(
                                      onPressed: () => _cancelScheduled(id),
                                      child: const Text('Cancel'),
                                    ),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                        if (rows.isNotEmpty)
                          const Text('Emergency reports', style: TextStyle(fontWeight: FontWeight.w700)),
                        if (rows.isNotEmpty) const SizedBox(height: 8),
                      ],
                      ...List.generate(rows.length, (i) {
                      final row = rows[i];
                      final r = row.report;
                      final progress = PatientMissionProgress.build(
                        booking: row.booking,
                        driver: row.driver,
                      );
                      final reportId = r['id']?.toString() ?? '';
                      final canOpen = reportId.isNotEmpty;
                      final booking = row.booking;
                      final status = booking?['status']?.toString() ?? '';
                      final isCompleted = status == 'Completed';

                      return Padding(
                        padding: EdgeInsets.only(bottom: i < rows.length - 1 ? 8 : 0),
                        child: Card(
                          child: ListTile(
                            title: Text('${r['incident_category']}'),
                            subtitle: Text(
                              isCompleted
                                  ? 'Completed · Tap for mission record'
                                  : '${progress.statusLabel}\n${progress.etaLabel}',
                              style: const TextStyle(height: 1.35),
                            ),
                            isThreeLine: true,
                            trailing: canOpen
                                ? Icon(Icons.chevron_right, color: PatientUi.accentRed.withValues(alpha: 0.8))
                                : null,
                            onTap: !canOpen
                                ? null
                                : () {
                                    if (isCompleted && booking != null) {
                                      showPatientMissionRecordSheet(
                                        context,
                                        report: r,
                                        booking: booking,
                                        driverName: progress.driverName,
                                      );
                                      return;
                                    }
                                    Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (_) => AmbulanceTrackingScreen(patientReportId: reportId),
                                      ),
                                    );
                                  },
                          ),
                        ),
                      );
                    }),
                    ],
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

