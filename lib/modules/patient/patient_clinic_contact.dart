import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/clinic_config.dart';

/// Clinic name and phone for patient "call clinic" on home screen.
class PatientClinicContact {
  const PatientClinicContact({required this.name, this.phone});

  final String name;
  final String? phone;

  bool get hasPhone => phone != null && phone!.replaceAll(RegExp(r'\D'), '').length >= 8;

  static Future<PatientClinicContact> load() async {
    const fallbackName = 'Clinic';
    final envPhone = ClinicConfig.clinicPhone.trim();
    if (!ClinicConfig.hasClinicId) {
      return PatientClinicContact(
        name: fallbackName,
        phone: envPhone.isEmpty ? null : envPhone,
      );
    }

    try {
      final row = await Supabase.instance.client
          .from('clinics')
          .select('name, phone')
          .eq('id', ClinicConfig.clinicId)
          .maybeSingle();
      if (row == null) {
        return PatientClinicContact(
          name: fallbackName,
          phone: envPhone.isEmpty ? null : envPhone,
        );
      }
      final dbPhone = (row['phone'] ?? '').toString().trim();
      final phone = dbPhone.isNotEmpty ? dbPhone : (envPhone.isEmpty ? null : envPhone);
      return PatientClinicContact(
        name: (row['name'] ?? fallbackName).toString(),
        phone: phone,
      );
    } catch (_) {
      return PatientClinicContact(
        name: fallbackName,
        phone: envPhone.isEmpty ? null : envPhone,
      );
    }
  }
}
