import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 👈 The new Database
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/login_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  // 👇 LOGOUT FUNCTION
  void logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  // 👇 ACCEPT JOB FUNCTION (Updates Firebase directly)
  void acceptJob(String jobId) {
    FirebaseFirestore.instance.collection('bookings').doc(jobId).update({
      'status': 'Accepted',
      'driver_id': FirebaseAuth.instance.currentUser?.email, // Assign to me
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Job Accepted! Head to location.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Available Jobs"),
        backgroundColor: Colors.redAccent,
        actions: [
          IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
        ],
      ),
      // 👇 REAL-TIME LISTENER
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('status', isEqualTo: 'Pending') // Only show new jobs
            .snapshots(),
        builder: (context, snapshot) {
          // 1. Loading State
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // 2. Error State
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          // 3. No Jobs State
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                "No pending jobs right now.",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          // 4. Show the List
          var jobs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              var job = jobs[index];
              var data = job.data() as Map<String, dynamic>;

              return Card(
                margin: const EdgeInsets.all(10),
                child: ListTile(
                  leading: const Icon(Icons.medical_services, color: Colors.red),
                  title: Text(data['patient_name'] ?? 'Unknown Patient'),
                  subtitle: Text("Location: ${data['location'] ?? 'No Location'}"),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () => acceptJob(job.id),
                    child: const Text("ACCEPT", style: TextStyle(color: Colors.white)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}