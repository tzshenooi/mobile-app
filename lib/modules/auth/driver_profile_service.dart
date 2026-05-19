import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_role_service.dart';

/// Loads the signed-in user's `drivers` row only (never auto-creates).
abstract final class DriverProfileService {
  DriverProfileService._();

  static Future<Map<String, dynamic>?> loadDriverProfile(
    SupabaseClient client,
    String userId,
  ) async {
    final user = client.auth.currentUser;
    if (user != null && user.id == userId) {
      final denied = await AuthRoleService.driverAccessDeniedReason(client, user);
      if (denied != null) return null;
    }

    final existing = await client.from('drivers').select('status').eq('id', userId).maybeSingle();
    if (existing == null) return null;
    return Map<String, dynamic>.from(existing);
  }
}
