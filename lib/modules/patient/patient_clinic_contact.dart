import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/clinic_config.dart';

/// Clinic name and phone for patient home; optional bed counts when clinic publishes them.
class PatientClinicContact {
  const PatientClinicContact({
    required this.name,
    this.phone,
    this.bedCapacity = 0,
    this.bedsOccupied = 0,
  });

  final String name;
  final String? phone;
  final int bedCapacity;
  final int bedsOccupied;

  bool get hasPhone => phone != null && phone!.replaceAll(RegExp(r'\D'), '').length >= 8;

  bool get showsBedAvailability => bedCapacity > 0;

  int get bedsAvailable {
    if (bedCapacity <= 0) return 0;
    final occ = bedsOccupied.clamp(0, bedCapacity);
    return bedCapacity - occ;
  }

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
          .select('name, phone, bed_capacity, beds_occupied')
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
      final cap = _parseInt(row['bed_capacity']);
      final occ = _parseInt(row['beds_occupied']);
      return PatientClinicContact(
        name: (row['name'] ?? fallbackName).toString(),
        phone: phone,
        bedCapacity: cap,
        bedsOccupied: occ,
      );
    } catch (_) {
      return PatientClinicContact(
        name: fallbackName,
        phone: envPhone.isEmpty ? null : envPhone,
      );
    }
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }
}
