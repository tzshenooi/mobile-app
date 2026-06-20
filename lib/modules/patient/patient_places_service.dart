import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../config/google_maps_config.dart';

/// Address suggestion (Google Places or Nominatim fallback).
class PatientPlaceSuggestion {
  const PatientPlaceSuggestion({
    required this.description,
    this.placeId,
    this.latLng,
    this.primaryLine,
    this.secondaryLine,
  });

  final String description;
  final String? placeId;
  final LatLng? latLng;
  final String? primaryLine;
  final String? secondaryLine;
}

class PatientPlaceDetails {
  const PatientPlaceDetails({required this.address, required this.latLng});

  final String address;
  final LatLng latLng;
}

class PatientPlacesStatus {
  PatientPlacesStatus._();
  static String? lastError;
  static String? lastStatus;
  static bool lastUsedGoogle = false;
  /// Set when the API key is HTTP-referrer restricted (web-only) and mobile calls get 403.
  static bool googleBlockedForMobile = false;
}

/// Google Places over HTTP (same data as dispatch). Falls back to Nominatim if the key rejects mobile calls.
abstract final class PatientPlacesService {
  PatientPlacesService._();

  static const _timeout = Duration(seconds: 10);
  static const _jsonHeaders = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  static Map<String, String> get _googleKeyHeaders => {
        ..._jsonHeaders,
        'X-Goog-Api-Key': googleMapsApiKey,
      };

  static bool _isGoogleBlockedForMobileHttp(http.Response res) {
    if (res.statusCode != 403) return false;
    final body = res.body;
    if (body.contains('API_KEY_HTTP_REFERRER_BLOCKED')) return true;
    if (body.contains('Android client application') && body.contains('blocked')) {
      return true;
    }
    if (body.contains('referer') && body.contains('blocked')) return true;
    return false;
  }

  static void _markGoogleBlockedIfNeeded(http.Response res) {
    if (!_isGoogleBlockedForMobileHttp(res)) return;
    if (PatientPlacesStatus.googleBlockedForMobile) return;
    PatientPlacesStatus.googleBlockedForMobile = true;
    if (kDebugMode) {
      debugPrint(
        '[Places] This Google key cannot be used for address search over HTTP in Flutter '
        '(web referrer or Android-app restriction). Using OpenStreetMap. '
        'For Google Places in the app, use a key with Application restrictions = None '
        'and API restrictions = Places API (New) only — keep a separate Android key for Maps SDK in AndroidManifest.',
      );
    }
  }

  static bool _isMobileRestrictionMessage(String message) {
    final m = message.toLowerCase();
    if (m.contains('referer') && m.contains('blocked')) return true;
    if (m.contains('referrer') && m.contains('blocked')) return true;
    if (m.contains('android client application') && m.contains('blocked')) return true;
    if (m.contains('api_key_http_referrer_blocked')) return true;
    if (m.contains('ip address restriction')) return true;
    return false;
  }

  /// [newSession] reserved for future session-token billing; ignored for HTTP.
  /// [near] biases Google results toward the map pin / GPS (e.g. USM Gelugor near Penang).
  static Future<List<PatientPlaceSuggestion>> autocomplete(
    String input, {
    bool newSession = false,
    LatLng? near,
  }) async {
    final q = input.trim();
    if (q.length < 2) return [];

    PatientPlacesStatus.lastError = null;
    PatientPlacesStatus.lastStatus = null;
    PatientPlacesStatus.lastUsedGoogle = false;

    if (hasGoogleMapsApiKey && !PatientPlacesStatus.googleBlockedForMobile) {
      final newApi = await _placesNewAutocomplete(q, near: near);
      if (newApi.isNotEmpty) {
        PatientPlacesStatus.lastUsedGoogle = true;
        return newApi;
      }

      if (!PatientPlacesStatus.googleBlockedForMobile) {
        final legacy = await _httpAutocomplete(q, near: near);
        if (legacy.isNotEmpty) {
          PatientPlacesStatus.lastUsedGoogle = true;
          return legacy;
        }
      }

      if (!PatientPlacesStatus.googleBlockedForMobile) {
        final textSearch = await _placesNewTextSearch(q, near: near);
        if (textSearch.isNotEmpty) {
          PatientPlacesStatus.lastUsedGoogle = true;
          return textSearch;
        }
      }

      if (!PatientPlacesStatus.googleBlockedForMobile) {
        final geo = await _httpGeocodeSearch(q);
        if (geo.isNotEmpty) {
          PatientPlacesStatus.lastUsedGoogle = true;
          return geo;
        }
      }
    }

    final osm = await _nominatimSearch(q);
    if (osm.isNotEmpty) return osm;

    return _nominatimSearch('$q, Malaysia');
  }

  /// Hospital-biased search (Google Places hospital type, then general fallback).
  static Future<List<PatientPlaceSuggestion>> searchHospitals(String input) async {
    final q = input.trim();
    if (q.length < 2) return [];

    PatientPlacesStatus.lastError = null;
    PatientPlacesStatus.lastStatus = null;
    PatientPlacesStatus.lastUsedGoogle = false;

    if (hasGoogleMapsApiKey && !PatientPlacesStatus.googleBlockedForMobile) {
      final hospitalAuto = await _placesNewHospitalAutocomplete(q);
      if (hospitalAuto.isNotEmpty) {
        PatientPlacesStatus.lastUsedGoogle = true;
        return hospitalAuto;
      }

      if (!PatientPlacesStatus.googleBlockedForMobile) {
        final hospitalText = await _placesNewHospitalTextSearch(q);
        if (hospitalText.isNotEmpty) {
          PatientPlacesStatus.lastUsedGoogle = true;
          return hospitalText;
        }
      }

      if (!PatientPlacesStatus.googleBlockedForMobile) {
        final textSearch = await _placesNewTextSearch('$q hospital');
        if (textSearch.isNotEmpty) {
          PatientPlacesStatus.lastUsedGoogle = true;
          return textSearch;
        }
      }
    }

    final osm = await _nominatimSearch('$q hospital');
    if (osm.isNotEmpty) return osm;

    return autocomplete(q);
  }

  /// True when the last search used OpenStreetMap (Google unavailable on this device).
  static bool get usingOpenStreetMapFallback =>
      PatientPlacesStatus.googleBlockedForMobile ||
      (PatientPlacesStatus.lastUsedGoogle == false &&
          PatientPlacesStatus.lastError != null);

  static Future<PatientPlaceDetails?> fetchPlaceDetails(String placeId) async {
    if (!hasGoogleMapsApiKey || PatientPlacesStatus.googleBlockedForMobile) return null;

    final newDetails = await _placesNewFetchDetails(placeId);
    if (newDetails != null) return newDetails;

    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
      'place_id': placeId,
      'fields': 'geometry,formatted_address',
      'key': googleMapsApiKey,
    });

    final res = await http.get(uri, headers: _jsonHeaders).timeout(_timeout);
    if (res.statusCode != 200) return null;

    final body = json.decode(res.body) as Map<String, dynamic>?;
    _recordLegacyGoogleStatus(body);
    if (body?['status'] != 'OK') return null;

    return _detailsFromLegacyResult(body!['result'] as Map<String, dynamic>?);
  }

  static Future<String?> reverseAddress(LatLng point) async {
    if (hasGoogleMapsApiKey && !PatientPlacesStatus.googleBlockedForMobile) {
      final g = await _httpReverse(point);
      if (g != null && g.isNotEmpty) return g;
    }
    return _nominatimReverse(point);
  }

  static Future<List<PatientPlaceSuggestion>> _placesNewAutocomplete(
    String input, {
    LatLng? near,
  }) async {
    final uri = Uri.https('places.googleapis.com', '/v1/places:autocomplete');
    final payload = <String, dynamic>{
      'input': input,
      'includedRegionCodes': ['MY'],
      'languageCode': 'en',
    };
    if (near != null) {
      payload['locationBias'] = {
        'circle': {
          'center': {'latitude': near.latitude, 'longitude': near.longitude},
          'radius': 50000.0,
        },
      };
    }
    final body = json.encode(payload);

    try {
      final res = await http
          .post(uri, headers: _googleKeyHeaders, body: body)
          .timeout(_timeout);
      if (res.statusCode != 200) {
        _markGoogleBlockedIfNeeded(res);
        if (kDebugMode && !PatientPlacesStatus.googleBlockedForMobile) {
          debugPrint('[Places New autocomplete] HTTP ${res.statusCode}: ${res.body}');
        }
        _recordNewApiError(res);
        return [];
      }

      final decoded = json.decode(res.body) as Map<String, dynamic>?;
      final suggestions = decoded?['suggestions'];
      if (suggestions is! List) return [];

      final out = <PatientPlaceSuggestion>[];
      for (final raw in suggestions.take(10)) {
        if (raw is! Map) continue;
        final s = Map<String, dynamic>.from(raw);
        final prediction = s['placePrediction'];
        if (prediction is! Map) continue;
        final pred = Map<String, dynamic>.from(prediction);

        final placeId = pred['placeId'] as String?;
        if (placeId == null || placeId.isEmpty) continue;

        String primary = '';
        String secondary = '';
        String full = '';

        final structured = pred['structuredFormat'];
        if (structured is Map) {
          final sf = Map<String, dynamic>.from(structured);
          primary = (sf['mainText']?['text'] as String?)?.trim() ?? '';
          secondary = (sf['secondaryText']?['text'] as String?)?.trim() ?? '';
        }
        final text = pred['text'];
        if (text is Map) {
          full = (Map<String, dynamic>.from(text)['text'] as String?)?.trim() ?? '';
        }
        if (full.isEmpty) {
          full = [primary, secondary].where((e) => e.isNotEmpty).join(', ');
        }

        out.add(PatientPlaceSuggestion(
          description: full,
          placeId: placeId,
          primaryLine: primary.isEmpty ? null : primary,
          secondaryLine: secondary.isEmpty ? null : secondary,
        ));
      }
      return out;
    } catch (e, st) {
      PatientPlacesStatus.lastError = e.toString();
      if (kDebugMode) debugPrint('[Places New autocomplete] $e\n$st');
      return [];
    }
  }

  static Future<List<PatientPlaceSuggestion>> _placesNewHospitalAutocomplete(String input) async {
    final uri = Uri.https('places.googleapis.com', '/v1/places:autocomplete');
    final body = json.encode({
      'input': input,
      'includedPrimaryTypes': ['hospital'],
      'includedRegionCodes': ['MY'],
      'languageCode': 'en',
    });

    try {
      final res = await http
          .post(uri, headers: _googleKeyHeaders, body: body)
          .timeout(_timeout);
      if (res.statusCode != 200) {
        _markGoogleBlockedIfNeeded(res);
        _recordNewApiError(res);
        return [];
      }

      final decoded = json.decode(res.body) as Map<String, dynamic>?;
      final suggestions = decoded?['suggestions'];
      if (suggestions is! List) return [];

      final out = <PatientPlaceSuggestion>[];
      for (final raw in suggestions.take(10)) {
        if (raw is! Map) continue;
        final s = Map<String, dynamic>.from(raw);
        final prediction = s['placePrediction'];
        if (prediction is! Map) continue;
        final pred = Map<String, dynamic>.from(prediction);

        final placeId = pred['placeId'] as String?;
        if (placeId == null || placeId.isEmpty) continue;

        String primary = '';
        String secondary = '';
        String full = '';

        final structured = pred['structuredFormat'];
        if (structured is Map) {
          final sf = Map<String, dynamic>.from(structured);
          primary = (sf['mainText']?['text'] as String?)?.trim() ?? '';
          secondary = (sf['secondaryText']?['text'] as String?)?.trim() ?? '';
        }
        final text = pred['text'];
        if (text is Map) {
          full = (Map<String, dynamic>.from(text)['text'] as String?)?.trim() ?? '';
        }
        if (full.isEmpty) {
          full = [primary, secondary].where((e) => e.isNotEmpty).join(', ');
        }

        out.add(PatientPlaceSuggestion(
          description: full,
          placeId: placeId,
          primaryLine: primary.isEmpty ? null : primary,
          secondaryLine: secondary.isEmpty ? null : secondary,
        ));
      }
      return out;
    } catch (e, st) {
      PatientPlacesStatus.lastError = e.toString();
      if (kDebugMode) debugPrint('[Places New hospital autocomplete] $e\n$st');
      return [];
    }
  }

  static Future<List<PatientPlaceSuggestion>> _placesNewHospitalTextSearch(String input) async {
    final uri = Uri.https('places.googleapis.com', '/v1/places:searchText');
    final body = json.encode({
      'textQuery': input,
      'includedType': 'hospital',
      'regionCode': 'MY',
      'languageCode': 'en',
      'maxResultCount': 10,
    });

    try {
      final res = await http
          .post(
            uri,
            headers: {
              ..._googleKeyHeaders,
              'X-Goog-FieldMask':
                  'places.id,places.formattedAddress,places.displayName,places.location',
            },
            body: body,
          )
          .timeout(_timeout);

      if (res.statusCode != 200) {
        _markGoogleBlockedIfNeeded(res);
        _recordNewApiError(res);
        return [];
      }

      final decoded = json.decode(res.body) as Map<String, dynamic>?;
      final places = decoded?['places'];
      if (places is! List) return [];

      final out = <PatientPlaceSuggestion>[];
      for (final raw in places.take(10)) {
        if (raw is! Map) continue;
        final place = Map<String, dynamic>.from(raw);
        final id = place['id'] as String?;
        final loc = place['location'] as Map<String, dynamic>?;
        final lat = (loc?['latitude'] as num?)?.toDouble();
        final lng = (loc?['longitude'] as num?)?.toDouble();
        LatLng? point;
        if (lat != null && lng != null) point = LatLng(lat, lng);

        String name = '';
        final dn = place['displayName'];
        if (dn is Map) name = (dn['text'] as String?)?.trim() ?? '';
        final formatted = (place['formattedAddress'] as String?)?.trim() ?? '';
        final desc = name.isNotEmpty
            ? (formatted.isNotEmpty && !formatted.toLowerCase().startsWith(name.toLowerCase())
                ? '$name, $formatted'
                : name)
            : formatted;
        if (desc.isEmpty) continue;

        out.add(PatientPlaceSuggestion(
          description: desc,
          placeId: id,
          latLng: point,
          primaryLine: name.isEmpty ? null : name,
          secondaryLine: formatted.isEmpty ? null : formatted,
        ));
      }
      return out;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Places New hospital text search] $e\n$st');
      return [];
    }
  }

  static Future<PatientPlaceDetails?> _placesNewFetchDetails(String placeId) async {
    final encodedId = Uri.encodeComponent(placeId);
    final uri = Uri.https('places.googleapis.com', '/v1/places/$encodedId');
    try {
      final res = await http
          .get(
            uri,
            headers: {
              ..._googleKeyHeaders,
              'X-Goog-FieldMask': 'id,formattedAddress,location',
            },
          )
          .timeout(_timeout);

      if (res.statusCode != 200) {
        if (kDebugMode) debugPrint('[Places New details] HTTP ${res.statusCode}: ${res.body}');
        return null;
      }

      final place = json.decode(res.body) as Map<String, dynamic>?;
      if (place == null) return null;

      final loc = place['location'] as Map<String, dynamic>?;
      if (loc == null) return null;

      final lat = (loc['latitude'] as num?)?.toDouble();
      final lng = (loc['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      final address = (place['formattedAddress'] as String?)?.trim() ?? '';
      return PatientPlaceDetails(
        address: address.isEmpty ? '$lat, $lng' : address,
        latLng: LatLng(lat, lng),
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Places New details] $e\n$st');
      return null;
    }
  }

  static void _recordNewApiError(http.Response res) {
    try {
      final body = json.decode(res.body) as Map<String, dynamic>?;
      final err = body?['error'] as Map<String, dynamic>?;
      PatientPlacesStatus.lastStatus = err?['status']?.toString() ?? 'HTTP_${res.statusCode}';
      PatientPlacesStatus.lastError = err?['message']?.toString();
    } catch (_) {
      PatientPlacesStatus.lastStatus = 'HTTP_${res.statusCode}';
    }
  }

  static void _recordLegacyGoogleStatus(Map<String, dynamic>? body) {
    if (body == null) return;
    final status = body['status']?.toString();
    if (status == null || status == 'OK' || status == 'ZERO_RESULTS') return;
    PatientPlacesStatus.lastStatus = status;
    PatientPlacesStatus.lastError = body['error_message']?.toString();
  }

  static PatientPlaceDetails? _detailsFromLegacyResult(Map<String, dynamic>? result) {
    if (result == null) return null;
    final geo = result['geometry'] as Map<String, dynamic>?;
    final loc = geo?['location'] as Map<String, dynamic>?;
    if (loc == null) return null;

    final lat = (loc['lat'] as num?)?.toDouble();
    final lng = (loc['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final address = (result['formatted_address'] as String?)?.trim() ?? '';
    return PatientPlaceDetails(
      address: address.isEmpty ? '$lat, $lng' : address,
      latLng: LatLng(lat, lng),
    );
  }

  /// Find places by name/keyword (e.g. "School of Management USM") when autocomplete is empty.
  static Future<List<PatientPlaceSuggestion>> _placesNewTextSearch(
    String input, {
    LatLng? near,
  }) async {
    final uri = Uri.https('places.googleapis.com', '/v1/places:searchText');
    final payload = <String, dynamic>{
      'textQuery': input,
      'regionCode': 'MY',
      'languageCode': 'en',
      'maxResultCount': 10,
    };
    if (near != null) {
      payload['locationBias'] = {
        'circle': {
          'center': {'latitude': near.latitude, 'longitude': near.longitude},
          'radius': 50000.0,
        },
      };
    }
    final body = json.encode(payload);

    try {
      final res = await http
          .post(
            uri,
            headers: {
              ..._googleKeyHeaders,
              'X-Goog-FieldMask':
                  'places.id,places.formattedAddress,places.displayName,places.location',
            },
            body: body,
          )
          .timeout(_timeout);

      if (res.statusCode != 200) {
        _markGoogleBlockedIfNeeded(res);
        if (kDebugMode && !PatientPlacesStatus.googleBlockedForMobile) {
          debugPrint('[Places New text search] HTTP ${res.statusCode}: ${res.body}');
        }
        _recordNewApiError(res);
        return [];
      }

      final decoded = json.decode(res.body) as Map<String, dynamic>?;
      final places = decoded?['places'];
      if (places is! List) return [];

      final out = <PatientPlaceSuggestion>[];
      for (final raw in places.take(10)) {
        if (raw is! Map) continue;
        final place = Map<String, dynamic>.from(raw);
        final id = place['id'] as String?;
        final loc = place['location'] as Map<String, dynamic>?;
        final lat = (loc?['latitude'] as num?)?.toDouble();
        final lng = (loc?['longitude'] as num?)?.toDouble();
        LatLng? point;
        if (lat != null && lng != null) point = LatLng(lat, lng);

        String name = '';
        final dn = place['displayName'];
        if (dn is Map) name = (dn['text'] as String?)?.trim() ?? '';
        final formatted = (place['formattedAddress'] as String?)?.trim() ?? '';
        final desc = name.isNotEmpty
            ? (formatted.isNotEmpty && !formatted.toLowerCase().startsWith(name.toLowerCase())
                ? '$name, $formatted'
                : name)
            : formatted;
        if (desc.isEmpty) continue;

        out.add(PatientPlaceSuggestion(
          description: desc,
          placeId: id,
          latLng: point,
          primaryLine: name.isEmpty ? null : name,
          secondaryLine: formatted.isEmpty ? null : formatted,
        ));
      }
      return out;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Places New text search] $e\n$st');
      return [];
    }
  }

  static Future<List<PatientPlaceSuggestion>> _httpAutocomplete(
    String input, {
    LatLng? near,
  }) async {
    final params = <String, String>{
      'input': input,
      'key': googleMapsApiKey,
      'components': 'country:my',
      'language': 'en',
    };
    if (near != null) {
      params['location'] = '${near.latitude},${near.longitude}';
      params['radius'] = '50000';
    }
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', params);

    final res = await http.get(uri, headers: _jsonHeaders).timeout(_timeout);
    if (res.statusCode != 200) {
      _markGoogleBlockedIfNeeded(res);
      return [];
    }

    final body = json.decode(res.body) as Map<String, dynamic>?;
    final status = body?['status'] as String?;
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      _recordLegacyGoogleStatus(body);
      final errMsg = body?['error_message']?.toString() ?? '';
      if (status == 'REQUEST_DENIED' && _isMobileRestrictionMessage(errMsg)) {
        PatientPlacesStatus.googleBlockedForMobile = true;
      }
      return [];
    }

    final preds = body?['predictions'];
    if (preds is! List) return [];

    final out = <PatientPlaceSuggestion>[];
    for (final p in preds.take(10)) {
      if (p is! Map) continue;
      final map = Map<String, dynamic>.from(p);
      final desc = (map['description'] as String?)?.trim();
      final id = map['place_id'] as String?;
      if (desc == null || desc.isEmpty || id == null) continue;

      String? primary;
      String? secondary;
      final structured = map['structured_formatting'];
      if (structured is Map) {
        final sf = Map<String, dynamic>.from(structured);
        primary = (sf['main_text'] as String?)?.trim();
        secondary = (sf['secondary_text'] as String?)?.trim();
      }

      out.add(PatientPlaceSuggestion(
        description: desc,
        placeId: id,
        primaryLine: primary?.isEmpty == true ? null : primary,
        secondaryLine: secondary?.isEmpty == true ? null : secondary,
      ));
    }
    return out;
  }

  static Future<List<PatientPlaceSuggestion>> _httpGeocodeSearch(String q) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': q,
      'key': googleMapsApiKey,
      'components': 'country:MY',
      'language': 'en',
    });

    final res = await http.get(uri, headers: _jsonHeaders).timeout(_timeout);
    if (res.statusCode != 200) {
      _markGoogleBlockedIfNeeded(res);
      return [];
    }

    final body = json.decode(res.body) as Map<String, dynamic>?;
    if (body?['status'] != 'OK') {
      _recordLegacyGoogleStatus(body);
      final errMsg = body?['error_message']?.toString() ?? '';
      if (body?['status'] == 'REQUEST_DENIED' && _isMobileRestrictionMessage(errMsg)) {
        PatientPlacesStatus.googleBlockedForMobile = true;
      }
      return [];
    }

    final results = body?['results'];
    if (results is! List) return [];

    final out = <PatientPlaceSuggestion>[];
    for (final r in results.take(10)) {
      if (r is! Map) continue;
      final map = Map<String, dynamic>.from(r);
      final desc = (map['formatted_address'] as String?)?.trim();
      if (desc == null || desc.isEmpty) continue;

      LatLng? point;
      final geo = map['geometry'] as Map<String, dynamic>?;
      final loc = geo?['location'] as Map<String, dynamic>?;
      if (loc != null) {
        final lat = (loc['lat'] as num?)?.toDouble();
        final lng = (loc['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) point = LatLng(lat, lng);
      }
      out.add(PatientPlaceSuggestion(
        description: desc,
        latLng: point,
        placeId: map['place_id'] as String?,
      ));
    }
    return out;
  }

  static Future<String?> _httpReverse(LatLng point) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'latlng': '${point.latitude},${point.longitude}',
      'key': googleMapsApiKey,
      'language': 'en',
    });

    final res = await http.get(uri, headers: _jsonHeaders).timeout(_timeout);
    if (res.statusCode != 200) return null;

    final body = json.decode(res.body) as Map<String, dynamic>?;
    if (body?['status'] != 'OK') return null;

    final results = body!['results'];
    if (results is! List || results.isEmpty) return null;

    final first = results.first;
    if (first is! Map) return null;
    return (Map<String, dynamic>.from(first)['formatted_address'] as String?)?.trim();
  }

  static Future<List<PatientPlaceSuggestion>> _nominatimSearch(String q) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'json',
      'limit': '8',
      'countrycodes': 'my',
      'addressdetails': '0',
    });

    final res = await http
        .get(
          uri,
          headers: {'User-Agent': 'SmartAmbulanceDriver/1.0 (mobile patient report)'},
        )
        .timeout(_timeout);

    if (res.statusCode != 200) return [];

    final decoded = json.decode(res.body);
    if (decoded is! List) return [];

    final out = <PatientPlaceSuggestion>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      try {
        final lat = double.parse(m['lat'].toString());
        final lon = double.parse(m['lon'].toString());
        final label = (m['display_name'] as String?)?.trim();
        if (label == null || label.isEmpty) continue;
        out.add(PatientPlaceSuggestion(description: label, latLng: LatLng(lat, lon)));
      } catch (_) {}
    }
    return out;
  }

  static Future<String?> _nominatimReverse(LatLng point) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': point.latitude.toString(),
      'lon': point.longitude.toString(),
      'format': 'json',
    });

    final res = await http
        .get(
          uri,
          headers: {'User-Agent': 'SmartAmbulanceDriver/1.0 (mobile patient report)'},
        )
        .timeout(_timeout);

    if (res.statusCode != 200) return null;
    final j = json.decode(res.body) as Map<String, dynamic>?;
    return (j?['display_name'] as String?)?.trim();
  }
}
