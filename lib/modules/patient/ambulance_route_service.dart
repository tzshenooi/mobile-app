import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../config/google_maps_config.dart';

/// Driving route between ambulance GPS and destination (Google Directions, OSRM fallback).
abstract final class AmbulanceRouteService {
  AmbulanceRouteService._();

  static const _timeout = Duration(seconds: 12);
  static const routeBlue = 0xFF4285F4;

  static Future<List<LatLng>> fetchDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (hasGoogleMapsApiKey) {
      final google = await _googleDirections(origin, destination);
      if (google != null && google.length >= 2) return google;
    }
    final osrm = await _osrmRoute(origin, destination);
    if (osrm != null && osrm.length >= 2) return osrm;
    return [origin, destination];
  }

  static Future<List<LatLng>?> _googleDirections(LatLng origin, LatLng destination) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'driving',
      'key': googleMapsApiKey,
    });
    try {
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return null;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final overview = (routes.first as Map)['overview_polyline'] as Map?;
      final encoded = overview?['points'] as String?;
      if (encoded == null || encoded.isEmpty) return null;
      return _decodePolyline(encoded);
    } catch (_) {
      return null;
    }
  }

  static Future<List<LatLng>?> _osrmRoute(LatLng origin, LatLng destination) async {
    final path =
        '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$path?overview=full&geometries=geojson',
    );
    try {
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') return null;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final coords = (routes.first as Map)['geometry']?['coordinates'] as List?;
      if (coords == null || coords.isEmpty) return null;
      return coords
          .map((c) {
            final pair = c as List;
            return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
          })
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Google encoded polyline algorithm.
  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
