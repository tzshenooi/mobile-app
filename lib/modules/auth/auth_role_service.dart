import 'package:supabase_flutter/supabase_flutter.dart';

/// Separates patient vs driver accounts (same Supabase Auth, different profiles).
abstract final class AuthRoleService {
  AuthRoleService._();

  static String? metadataRole(User? user) {
    final r = user?.userMetadata?['role']?.toString().toLowerCase();
    if (r == null || r.isEmpty) return null;
    return r;
  }

  static bool isPatientRole(User? user) => metadataRole(user) == 'patient';

  static bool isDriverRole(User? user) => metadataRole(user) == 'driver';

  static Future<bool> hasDriverRow(SupabaseClient client, String userId) async {
    final row = await client.from('drivers').select('id').eq('id', userId).maybeSingle();
    return row != null;
  }

  /// Driver flow: must have a `drivers` row and must not be a patient-only account.
  static Future<String?> driverAccessDeniedReason(SupabaseClient client, User user) async {
    if (isPatientRole(user)) {
      return 'This account is registered as a patient. Use “I need help” to sign in.';
    }
    if (!await hasDriverRow(client, user.id)) {
      return 'No driver profile for this email. Register as a driver or ask your clinic to add you.';
    }
    return null;
  }

  /// Patient flow: must not be a driver account.
  static Future<String?> patientAccessDeniedReason(SupabaseClient client, User user) async {
    if (isDriverRole(user) || await hasDriverRow(client, user.id)) {
      return 'This account is for ambulance drivers. Use “I’m a driver” to sign in.';
    }
    return null;
  }
}
