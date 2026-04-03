import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator_android/geolocator_android.dart';
import '../auth/login_screen.dart';

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

  // 🎨 UI Constants matching your "Emergency Theme"
  final Color primaryBlue = const Color(0xFF2563EB);
  final Color darkBlue = const Color(0xFF1E40AF);
  final Color bgGray = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForNewJobs();
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

  // --- 🛠️ CORE FUNCTIONS (UNTOUCHED LOGIC) ---

  Future<void> _toggleStatus(bool value) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    if (value == false && _activeBookingId != null) return; 

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
        await supabase.from('bookings').update({
          'status': 'Picked Up',
          'location': 'Transferring to ${targetHospital['name']}',
          'latitude': targetHospital['latitude'],
          'longitude': targetHospital['longitude'],
          'destination_facility': targetHospital['id'],
        }).eq('id', _activeBookingId!);

        _launchMaps(targetHospital['latitude'], targetHospital['longitude']);
      }
    } catch (e) { debugPrint("❌ Reroute Error: $e"); }
  }

  void _showJobPopup(Map<String, dynamic> booking) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text("🚨 EMERGENCY ALERT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        content: Text("New SOS received at:\n${booking['location']}"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("IGNORE")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              await supabase.from('bookings').update({'status': 'Accepted'}).eq('id', booking['id']);
              await supabase.from('drivers').update({'status': 'Busy'}).eq('id', supabase.auth.currentUser!.id);
              setState(() { _activeBookingId = booking['id'].toString(); _isOnline = true; });
              Navigator.pop(context);
              _launchMaps(booking['latitude'], booking['longitude']);
            },
            child: const Text("ACCEPT", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _launchMaps(dynamic lat, dynamic lng) async {
    final url = Uri.parse("google.navigation:q=$lat,$lng&mode=d");
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  // --- 🎨 UI COMPONENTS (REDESIGNED) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 🔵 HEADER SECTION
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 60, left: 25, right: 25, bottom: 80),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [primaryBlue, darkBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
                          Text("Driver Portal", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          Text("Emergency Services", style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white),
                    onPressed: () async {
                      await _toggleStatus(false);
                      await supabase.auth.signOut();
                      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
                    },
                  )
                ],
              ),
            ),

            // 🏥 FLOATING STATUS CARD
            Transform.translate(
              offset: const Offset(0, -40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(
                          color: _isOnline ? Colors.green[50] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(Icons.medical_services_outlined, color: _isOnline ? Colors.green : Colors.grey, size: 28),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1E293B))),
                            Text(_isOnline ? "Online - Available" : "Offline", style: TextStyle(color: _isOnline ? Colors.green : Colors.grey, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isOnline,
                        onChanged: _toggleStatus,
                        activeColor: Colors.green,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 🚑 MISSION LIST
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Active Missions", style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const SizedBox(height: 15),
                  if (_activeBookingId != null) _buildActiveMissionCard() else _buildEmptyState(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveMissionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(backgroundColor: Colors.blue[50], child: Icon(Icons.emergency_outlined, color: primaryBlue, size: 20)),
                  const SizedBox(width: 12),
                  const Text("EM-MISSION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red[100]!)),
                child: const Text("High", style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
              )
            ],
          ),
          const SizedBox(height: 20),
          // Actions
          GestureDetector(
            onTap: _completeJob,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [primaryBlue, darkBlue]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: primaryBlue.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 5))],
              ),
              child: const Center(child: Text("PATIENT SECURED (REROUTE)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              await supabase.from('bookings').update({'status': 'Completed'}).eq('id', _activeBookingId!);
              await supabase.from('drivers').update({'status': 'Available'}).eq('id', supabase.auth.currentUser!.id);
              setState(() => _activeBookingId = null);
            },
            child: const Text("Arrived at Hospital? Clear SOS", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 10),
            const Text("No missions currently active", style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}