import 'package:flutter/material.dart';

import '../shared/mission_record_evidence_section.dart';
import 'patient_ui.dart';

/// Read-only completed mission record for the patient (My reports).
void showPatientMissionRecordSheet(
  BuildContext context, {
  required Map<String, dynamic> report,
  required Map<String, dynamic> booking,
  String? driverName,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.88;
      final incident = report['incident_category']?.toString() ?? 'Report';
      final when = _formatWhen(
        booking['discharge_completed_at'] ??
            booking['created_at'] ??
            report['created_at'],
      );

      return SizedBox(
        height: maxH,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.paddingOf(ctx).bottom + 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      incident,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mission record',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    _row('Status', 'Completed'),
                    if (when != null) _row('Completed', when),
                    if (driverName != null && driverName.isNotEmpty)
                      _row('Driver', driverName),
                    _row('Pickup', booking['location']?.toString() ?? '—'),
                    MissionRecordEvidenceSection(
                      booking: booking,
                      patientReportId: report['id']?.toString(),
                      forPatient: true,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.paddingOf(ctx).bottom + 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(backgroundColor: PatientUi.accentRed),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

String? _formatWhen(dynamic raw) {
  if (raw == null) return null;
  final d = DateTime.tryParse(raw.toString());
  if (d == null) return null;
  final local = d.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '${local.day}/${local.month}/${local.year} $h:$m';
}

Widget _row(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.blueGrey),
          ),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 14, color: Color(0xFF334155))),
        ),
      ],
    ),
  );
}
