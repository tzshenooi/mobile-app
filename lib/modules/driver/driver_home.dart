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
  Map<String, dynamic>? _activeBookingData; // Added to store mission details

  // 🎨 UI Constants - Tactical Command Theme
  final Color primaryBlue = const Color(0xFF2563EB);
  final Color darkBlue = const Color(0xFF1E40AF);
  final Color bgGray = const Color(0xFFF8FAFC);
  final Color emergencyRed = const Color(0xFFEF4444);

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
    final data = await supabase.from('drivers').select('status').eq('id', userId).single();
    setState(() {
      _isOnline = (data['status'] == 'Available' || data['status'] == 'Busy');
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
        _showSnackBar("Rerouting to ${targetHospital['name']}...");
      }
    } catch (e) { debugPrint("❌ Reroute Error: $e"); }
  }

  void _showJobPopup(Map<String, dynamic> booking) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: emergencyRed),
            const SizedBox(width: 10),
            const Text("DISPATCH ALERT", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text("New SOS received. Proceed to:\n\n${booking['location']}", style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("IGNORE")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: emergencyRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              await supabase.from('bookings').update({'status': 'Accepted'}).eq('id', booking['id']);
              await supabase.from('drivers').update({'status': 'Busy'}).eq('id', supabase.auth.currentUser!.id);
              setState(() { 
                _activeBookingId = booking['id'].toString(); 
                _activeBookingData = booking;
                _isOnline = true; 
              });
              Navigator.pop(context);
              _launchMaps(booking['latitude'], booking['longitude']);
            },
            child: const Text("ACCEPT MISSION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
          ElevatedButton(
            onPressed: _completeJob,
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
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              await supabase.from('bookings').update({'status': 'Completed'}).eq('id', _activeBookingId!);
              await supabase.from('drivers').update({'status': 'Available'}).eq('id', supabase.auth.currentUser!.id);
              setState(() { _activeBookingId = null; _activeBookingData = null; });
              _showSnackBar("Mission Completed Successfully");
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              side: const BorderSide(color: Colors.redAccent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text("COMPLETE DISCHARGE", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          )
        ],
      ),
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