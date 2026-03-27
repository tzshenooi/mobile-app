import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator_android/geolocator_android.dart'; 

// 👇 Ensure this matches your project folder name
import '../auth/login_screen.dart'; 

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  final supabase = Supabase.instance.client;
  StreamSubscription<Position>? _positionStream;
  bool _isOnline = false;
  String? _activeBookingId; 

  @override
  void initState() {
    super.initState();
    _listenForNewJobs();
  }

  Future<void> _toggleStatus(bool value) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

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
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Location services are disabled. Please enable them.')));
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permissions are denied.')));
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Location permissions are permanently denied.')));
      }
      return false;
    }

    return true;
  }

  void _startLiveTracking() async {
    try {
      Position initialPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      _updateDatabase(initialPos.latitude, initialPos.longitude);

      late LocationSettings locationSettings;

      if (Theme.of(context).platform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2, 
          // Note: Ensure android.permission.WAKE_LOCK is in AndroidManifest.xml
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Ambulance tracking is active in the background",
            notificationTitle: "Smart Dispatch Running",
            enableWakeLock: true,
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
      }, onError: (e) {
        debugPrint("🛰️ Stream Error: $e");
      });
    } catch (e) {
      debugPrint("❌ Error starting tracking: $e");
      // Fallback if wake_lock fails
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Tracking started without WakeLock safety."))
        );
      }
    }
  }

  void _updateDatabase(double lat, double lng) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    
    try {
      await supabase.from('drivers').update({
        'current_lat': lat,
        'current_lng': lng,
      }).eq('id', userId);
    } catch (e) {
      debugPrint("❌ Database Update Error: $e");
    }
  }

  // void _listenForNewJobs() {
  //   supabase
  //       .channel('public:bookings')
  //       .onPostgresChanges(
  //         event: PostgresChangeEvent.insert,
  //         schema: 'public',
  //         table: 'bookings',
  //         callback: (payload) {
  //           if (payload.newRecord['suggested_driver'] == 'hiarc') {
  //             _showJobPopup(payload.newRecord);
  //           }
  //         },
  //       )
  //       .subscribe();
  // }

  void _listenForNewJobs() {
  final myId = supabase.auth.currentUser?.id; // Get the logged-in ID
  supabase
      .channel('public:bookings')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'bookings',
        callback: (payload) {
          // Listen for bookings specifically assigned to THIS driver's ID
          if (payload.newRecord['driver_id'] == myId) {
            _showJobPopup(payload.newRecord);
          }
        },
      )
      .subscribe();
}

  Future<void> _completeJob() async {
    if (_activeBookingId == null) return;
    
    try {
      await supabase
          .from('bookings')
          .update({'status': 'Completed'})
          .eq('id', _activeBookingId!);

      setState(() {
        _activeBookingId = null; 
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Patient Secured. SOS Cleared."), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      debugPrint("❌ Failed to complete job: $e");
    }
  }

  void _showJobPopup(Map<String, dynamic> booking) {
  // Check if the driver is currently on a mission
  bool isBusy = _activeBookingId != null;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text("EMERGENCY ALERT"),
      content: Text(isBusy 
        ? "New SOS received, but you are currently BUSY with another patient." 
        : "New SOS received at:\n${booking['location']}"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: const Text("IGNORE")
        ),
        // 🟢 DISABLE button if the driver is busy
        // Inside _showJobPopup in driver_home.dart
ElevatedButton(
  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
  onPressed: () async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // 1. Update mission status to 'Accepted'
      await supabase
          .from('bookings')
          .update({'status': 'Accepted'})
          .eq('id', booking['id']);

      // 2. Update driver status to 'Busy'
      await supabase
          .from('drivers')
          .update({'status': 'Busy'})
          .eq('id', userId);

      setState(() {
        _activeBookingId = booking['id'].toString();
      });

      if (mounted) Navigator.pop(context);
      
      // 3. Start Navigation
      _launchMaps(booking['latitude'], booking['longitude']);
    } catch (e) {
      debugPrint("❌ Error during acceptance: $e");
    }
  },
  child: const Text("ACCEPT & NAVIGATE", style: TextStyle(color: Colors.white)),
),
      ],
    ),
  );
}
  Future<void> _launchMaps(dynamic lat, dynamic lng) async {
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
        title: const Text("Ambulance Driver Portal"), 
        backgroundColor: _isOnline ? Colors.green : Colors.red,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              if (mounted) {
                Navigator.pushReplacement(
                  context, 
                  MaterialPageRoute(builder: (context) => const LoginScreen())
                );
              }
            },
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isOnline ? Icons.radar : Icons.power_off, 
              size: 100, 
              color: _isOnline ? Colors.green : Colors.grey
            ),
            const SizedBox(height: 10),
            Text(
              _isOnline ? "ON DUTY - TRACKING ACTIVE" : "OFF DUTY", 
              style: TextStyle(
                fontSize: 22, 
                fontWeight: FontWeight.bold,
                color: _isOnline ? Colors.green[700] : Colors.grey
              )
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50),
              child: SwitchListTile(
                title: const Text("Go Online"), 
                value: _isOnline, 
                onChanged: _toggleStatus,
                activeColor: Colors.green,
              ),
            ),
            const SizedBox(height: 50),
            if (_activeBookingId != null) 
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[900],
                    minimumSize: const Size(double.infinity, 65),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  onPressed: _completeJob,
                  icon: const Icon(Icons.check_circle, color: Colors.white, size: 28),
                  label: const Text(
                    "PATIENT SECURED (CLEAR SOS)", 
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}