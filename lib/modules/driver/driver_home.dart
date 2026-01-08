import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../auth/login_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  List<dynamic> jobs = [];
  bool isLoading = true;
  
  // REPLACE WITH YOUR PC IP
  final String baseUrl = "http://10.0.2.2:5000"; 

  @override
  void initState() {
    super.initState();
    fetchJobs();
  }

  Future<void> fetchJobs() async {
    try {
      // Fetch jobs assigned to Driver 1
      final response = await http.get(Uri.parse("$baseUrl/driver_bookings/1"));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          jobs = data['data'];
          isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching jobs: $e");
    }
  }

  Future<void> updateStatus(int bookingId, String newStatus) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/update_status"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "booking_id": bookingId,
          "status": newStatus
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Status updated to: $newStatus")),
        );
        fetchJobs(); // Refresh list to show new button state
      }
    } catch (e) {
      print("Error updating status: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Tasks"),
        backgroundColor: Colors.red,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: fetchJobs),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : jobs.isEmpty
              ? const Center(child: Text("No active jobs assigned."))
              : ListView.builder(
                  itemCount: jobs.length,
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    String status = job['status'];
                    
                    // Determine Button Logic based on current status
                    String buttonText = "START NAVIGATION";
                    Color buttonColor = Colors.green;
                    String nextStatus = "En Route";

                    if (status == "En Route") {
                      buttonText = "COMPLETE JOB";
                      buttonColor = Colors.orange;
                      nextStatus = "Completed";
                    } else if (status == "Completed") {
                      return const SizedBox.shrink(); // Hide completed jobs from list
                    }

                    return Card(
                      margin: const EdgeInsets.all(10),
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("EMERGENCY: ${job['emergency_type']}", 
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: status == "En Route" ? Colors.orange[100] : Colors.blue[100],
                                    borderRadius: BorderRadius.circular(4)
                                  ),
                                  child: Text(status, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                                )
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text("Patient: ${job['patient_name']}", style: const TextStyle(fontSize: 16)),
                            Text("Location: ${job['location']}", style: const TextStyle(fontSize: 16)),
                            const SizedBox(height: 15),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: Icon(status == "En Route" ? Icons.check_circle : Icons.navigation),
                                label: Text(buttonText),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: buttonColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () {
                                  updateStatus(job['id'], nextStatus);
                                },
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}