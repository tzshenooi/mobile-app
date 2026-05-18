import 'package:supabase_flutter/supabase_flutter.dart';

/// Scheduled / bedridden bookings assigned to a driver before pickup time.
abstract final class DriverScheduledMissionsService {
  DriverScheduledMissionsService._();

  static const scheduledStatus = 'Scheduled';
  static const alertLeadMinutes = 30;
  static const alertGraceAfterMinutes = 15;

  static DateTime? parseScheduledAt(Map<String, dynamic> booking) {
    final raw = booking['scheduled_at'];
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  static bool isAcknowledged(Map<String, dynamic> booking) {
    final ack = booking['scheduled_driver_acknowledged_at'];
    return ack != null && ack.toString().isNotEmpty;
  }

  /// True during [lead .. pickup+grace] while not yet acknowledged.
  static bool isInAlertWindow(Map<String, dynamic> booking) {
    if ((booking['status'] ?? '').toString() != scheduledStatus) return false;
    if (isAcknowledged(booking)) return false;
    final pickup = parseScheduledAt(booking);
    if (pickup == null) return false;
    final now = DateTime.now();
    final start = pickup.subtract(const Duration(minutes: alertLeadMinutes));
    final end = pickup.add(const Duration(minutes: alertGraceAfterMinutes));
    return !now.isBefore(start) && now.isBefore(end);
  }

  static String formatPickupLabel(Map<String, dynamic> booking) {
    final pickup = parseScheduledAt(booking);
    if (pickup == null) return 'Pickup time not set';
    final h = pickup.hour.toString().padLeft(2, '0');
    final m = pickup.minute.toString().padLeft(2, '0');
    return '${pickup.day}/${pickup.month}/${pickup.year} $h:$m';
  }

  static String minutesUntilPickup(Map<String, dynamic> booking) {
    final pickup = parseScheduledAt(booking);
    if (pickup == null) return '';
    final diff = pickup.difference(DateTime.now());
    if (diff.isNegative) return 'Pickup time passed';
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes} min';
    return 'in ${diff.inHours}h ${diff.inMinutes % 60}m';
  }

  static Future<List<Map<String, dynamic>>> loadForDriver(
    SupabaseClient client,
    String driverId,
  ) async {
    final rows = await client
        .from('bookings')
        .select('*')
        .eq('driver_id', driverId)
        .eq('status', scheduledStatus)
        .order('scheduled_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<void> acknowledgePickup(
    SupabaseClient client,
    String bookingId,
  ) async {
    await client.from('bookings').update({
      'scheduled_driver_acknowledged_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bookingId);
  }

  static Future<void> startMissionNow(
    SupabaseClient client,
    String bookingId,
  ) async {
    await client.from('bookings').update({
      'status': 'Pending',
      'booking_kind': 'emergency',
      'requested_at': DateTime.now().toUtc().toIso8601String(),
      'scheduled_driver_acknowledged_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bookingId);
  }
}
