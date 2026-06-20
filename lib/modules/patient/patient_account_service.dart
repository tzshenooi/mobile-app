import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class PatientAccountService {
  PatientAccountService._();

  /// Permanently deletes the signed-in patient account via Supabase RPC.
  static Future<void> deleteOwnAccount(SupabaseClient client) async {
    await client.rpc<void>('delete_own_patient_account');
  }
}
