import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator_android/geolocator_android.dart';
import '../auth/login_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  StreamSubscription<Position>? _positionStream;
  bool _isOnline = false;
  String? _activeBookingId;
  Map<String, dynamic>? _activeBookingData; // Added to store mission details
  File? _scenePreview;
  File? _handoverPreview;
  // 🎨 UI Constants - Tactical Command Theme
  final Color primaryBlue = const Color(0xFF2563EB);
  final Color darkBlue = const Color(0xFF1E40AF);
  final Color bgGray = const Color(0xFFF8FAFC);
  final Color emergencyRed = const Color(0xFFEF4444);

  void _clearEvidencePreviews() {
    _scenePreview = null;
    _handoverPreview = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForNewJobs();
    _checkInitialStatus(); // Added to sync UI on restart
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _toggleStatus(false);
    }
  }

  // --- 🛠️ CORE FUNCTIONS (PRESERVED LOGIC) ---

  Future<void> _checkInitialStatus() async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;
  
  // 1. Get Driver Status
  final driverData = await supabase.from('drivers').select('status').eq('id', userId).single();
  
  // 2. 🟢 FIX: Check if there is an existing booking that is NOT completed
  final activeBooking = await supabase
      .from('bookings')
      .select()
      .eq('driver_id', userId)
      .filter('status', 'in', '("Accepted", "En Route", "Picked Up")') // Fetch all active states
      .maybeSingle();

  setState(() {
    _isOnline = (driverData['status'] == 'Available' || driverData['status'] == 'Busy');
    if (activeBooking != null) {
      final previousBookingId = _activeBookingId;
      _activeBookingId = activeBooking['id'].toString();
      _activeBookingData = activeBooking;
      if (previousBookingId != _activeBookingId) {
        _clearEvidencePreviews();
      }
    }
  });
}

  Future<void> _toggleStatus(bool value) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    
    // Prevent going offline during active mission
    if (value == false && _activeBookingId != null) {
      _showSnackBar("Cannot go offline during an active mission.");
      return;
    }

    final data = await supabase.from('drivers').select('status').eq('id', userId).single();
    if (data['status'] == 'Pending') {
      _showSnackBar("Your account is awaiting dispatcher verification.");
      return;
    } else if (data['status'] == 'Rejected') {
      _showSnackBar("Your account has been rejected. Contact admin.");
      return;
    }

    if (value) {
      bool hasPermission = await _handleLocationPermission();
      if (!hasPermission) return;
    }

    setState(() => _isOnline = value);

    try {
      await supabase.from('drivers').update({
        'status': _isOnline ? 'Available' : 'Offline',
      }).eq('id', userId);

      if (_isOnline) {
        _startLiveTracking();
      } else {
        await _positionStream?.cancel();
        _positionStream = null;
      }
    } catch (e) {
      debugPrint("❌ Status Toggle Error: $e");
    }
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    return true;
  }

  void _startLiveTracking() async {
    try {
      Position initialPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _updateDatabase(initialPos.latitude, initialPos.longitude);

      LocationSettings locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Ambulance tracking is active",
          notificationTitle: "Smart Dispatch Running",
          enableWakeLock: true,
        ),
      );

      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
        if (_isOnline) _updateDatabase(position.latitude, position.longitude);
      });
    } catch (e) {
      debugPrint("❌ Tracking Error: $e");
    }
  }

  void _updateDatabase(double lat, double lng) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase.from('drivers').update({'current_lat': lat, 'current_lng': lng}).eq('id', userId);
  }

  void _listenForNewJobs() {
    final myId = supabase.auth.currentUser?.id;
    supabase.channel('public:bookings').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'bookings',
      callback: (payload) {
        if (payload.newRecord['driver_id'] == myId) {
          _showJobPopup(payload.newRecord);
        }
      },
    ).subscribe();
  }

  String _safeEvidenceExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    return '.jpg';
  }

  Future<void> _takePhoto(String type) async {
  final ImagePicker picker = ImagePicker();
  
  // 1. Open the Camera
  final XFile? image = await picker.pickImage(
    source: ImageSource.camera,
    imageQuality: 50, // Compress to save mobile data
  );

  if (image == null) return; // User cancelled
  if (_activeBookingId == null) {
    _showSnackBar("No active mission found. Cannot upload evidence.");
    return;
  }
  setState(() {
    if (type == 'scene') _scenePreview = File(image.path);
    if (type == 'handover') _handoverPreview = File(image.path);
  });

  _showSnackBar("Uploading $type evidence...");

  try {
    final file = File(image.path);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw Exception('Selected image is empty.');

    final ext = _safeEvidenceExtension(file.path);
    final contentType = ext == '.png'
        ? 'image/png'
        : ext == '.webp'
            ? 'image/webp'
            : 'image/jpeg';

    final fileName = "bookings/${_activeBookingId!}/${type}_${DateTime.now().microsecondsSinceEpoch}$ext";
    
    // 2. Upload to Supabase Storage Bucket
    // Make sure you have a bucket named 'mission-evidence' created in Supabase!
    await supabase.storage.from('mission-evidence').uploadBinary(
          fileName,
          bytes,
          fileOptions: FileOptions(cacheControl: '3600', upsert: true, contentType: contentType),
        );

    // 3. (Optional) Log the URL back to your booking record
    final publicUrl = supabase.storage.from('mission-evidence').getPublicUrl(fileName);
    
    await supabase.from('bookings').update({
      type == 'scene' ? 'scene_photo' : 'handover_photo': publicUrl,
    }).eq('id', _activeBookingId!);

    setState(() {
      _activeBookingData ??= <String, dynamic>{};
      if (type == 'scene') {
        _activeBookingData!['scene_photo'] = publicUrl;
      } else {
        _activeBookingData!['handover_photo'] = publicUrl;
      }
    });

    _showSnackBar("✅ $type photo saved successfully.");
  } catch (e) {
    final msg = e.toString();
    debugPrint("❌ Photo Upload Error: $msg");
    if (msg.toLowerCase().contains('bucket') && msg.toLowerCase().contains('not found')) {
      _showSnackBar("Upload failed: bucket 'mission-evidence' not found in Supabase Storage.");
    } else if (msg.toLowerCase().contains('permission') || msg.toLowerCase().contains('not authorized') || msg.toLowerCase().contains('row level security')) {
      _showSnackBar("Upload failed: Storage permission denied (check RLS policy for 'mission-evidence').");
    } else {
      _showSnackBar("Upload failed: $msg");
    }
  }
}

  Future<void> _completeJob() async {
    if (_activeBookingId == null) return;
    try {
      final bookingData = await supabase.from('bookings').select().eq('id', _activeBookingId!).single();
      final List<Map<String, dynamic>> allHospitals = await supabase.from('hospitals').select().gt('beds', 0);

      Map<String, dynamic>? targetHospital;
      double minDistance = double.infinity;

      for (var hosp in allHospitals) {
        double dist = Geolocator.distanceBetween(
          (bookingData['latitude'] as num).toDouble(), 
          (bookingData['longitude'] as num).toDouble(), 
          (hosp['latitude'] as num).toDouble(), 
          (hosp['longitude'] as num).toDouble()
        );
        if (dist < minDistance) {
          minDistance = dist;
          targetHospital = hosp;
        }
      }

      if (targetHospital != null) {
        final updatedBooking = {
          'status': 'Picked Up',
          'location': 'Transferring to ${targetHospital['name']}',
          'latitude': targetHospital['latitude'],
          'longitude': targetHospital['longitude'],
          'destination_facility': targetHospital['id'],
        };
        await supabase.from('bookings').update(updatedBooking).eq('id', _activeBookingId!);

        if (mounted) {
          setState(() {
            _activeBookingData ??= <String, dynamic>{};
            _activeBookingData!.addAll(updatedBooking);
          });
        }

        _launchMaps(targetHospital['latitude'], targetHospital['longitude']);
        _showSnackBar("Rerouting to ${targetHospital['name']}...");
      }
    } catch (e) { debugPrint("❌ Reroute Error: $e"); }
  }

  // Change your popup to look like a Command, not a Choice
void _showJobPopup(Map<String, dynamic> booking) {
  showDialog(
    context: context,
    barrierDismissible: false, // Driver MUST acknowledge
    builder: (context) => AlertDialog(
      title: const Text("🚨 MISSION ASSIGNED"),
      content: Text("Proceed immediately to:\n${booking['location']}"),
      actions: [
        ElevatedButton(
          child: const Text("ACKNOWLEDGE & NAVIGATE"),
          onPressed: () async {
  // Update status to 'En Route' so it doesn't disappear
  await supabase.from('bookings').update({'status': 'En Route'}).eq('id', booking['id']);
  await supabase.from('drivers').update({'status': 'Busy'}).eq('id', supabase.auth.currentUser!.id);
  
  setState(() { 
    final previousBookingId = _activeBookingId;
    _activeBookingId = booking['id'].toString(); 
    _activeBookingData = booking;
    if (previousBookingId != _activeBookingId) {
      _clearEvidencePreviews();
    }
  });
  
  Navigator.pop(context);
  _launchMaps(booking['latitude'], booking['longitude']);
},
        ),
      ],
    ),
  );
}

  Future<void> _launchMaps(dynamic lat, dynamic lng) async {
    final url = Uri.parse("google.navigation:q=$lat,$lng&mode=d");
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.blueGrey[900], behavior: SnackBarBehavior.floating),
    );
  }

  // --- 🎨 UI COMPONENTS (INTEGRATED REDESIGN) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                _buildTacticalHeader(),
                _buildFloatingStatusCard(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Active Missions", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 15),
                      if (_activeBookingId != null) _buildProfessionalMissionCard() else _buildEmptyState(),
                      const SizedBox(height: 120), // Padding for bottom nav
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildTacticalHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 60, left: 25, right: 25, bottom: 80),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primaryBlue, darkBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: darkBlue.withOpacity(0.3), blurRadius: 20)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
                child: const Icon(Icons.shield_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Driver Portal", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  Text("Emergency Services", style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new, color: Colors.white, size: 28),
            onPressed: () async {
              await _toggleStatus(false);
              await supabase.auth.signOut();
              if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
            },
          )
        ],
      ),
    );
  }

  Widget _buildFloatingStatusCard() {
    return Transform.translate(
      offset: const Offset(0, -40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 25),
        child: Container(
          decoration: BoxDecoration(
            boxShadow: _isOnline ? [BoxShadow(color: Colors.green.withOpacity(0.15), blurRadius: 30, spreadRadius: 5)] : [],
          ),
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            elevation: 10,
            child: Padding(
              padding: const EdgeInsets.all(25),
              child: Row(
                children: [
                  Container(
                    width: 55, height: 55,
                    decoration: BoxDecoration(
                      color: _isOnline ? Colors.green[50] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.wifi_tethering, color: _isOnline ? Colors.green : Colors.grey, size: 28),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("System Connectivity", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                        Text(_isOnline ? "Online - Available" : "Offline", 
                          style: TextStyle(color: _isOnline ? Colors.green : Colors.grey, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _isOnline,
                    onChanged: _toggleStatus,
                    activeColor: Colors.green,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfessionalMissionCard() {
  // 🟢 State check: What is the current progress of the mission?
final String statusRaw = (_activeBookingData?['status'] ?? 'En Route').toString();
final String status = statusRaw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
final bool isPhase1 =
    status.contains('pending') ||
    status.contains('accepted') ||
    status.contains('en route') ||
    status.contains('assigned');
final bool isPhase2 = status.contains('picked up') || status.contains('pickedup') || status.contains('transferring');
final bool hasSceneEvidence =
    _scenePreview != null || ((_activeBookingData?['scene_photo'] ?? '').toString().trim().isNotEmpty);
final bool hasHandoverEvidence =
    _handoverPreview != null || ((_activeBookingData?['handover_photo'] ?? '').toString().trim().isNotEmpty);
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: primaryBlue.withOpacity(0.1)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("ACTIVE MISSION", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.1, color: Colors.blueGrey)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(12)),
              child: const Text("CRITICAL", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
            )
          ],
        ),
        const SizedBox(height: 6),
        Text(
          statusRaw,
          style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
        const SizedBox(height: 15),
        Text(_activeBookingData?['patient_name']?.toUpperCase() ?? "UNKNOWN PATIENT", 
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.location_on, color: primaryBlue, size: 16),
            const SizedBox(width: 5),
            Expanded(child: Text(_activeBookingData?['location'] ?? "Syncing location...", style: const TextStyle(color: Colors.grey))),
          ],
        ),
        const SizedBox(height: 25),

        _buildEvidenceStrip(),

        // --- 🚑 PHASE 1: ARRIVAL & SECURING PATIENT ---
        if (isPhase1) ...[
          // Step 1: Photo Evidence Button
          ElevatedButton.icon(
            onPressed: () => _takePhoto("scene"), // We will create this function
            icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
            label: const Text("CAPTURE SCENE EVIDENCE"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[700],
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          // Step 2: Secure & Reroute Button
          if (!hasSceneEvidence)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                "Capture scene evidence first to proceed.",
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ),
          if (hasSceneEvidence)
            ElevatedButton(
              onPressed: _completeJob, // Your existing reroute logic
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 5,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_hospital_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text("SECURE PATIENT & REROUTE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
        ],

        // --- 🏥 PHASE 2: HOSPITAL DISCHARGE ---
        if (isPhase2) ...[
          // Step 1: Handover Confirmation Button
          ElevatedButton.icon(
            onPressed: () => _takePhoto("handover"),
            icon: const Icon(Icons.assignment_turned_in_rounded, color: Colors.white),
            label: const Text("CAPTURE HANDOVER PHOTO"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[700],
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          // Step 2: Complete Discharge
          if (!hasHandoverEvidence)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                "Capture handover evidence before completing discharge.",
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ),
          if (hasHandoverEvidence)
            OutlinedButton(
              onPressed: () async {
                await supabase.from('bookings').update({'status': 'Completed'}).eq('id', _activeBookingId!);
                await supabase.from('drivers').update({'status': 'Available'}).eq('id', supabase.auth.currentUser!.id);
              setState(() {
                _activeBookingId = null;
                _activeBookingData = null;
                _clearEvidencePreviews();
              });
                _showSnackBar("Mission Completed Successfully");
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 55),
                side: const BorderSide(color: Colors.redAccent, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("COMPLETE DISCHARGE", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],

        if (!isPhase1 && !isPhase2) ...[
          ElevatedButton.icon(
            onPressed: () => _takePhoto("scene"),
            icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
            label: const Text("CAPTURE SCENE EVIDENCE"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[700],
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _buildEvidenceStrip() {
  final sceneUrl = (_activeBookingData?['scene_photo'] ?? '').toString().trim();
  final handoverUrl = (_activeBookingData?['handover_photo'] ?? '').toString().trim();
  final hasAny = _scenePreview != null ||
      _handoverPreview != null ||
      sceneUrl.isNotEmpty ||
      handoverUrl.isNotEmpty;

  if (!hasAny) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 15),
    child: Row(
      children: [
        if (_scenePreview != null || sceneUrl.isNotEmpty)
          _buildEvidenceThumbnail("SCENE", file: _scenePreview, url: sceneUrl),
        const SizedBox(width: 10),
        if (_handoverPreview != null || handoverUrl.isNotEmpty)
          _buildEvidenceThumbnail("HANDOVER", file: _handoverPreview, url: handoverUrl),
      ],
    ),
  );
}

Widget _buildEvidenceThumbnail(String label, {File? file, String? url}) {
  final u = (url ?? '').trim();
  final Widget image = file != null
      ? Image.file(file, width: 80, height: 80, fit: BoxFit.cover)
      : Image.network(
          u,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 80,
              height: 80,
              color: Colors.grey[200],
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
            );
          },
        );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: image,
      ),
    ],
  );
}

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Icon(Icons.radio_button_checked, size: 50, color: Colors.grey[300]),
          const SizedBox(height: 15),
          const Text("Ready and Scanning for SOS", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withOpacity(0), Colors.white.withOpacity(0.8)]),
        ),
        child: Container(
          height: 75,
          decoration: BoxDecoration(
            color: darkBlue,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [BoxShadow(color: darkBlue.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navIcon(Icons.home_filled, true),
              _navIcon(Icons.description_outlined, false),
              // Dynamic Navigate Button
              GestureDetector(
                onTap: () {
                  if (_activeBookingData != null) {
                    _launchMaps(_activeBookingData!['latitude'], _activeBookingData!['longitude']);
                  } else {
                    _showSnackBar("No active mission to navigate.");
                  }
                },
                child: Container(
                  height: 55, width: 55,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(Icons.navigation_rounded, color: darkBlue, size: 30),
                ),
              ),
              _navIcon(Icons.message_outlined, false),
              _navIcon(Icons.person_outline, false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, bool isActive) {
    return Icon(icon, color: isActive ? Colors.white : Colors.white54, size: 26);
  }
}