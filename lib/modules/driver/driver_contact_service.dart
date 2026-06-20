import 'package:supabase_flutter/supabase_flutter.dart';

class DriverContactDetails {
  const DriverContactDetails({
    this.phoneNumber,
    this.icNumber,
  });

  final String? phoneNumber;
  final String? icNumber;
}

abstract final class DriverContactService {
  DriverContactService._();

  static Future<DriverContactDetails?> load(SupabaseClient client, String driverId) async {
    final row = await client
        .from('drivers')
        .select('phone_number, ic_number')
        .eq('id', driverId)
        .maybeSingle();
    if (row == null) return null;
    return DriverContactDetails(
      phoneNumber: row['phone_number']?.toString().trim(),
      icNumber: row['ic_number']?.toString().trim(),
    );
  }

  static Future<void> save({
    required SupabaseClient client,
    String? phoneNumber,
    String? icNumber,
  }) async {
    await client.rpc<void>(
      'update_own_driver_contact',
      params: {
        'p_phone_number': phoneNumber?.trim(),
        'p_ic_number': icNumber?.trim(),
      },
    );
  }
}
