import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolve where the driver should navigate (pickup vs hospital after clinic assigns destination).
class DriverNavigationTarget {
  const DriverNavigationTarget({
    required this.lat,
    required this.lng,
    required this.label,
    required this.isHospital,
  });

  final double lat;
  final double lng;
  final String label;
  final bool isHospital;
}

abstract final class DriverNavigationDestination {
  DriverNavigationDestination._();

  static double? _num(dynamic v) {
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (n == null || !n.isFinite) return null;
    return n;
  }

  static bool isPickedUp(Map<String, dynamic> booking) {
    return (booking['status'] ?? '').toString().toLowerCase() == 'picked up';
  }

  static bool hasHospitalAssignment(Map<String, dynamic> booking) {
    if (!isPickedUp(booking)) return false;
    final name = (booking['hospital_name'] ?? '').toString().trim();
    if (name.isEmpty) return false;
    return _num(booking['destination_latitude']) != null ||
        booking['destination_clinic_id'] != null;
  }

  static String fingerprint(Map<String, dynamic> booking) {
    return [
      booking['id'],
      booking['hospital_name'],
      booking['destination_latitude'],
      booking['destination_longitude'],
      booking['destination_clinic_id'],
    ].join('|');
  }

  static bool destinationJustAssigned(
    Map<String, dynamic>? previous,
    Map<String, dynamic> current,
  ) {
    if (!hasHospitalAssignment(current)) return false;
    if (previous == null) return false;
    return fingerprint(previous) != fingerprint(current);
  }

  static Future<DriverNavigationTarget?> resolve({
    required SupabaseClient client,
    required Map<String, dynamic> booking,
  }) async {
    if (isPickedUp(booking)) {
      var lat = _num(booking['destination_latitude']);
      var lng = _num(booking['destination_longitude']);
      var label = (booking['hospital_name'] ?? 'Hospital').toString().trim();

      if (lat == null || lng == null) {
        final clinicId = booking['destination_clinic_id']?.toString();
        if (clinicId != null && clinicId.isNotEmpty) {
          final clinic = await client
              .from('clinics')
              .select('name, latitude, longitude')
              .eq('id', clinicId)
              .maybeSingle();
          if (clinic != null) {
            lat = _num(clinic['latitude']);
            lng = _num(clinic['longitude']);
            final clinicName = clinic['name']?.toString().trim();
            if (clinicName != null && clinicName.isNotEmpty) label = clinicName;
          }
        }
      }

      if (lat != null && lng != null && label.isNotEmpty) {
        return DriverNavigationTarget(lat: lat, lng: lng, label: label, isHospital: true);
      }
    }

    final lat = _num(booking['latitude']);
    final lng = _num(booking['longitude']);
    if (lat == null || lng == null) return null;
    final pickup = (booking['location'] ?? 'Incident location').toString();
    return DriverNavigationTarget(lat: lat, lng: lng, label: pickup, isHospital: false);
  }
}
