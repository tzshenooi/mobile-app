import 'package:supabase_flutter/supabase_flutter.dart';

/// Active dispatch rows assigned to a driver (restored after app restart).
abstract final class DriverActiveMissionsService {
  DriverActiveMissionsService._();

  static const activeStatuses = [
    'Pending',
    'Assigned',
    'Accepted',
    'En Route',
    'Picked Up',
  ];

  static bool isActiveStatus(String? status) {
    return activeStatuses.contains((status ?? '').toString());
  }

  static Future<Map<String, dynamic>?> loadForDriver(
    SupabaseClient client,
    String driverId,
  ) async {
    return client
        .from('bookings')
        .select()
        .eq('driver_id', driverId)
        .inFilter('status', activeStatuses)
        .order('requested_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }
}
