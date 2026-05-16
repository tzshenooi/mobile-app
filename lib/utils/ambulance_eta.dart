import 'dart:math' as math;

/// Haversine distance + ETA estimate (matches web-app `driverFleet.js`: 45 km/h).
abstract final class AmbulanceEta {
  AmbulanceEta._();

  static const _earthRadiusKm = 6371.0;
  static const _avgSpeedKmh = 45.0;

  static double haversineKm(double lat1, double lng1, double lat2, double lng2) {
    double toRad(double d) => d * math.pi / 180;
    final dLat = toRad(lat2 - lat1);
    final dLng = toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) * math.cos(toRad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return _earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Minutes until arrival, or null when GPS/destination is missing.
  static int? computeEtaMinutes({
    required double? driverLat,
    required double? driverLng,
    required double destLat,
    required double destLng,
  }) {
    if (driverLat == null || driverLng == null) return null;
    if (!driverLat.isFinite || !driverLng.isFinite) return null;
    if (!destLat.isFinite || !destLng.isFinite) return null;
    final km = haversineKm(driverLat, driverLng, destLat, destLng);
    return (km / _avgSpeedKmh * 60).round().clamp(1, 999);
  }

  static String formatEtaLabel(int? minutes) {
    if (minutes == null) return 'Calculating…';
    return '$minutes min';
  }
}
