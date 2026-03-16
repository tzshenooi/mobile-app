import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator_android/geolocator_android.dart'; 

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  final supabase = Supabase.instance.client;
  StreamSubscription<Position>? _positionStream;
  bool _isOnline = false;
  String? _activeBookingId; // Tracks the current active job ID

  @override
  void initState() {
    super.initState();
    _listenForNewJobs();
  }

  void _toggleStatus(bool value) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isOnline = value);

    try {
      await supabase.from('drivers').update({
        'status': _isOnline ? 'Available' : 'Offline',
      }).eq('id', userId);

      if (_isOnline) {
        await _positionStream?.cancel();
        _startLiveTracking();
      } else {
        await _positionStream?.cancel();
        _positionStream = null;
        print("📡 Tracking Stopped Manually");
      }
    } catch (e) {
      print("❌ Status Toggle Error: $e");
    }
  }

  void _startLiveTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    Position initialPos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high
    );
    _updateDatabase(initialPos.latitude, initialPos.longitude);

    late LocationSettings locationSettings;

    if (Theme.of(context).platform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, 
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Ambulance tracking is active in the background",
          notificationTitle: "Smart Dispatch Running",
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );
    }

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      if (_isOnline) {
        _updateDatabase(position.latitude, position.longitude);
      }
    });
  }

  void _updateDatabase(double lat, double lng) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    
    print("🛰️ [${DateTime.now().second}s] Updating DB: $lat, $lng");
    await supabase.from('drivers').update({
      'current_lat': lat,
      'current_lng': lng,
    }).eq('id', userId);
  }

  void _listenForNewJobs() {
    supabase
        .channel('public:bookings')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'bookings',
          callback: (payload) {
            if (payload.newRecord['suggested_driver'] == 'hiarc') {
              // We show the popup but don't set the ID yet
              _showJobPopup(payload.newRecord);
            }
          },
        )
        .subscribe();
  }

  // 🔥 Manual Clear SOS logic
  Future<void> _completeJob() async {
    if (_activeBookingId == null) return;
    
    try {
      await supabase
          .from('bookings')
          .update({'status': 'Completed'})
          .eq('id', _activeBookingId!);

      setState(() {
        _activeBookingId = null; // Hide the button
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Patient Secured. SOS Cleared."))
      );
    } catch (e) {
      print("❌ Failed to complete job: $e");
    }
  }

  void _showJobPopup(Map<String, dynamic> booking) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("🚨 EMERGENCY ASSIGNED"),
        content: Text("Target: ${booking['location']}"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("IGNORE")
          ),
          ElevatedButton(
            onPressed: () {
              // 🔥 CRITICAL: Set the active ID when the driver accepts the job
              setState(() {
                _activeBookingId = booking['id'].toString();
              });
              Navigator.pop(context);
              _launchMaps(booking['latitude'], booking['longitude']);
            },
            child: const Text("NAVIGATE"),
          ),
        ],
      ),
    );
  }

  Future<void> _launchMaps(double lat, double lng) async {
    final url = Uri.parse("google.navigation:q=$lat,$lng&mode=d");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ambulance Driver"), 
        backgroundColor: _isOnline ? Colors.green : Colors.red
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isOnline ? Icons.radar : Icons.power_off, 
              size: 80, 
              color: _isOnline ? Colors.green : Colors.grey
            ),
            const SizedBox(height: 10),
            Text(
              _isOnline ? "ON DUTY" : "OFF DUTY", 
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text("Duty Status"), 
              value: _isOnline, 
              onChanged: _toggleStatus
            ),
            const SizedBox(height: 40),
            
            // 🔥 The button will now appear after you click "NAVIGATE" in the popup
            if (_activeBookingId != null) 
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  onPressed: _completeJob,
                  icon: const Icon(Icons.check_circle, color: Colors.white),
                  label: const Text(
                    "PATIENT SECURED (CLEAR SOS)", 
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}