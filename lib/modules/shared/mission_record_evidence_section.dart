import 'package:flutter/material.dart';

import '../driver/driver_ui.dart';
import '../patient/patient_media_preview.dart';
import '../patient/patient_ui.dart';
import 'mission_chat_transcript_panel.dart';
import 'patient_report_attachments_panel.dart';

/// All evidence for one completed mission (driver or patient records).
class MissionRecordEvidenceSection extends StatelessWidget {
  const MissionRecordEvidenceSection({
    super.key,
    required this.booking,
    this.patientReportId,
    this.forPatient = false,
  });

  final Map<String, dynamic> booking;
  /// Used when the booking row has no `patient_report_id` (patient view).
  final String? patientReportId;
  final bool forPatient;

  @override
  Widget build(BuildContext context) {
    final bookingId = booking['id']?.toString();
    final reportId =
        patientReportId ?? booking['patient_report_id']?.toString();
    final accent = forPatient ? PatientUi.accentRed : DriverUi.primaryBlue;
    final sceneUrl = (booking['scene_photo'] ?? '').toString().trim();
    final handoverUrl = (booking['handover_photo'] ?? '').toString().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _EvidenceHeading('Evidence on file'),
        if (sceneUrl.isNotEmpty) ...[
          const _EvidenceSubheading('Scene photo (driver)'),
          RemoteAttachmentPreview(
            name: 'scene.jpg',
            url: sceneUrl,
            kind: 'image',
            accentColor: accent,
          ),
          const SizedBox(height: 12),
        ],
        if (handoverUrl.isNotEmpty) ...[
          const _EvidenceSubheading('Handover photo (driver)'),
          RemoteAttachmentPreview(
            name: 'handover.jpg',
            url: handoverUrl,
            kind: 'image',
            accentColor: accent,
          ),
          const SizedBox(height: 12),
        ],
        if (sceneUrl.isEmpty && handoverUrl.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'No driver photos stored for this mission.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
        if (reportId != null && reportId.isNotEmpty) ...[
          PatientReportAttachmentsPanel(
            patientReportId: reportId,
            title: forPatient
                ? 'Your attachments (voice / photo / video)'
                : 'Patient report media (voice / photo / video)',
            useCurrentUserAsReporter: forPatient,
            accentColor: accent,
          ),
          const SizedBox(height: 12),
        ],
        if (bookingId != null && bookingId.isNotEmpty)
          MissionChatTranscriptPanel(
            bookingId: bookingId,
            isDriverView: !forPatient,
            accentColor: accent,
          ),
      ],
    );
  }
}

class _EvidenceHeading extends StatelessWidget {
  const _EvidenceHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }
}

class _EvidenceSubheading extends StatelessWidget {
  const _EvidenceSubheading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.blueGrey),
      ),
    );
  }
}
