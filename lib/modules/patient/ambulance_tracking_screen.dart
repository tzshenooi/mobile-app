import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/local_notification_service.dart';
import 'patient_mission_loader.dart';
import 'patient_mission_progress.dart';
import 'patient_tracking_map.dart';
import 'patient_ui.dart';
import '../shared/mission_chat_panel.dart';
import '../shared/patient_report_attachments_panel.dart';

/// Live ambulance progress + ETA for a patient report.
class AmbulanceTrackingScreen extends StatefulWidget {
  const AmbulanceTrackingScreen({super.key, required this.patientReportId});

  final String patientReportId;

  @override
  State<AmbulanceTrackingScreen> createState() => _AmbulanceTrackingScreenState();
}

class _AmbulanceTrackingScreenState extends State<AmbulanceTrackingScreen>
    with WidgetsBindingObserver {
  final _client = Supabase.instance.client;

  Map<String, dynamic>? _report;
  Map<String, dynamic>? _booking;
  Map<String, dynamic>? _driver;
  Map<String, dynamic>? _clinic;
  bool _loading = true;
  String? _error;
  bool _appInForeground = true;
  String? _lastNotifiedStatus;
  String? _lastNotifiedDriverId;

  RealtimeChannel? _channel;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || _loading) return;
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) throw Exception('Sign in again.');

      final data = await PatientMissionLoader.load(
        client: _client,
        patientReportId: widget.patientReportId,
        userId: uid,
      );

      _report = data.report;
      _booking = data.booking;
      _driver = data.driver;
      await _loadClinicIfNeeded();
      _subscribeRealtime();

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
  }

  Future<void> _maybeNotifyMissionUpdate({
    required Map<String, dynamic>? previous,
    required Map<String, dynamic> next,
  }) async {
    if (_appInForeground) return;

    final status = next['status']?.toString();
    final driverId = next['driver_id']?.toString();
    final driverMap =
        PatientMissionLoader.parseNestedMap(next['drivers']) ?? _driver;
    final driverName = driverMap?['name']?.toString();

    if (driverId != null &&
        previous?['driver_id'] == null &&
        _lastNotifiedDriverId != driverId) {
      _lastNotifiedDriverId = driverId;
      await LocalNotificationService.instance.showPatientMissionStatus(
        status: 'Assigned',
        driverName: driverName,
      );
      return;
    }

    if (status == null || status.isEmpty) return;
    if (_lastNotifiedStatus == status) return;
    const notifyStatuses = {
      'Pending',
      'Assigned',
      'Accepted',
      'En Route',
      'Picked Up',
      'Completed',
      'Cancelled',
    };
    if (!notifyStatuses.contains(status)) return;
    _lastNotifiedStatus = status;
    await LocalNotificationService.instance.showPatientMissionStatus(
      status: status,
      driverName: driverName,
    );
  }

  Future<void> _applyBookingUpdate(Map<String, dynamic> next) async {
    final previous = _booking == null
        ? null
        : Map<String, dynamic>.from(_booking!);
    final prevDriver = _booking?['driver_id'];
    final merged = Map<String, dynamic>.from(_booking ?? {});
    merged.addAll(next);
    setState(() {
      _booking = merged;
      _driver = PatientMissionLoader.parseNestedMap(_booking?['drivers']) ?? _driver;
    });
    await _maybeNotifyMissionUpdate(previous: previous, next: merged);
    if (next['driver_id'] != prevDriver) {
      await _refreshDriver();
      _subscribeRealtime();
    }
    if (next['status'] == 'Picked Up') {
      await _loadClinicIfNeeded();
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadClinicIfNeeded() async {
    _clinic = null;
    final booking = _booking;
    if (booking == null) return;
    if (booking['status']?.toString() != 'Picked Up') return;
    final clinicId = booking['destination_clinic_id']?.toString();
    if (clinicId == null || clinicId.isEmpty) return;

    final row = await _client
        .from('clinics')
        .select('id, name, latitude, longitude')
        .eq('id', clinicId)
        .maybeSingle();
    if (row != null) _clinic = Map<String, dynamic>.from(row);
  }

  void _subscribeRealtime() {
    _channel?.unsubscribe();
    final bookingId = _booking?['id']?.toString();
    final driverId = _booking?['driver_id']?.toString();
    final reportFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'patient_report_id',
      value: widget.patientReportId,
    );

    var ch = _client.channel('patient-track-${widget.patientReportId}');

    Future<void> onBookingPayload(PostgresChangePayload payload) async {
      if (!mounted) return;
      if (payload.eventType == PostgresChangeEvent.delete) return;
      await _applyBookingUpdate(Map<String, dynamic>.from(payload.newRecord));
    }

    ch = ch
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'bookings',
          filter: reportFilter,
          callback: onBookingPayload,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          filter: reportFilter,
          callback: onBookingPayload,
        );

    if (bookingId != null) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'bookings',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: bookingId,
        ),
        callback: onBookingPayload,
      );
    }

    if (driverId != null) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'drivers',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: driverId,
        ),
        callback: (payload) {
          if (!mounted) return;
          setState(() {
            _driver = Map<String, dynamic>.from(payload.newRecord);
          });
        },
      );
    }

    _channel = ch..subscribe();
  }

  Future<void> _refreshDriver() async {
    final driverId = _booking?['driver_id']?.toString();
    if (driverId == null) return;
    final row = await _client
        .from('drivers')
        .select('id, name, current_lat, current_lng, status')
        .eq('id', driverId)
        .maybeSingle();
    if (row != null && mounted) {
      setState(() => _driver = Map<String, dynamic>.from(row));
    }
  }

  LatLng? _ambulanceLatLng() {
    final lat = _driver?['current_lat'];
    final lng = _driver?['current_lng'];
    if (lat == null || lng == null) return null;
    final la = lat is num ? lat.toDouble() : double.tryParse('$lat');
    final ln = lng is num ? lng.toDouble() : double.tryParse('$lng');
    if (la == null || ln == null || !la.isFinite || !ln.isFinite) return null;
    return LatLng(la, ln);
  }

  @override
  Widget build(BuildContext context) {
    final progress = PatientMissionProgress.build(
      booking: _booking,
      driver: _driver,
      clinic: _clinic,
    );
    final dest = progress.destination;
    final reportLat = _report?['latitude'];
    final reportLng = _report?['longitude'];
    final fallbackDest = (reportLat != null && reportLng != null)
        ? LatLng(
            reportLat is num ? reportLat.toDouble() : double.parse('$reportLat'),
            reportLng is num ? reportLng.toDouble() : double.parse('$reportLng'),
          )
        : const LatLng(PatientUi.malaysiaDefaultLat, PatientUi.malaysiaDefaultLng);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ambulance progress'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    children: [
                      PatientTrackingMap(
                        destination: dest != null ? LatLng(dest.lat, dest.lng) : fallbackDest,
                        ambulancePosition: _ambulanceLatLng(),
                        height: 300,
                      ),
                      const SizedBox(height: 20),
                      _EtaCard(progress: progress),
                      if (_booking == null) ...[
                        const SizedBox(height: 12),
                        _SetupHintBanner(
                          message:
                              'Clinic has not linked a dispatch yet, or the app cannot read it. '
                              'After the clinic taps “Send ambulance”, this screen updates automatically. '
                              'If it stays here, run web-app/supabase/patient_tracking_rls.sql in Supabase.',
                        ),
                      ] else if (_booking?['driver_id'] == null) ...[
                        const SizedBox(height: 12),
                        _SetupHintBanner(
                          message:
                              'Your report is with the clinic. Progress moves to “Ambulance assigned” '
                              'when they dispatch a driver from the clinic portal.',
                        ),
                      ],
                      const SizedBox(height: 16),
                      _ProgressSteps(currentStep: progress.stepIndex),
                      const SizedBox(height: 16),
                      if (progress.driverName != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.local_shipping_outlined, color: Colors.grey.shade700),
                          title: const Text('Assigned unit'),
                          subtitle: Text(progress.driverName!),
                        ),
                      if (dest != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.flag_outlined, color: Colors.grey.shade700),
                          title: Text(
                            (_booking?['status']?.toString() == 'Picked Up')
                                ? 'Heading to'
                                : 'Incident',
                          ),
                          subtitle: Text(dest.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      Text(
                        _report?['incident_category']?.toString() ?? 'Report',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      PatientReportAttachmentsPanel(
                        patientReportId: widget.patientReportId,
                        title: 'Your attachments',
                        inlinePreview: true,
                        useCurrentUserAsReporter: true,
                      ),
                      if (!progress.isActive)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'This mission is no longer active.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      if (_booking != null &&
                          _booking!['driver_id'] != null &&
                          kPatientActiveMissionStatuses.contains(_booking!['status']?.toString())) ...[
                        const SizedBox(height: 20),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: MissionChatPanel(
                              bookingId: _booking!['id'].toString(),
                              isDriver: false,
                              peerLabel: progress.driverName ?? 'your driver',
                              enabled: true,
                              compact: true,
                              quickReplies: const [
                                'I am at the pickup location',
                                'Please hurry',
                                'Thank you',
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _SetupHintBanner extends StatelessWidget {
  const _SetupHintBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: Colors.amber.shade900),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 13, height: 1.35, color: Colors.amber.shade900)),
          ),
        ],
      ),
    );
  }
}

class _EtaCard extends StatelessWidget {
  const _EtaCard({required this.progress});

  final PatientMissionProgressView progress;

  @override
  Widget build(BuildContext context) {
    final accent = PatientUi.accentRed;
    final bigEta = progress.etaMinutes != null ? '${progress.etaMinutes}' : '—';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(progress.statusLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (progress.etaMinutes != null) ...[
                Text(
                  bigEta,
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('min', style: TextStyle(fontSize: 18, color: accent.withValues(alpha: 0.85))),
                ),
                const Spacer(),
              ],
              Expanded(
                child: Text(
                  progress.etaLabel,
                  textAlign: progress.etaMinutes != null ? TextAlign.end : TextAlign.start,
                  style: TextStyle(color: Colors.grey.shade800, height: 1.35),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressSteps extends StatelessWidget {
  const _ProgressSteps({required this.currentStep});

  final int currentStep;

  static const _labels = [
    'Report sent',
    'Ambulance assigned',
    'En route to you',
    'Picked up',
    'Completed',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Progress', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),
        for (var i = 0; i < _labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  i <= currentStep ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 22,
                  color: i <= currentStep ? PatientUi.accentRed : Colors.grey.shade400,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _labels[i],
                    style: TextStyle(
                      fontWeight: i == currentStep ? FontWeight.w600 : FontWeight.normal,
                      color: i <= currentStep ? Colors.black87 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
