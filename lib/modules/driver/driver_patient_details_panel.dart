import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _incidentLabels = <String, String>{
  'fire': 'Fire',
  'crime': 'Crime',
  'medical_aid': 'Medical Aid',
  'humanitarian_aid': 'Humanitarian Aid',
  'sea_emergency': 'Sea Emergency',
};

String incidentCategoryLabel(String? key) {
  if (key == null || key.trim().isEmpty) return '';
  final k = key.trim();
  if (_incidentLabels.containsKey(k)) return _incidentLabels[k]!;
  if (k.contains('_')) {
    return k.split('_').map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
  }
  return k;
}

/// Caller / incident details for driver active mission card.
class DriverPatientDetailsPanel extends StatefulWidget {
  const DriverPatientDetailsPanel({
    super.key,
    required this.booking,
    this.accentColor,
  });

  final Map<String, dynamic>? booking;
  final Color? accentColor;

  @override
  State<DriverPatientDetailsPanel> createState() => _DriverPatientDetailsPanelState();
}

class _DriverPatientDetailsPanelState extends State<DriverPatientDetailsPanel> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _report;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadReportFallback();
  }

  @override
  void didUpdateWidget(covariant DriverPatientDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.booking?['id'] != widget.booking?['id'] ||
        oldWidget.booking?['patient_report_id'] != widget.booking?['patient_report_id']) {
      _loadReportFallback();
    }
  }

  Future<void> _loadReportFallback() async {
    final booking = widget.booking;
    final reportId = booking?['patient_report_id']?.toString();
    if (reportId == null || reportId.isEmpty) {
      if (mounted) setState(() => _report = null);
      return;
    }

    final hasBookingDetails =
        _nonEmpty(booking?['notes']) && _nonEmpty(booking?['emergency_type']);
    if (hasBookingDetails) {
      if (mounted) setState(() => _report = null);
      return;
    }

    setState(() => _loading = true);
    try {
      final row = await _client
          .from('patient_reports')
          .select('details, incident_category, patient_id, reporter_name')
          .eq('id', reportId)
          .maybeSingle();
      if (mounted) setState(() => _report = row == null ? null : Map<String, dynamic>.from(row));
    } catch (_) {
      if (mounted) setState(() => _report = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _nonEmpty(dynamic v) => v != null && v.toString().trim().isNotEmpty;

  String? _text(String? primary, String? fallback) {
    final a = primary?.trim();
    if (a != null && a.isNotEmpty) return a;
    final b = fallback?.trim();
    return (b != null && b.isNotEmpty) ? b : null;
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    if (booking == null) return const SizedBox.shrink();

    final patientId = _text(booking['patient_id']?.toString(), _report?['patient_id']?.toString());
    final emergency = _text(
      booking['emergency_type']?.toString(),
      incidentCategoryLabel(_report?['incident_category']?.toString()),
    );
    final notes = _text(booking['notes']?.toString(), _report?['details']?.toString());
    final caller = _text(booking['patient_name']?.toString(), _report?['reporter_name']?.toString());

    if (patientId == null && emergency == null && notes == null && caller == null) {
      return _loading
          ? const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : const SizedBox.shrink();
    }

    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PATIENT DETAILS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: accent.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 10),
          if (caller != null) _row('Caller', caller),
          if (patientId != null) _row('Patient ID', patientId),
          if (emergency != null) _row('Emergency', emergency),
          if (notes != null) _row('Details', notes, multiline: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: const Color(0xFF334155),
              height: multiline ? 1.35 : 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
