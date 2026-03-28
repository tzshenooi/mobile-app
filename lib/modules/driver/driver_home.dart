import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator_android/geolocator_android.dart';

// 👇 Ensure this matches your project folder structure
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 🟢 Force status to Offline on every fresh launch/login
    // _activeBookingId = null;
    // _toggleStatus(false);
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
    // 🟢 Only toggle offline if the app is fully CLOSED (detached)
    // Removed 'paused' so navigation doesn't kill your status
    if (state == AppLifecycleState.detached) {
      _toggleStatus(false);
    }
  }

  Future<void> _toggleStatus(bool value) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;

  // 🟢 If we are on an active mission, don't allow going offline 
  // unless the user really forces it.
  if (!value && _activeBookingId != null) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot go offline during an active mission!"))
      );
    }
    return; 
  }

  if (value) {
    bool hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;
  }

  setState(() => _isOnline = value);

  try {
    await supabase.from('drivers').update({
      'status': value ? 'Available' : 'Offline',
    }).eq('id', userId);

    if (value) {
      _startLiveTracking();
    } else {
      _positionStream?.cancel();
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
        return false;
      }
    }
    return true;
  }

  void _startLiveTracking() async {
    try {
      Position initialPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _updateDatabase(initialPos.latitude, initialPos.longitude);

      late LocationSettings locationSettings;
      if (Theme.of(context).platform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Ambulance tracking is active in the background",
            notificationTitle: "Smart Dispatch Running",
            enableWakeLock: true,
          ),
        );
      } else {
        locationSettings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2);
      }

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
  final channel = supabase.channel('public:bookings');

  channel.onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: 'bookings',
    callback: (payload) {
      print("🔔 Realtime Payload Received: ${payload.newRecord}"); // 🟢 Debug point
      if (payload.newRecord['driver_id'] == myId) {
        _showJobPopup(payload.newRecord);
      }
    },
  ).subscribe((status, [error]) {
    print("🛰️ Subscription Status: $status"); // 🟢 Should say 'SUBSCRIBED'
  });
}

  // 🚀 SMART REROUTE LOGIC
  Future<void> _completeJob() async {
    if (_activeBookingId == null) return;

    try {
      final bookingData = await supabase.from('bookings').select().eq('id', _activeBookingId!).single();
      final String emergencyType = bookingData['emergency_type'] ?? 'Medical';
      final double lat = (bookingData['latitude'] as num).toDouble();
      final double lng = (bookingData['longitude'] as num).toDouble();

      // Fetch all available hospitals
      final List<Map<String, dynamic>> allHospitals = await supabase.from('hospitals').select().gt('beds', 0);

      Map<String, dynamic>? targetHospital;
      double minDistance = double.infinity;

      for (var hosp in allHospitals) {
        double dist = Geolocator.distanceBetween(lat, lng, (hosp['latitude'] as num).toDouble(), (hosp['longitude'] as num).toDouble());
        
        // Prioritize specialty matches first
        if (hosp['specialty'] == emergencyType) {
          targetHospital = hosp;
          minDistance = dist;
          break; 
        }
        if (dist < minDistance) {
          minDistance = dist;
          targetHospital = hosp;
        }
      }

      if (targetHospital != null) {
        // Update booking for Reroute
        await supabase.from('bookings').update({
          'status': 'Picked Up',
          'location': 'Transferring to ${targetHospital['name']}',
          'latitude': targetHospital['latitude'],
          'longitude': targetHospital['longitude'],
          'destination_facility': targetHospital['id'],
        }).eq('id', _activeBookingId!);

        _launchMaps(targetHospital['latitude'], targetHospital['longitude']);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("🚑 Rerouting to ${targetHospital['name']} (${(minDistance / 1000).toStringAsFixed(1)}km)"),
            backgroundColor: Colors.blue[800],
          ));
        }
      }
    } catch (e) {
      debugPrint("❌ Reroute Error: $e");
    }
  }

  void _showJobPopup(Map<String, dynamic> booking) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("EMERGENCY ALERT"),
        content: Text("New SOS received at:\n${booking['location']}"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("IGNORE")),
          ElevatedButton(
  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
  onPressed: () async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // 🟢 1. Update Mission Status to 'Accepted'
      await supabase
          .from('bookings')
          .update({'status': 'Accepted'})
          .eq('id', booking['id']);

      // 🟢 2. Update Driver to 'Busy' 
      // This tells the React Dashboard to turn the dot Orange
      await supabase
          .from('drivers')
          .update({'status': 'Busy'})
          .eq('id', userId);

      // 🟢 3. Synchronize Local State
      setState(() {
        _isOnline = true; // FORCE UI to stay green/online
        _activeBookingId = booking['id'].toString();
      });

      // 🟢 4. UI Cleanup & Navigation
      if (mounted) {
        Navigator.pop(context); // Close the popup
        
        // Brief delay ensures database write is finished before opening Maps
        Future.delayed(const Duration(milliseconds: 500), () {
          _launchMaps(booking['latitude'], booking['longitude']);
        });
      }
      
      debugPrint("✅ Job Accepted. Driver status: Busy, App state: Online");
    } catch (e) {
      debugPrint("❌ Accept Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error accepting job: $e"), backgroundColor: Colors.red),
        );
      }
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
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  Future<void> _showHandoverDialog() async {
  final TextEditingController notesController = TextEditingController();
  String severity = 'Stable';

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [Icon(Icons.assignment_turned_in, color: Colors.blue), SizedBox(width: 10), Text("Patient Handover")],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Enter final observations for the receiving doctor:"),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            value: severity,
            items: ['Stable', 'Critical', 'Unconscious'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) => severity = val!,
            decoration: const InputDecoration(labelText: "Condition on Arrival"),
          ),
          TextField(
            controller: notesController,
            maxLines: 3,
            decoration: const InputDecoration(hintText: "Notes (e.g., Blood pressure, allergies...)"),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
        ElevatedButton(
          onPressed: () async {
            // 🟢 Update Booking with Handover Notes
            await supabase.from('bookings').update({
              'status': 'Completed',
              'handover_notes': notesController.text,
              'patient_condition': severity,
              'completed_at': DateTime.now().toIso8601String(),
            }).eq('id', _activeBookingId!);

            // 🟢 Set Driver back to Available
            await supabase.from('drivers').update({'status': 'Available'}).eq('id', supabase.auth.currentUser!.id);
            
            setState(() => _activeBookingId = null);
            if (mounted) Navigator.pop(context);
          },
          child: const Text("SUBMIT & CLOSE MISSION"),
        ),
      ],
    ),
  );
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
              await _toggleStatus(false);
              await supabase.auth.signOut();
              if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
            },
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_isOnline ? Icons.radar : Icons.power_off, size: 100, color: _isOnline ? Colors.green : Colors.grey),
            const SizedBox(height: 10),
            Text(_isOnline ? "ON DUTY - TRACKING ACTIVE" : "OFF DUTY", 
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _isOnline ? Colors.green[700] : Colors.grey)),
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
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[900],
                        minimumSize: const Size(double.infinity, 65),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                      ),
                      onPressed: _completeJob, // 🚑 Trigger Reroute
                      icon: const Icon(Icons.local_hospital, color: Colors.white, size: 28),
                      label: const Text("PATIENT SECURED (REROUTE)", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 15),
TextButton(
                      onPressed: () async {
                        final userId = supabase.auth.currentUser?.id;
                        if (userId == null) return;

                        await supabase.from('bookings').update({'status': 'Completed'}).eq('id', _activeBookingId!);
                        await supabase.from('drivers').update({'status': 'Available'}).eq('id', userId);
                        
                        setState(() {
                          _activeBookingId = null;
                          _isOnline = true; // 🟢 Keep them online so they are available for next job
                        });
                      },
                      child: const Text("Arrived at Hospital? Clear SOS", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}