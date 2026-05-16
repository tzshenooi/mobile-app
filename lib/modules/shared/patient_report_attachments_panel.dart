import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../patient/patient_media_preview.dart';
import '../patient/patient_ui.dart';

/// Voice / photo / video attached to a patient report (clinic, driver, or patient view).
class PatientReportAttachmentsPanel extends StatefulWidget {
  const PatientReportAttachmentsPanel({
    super.key,
    required this.patientReportId,
    this.title = 'Patient attachments',
    this.inlinePreview = true,
    this.useCurrentUserAsReporter = false,
    this.accentColor,
  });

  final String patientReportId;
  final String title;
  /// When true, show image / video / audio players inline.
  final bool inlinePreview;
  /// Patient viewing own uploads — skip extra report row read.
  final bool useCurrentUserAsReporter;
  final Color? accentColor;

  @override
  State<PatientReportAttachmentsPanel> createState() => _PatientReportAttachmentsPanelState();
}

class _AttachmentItem {
  _AttachmentItem({required this.name, required this.path, required this.kind});

  final String name;
  final String path;
  final String kind;
  String? signedUrl;
}

class _PatientReportAttachmentsPanelState extends State<PatientReportAttachmentsPanel> {
  static const _bucket = 'patient-reports';

  final _client = Supabase.instance.client;
  List<_AttachmentItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PatientReportAttachmentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientReportId != widget.patientReportId) {
      _load();
    }
  }

  String _guessKind(String name) => attachmentKindFromName(name);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
    });

    try {
      String? reporterId;
      if (widget.useCurrentUserAsReporter) {
        reporterId = _client.auth.currentUser?.id;
      } else {
        final report = await _client
            .from('patient_reports')
            .select('reporter_user_id')
            .eq('id', widget.patientReportId)
            .maybeSingle();
        reporterId = report?['reporter_user_id']?.toString();
      }

      if (reporterId == null || reporterId.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final prefix = '$reporterId/${widget.patientReportId}';
      final bucket = _client.storage.from(_bucket);
      final found = <_AttachmentItem>[];

      final level1 = await bucket.list(path: prefix);
      for (final entry in level1) {
        final subPath = '$prefix/${entry.name}';
        if (entry.id == null) {
          final level2 = await bucket.list(path: subPath);
          for (final file in level2) {
            if (file.id == null) continue;
            found.add(
              _AttachmentItem(
                name: file.name,
                path: '$subPath/${file.name}',
                kind: _guessKind(file.name),
              ),
            );
          }
        } else {
          found.add(
            _AttachmentItem(
              name: entry.name,
              path: subPath,
              kind: _guessKind(entry.name),
            ),
          );
        }
      }

      for (final item in found) {
        item.signedUrl = await bucket.createSignedUrl(item.path, 3600);
      }

      if (!mounted) return;
      setState(() {
        _items = found;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ??
        (widget.useCurrentUserAsReporter ? PatientUi.accentRed : const Color(0xFF2563EB));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.06,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 10),
          if (_loading) LinearProgressIndicator(minHeight: 2, color: accent),
          if (_error != null)
            Text(
              'Could not load attachments.',
              style: TextStyle(fontSize: 12, color: Colors.amber.shade900, height: 1.35),
            ),
          if (!_loading && _error == null && _items.isEmpty)
            const Text('No media attached to this report.', style: TextStyle(fontSize: 13, color: Colors.grey)),
          if (widget.inlinePreview && _items.isNotEmpty)
            ..._items.map(
              (item) => item.signedUrl == null
                  ? const SizedBox.shrink()
                  : RemoteAttachmentPreview(
                      name: item.name,
                      url: item.signedUrl!,
                      kind: item.kind,
                      accentColor: accent,
                    ),
            ),
        ],
      ),
    );
  }
}
