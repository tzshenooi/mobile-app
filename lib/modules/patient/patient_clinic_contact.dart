import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/clinic_config.dart';
import '../../services/nearest_clinic_service.dart';

/// Clinic name and phone for patient home.
class PatientClinicContact {
  const PatientClinicContact({
    required this.name,
    this.phone,
  });

  final String name;
  final String? phone;

  bool get hasPhone => phone != null && phone!.replaceAll(RegExp(r'\D'), '').length >= 8;

  static Future<PatientClinicContact> load() async {
    const fallbackName = 'Clinic';
    final envPhone = ClinicConfig.clinicPhone.trim();

    final clinicId = await _resolveClinicId();
    if (clinicId != null) {
      final contact = await _fromClinicId(
        clinicId,
        envPhone: envPhone,
        fallbackName: fallbackName,
      );
      if (contact.hasPhone) return contact;
    }

    final fallback = await _firstClinicWithPhone(fallbackName: fallbackName);
    if (fallback != null) return fallback;

    return PatientClinicContact(
      name: fallbackName,
      phone: envPhone.isEmpty ? null : envPhone,
    );
  }

  static Future<PatientClinicContact> _fromClinicId(
    String clinicId, {
    required String envPhone,
    required String fallbackName,
  }) async {
    try {
      final row = await Supabase.instance.client
          .from('clinics')
          .select('name, phone')
          .eq('id', clinicId)
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

  static Future<PatientClinicContact?> _firstClinicWithPhone({required String fallbackName}) async {
    try {
      final rows = await Supabase.instance.client
          .from('clinics')
          .select('name, phone')
          .not('phone', 'is', null)
          .order('name')
          .limit(25);
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final dbPhone = (row['phone'] ?? '').toString().trim();
        if (dbPhone.replaceAll(RegExp(r'\D'), '').length < 8) continue;
        return PatientClinicContact(
          name: (row['name'] ?? fallbackName).toString(),
          phone: dbPhone,
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _resolveClinicId() async {
    if (ClinicConfig.hasClinicId) return ClinicConfig.clinicId;

    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition();
      final nearest = await NearestClinicService.findNearest(
        client: Supabase.instance.client,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      return nearest?.id;
    } catch (_) {
      return null;
    }
  }
}
