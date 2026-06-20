import 'package:latlong2/latlong.dart';

/// Registered clinic row with map coordinates for routing.
class RoutableClinic {
  const RoutableClinic({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String? address;

  LatLng get latLng => LatLng(latitude, longitude);
}

enum HospitalDestinationSource { registered, search }

/// Selected hospital/clinic destination from the hybrid picker.
class HospitalDestinationSelection {
  const HospitalDestinationSelection({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.source,
    this.clinicId,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String? clinicId;
  final HospitalDestinationSource source;
}

abstract final class PatientClinicRouting {
  PatientClinicRouting._();

  static double? _num(dynamic v) {
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (n == null || !n.isFinite) return null;
    return n;
  }

  static bool isHospitalDestinationType(String? type) {
    return type == 'public_hospital' || type == 'private_hospital';
  }

  static RoutableClinic? fromRow(Map<String, dynamic> row) {
    final lat = _num(row['latitude']);
    final lng = _num(row['longitude']);
    final id = row['id']?.toString();
    if (lat == null || lng == null || id == null || id.isEmpty) return null;
    final name = (row['name'] ?? 'Clinic').toString().trim();
    if (name.isEmpty) return null;
    return RoutableClinic(
      id: id,
      name: name,
      latitude: lat,
      longitude: lng,
      address: row['address']?.toString().trim(),
    );
  }

  static RoutableClinic? matchClinicByName(List<RoutableClinic> clinics, String name) {
    final q = name.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final c in clinics) {
      if (c.name.trim().toLowerCase() == q) return c;
    }
    return null;
  }
}
