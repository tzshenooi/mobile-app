import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../shared/mission_chat_panel.dart';
import 'driver_ui.dart';

/// Driver ↔ patient chat while on duty with an active patient-report mission.
class DriverPatientChatTab extends StatefulWidget {
  const DriverPatientChatTab({
    super.key,
    required this.driverId,
    required this.isOnDuty,
    this.activeBooking,
  });

  final String driverId;
  final bool isOnDuty;
  final Map<String, dynamic>? activeBooking;

  @override
  State<DriverPatientChatTab> createState() => _DriverPatientChatTabState();
}

class _DriverPatientChatTabState extends State<DriverPatientChatTab> {
  String? _patientLabel;
  bool _hasPatientApp = false;

  @override
  void initState() {
    super.initState();
    _resolvePatient();
  }

  @override
  void didUpdateWidget(covariant DriverPatientChatTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeBooking?['id'] != widget.activeBooking?['id']) {
      _resolvePatient();
    }
  }

  Future<void> _resolvePatient() async {
    final booking = widget.activeBooking;
    final reportId = booking?['patient_report_id']?.toString();
    if (reportId == null || reportId.isEmpty) {
      setState(() {
        _hasPatientApp = false;
        _patientLabel = booking?['patient_name']?.toString() ?? 'Patient';
      });
      return;
    }

    setState(() {
      _hasPatientApp = true;
      _patientLabel = booking?['patient_name']?.toString() ?? 'Patient';
    });

    try {
      final row = await Supabase.instance.client
          .from('patient_reports')
          .select('reporter_name')
          .eq('id', reportId)
          .maybeSingle();
      final reporter = row?['reporter_name']?.toString().trim();
      if (reporter != null && reporter.isNotEmpty && mounted) {
        setState(() => _patientLabel = reporter);
      }
    } catch (_) {}
  }

  static const _driverQuickReplies = [
    'Ambulance is on the way',
    'We have arrived',
    'Patient secured — heading to destination',
    'Delayed due to traffic',
  ];

  @override
  Widget build(BuildContext context) {
    final booking = widget.activeBooking;
    final bookingId = booking?['id']?.toString();
    final patientName = _patientLabel ?? 'Patient';

    String? disabledHint;
    var enabled = false;
    if (!widget.isOnDuty) {
      disabledHint = 'Go online on the Home tab to message the patient.';
    } else if (bookingId == null) {
      disabledHint = 'No active mission. Chat opens when you accept a patient report dispatch.';
    } else if (!_hasPatientApp) {
      disabledHint =
          'This dispatch is not linked to a patient app user (e.g. clinic transfer). Use clinic contact instead.';
    } else {
      enabled = true;
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [DriverUi.primaryBlue, DriverUi.darkBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.forum_outlined, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Patient chat',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        enabled ? patientName : 'On duty — patient channel',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (booking != null && enabled)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DriverUi.primaryBlue.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, color: DriverUi.primaryBlue, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active mission',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.blueGrey),
                        ),
                        Text(
                          booking['patient_name']?.toString() ?? patientName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              child: enabled && bookingId != null
                  ? MissionChatPanel(
                      bookingId: bookingId,
                      isDriver: true,
                      peerLabel: patientName,
                      enabled: true,
                      quickReplies: _driverQuickReplies,
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          disabledHint ?? 'Chat unavailable.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.blueGrey, height: 1.45),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
