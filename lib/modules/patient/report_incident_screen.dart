import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/clinic_config.dart';
import 'patient_location_map.dart';
import 'patient_places_service.dart';
import 'patient_report_fs_stub.dart'
    if (dart.library.io) 'patient_report_fs.dart';
import 'ambulance_tracking_screen.dart';
import 'patient_media_preview.dart';
import 'patient_ui.dart';

/// Incident types (stored in `patient_reports.incident_category`).
const List<({String key, String label})> kIncidentCategories = [
  (key: 'fire', label: 'Fire'),
  (key: 'crime', label: 'Crime'),
  (key: 'medical_aid', label: 'Medical Aid'),
  (key: 'humanitarian_aid', label: 'Humanitarian Aid'),
  (key: 'sea_emergency', label: 'Sea Emergency'),
];

String _incidentCategoryLabel(String key) {
  for (final c in kIncidentCategories) {
    if (c.key == key) return c.label;
  }
  return key;
}

class _PickedAttachment {
  _PickedAttachment(this.file, this.sizeBytes);

  final XFile file;
  final int sizeBytes;
}

class ReportIncidentScreen extends StatefulWidget {
  const ReportIncidentScreen({super.key});

  @override
  State<ReportIncidentScreen> createState() => _ReportIncidentScreenState();
}

class _ReportIncidentScreenState extends State<ReportIncidentScreen> {
  static const _maxAttachments = 5;
  static const _maxMegabytesCap = 5;
  static int get _maxBytes => _maxMegabytesCap * 1024 * 1024;

  final _details = TextEditingController();
  final _patientId = TextEditingController();
  String? _destinationType;
  final _picker = ImagePicker();
  final _voiceRecorder = AudioRecorder();

  LatLng _pin = LatLng(PatientUi.malaysiaDefaultLat, PatientUi.malaysiaDefaultLng);
  /// Human-readable line (Nominatim) + stored on submit as `location_label`.
  String _addressHint = '';
  String _addressDisplay = '';
  Timer? _geocodeDebounce;
  bool _geocoding = false;
  String? _categoryKey;
  bool _loadingLoc = false;
  bool _submitting = false;

  final List<_PickedAttachment> _attachments = [];
  int _attachmentBytesTotal = 0;

  static Color get _dividerGrey => const Color(0xFFBDBDBD);
  static Color get _textGrey => const Color(0xFF828282);

  @override
  void initState() {
    super.initState();
    _details.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _useCurrentLocation());
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _voiceRecorder.dispose();
    _details.dispose();
    _patientId.dispose();
    super.dispose();
  }

  void _recalcTotals() {
    _attachmentBytesTotal = _attachments.fold<int>(0, (a, x) => a + x.sizeBytes);
  }

  Future<void> _deletePath(String path) async => patientReportFsDelete(path);

  bool _canAddBytes(int incoming) {
    if (_attachments.length >= _maxAttachments) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 5 attachments.')));
      return false;
    }
    if (_attachmentBytesTotal + incoming > _maxBytes) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Total size exceeds $_maxMegabytesCap MB.')));
      return false;
    }
    return true;
  }

  Future<void> _addAttachment(XFile file, int sizeBytes) async {
    if (!_canAddBytes(sizeBytes)) return;
    setState(() {
      _attachments.add(_PickedAttachment(file, sizeBytes));
      _recalcTotals();
    });
  }

  Future<void> _ensureLocationPermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
      throw Exception('Turn on location permission in Settings.');
    }
  }

  void _scheduleReverseGeocode() {
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _reverseGeocode(_pin);
    });
  }

  Future<void> _reverseGeocode(LatLng ll) async {
    setState(() => _geocoding = true);
    final name = await PatientPlacesService.reverseAddress(ll);
    if (!mounted) return;
    final line = (name != null && name.isNotEmpty)
        ? name
        : '${ll.latitude.toStringAsFixed(5)}, ${ll.longitude.toStringAsFixed(5)}';
    setState(() {
      _addressDisplay = line;
      _addressHint = line;
      _geocoding = false;
    });
  }

  Future<void> _showChangeIncidentLocationSheet() async {
    final accent = Theme.of(context).colorScheme.primary;
    final picked = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return _ChangeIncidentLocationSheet(
          initial: _pin,
          accent: accent,
          dividerGrey: _dividerGrey,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _pin = picked);
      _scheduleReverseGeocode();
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _loadingLoc = true);
    try {
      await _ensureLocationPermission();
      final p0 = await Geolocator.getCurrentPosition();
      final next = LatLng(p0.latitude, p0.longitude);
      setState(() => _pin = next);
      _scheduleReverseGeocode();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loadingLoc = false);
    }
  }

  Future<void> _attachVoiceNote() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice notes are available on Android and iOS.')),
      );
      return;
    }
    if (!await _voiceRecorder.hasPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission is needed.')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final outPath = p.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');

    final recordedPath = await showModalBottomSheet<String?>(
      context: context,
      isDismissible: true,
      builder: (ctx) {
        return _VoiceRecordSheet(recorder: _voiceRecorder, targetPath: outPath, maxSeconds: 60);
      },
    );

    if (!mounted || recordedPath == null || recordedPath.isEmpty) {
      try {
        if (await _voiceRecorder.isRecording()) {
          await _voiceRecorder.cancel();
        }
      } catch (_) {}
      await _deletePath(outPath);
      return;
    }

    final len = await XFile(recordedPath).length();
    if (len == 0) {
      await _deletePath(recordedPath);
      return;
    }
    if (!_canAddBytes(len)) {
      await _deletePath(recordedPath);
      return;
    }
    await _addAttachment(XFile(recordedPath), len);
  }

  Future<void> _showCameraChoices() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _takePhotoFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Video (up to 10 seconds)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _takeShortVideoFromCamera();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _takePhotoFromCamera() async {
    try {
      final img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 82);
      if (img == null) return;
      final len = await img.length();
      await _addAttachment(img, len);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _takeShortVideoFromCamera() async {
    try {
      final vid = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 10),
      );
      if (vid == null) return;
      final len = await vid.length();
      await _addAttachment(vid, len);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _removeAttachment(int index) async {
    final item = _attachments.removeAt(index);
    await _deletePath(item.file.path);
    if (mounted) {
      setState(_recalcTotals);
    }
  }

  Future<void> _tryUploadAttachments(String reportId) async {
    if (kIsWeb || _attachments.isEmpty) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final client = Supabase.instance.client;
    const bucket = 'patient-reports';

    for (var i = 0; i < _attachments.length; i++) {
      final item = _attachments[i];
      try {
        final bytes = await item.file.readAsBytes();
        final rawName = p.basename(item.file.path);
        final name = rawName.replaceAll(RegExp(r'[^\w.-]'), '_');
        final objectPath = '$uid/$reportId/${DateTime.now().millisecondsSinceEpoch}_$i/$name';
        await client.storage.from(bucket).uploadBinary(
              objectPath,
              bytes,
              fileOptions: const FileOptions(cacheControl: '3600'),
            );
      } catch (_) {
        // Requires a `patient-reports` bucket + policies in Supabase.
      }
    }
  }

  Future<void> _submit() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in again.')));
      return;
    }
    final cat = _categoryKey;
    if (cat == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick an incident type.')));
      return;
    }
    final details = _details.text.trim();
    if (details.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter details.')));
      return;
    }
    if (details.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max 500 characters.')));
      return;
    }

    setState(() => _submitting = true);
    try {
      final inserted = await Supabase.instance.client
          .from('patient_reports')
          .insert({
            'reporter_user_id': uid,
            'reporter_name': Supabase.instance.client.auth.currentUser?.email,
            'reporter_phone': null,
            'latitude': _pin.latitude,
            'longitude': _pin.longitude,
            'location_label': _addressHint.isEmpty ? null : _addressHint,
            'incident_category': cat,
            'details': details,
            'status': 'submitted',
            'patient_id': _patientId.text.trim().isEmpty ? null : _patientId.text.trim(),
            'destination_type': _destinationType,
          })
          .select('id')
          .maybeSingle();

      final rid = inserted?['id']?.toString();
      if (rid != null) {
        if (_attachments.isNotEmpty) {
          await _tryUploadAttachments(rid);
        }

        final reporterLabel =
            Supabase.instance.client.auth.currentUser?.email?.split('@').first ?? 'Patient';
        final nowIso = DateTime.now().toUtc().toIso8601String();
        final pid = _patientId.text.trim();
        final mission = <String, dynamic>{
          'patient_name': reporterLabel,
          'patient_id': pid.isEmpty ? null : pid,
          'location': _addressHint.isEmpty ? null : _addressHint,
          'latitude': _pin.latitude,
          'longitude': _pin.longitude,
          'emergency_type': _incidentCategoryLabel(cat),
          'notes': details,
          'status': 'Pending',
          'driver_id': null,
          'patient_report_id': rid,
          'requested_at': nowIso,
          'destination_type': _destinationType,
          'medication_service_eligible': _destinationType == 'public_hospital',
        };
        if (ClinicConfig.hasClinicId) {
          mission['assigned_clinic_id'] = ClinicConfig.clinicId;
        }
        await Supabase.instance.client.from('bookings').insert(mission);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted.')));
      if (rid != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => AmbulanceTrackingScreen(patientReportId: rid),
          ),
        );
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e\nRun patient_reports setup in Supabase if the table is missing.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    OutlineInputBorder fieldBorder(Color c) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: 1));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context)),
        title: const Text(
          'Incident Details',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Text('Submit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          Text(
            'Note: Tap the map or use your current location if the incident happened somewhere other than your GPS position.',
            style: TextStyle(fontSize: 12.5, height: 1.35, color: _textGrey),
          ),
          const SizedBox(height: 12),
          PatientLocationMap(
            center: _pin,
            height: 200,
            zoom: 14,
            onPositionChanged: (latlng) {
              setState(() => _pin = latlng);
              _scheduleReverseGeocode();
            },
          ),
          const SizedBox(height: 14),
          if (_geocoding && _addressDisplay.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 3),
            )
          else if (_addressDisplay.isNotEmpty)
            Text(
              _addressDisplay,
              style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
            )
          else
            Text(
              '${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _showChangeIncidentLocationSheet,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent, width: 1.2),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              ),
              child: const Text('Change Incident Location', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _loadingLoc ? null : _useCurrentLocation,
            icon: _loadingLoc
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.my_location, size: 20, color: accent),
            label: Text('Use current location', style: TextStyle(color: accent, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 22),
          const Text(
            'Incident Information',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17.5, color: Colors.black87),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.95,
            ),
            itemCount: kIncidentCategories.length,
            itemBuilder: (ctx, i) {
              final c = kIncidentCategories[i];
              final sel = _categoryKey == c.key;
              return OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: sel ? accent : Colors.black87,
                  side: BorderSide(color: sel ? accent : _dividerGrey, width: 1),
                  backgroundColor: sel ? accent.withValues(alpha: 0.08) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => setState(() => _categoryKey = c.key),
                child: Text(c.label, textAlign: TextAlign.center),
              );
            },
          ),
          const SizedBox(height: 18),
          const Text(
            'Patient ID (optional)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _patientId,
            decoration: InputDecoration(
              hintText: 'NRIC or hospital number',
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: fieldBorder(_dividerGrey),
              enabledBorder: fieldBorder(_dividerGrey),
              focusedBorder: fieldBorder(accent.withValues(alpha: 0.7)),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Where should the ambulance go?',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _destinationType,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              border: fieldBorder(_dividerGrey),
              enabledBorder: fieldBorder(_dividerGrey),
              focusedBorder: fieldBorder(accent.withValues(alpha: 0.7)),
            ),
            hint: const Text('Select destination'),
            items: const [
              DropdownMenuItem(value: 'public_hospital', child: Text('Public hospital')),
              DropdownMenuItem(value: 'house', child: Text('House / home')),
              DropdownMenuItem(value: 'private_hospital', child: Text('Private hospital')),
            ],
            onChanged: (v) => setState(() => _destinationType = v),
          ),
          const SizedBox(height: 18),
          const Text(
            'Details',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              TextField(
                controller: _details,
                maxLines: 8,
                maxLength: 500,
                buildCounter: (context, {required currentLength, required maxLength, required isFocused}) =>
                    const SizedBox.shrink(),
                decoration: InputDecoration(
                  hintText: 'Details',
                  alignLabelWithHint: true,
                  contentPadding: const EdgeInsets.only(left: 14, top: 16, right: 14, bottom: 34),
                  border: fieldBorder(_dividerGrey),
                  enabledBorder: fieldBorder(_dividerGrey),
                  focusedBorder: fieldBorder(accent.withValues(alpha: 0.7)),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 8,
                child: Text(
                  'Character limit: ${_details.text.length}/500',
                  style: TextStyle(fontSize: 12, color: _textGrey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Text(
                'Attach Media',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17.5, color: Colors.black87),
              ),
              const Spacer(),
              Text(
                '${_attachments.length}/$_maxAttachments (${(_attachmentBytesTotal / (1024 * 1024)).toStringAsFixed(2)}MB/$_maxMegabytesCap)',
                style: TextStyle(fontSize: 13, color: _textGrey),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MediaSquareButton(
                  icon: Icons.mic_none_rounded,
                  label: 'Voice Note',
                  onTap: () => _attachVoiceNote(),
                  borderColor: _dividerGrey,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _MediaSquareButton(
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  onTap: () => _showCameraChoices(),
                  borderColor: _dividerGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: _dividerGrey),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: _attachments.isEmpty
                ? Text('No attachments added yet', style: TextStyle(color: _textGrey, fontSize: 14))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < _attachments.length; i++)
                        LocalAttachmentPreview(
                          file: _attachments[i].file,
                          compact: true,
                          onRemove: () => _removeAttachment(i),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Note: Upload a voice note (max 60 seconds) or a video (10 seconds)',
              style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaSquareButton extends StatelessWidget {
  const _MediaSquareButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.borderColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: Colors.grey.shade700),
              const SizedBox(height: 10),
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen style bottom sheet: move pin, GPS, then return chosen [LatLng].
class _ChangeIncidentLocationSheet extends StatefulWidget {
  const _ChangeIncidentLocationSheet({
    required this.initial,
    required this.accent,
    required this.dividerGrey,
  });

  final LatLng initial;
  final Color accent;
  final Color dividerGrey;

  @override
  State<_ChangeIncidentLocationSheet> createState() => _ChangeIncidentLocationSheetState();
}

class _ChangeIncidentLocationSheetState extends State<_ChangeIncidentLocationSheet> {
  late LatLng _pin;
  final TextEditingController _searchQuery = TextEditingController();
  bool _placesNewSession = true;
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  bool _loadingGps = false;
  bool _searching = false;
  bool _resolvingPlace = false;
  List<PatientPlaceSuggestion> _searchHits = [];

  void _searchUiTick() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _pin = widget.initial;
    _searchQuery.addListener(_searchUiTick);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchQuery.removeListener(_searchUiTick);
    _searchQuery.dispose();
    super.dispose();
  }

  void _onSearchTextChanged(String raw) {
    _searchDebounce?.cancel();
    final q = raw.trim();
    if (q.length < 2) {
      setState(() {
        _searchHits = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _runAddressSearch(q));
  }

  Future<void> _runAddressSearch(String q) async {
    final gen = ++_searchGeneration;
    try {
      final hits = await PatientPlacesService.autocomplete(q, newSession: _placesNewSession);
      _placesNewSession = false;
      if (!mounted || gen != _searchGeneration) return;
      setState(() {
        _searchHits = hits;
        _searching = false;
      });
      if (hits.isEmpty &&
          !PatientPlacesStatus.lastUsedGoogle &&
          PatientPlacesStatus.lastStatus != null &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Search: ${PatientPlacesStatus.lastStatus ?? "no results"}. '
              'In Google Cloud enable Places API (New) + Places API, and add an Android app restriction '
              '(package com.example.flutter_application_1 + your debug SHA-1) on the API key — '
              'HTTP referrer keys only work on the web app.',
            ),
            duration: const Duration(seconds: 7),
          ),
        );
      }
    } catch (_) {
      if (!mounted || gen != _searchGeneration) return;
      setState(() {
        _searchHits = [];
        _searching = false;
      });
    }
  }

  Future<void> _selectSearchHit(PatientPlaceSuggestion hit) async {
    LatLng? point = hit.latLng;
    if (point == null && hit.placeId != null) {
      setState(() => _resolvingPlace = true);
      final details = await PatientPlacesService.fetchPlaceDetails(hit.placeId!);
      if (!mounted) return;
      setState(() => _resolvingPlace = false);
      if (details == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load that address. Try another result.')),
        );
        return;
      }
      point = details.latLng;
    }
    if (point == null) return;

    setState(() {
      _pin = point!;
      _searchHits = [];
      _searchQuery.clear();
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _useGps() async {
    setState(() => _loadingGps = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        throw Exception('Turn on location permission in Settings.');
      }
      final p0 = await Geolocator.getCurrentPosition();
      final next = LatLng(p0.latitude, p0.longitude);
      if (!mounted) return;
      setState(() => _pin = next);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final viewInsets = mq.viewInsets.bottom;
    final maxSheetHeight =
        mq.size.height - mq.padding.top - mq.padding.bottom - viewInsets;

    OutlineInputBorder searchBorder(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: 1),
        );

    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight * 0.92),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Incident location',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.grey.shade900),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _searchQuery,
                    onChanged: _onSearchTextChanged,
                    onSubmitted: (v) {
                      _searchDebounce?.cancel();
                      final q = v.trim();
                      if (q.length >= 2) _runAddressSearch(q);
                    },
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search place or address (school, hospital, street…)',
                      prefixIcon: Icon(Icons.search, color: widget.accent),
                      suffixIcon: _searchQuery.text.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(Icons.clear, color: Colors.grey.shade600),
                              onPressed: () {
                                _searchDebounce?.cancel();
                                _searchQuery.clear();
                                setState(() {
                                  _searchHits = [];
                                  _searching = false;
                                });
                              },
                            ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                      border: searchBorder(widget.dividerGrey),
                      enabledBorder: searchBorder(widget.dividerGrey),
                      focusedBorder: searchBorder(widget.accent),
                    ),
                  ),
                ),
                if (_searching || _resolvingPlace)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_searchHits.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border.all(color: widget.dividerGrey),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _searchHits.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade300),
                          itemBuilder: (ctx, i) {
                            final h = _searchHits[i];
                            return ListTile(
                              dense: true,
                              leading: Icon(Icons.place_outlined, size: 22, color: Colors.grey.shade600),
                              title: h.primaryLine != null
                                  ? RichText(
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      text: TextSpan(
                                        style: const TextStyle(fontSize: 13.5, height: 1.25, color: Colors.black87),
                                        children: [
                                          TextSpan(
                                            text: h.primaryLine,
                                            style: const TextStyle(fontWeight: FontWeight.w700),
                                          ),
                                          if (h.secondaryLine != null && h.secondaryLine!.isNotEmpty)
                                            TextSpan(text: ' ${h.secondaryLine}'),
                                        ],
                                      ),
                                    )
                                  : Text(
                                      h.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13.5, height: 1.25),
                                    ),
                              trailing: Icon(Icons.north_west, size: 18, color: widget.accent),
                              onTap: _resolvingPlace ? null : () => _selectSearchHit(h),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                        child: Text(
                          'Pick a search result, or tap the map to move the pin.',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final mapH = constraints.maxHeight.clamp(120.0, 280.0);
                              return PatientLocationMap(
                                center: _pin,
                                height: mapH,
                                zoom: 16,
                                onPositionChanged: (latlng) => setState(() => _pin = latlng),
                              );
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: OutlinedButton.icon(
                          onPressed: _loadingGps ? null : _useGps,
                          icon: _loadingGps
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(Icons.my_location, color: widget.accent),
                          label: Text(
                            'Use current location',
                            style: TextStyle(color: widget.accent, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: widget.accent,
                            side: BorderSide(color: widget.dividerGrey),
                            minimumSize: const Size.fromHeight(44),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + mq.padding.bottom),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: widget.accent),
                            onPressed: () => Navigator.pop(context, _pin),
                            child: const Text('Done'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceRecordSheet extends StatefulWidget {
  const _VoiceRecordSheet({required this.recorder, required this.targetPath, required this.maxSeconds});

  final AudioRecorder recorder;
  final String targetPath;
  final int maxSeconds;

  @override
  State<_VoiceRecordSheet> createState() => _VoiceRecordSheetState();
}

class _VoiceRecordSheetState extends State<_VoiceRecordSheet> {
  Timer? _ticker;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      await widget.recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: widget.targetPath);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!mounted) return;
        setState(() => _elapsed++);
        if (_elapsed >= widget.maxSeconds) {
          await _finish();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    String? stopped;
    try {
      stopped = await widget.recorder.stop();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context, stopped ?? widget.targetPath);
  }

  Future<void> _discard() async {
    _ticker?.cancel();
    try {
      await widget.recorder.cancel();
    } catch (_) {}
    await patientReportFsDelete(widget.targetPath);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.paddingOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Recording', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text(
            '${_elapsed.clamp(0, widget.maxSeconds)} / ${widget.maxSeconds}s',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(onPressed: () => _discard(), child: const Text('Discard')),
              FilledButton(
                onPressed: () => _finish(),
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
