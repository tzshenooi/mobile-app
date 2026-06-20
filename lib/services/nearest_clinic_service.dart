import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/ambulance_eta.dart';

/// Nearest registered clinic to a GPS point (scheduled bookings, call-clinic contact).
class NearestClinicMatch {
  const NearestClinicMatch({
    required this.id,
    required this.name,
    required this.distanceKm,
  });

  final String id;
  final String name;
  final double distanceKm;
}

abstract final class NearestClinicService {
  NearestClinicService._();

  static double? _num(dynamic v) {
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (n == null || !n.isFinite) return null;
    return n;
  }

  /// Returns the closest clinic with map coordinates, or null if none exist.
  static Future<NearestClinicMatch?> findNearest({
    required SupabaseClient client,
    required double latitude,
    required double longitude,
  }) async {
    if (!latitude.isFinite || !longitude.isFinite) return null;

    final rows = await client.from('clinics').select('id, name, latitude, longitude');

    NearestClinicMatch? best;
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final lat = _num(row['latitude']);
      final lng = _num(row['longitude']);
      if (lat == null || lng == null) continue;

      final km = AmbulanceEta.haversineKm(latitude, longitude, lat, lng);
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;

      if (best == null || km < best.distanceKm) {
        best = NearestClinicMatch(
          id: id,
          name: (row['name'] ?? 'Clinic').toString(),
          distanceKm: km,
        );
      }
    }
    return best;
  }

  /// Nearest clinic with GPS, else build-time [ClinicConfig.clinicId] fallback.
  static Future<NearestClinicMatch?> resolveForPatient({
    required SupabaseClient client,
    required double latitude,
    required double longitude,
    String? fallbackClinicId,
  }) async {
    final nearest = await findNearest(
      client: client,
      latitude: latitude,
      longitude: longitude,
    );
    if (nearest != null) return nearest;

    final fallback = (fallbackClinicId ?? '').trim();
    if (fallback.isEmpty) return null;
    return NearestClinicMatch(id: fallback, name: 'Clinic', distanceKm: 0);
  }
}
