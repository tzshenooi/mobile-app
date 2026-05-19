import 'package:flutter/material.dart';

import '../driver/driver_ui.dart';
import 'mission_chat_service.dart';

/// Read-only mission chat for completed records (evidence).
class MissionChatTranscriptPanel extends StatefulWidget {
  const MissionChatTranscriptPanel({
    super.key,
    required this.bookingId,
    this.isDriverView = true,
    this.accentColor,
  });

  final String bookingId;
  final bool isDriverView;
  final Color? accentColor;

  @override
  State<MissionChatTranscriptPanel> createState() => _MissionChatTranscriptPanelState();
}

class _MissionChatTranscriptPanelState extends State<MissionChatTranscriptPanel> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MissionChatTranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await MissionChatService.loadMessages(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _messages = rows;
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
    final accent = widget.accentColor ?? DriverUi.primaryBlue;

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
          const Text(
            'MISSION CHAT (RECORD)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.06,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 8),
          if (_loading) LinearProgressIndicator(minHeight: 2, color: accent),
          if (_error != null)
            Text(
              'Could not load chat history.',
              style: TextStyle(fontSize: 12, color: Colors.amber.shade900, height: 1.35),
            ),
          if (!_loading && _error == null && _messages.isEmpty)
            const Text(
              'No chat messages on this mission.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          if (!_loading && _messages.isNotEmpty)
            ..._messages.map(_line),
        ],
      ),
    );
  }

  Widget _line(Map<String, dynamic> m) {
    final role = m['sender_role']?.toString() ?? '';
    final label = role == 'driver' ? 'Driver' : 'Patient';
    final when = DateTime.tryParse(m['created_at']?.toString() ?? '');
    final mine = widget.isDriverView ? role == 'driver' : role == 'patient';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            mine ? Icons.person_pin : Icons.person_outline,
            size: 18,
            color: mine ? DriverUi.primaryBlue : Colors.blueGrey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label · ${DriverUi.formatWhen(when)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.blueGrey),
                ),
                const SizedBox(height: 2),
                Text(
                  m['body']?.toString() ?? '',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
