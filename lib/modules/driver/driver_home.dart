import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; // Ensure geolocator is in pubspec.yaml
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; 
import '../../main.dart';
import '../auth/login_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    // Use a slight delay to ensure the UI is ready before triggering GPS permissions
    Future.delayed(Duration.zero, () {
      _initGpsUpdates();
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel(); // Stop tracking when app is closed or logged out
    super.dispose();
  }

  // --- NEW: Safe GPS Initialization (Fulfills FR-002) ---
  Future<void> _initGpsUpdates() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      // Start listener: Updates Supabase every 10 meters moved
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, 
        ),
      ).listen((Position position) async {
        final user = supabase.auth.currentUser;
        if (user != null) {
          await supabase.from('drivers').update({
            'current_lat': position.latitude,
            'current_lng': position.longitude,
          }).eq('email', user.email!);
        }
      });
    } catch (e) {
      debugPrint("GPS Error: $e");
    }
  }

  // 1. Logout Function
  Future<void> logout() async {
    await _positionStream?.cancel();
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  // 2. Open Google Maps (Fulfills FR-004)
  Future<void> openMap(String locationName) async {
    final query = Uri.encodeComponent(locationName);
    // Properly formatted navigation URL for real-time routing
    final googleUrl = Uri.parse("google.navigation:q=$query&mode=d");
    try {
      if (await canLaunchUrl(googleUrl)) {
        await launchUrl(googleUrl, mode: LaunchMode.externalApplication);
      } else {
        // Fallback for browsers/simulators
        final webUrl = Uri.parse("https://www.google.com/maps/search/?api=1&query=$query");
        await launchUrl(webUrl);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open Maps")));
      }
    }
  }

  // 3. Accept Job Logic (Fulfills FR-007)
  Future<void> acceptJob(int jobId) async {
    final user = supabase.auth.currentUser;
    await supabase.from('bookings').update({
      'status': 'Accepted',
      'driver_id': user?.email,
    }).eq('id', jobId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Tasks", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFFE74C3C), 
        actions: [
          IconButton(
            onPressed: logout,
            icon: const Icon(Icons.logout, color: Colors.white),
          )
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase.from('bookings').stream(primaryKey: ['id']).order('created_at'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final jobs = snapshot.data!;
          final currentUserEmail = supabase.auth.currentUser?.email;

          final myJobs = jobs.where((job) {
             return job['driver_id'] == currentUserEmail;
          }).toList();

          if (myJobs.isEmpty) {
            return const Center(child: Text("No jobs assigned to you yet 📭"));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: myJobs.length,
            itemBuilder: (context, index) {
              final job = myJobs[index];
              final isAccepted = job['status'] == 'Accepted';

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "EMERGENCY: ${job['emergency_type'] ?? 'Medical'}",
                            style: const TextStyle(color: Color(0xFFE74C3C), fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isAccepted ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              job['status'],
                              style: TextStyle(
                                color: isAccepted ? Colors.green : Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const Divider(height: 24, color: Color(0xFFEEEEEE)),

                      _buildInfoRow("Patient:", job['patient_name'] ?? 'Unknown'),
                      const SizedBox(height: 8),
                      _buildInfoRow("Location:", job['location'] ?? 'Unknown'),
                      if (job['notes'] != null && job['notes'] != '') ...[
                         const SizedBox(height: 8),
                         _buildInfoRow("Notes:", job['notes']),
                      ],

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (isAccepted) {
                              openMap(job['location'] ?? '');
                            } else {
                              acceptJob(job['id']);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isAccepted ? const Color(0xFF27AE60) : const Color(0xFFE74C3C),
                            foregroundColor: Colors.white,
                          ),
                          icon: Icon(isAccepted ? Icons.navigation : Icons.check_circle, size: 18),
                          label: Text(
                            isAccepted ? "START NAVIGATION" : "ACCEPT JOB",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87, fontSize: 15),
        children: [
          TextSpan(text: "$label ", style: const TextStyle(color: Colors.grey)),
          TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}