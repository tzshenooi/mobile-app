import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/local_notification_service.dart';
import '../driver/driver_ui.dart';
import 'mission_chat_service.dart';

/// In-thread chat UI for driver ↔ patient on one booking.
class MissionChatPanel extends StatefulWidget {
  const MissionChatPanel({
    super.key,
    required this.bookingId,
    required this.isDriver,
    required this.peerLabel,
    this.enabled = true,
    this.disabledHint,
    this.quickReplies = const [],
    this.compact = false,
  });

  final String bookingId;
  final bool isDriver;
  final String peerLabel;
  final bool enabled;
  final String? disabledHint;
  final List<String> quickReplies;
  final bool compact;

  @override
  State<MissionChatPanel> createState() => _MissionChatPanelState();
}

class _MissionChatPanelState extends State<MissionChatPanel>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _tableMissing = false;
  bool _appInForeground = true;
  String? _lastNotifiedMessageId;
  Timer? _pollTimer;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load(silent: true));
    _subscribeRealtime();
  }

  @override
  void didUpdateWidget(covariant MissionChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId) {
      _channel?.unsubscribe();
      _load();
      _subscribeRealtime();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _channel?.unsubscribe();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('mission-chat-${widget.bookingId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'mission_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: widget.bookingId,
          ),
          callback: (_) => _load(silent: true),
        )
        .subscribe();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
  }

  void _maybeNotifyPeerMessage(List<Map<String, dynamic>> rows) {
    if (_appInForeground || rows.isEmpty) return;
    final myRole = widget.isDriver ? 'driver' : 'patient';
    for (var i = rows.length - 1; i >= 0; i--) {
      final message = rows[i];
      final role = message['sender_role']?.toString();
      if (role == myRole) continue;
      final id = message['id']?.toString();
      if (id == null || id == _lastNotifiedMessageId) return;
      _lastNotifiedMessageId = id;
      final preview = message['body']?.toString() ?? 'New message';
      LocalNotificationService.instance.showChatMessage(
        senderLabel: widget.peerLabel,
        preview: preview,
        idSeed: id.hashCode,
      );
      return;
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final rows = await MissionChatService.loadMessages(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _messages = rows;
        _loading = false;
        _tableMissing = false;
      });
      _maybeNotifyPeerMessage(rows);
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _tableMissing = MissionChatService.tableMissingError(e);
        if (_tableMissing) _messages = [];
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _send(String body) async {
    if (!widget.enabled || _sending) return;
    final text = body.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      await MissionChatService.send(
        bookingId: widget.bookingId,
        asDriver: widget.isDriver,
        body: text,
      );
      _textController.clear();
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tableMissing) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Run web-app/supabase/mission_messages.sql in Supabase to enable patient chat.',
          style: TextStyle(fontSize: 12, color: Colors.amber[900], height: 1.35),
        ),
      );
    }

    if (!widget.enabled) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          widget.disabledHint ?? 'Chat is not available right now.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.blueGrey, height: 1.4),
        ),
      );
    }

    final listHeight = widget.compact ? 200.0 : 280.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              widget.isDriver ? 'Chat with ${widget.peerLabel}' : 'Message ${widget.peerLabel}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        SizedBox(
          height: listHeight,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: DriverUi.primaryBlue))
              : _messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet.\nSay hello to ${widget.peerLabel}.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.blueGrey, height: 1.4, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) => _bubble(_messages[i]),
                    ),
        ),
        if (widget.quickReplies.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.quickReplies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                return ActionChip(
                  label: Text(widget.quickReplies[i], style: const TextStyle(fontSize: 11)),
                  onPressed: _sending ? null : () => _send(widget.quickReplies[i]),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                enabled: widget.enabled && !_sending,
                decoration: InputDecoration(
                  hintText: widget.isDriver ? 'Message patient…' : 'Message driver…',
                  filled: true,
                  fillColor: DriverUi.bgGray,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : () => _send(_textController.text),
              style: IconButton.styleFrom(
                backgroundColor: widget.isDriver ? DriverUi.primaryBlue : const Color(0xFFE74C3C),
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 20, color: Colors.white),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final role = m['sender_role']?.toString();
    final mine = widget.isDriver ? role == 'driver' : role == 'patient';
    final when = DateTime.tryParse(m['created_at']?.toString() ?? '');
    final color = mine
        ? (widget.isDriver ? DriverUi.primaryBlue : const Color(0xFFE74C3C))
        : Colors.grey.shade200;
    final textColor = mine ? Colors.white : const Color(0xFF1E293B);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(m['body']?.toString() ?? '', style: TextStyle(color: textColor, fontSize: 14)),
            const SizedBox(height: 2),
            Text(
              DriverUi.formatWhen(when),
              style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
