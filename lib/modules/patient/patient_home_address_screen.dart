import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'patient_home_address_service.dart';
import 'patient_location_map.dart';
import 'patient_places_service.dart';
import 'patient_ui.dart';

/// Save home pin + address for clinic "House / home" discharge routing.
class PatientHomeAddressScreen extends StatefulWidget {
  const PatientHomeAddressScreen({super.key});

  @override
  State<PatientHomeAddressScreen> createState() => _PatientHomeAddressScreenState();
}

class _PatientHomeAddressScreenState extends State<PatientHomeAddressScreen> {
  final _client = Supabase.instance.client;
  final _search = TextEditingController();

  LatLng _pin = LatLng(PatientUi.malaysiaDefaultLat, PatientUi.malaysiaDefaultLng);
  String _addressLine = '';
  List<PatientPlaceSuggestion> _searchHits = [];
  bool _loading = true;
  bool _saving = false;
  bool _searching = false;
  bool _loadingLoc = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final home = await PatientHomeAddressService.load(_client, uid);
      if (!mounted) return;
      if (home != null) {
        setState(() {
          _pin = LatLng(home.latitude, home.longitude);
          _addressLine = home.address;
          _search.text = home.address;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final trimmed = q.trim();
      if (trimmed.length < 3) {
        if (mounted) setState(() => _searchHits = []);
        return;
      }
      setState(() => _searching = true);
      try {
        final hits = await PatientPlacesService.autocomplete(trimmed, near: _pin);
        if (mounted) setState(() => _searchHits = hits);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _pickSuggestion(PatientPlaceSuggestion hit) async {
    if (hit.latLng != null) {
      setState(() {
        _pin = hit.latLng!;
        _addressLine = hit.description;
        _search.text = hit.description;
        _searchHits = [];
      });
      return;
    }
    if (hit.placeId == null) return;
    final details = await PatientPlacesService.fetchPlaceDetails(hit.placeId!);
    if (!mounted || details == null) return;
    setState(() {
      _pin = details.latLng;
      _addressLine = details.address;
      _search.text = details.address;
      _searchHits = [];
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _loadingLoc = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception('Location permission is required to set your home address.');
      }
      final pos = await Geolocator.getCurrentPosition();
      final next = LatLng(pos.latitude, pos.longitude);
      final name = await PatientPlacesService.reverseAddress(next);
      if (!mounted) return;
      setState(() {
        _pin = next;
        _addressLine = (name != null && name.isNotEmpty)
            ? name
            : '${next.latitude.toStringAsFixed(5)}, ${next.longitude.toStringAsFixed(5)}';
        _search.text = _addressLine;
        _searchHits = [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loadingLoc = false);
    }
  }

  Future<void> _save() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    final address = _addressLine.trim().isNotEmpty ? _addressLine.trim() : _search.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Search or pick your home on the map.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await PatientHomeAddressService.save(
        _client,
        uid,
        address: address,
        latitude: _pin.latitude,
        longitude: _pin.longitude,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Home address saved. Clinics can send you home after treatment.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e\nRun patient_profiles.sql in Supabase if the table is missing.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = PatientUi.accentRed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home address'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PatientUi.accentRed))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text(
                  'Used when a clinic sends you home after an ambulance trip. '
                  'Set this once so dispatch can route the driver to your house.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    labelText: 'Search home address',
                    hintText: 'Street, area, postcode…',
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_searchHits.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._searchHits.take(5).map(
                    (hit) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined, size: 20),
                      title: Text(hit.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _pickSuggestion(hit),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                PatientLocationMap(
                  center: _pin,
                  height: 200,
                  onPositionChanged: (ll) async {
                    setState(() => _pin = ll);
                    final name = await PatientPlacesService.reverseAddress(ll);
                    if (!mounted) return;
                    setState(() {
                      _addressLine = (name != null && name.isNotEmpty)
                          ? name
                          : '${ll.latitude.toStringAsFixed(5)}, ${ll.longitude.toStringAsFixed(5)}';
                    });
                  },
                ),
                if (_addressLine.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(_addressLine, style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _loadingLoc ? null : _useCurrentLocation,
                  icon: _loadingLoc
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.my_location, color: accent),
                  label: Text('Use current location', style: TextStyle(color: accent)),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: Text(_saving ? 'Saving…' : 'Save home address'),
                ),
              ],
            ),
    );
  }
}
