import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/clinic_config.dart';

/// Ensures a `drivers` row exists for the signed-in auth user (same id).
abstract final class DriverProfileService {
  DriverProfileService._();

  static Future<Map<String, dynamic>?> loadOrCreate(SupabaseClient client, String userId) async {
    final existing = await client.from('drivers').select('status').eq('id', userId).maybeSingle();
    if (existing != null) {
      return Map<String, dynamic>.from(existing);
    }

    final user = client.auth.currentUser;
    final role = user?.userMetadata?['role']?.toString().toLowerCase();
    if (role == 'patient') {
      return null;
    }
    final name = user?.userMetadata?['name']?.toString().trim();
    final email = user?.email;

    final row = <String, dynamic>{
      'id': userId,
      'name': (name != null && name.isNotEmpty) ? name : (email?.split('@').first ?? 'Driver'),
      'email': email,
      'status': 'Offline',
    };
    if (ClinicConfig.hasClinicId) {
      row['base_clinic_id'] = ClinicConfig.clinicId;
    }

    await client.from('drivers').insert(row);
    return client.from('drivers').select('status').eq('id', userId).maybeSingle();
  }
}
