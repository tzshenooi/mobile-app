import 'package:supabase_flutter/supabase_flutter.dart';

/// Load / send driver ↔ patient messages on an active booking.
abstract final class MissionChatService {
  MissionChatService._();

  static final _client = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> loadMessages(String bookingId) async {
    final data = await _client
        .from('mission_messages')
        .select('id, body, sender_role, created_at')
        .eq('booking_id', bookingId)
        .order('created_at', ascending: true)
        .limit(100);
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<void> send({
    required String bookingId,
    required bool asDriver,
    required String body,
  }) async {
    final text = body.trim();
    if (text.isEmpty) return;
    await _client.from('mission_messages').insert({
      'booking_id': bookingId,
      'sender_role': asDriver ? 'driver' : 'patient',
      'body': text,
    });
  }

  static bool tableMissingError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('mission_messages') &&
        (msg.contains('does not exist') || msg.contains('404') || msg.contains('schema cache'));
  }
}
