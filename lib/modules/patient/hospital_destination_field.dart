import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'patient_clinic_routing.dart';
import 'patient_places_service.dart';

/// Hybrid hospital picker: registered clinic dropdown or Google/OSM hospital search.
class HospitalDestinationField extends StatefulWidget {
  const HospitalDestinationField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final HospitalDestinationSelection? value;
  final ValueChanged<HospitalDestinationSelection?> onChanged;
  final bool enabled;

  @override
  State<HospitalDestinationField> createState() => _HospitalDestinationFieldState();
}

class _HospitalDestinationFieldState extends State<HospitalDestinationField> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _searchGen = 0;
  bool _loadingClinics = true;
  bool _searching = false;
  List<RoutableClinic> _clinics = [];
  List<PatientPlaceSuggestion> _hits = [];

  @override
  void initState() {
    super.initState();
    _search.text = widget.value?.source == HospitalDestinationSource.search
        ? widget.value!.name
        : '';
    _search.addListener(_onSearchChanged);
    _loadClinics();
  }

  @override
  void didUpdateWidget(HospitalDestinationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == null && oldWidget.value != null) {
      _search.clear();
      setState(() => _hits = []);
    } else if (widget.value?.source == HospitalDestinationSource.search &&
        widget.value?.name != oldWidget.value?.name) {
      _search.text = widget.value!.name;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadClinics() async {
    try {
      final rows = await Supabase.instance.client
          .from('clinics')
          .select('id, name, address, latitude, longitude, specialty')
          .order('name');
      if (!mounted) return;
      final clinics = <RoutableClinic>[];
      for (final raw in rows) {
        final clinic = PatientClinicRouting.fromRow(Map<String, dynamic>.from(raw as Map));
        if (clinic != null) clinics.add(clinic);
      }
      setState(() {
        _clinics = clinics;
        _loadingClinics = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingClinics = false);
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final q = _search.text.trim();
    if (q.length < 2) {
      setState(() {
        _hits = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final gen = ++_searchGen;
    try {
      final hits = await PatientPlacesService.searchHospitals(q);
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _hits = hits;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _hits = [];
        _searching = false;
      });
    }
  }

  void _selectRegistered(String? clinicId) {
    if (!widget.enabled) return;
    if (clinicId == null || clinicId.isEmpty) {
      widget.onChanged(null);
      _search.clear();
      return;
    }
    RoutableClinic? clinic;
    for (final c in _clinics) {
      if (c.id == clinicId) {
        clinic = c;
        break;
      }
    }
    if (clinic == null) return;
    _search.clear();
    setState(() => _hits = []);
    widget.onChanged(HospitalDestinationSelection(
      name: clinic.name,
      address: clinic.address ?? clinic.name,
      latitude: clinic.latitude,
      longitude: clinic.longitude,
      clinicId: clinic.id,
      source: HospitalDestinationSource.registered,
    ));
  }

  Future<void> _pickSuggestion(PatientPlaceSuggestion hit) async {
    if (!widget.enabled) return;

    LatLng? point = hit.latLng;
    String address = hit.description;
    String name = hit.primaryLine?.trim().isNotEmpty == true
        ? hit.primaryLine!.trim()
        : hit.description.split(',').first.trim();

    if (point == null && hit.placeId != null) {
      final details = await PatientPlacesService.fetchPlaceDetails(hit.placeId!);
      if (details == null) return;
      point = details.latLng;
      address = details.address;
      if (name.isEmpty) {
        name = details.address.split(',').first.trim();
      }
    }
    if (point == null) return;

    final matched = PatientClinicRouting.matchClinicByName(_clinics, name);
    _search.text = name;
    setState(() => _hits = []);
    widget.onChanged(HospitalDestinationSelection(
      name: name,
      address: address,
      latitude: point.latitude,
      longitude: point.longitude,
      clinicId: matched?.id,
      source: HospitalDestinationSource.search,
    ));
  }

  String? get _registeredId {
    final v = widget.value;
    if (v == null || v.source != HospitalDestinationSource.registered) return null;
    return v.clinicId;
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: _registeredId,
          decoration: InputDecoration(
            labelText: 'Registered clinic',
            border: const OutlineInputBorder(),
            helperText: _loadingClinics
                ? 'Loading clinics…'
                : _clinics.isEmpty
                    ? 'No clinics with map location yet — use search below.'
                    : null,
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Quick pick from registered clinics…')),
            ..._clinics.map(
              (c) => DropdownMenuItem(
                value: c.id,
                child: Text(
                  c.specialty != null && c.specialty!.isNotEmpty
                      ? '${c.name} · ${c.specialty}'
                      : c.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: widget.enabled && !_loadingClinics ? _selectRegistered : null,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '— or search on Google Maps —',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 12),
        if (PatientPlacesStatus.googleBlockedForMobile)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Hospital search uses OpenStreetMap when Google is unavailable on mobile.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
            ),
          ),
        TextField(
          controller: _search,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: 'Search hospital name',
            hintText: 'e.g. Lam Wah Ee, Gleneagles…',
            border: const OutlineInputBorder(),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        if (_hits.isNotEmpty)
          ..._hits.take(5).map(
                (h) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.local_hospital_outlined, size: 20),
                  title: Text(
                    h.primaryLine ?? h.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: h.secondaryLine != null
                      ? Text(h.secondaryLine!, maxLines: 2, overflow: TextOverflow.ellipsis)
                      : null,
                  onTap: () => _pickSuggestion(h),
                ),
              ),
        if (value != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blueGrey.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (value.address.isNotEmpty && value.address != value.name) ...[
                  const SizedBox(height: 4),
                  Text(
                    value.address,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${value.latitude.toStringAsFixed(5)}, ${value.longitude.toStringAsFixed(5)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    value.source == HospitalDestinationSource.registered
                        ? 'Registered clinic'
                        : 'Google / map search',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
