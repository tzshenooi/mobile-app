import 'package:supabase_flutter/supabase_flutter.dart';

class PatientHomeAddress {
  const PatientHomeAddress({
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String address;
  final double latitude;
  final double longitude;

  bool get isComplete =>
      address.trim().isNotEmpty && latitude.isFinite && longitude.isFinite;
}

abstract final class PatientHomeAddressService {
  PatientHomeAddressService._();

  static Future<PatientHomeAddress?> load(SupabaseClient client, String userId) async {
    final row = await client
        .from('patient_profiles')
        .select('home_address, home_latitude, home_longitude')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;

    final address = row['home_address']?.toString().trim() ?? '';
    final lat = _num(row['home_latitude']);
    final lng = _num(row['home_longitude']);
    if (address.isEmpty || lat == null || lng == null) return null;

    return PatientHomeAddress(address: address, latitude: lat, longitude: lng);
  }

  static Future<void> save(
    SupabaseClient client,
    String userId, {
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    final payload = {
      'user_id': userId,
      'home_address': address.trim(),
      'home_latitude': latitude,
      'home_longitude': longitude,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await client.from('patient_profiles').upsert(payload);
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (n == null || !n.isFinite) return null;
    return n;
  }
}
