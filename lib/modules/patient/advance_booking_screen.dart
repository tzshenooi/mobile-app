import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/nearest_clinic_service.dart';
import '../../config/clinic_config.dart';
import 'hospital_destination_field.dart';
import 'patient_clinic_routing.dart';
import 'patient_location_map.dart';
import 'patient_places_service.dart';
import 'patient_ui.dart';
/// Advance / bedridden non-emergency transport request for the linked clinic.
class AdvanceBookingScreen extends StatefulWidget {
  const AdvanceBookingScreen({super.key});

  @override
  State<AdvanceBookingScreen> createState() => _AdvanceBookingScreenState();
}

class _AdvanceBookingScreenState extends State<AdvanceBookingScreen> {
  final _patientName = TextEditingController();
  final _patientId = TextEditingController();
  final _notes = TextEditingController();
  final _addressSearch = TextEditingController();

  LatLng _pin = LatLng(PatientUi.malaysiaDefaultLat, PatientUi.malaysiaDefaultLng);
  String _addressLine = '';
  String? _destinationType;
  HospitalDestinationSelection? _hospitalDestination;  DateTime? _pickupAt;
  bool _bedridden = true;
  bool _loadingLoc = false;
  bool _submitting = false;
  bool _searching = false;
  Timer? _searchDebounce;
  int _searchGen = 0;
  List<PatientPlaceSuggestion> _searchHits = [];

  @override
  void initState() {
    super.initState();
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    _patientName.text = email.split('@').first;
    _addressSearch.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _useCurrentLocation());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _addressSearch.removeListener(_onSearchChanged);
    _patientName.dispose();
    _patientId.dispose();
    _notes.dispose();    _addressSearch.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final q = _addressSearch.text.trim();
    if (q.length < 3) {
      setState(() {
        _searchHits = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final gen = ++_searchGen;
    try {
      final hits = await PatientPlacesService.autocomplete(q, near: _pin);
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _searchHits = hits;
        _searching = false;
      });
      if (PatientPlacesStatus.googleBlockedForMobile && mounted) setState(() {});
    } catch (_) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _searchHits = [];
        _searching = false;
      });
    }
  }

  Future<void> _pickSuggestion(PatientPlaceSuggestion hit) async {
    if (hit.latLng != null) {
      setState(() {
        _pin = hit.latLng!;
        _addressLine = hit.description;
        _searchHits = [];
        _addressSearch.text = hit.description;
      });
      return;
    }
    if (hit.placeId == null) return;
    final details = await PatientPlacesService.fetchPlaceDetails(hit.placeId!);
    if (!mounted || details == null) return;
    setState(() {
      _pin = details.latLng;
      _addressLine = details.address;
      _searchHits = [];
      _addressSearch.text = details.address;
    });
  }

  Future<void> _reverseGeocode(LatLng ll) async {
    final name = await PatientPlacesService.reverseAddress(ll);
    if (!mounted) return;
    setState(() {
      _addressLine = (name != null && name.isNotEmpty)
          ? name
          : '${ll.latitude.toStringAsFixed(5)}, ${ll.longitude.toStringAsFixed(5)}';
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
        throw Exception('Location permission is required for pickup.');
      }
      final pos = await Geolocator.getCurrentPosition();
      final next = LatLng(pos.latitude, pos.longitude);
      setState(() => _pin = next);
      await _reverseGeocode(next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loadingLoc = false);
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null || !mounted) return;
    setState(() {
      _pickupAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String _formatPickup(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} $h:$m';
  }

  Future<void> _submit() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final name = _patientName.text.trim();
    final pid = _patientId.text.trim();
    if (name.isEmpty || pid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter patient name and ID.')));
      return;
    }
    if (_destinationType == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a destination type.')));
      return;
    }
    if (PatientClinicRouting.isHospitalDestinationType(_destinationType)) {
      if (_hospitalDestination == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pick a clinic from the list or search on Google Maps.'),
          ),
        );
        return;
      }
    }
    if (_pickupAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a pickup date and time.')));
      return;
    }
    if (_pickupAt!.isBefore(DateTime.now().add(const Duration(minutes: 15)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pickup must be at least 15 minutes from now.')),
      );
      return;
    }
    if (_addressLine.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set a pickup address.')));
      return;
    }

    setState(() => _submitting = true);
    try {
      final assignedClinic = await NearestClinicService.resolveForPatient(
        client: Supabase.instance.client,
        latitude: _pin.latitude,
        longitude: _pin.longitude,
        fallbackClinicId: ClinicConfig.hasClinicId ? ClinicConfig.clinicId : null,
      );
      if (assignedClinic == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No clinic with a map location found. Ask your clinic to set their address in the portal.',
            ),
          ),
        );
        return;
      }

      final dest = _hospitalDestination;
      await Supabase.instance.client.from('bookings').insert({
        'patient_name': name,
        'patient_id': pid,
        'location': _addressLine,
        'latitude': _pin.latitude,
        'longitude': _pin.longitude,
        'emergency_type': 'Scheduled',
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'status': 'Scheduled',
        'booking_kind': 'scheduled',
        'scheduled_at': _pickupAt!.toUtc().toIso8601String(),
        'is_bedridden': _bedridden,
        'driver_id': null,
        'reporter_user_id': uid,
        'assigned_clinic_id': assignedClinic.id,
        'requested_at': DateTime.now().toUtc().toIso8601String(),
        'hospital_name': dest?.name,
        'destination_type': _destinationType,
        'destination_clinic_id': dest?.clinicId,
        'destination_latitude': dest?.latitude,
        'destination_longitude': dest?.longitude,
        'medication_service_eligible': _destinationType == 'public_hospital',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scheduled booking sent to ${assignedClinic.name}.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = PatientUi.accentRed;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule transport'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Text(
            'Non-emergency / bedridden transport. Your clinic will confirm and dispatch closer to the pickup time.',
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bedridden / stretcher required'),
            value: _bedridden,
            activeThumbColor: accent,
            onChanged: (v) => setState(() => _bedridden = v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Planned pickup'),
            subtitle: Text(_pickupAt == null ? 'Tap to choose' : _formatPickup(_pickupAt!)),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: _pickDateTime,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _patientId,
            decoration: const InputDecoration(labelText: 'Patient ID', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _patientName,
            decoration: const InputDecoration(labelText: 'Patient name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _destinationType,
            decoration: const InputDecoration(labelText: 'Destination', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'public_hospital', child: Text('Public')),
              DropdownMenuItem(value: 'house', child: Text('House / home')),
              DropdownMenuItem(value: 'private_hospital', child: Text('Private')),
            ],
            onChanged: (v) => setState(() {
              _destinationType = v;
              if (!PatientClinicRouting.isHospitalDestinationType(v)) {
                _hospitalDestination = null;
              }
            }),
          ),
          if (PatientClinicRouting.isHospitalDestinationType(_destinationType)) ...[
            const SizedBox(height: 16),
            const Text('Destination', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            HospitalDestinationField(
              value: _hospitalDestination,
              onChanged: (v) => setState(() => _hospitalDestination = v),
            ),
          ],          const SizedBox(height: 16),
          const Text('Pickup location', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (PatientPlacesStatus.googleBlockedForMobile)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Address search uses OpenStreetMap (Google key is web-only). '
                'You can also drag the map pin or use GPS.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
              ),
            ),
          TextField(
            controller: _addressSearch,
            decoration: InputDecoration(
              hintText: 'Search address…',
              border: const OutlineInputBorder(),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
          if (_searchHits.isNotEmpty)
            ..._searchHits.take(5).map(
              (h) => ListTile(
                dense: true,
                title: Text(h.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => _pickSuggestion(h),
              ),
            ),
          const SizedBox(height: 8),
          PatientLocationMap(
            center: _pin,
            height: 200,
            onPositionChanged: (p) {
              setState(() => _pin = p);
              _reverseGeocode(p);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _addressLine.isEmpty ? 'Move the pin or search above' : _addressLine,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          TextButton.icon(
            onPressed: _loadingLoc ? null : _useCurrentLocation,
            icon: _loadingLoc
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            label: const Text('Use my location'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(_submitting ? 'Submitting…' : 'Submit to clinic'),
          ),
        ],
      ),
    );
  }
}
