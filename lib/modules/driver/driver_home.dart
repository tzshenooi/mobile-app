import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:smart_ambulance_driver/app_nav.dart';
import 'package:smart_ambulance_driver/services/local_notification_service.dart';
import 'package:smart_ambulance_driver/services/driver_scheduled_missions_service.dart';
import 'package:smart_ambulance_driver/services/driver_scheduled_alert_coordinator.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import 'driver_patient_chat_tab.dart';
import 'driver_profile_tab.dart';
import 'driver_records_tab.dart';
import 'driver_ui.dart';
import '../shared/patient_report_attachments_panel.dart';

enum _DriverNavTab { home, records, chat, profile }

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> with WidgetsBindingObserver {
  static const MethodChannel _appLifecycleChannel =
      MethodChannel('smart_ambulance/app_lifecycle');
  final supabase = Supabase.instance.client;
  StreamSubscription<Position>? _positionStream;
  Timer? _missionPollTimer;
  bool _isOnline = false;
  bool _isInForeground = true;
  String? _lastMissionPromptId;
  String? _lastMissionNotificationId;
  String? _activeBookingId;
  Map<String, dynamic>? _activeBookingData; // Added to store mission details
  File? _scenePreview;
  File? _handoverPreview;
  _DriverNavTab _navTab = _DriverNavTab.home;
  String? _clinicId;
  String? _clinicName;
  String? _clinicEmail;
  List<Map<String, dynamic>> _scheduledMissions = [];
  final _scheduledAlertCoordinator = DriverScheduledAlertCoordinator();
  // 🎨 UI Constants - Tactical Command Theme
  final Color primaryBlue = DriverUi.primaryBlue;
  final Color darkBlue = DriverUi.darkBlue;
  final Color bgGray = DriverUi.bgGray;
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
    _loadClinicMeta();
    _startMissionPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LocalNotificationService.instance.ensureCanNotify();
      _syncScheduledMissions();
    });
  }

  Future<void> _loadClinicMeta() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      final driver = await supabase
          .from('drivers')
          .select('base_clinic_id')
          .eq('id', userId)
          .maybeSingle();
      final clinicId = driver?['base_clinic_id']?.toString();
      if (clinicId == null || clinicId.isEmpty) return;
      final clinic = await supabase.from('clinics').select('name, email').eq('id', clinicId).maybeSingle();
      if (!mounted) return;
      setState(() {
        _clinicId = clinicId;
        _clinicName = clinic?['name']?.toString();
        _clinicEmail = clinic?['email']?.toString();
      });
    } catch (e) {
      debugPrint('Clinic meta load: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _missionPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isInForeground = true;
      _checkInitialStatus();
      _syncMissionFromServer();
      _syncScheduledMissions();
    }
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _isInForeground = false;
    }
  }

  // --- 🛠️ CORE FUNCTIONS (PRESERVED LOGIC) ---

  Future<void> _checkInitialStatus() async {
  try {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;
  
  // 1. Get Driver Status
  final driverData = await supabase.from('drivers').select('status').eq('id', userId).single();
  
  // 2. 🟢 FIX: Check if there is an existing booking that is NOT completed
  final activeBooking = await supabase
      .from('bookings')
      .select()
      .eq('driver_id', userId)
      .filter('status', 'in', '("Pending", "Assigned", "Accepted", "En Route", "Picked Up")')
      .limit(1)
      .maybeSingle();

  setState(() {
    final st = (driverData['status'] ?? '').toString();
    _isOnline = st == 'Available' || st == 'Busy';
    if (activeBooking != null) {
      final previousBookingId = _activeBookingId;
      _activeBookingId = activeBooking['id'].toString();
      _activeBookingData = activeBooking;
      if (previousBookingId != _activeBookingId) {
        _clearEvidencePreviews();
      }
    }
  });
  } catch (e) {
    debugPrint("❌ Initial status sync error: $e");
  }
}

  void _startMissionPolling() {
    _missionPollTimer?.cancel();
    _missionPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _syncMissionFromServer();
      _syncScheduledMissions();
    });
  }

  Future<void> _syncScheduledMissions() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final rows = await DriverScheduledMissionsService.loadForDriver(supabase, userId);
      if (mounted) setState(() => _scheduledMissions = rows);

      await _scheduledAlertCoordinator.process(
        bookings: rows,
        inForeground: _isInForeground,
        onNotify: (b) => LocalNotificationService.instance.showScheduledPickupReminder(booking: b),
        onShowDialog: _showScheduledAcknowledgeDialog,
        onCancelNotify: (id) => LocalNotificationService.instance.cancelScheduledReminder(id),
      );
    } catch (e) {
      debugPrint('Scheduled sync error: $e');
    }
  }

  Future<void> _showScheduledAcknowledgeDialog(Map<String, dynamic> booking) async {
    if (!mounted) return;
    final id = booking['id']?.toString();
    if (id == null) return;
    final patient = booking['patient_name']?.toString() ?? 'Patient';
    final pickup = DriverScheduledMissionsService.formatPickupLabel(booking);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Scheduled pickup'),
        content: Text(
          'Pickup for $patient is coming up ($pickup).\n\n'
          '${booking['location'] ?? ''}\n\n'
          'Acknowledge to stop alerts. Start the mission when you are ready to go.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await DriverScheduledMissionsService.acknowledgePickup(supabase, id);
              _scheduledAlertCoordinator.clear(id);
              await LocalNotificationService.instance.cancelScheduledReminder(id);
              if (ctx.mounted) Navigator.pop(ctx);
              _syncScheduledMissions();
            },
            child: const Text('ACKNOWLEDGE'),
          ),
          FilledButton(
            onPressed: () async {
              await DriverScheduledMissionsService.startMissionNow(supabase, id);
              _scheduledAlertCoordinator.clear(id);
              await LocalNotificationService.instance.cancelScheduledReminder(id);
              if (ctx.mounted) Navigator.pop(ctx);
              await _syncMissionFromServer();
              _syncScheduledMissions();
            },
            child: const Text('START MISSION NOW'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncMissionFromServer() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final booking = await supabase
          .from('bookings')
          .select()
          .eq('driver_id', userId)
          .filter('status', 'in', '("Pending", "Assigned", "Accepted", "En Route", "Picked Up")')
          .limit(1)
          .maybeSingle();

      if (booking == null) {
        // If no active booking is returned, verify the currently tracked booking
        // before clearing UI to avoid transient disappearance after app switching.
        if (_activeBookingId != null) {
          final current = await supabase
              .from('bookings')
              .select()
              .eq('id', _activeBookingId!)
              .maybeSingle();
          if (current == null) return;
          final st = (current['status'] ?? '').toString().toLowerCase();
          if (st == 'completed' || st == 'cancelled') {
            if (mounted) {
              setState(() {
                _activeBookingId = null;
                _activeBookingData = null;
                _clearEvidencePreviews();
              });
            }
            return;
          }
          _activeBookingData = current;
        }
        return;
      }

      final bookingId = booking['id']?.toString();
      if (bookingId == null) return;

      if (_activeBookingId != bookingId && mounted) {
        setState(() {
          final previousBookingId = _activeBookingId;
          _activeBookingId = bookingId;
          _activeBookingData = booking;
          if (previousBookingId != _activeBookingId) {
            _clearEvidencePreviews();
          }
        });
      } else {
        _activeBookingData = booking;
      }

      final status = (booking['status'] ?? '').toString().toLowerCase();
      final shouldPrompt = status == 'pending' || status == 'assigned';

      if (shouldPrompt && _lastMissionNotificationId != bookingId) {
        _lastMissionNotificationId = bookingId;
        LocalNotificationService.instance.showDriverDispatch(booking: booking);
        if (_isInForeground && _lastMissionPromptId != bookingId && mounted) {
          _lastMissionPromptId = bookingId;
          _showJobPopup(booking);
        }
      }
    } catch (e) {
      debugPrint("❌ Mission sync error: $e");
    }
  }

  Future<void> _toggleStatus(bool value) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    
    // Prevent going offline during active mission (local + server-side check).
    if (value == false) {
      if (_activeBookingId != null) {
        _showSnackBar("Cannot go offline during an active mission.");
        return;
      }
      final activeMission = await supabase
          .from('bookings')
          .select('id')
          .eq('driver_id', userId)
          .filter('status', 'in', '("Pending", "Assigned", "Accepted", "En Route", "Picked Up")')
          .limit(1)
          .maybeSingle();
      if (activeMission != null) {
        _showSnackBar("Cannot go offline during an active mission.");
        return;
      }
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
    if (!serviceEnabled) {
      _showSnackBar("Please turn on GPS / Location services to go Online.");
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar("Location permission is required to share your ambulance position.");
        return false;
      }
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

  void _handleIncomingMissionPayload(Map<String, dynamic> row) {
    final status = (row['status'] ?? '').toString().toLowerCase();
    if (status != 'pending' && status != 'assigned') return;

    final bookingId = row['id']?.toString();
    if (bookingId == null) return;

    _activeBookingId = bookingId;
    _activeBookingData = row;

    if (_lastMissionNotificationId == bookingId) return;
    _lastMissionNotificationId = bookingId;
    LocalNotificationService.instance.showDriverDispatch(booking: row);

    if (_isInForeground && _lastMissionPromptId != bookingId && mounted) {
      _lastMissionPromptId = bookingId;
      _showJobPopup(row);
    }
  }

  void _listenForNewJobs() {
    final myId = supabase.auth.currentUser?.id;
    supabase.channel('public:bookings').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'bookings',
      callback: (payload) {
        if (payload.newRecord['driver_id'] != myId) return;
        final status = (payload.newRecord['status'] ?? '').toString();
        if (status == DriverScheduledMissionsService.scheduledStatus) {
          _syncScheduledMissions();
          return;
        }
        _handleIncomingMissionPayload(payload.newRecord);
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'bookings',
      callback: (payload) {
        if (payload.newRecord['driver_id'] != myId) return;
        final status = (payload.newRecord['status'] ?? '').toString();
        if (status == DriverScheduledMissionsService.scheduledStatus) {
          _syncScheduledMissions();
          return;
        }
        _handleIncomingMissionPayload(payload.newRecord);
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

  /// Patient secured on scene. Hospital/destination is set on the clinic dispatch portal.
  Future<void> _securePatient() async {
    if (_activeBookingId == null) return;
    try {
      final pickedUpAt = DateTime.now().toUtc().toIso8601String();
      await supabase.from('bookings').update({
        'status': 'Picked Up',
        'patient_picked_up_at': pickedUpAt,
      }).eq('id', _activeBookingId!);
      final fresh = await supabase.from('bookings').select().eq('id', _activeBookingId!).single();

      if (mounted) {
        setState(() {
          _activeBookingData = Map<String, dynamic>.from(fresh);
        });
      }

      final hospital = (_activeBookingData?['hospital_name'] ?? '').toString().trim();
      if (hospital.isNotEmpty) {
        _showSnackBar('Patient secured. Destination: $hospital (from clinic).');
      } else {
        _showSnackBar('Patient secured. Clinic will confirm hospital on the portal.');
      }
    } catch (e) {
      debugPrint('❌ Secure patient error: $e');
      _showSnackBar('Could not update mission status.');
    }
  }

  String? _bookingDestinationSummary() {
    final hospital = (_activeBookingData?['hospital_name'] ?? '').toString().trim();
    final destType = (_activeBookingData?['destination_type'] ?? '').toString().trim();
    if (hospital.isEmpty && destType.isEmpty) return null;
    if (hospital.isNotEmpty && destType.isNotEmpty) {
      final label = destType.replaceAll('_', ' ');
      return '$hospital ($label)';
    }
    return hospital.isNotEmpty ? hospital : destType;
  }

  // Change your popup to look like a Command, not a Choice
Future<void> _acknowledgeAndNavigate(Map<String, dynamic> booking) async {
  await supabase.from('bookings').update({
    'status': 'En Route',
    'ambulance_departed_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', booking['id']);
  await supabase.from('drivers').update({'status': 'Busy'}).eq('id', supabase.auth.currentUser!.id);

  setState(() {
    final previousBookingId = _activeBookingId;
    _activeBookingId = booking['id'].toString();
    _activeBookingData = {
      ...booking,
      'status': 'En Route',
      'ambulance_departed_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (previousBookingId != _activeBookingId) {
      _clearEvidencePreviews();
    }
  });

  _launchMaps(booking['latitude'], booking['longitude']);
}

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
  await _acknowledgeAndNavigate(booking);
  if (mounted) Navigator.pop(context);
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
    final userId = supabase.auth.currentUser?.id ?? '';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        await _appLifecycleChannel.invokeMethod('moveTaskToBack');
      },
      child: Scaffold(
        backgroundColor: bgGray,
        body: Stack(
          children: [
            IndexedStack(
              index: _navTab.index,
              children: [
                _buildHomeTab(),
                DriverRecordsTab(
                  driverId: userId,
                  isVisible: _navTab == _DriverNavTab.records,
                ),
                DriverPatientChatTab(
                  driverId: userId,
                  isOnDuty: _isOnline,
                  activeBooking: _activeBookingData,
                ),
                DriverProfileTab(
                  driverId: userId,
                  onSignOut: () async {
                    await _toggleStatus(false);
                    await supabase.auth.signOut();
                    if (mounted) {
                      rootNavigatorKey.currentState?.pushNamedAndRemoveUntil('/roles', (_) => false);
                    }
                  },
                ),
              ],
            ),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildTacticalHeader(),
          _buildFloatingStatusCard(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_scheduledMissions.isNotEmpty) ...[
                  const Text(
                    'Upcoming schedule',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 12),
                  ..._scheduledMissions.map(_buildScheduledMissionCard),
                  const SizedBox(height: 24),
                ],
                const Text(
                  "Active Missions",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 15),
                if (_activeBookingId != null) _buildProfessionalMissionCard() else _buildEmptyState(),
                const SizedBox(height: 120),
              ],
            ),
          ),
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
              if (mounted) {
                rootNavigatorKey.currentState?.pushNamedAndRemoveUntil('/roles', (_) => false);
              }
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

  Widget _buildScheduledMissionCard(Map<String, dynamic> booking) {
    final id = booking['id']?.toString() ?? '';
    final ack = DriverScheduledMissionsService.isAcknowledged(booking);
    final alerting = DriverScheduledMissionsService.isInAlertWindow(booking);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: alerting ? Colors.orange.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: alerting ? Colors.orange : primaryBlue.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('SCHEDULED', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1)),
              const Spacer(),
              if (alerting && !ack)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(8)),
                  child: const Text('ACK REQUIRED', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                )
              else if (ack)
                const Text('Acknowledged', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            booking['patient_name']?.toString() ?? 'Patient',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            DriverScheduledMissionsService.formatPickupLabel(booking),
            style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
          ),
          Text(
            DriverScheduledMissionsService.minutesUntilPickup(booking),
            style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(booking['location']?.toString() ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: id.isEmpty
                      ? null
                      : () async {
                          await DriverScheduledMissionsService.acknowledgePickup(supabase, id);
                          _scheduledAlertCoordinator.clear(id);
                          await LocalNotificationService.instance.cancelScheduledReminder(id);
                          _syncScheduledMissions();
                        },
                  child: const Text('Acknowledge'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: id.isEmpty
                      ? null
                      : () async {
                          await DriverScheduledMissionsService.startMissionNow(supabase, id);
                          _scheduledAlertCoordinator.clear(id);
                          await LocalNotificationService.instance.cancelScheduledReminder(id);
                          await _syncMissionFromServer();
                          _syncScheduledMissions();
                        },
                  style: FilledButton.styleFrom(backgroundColor: primaryBlue),
                  child: const Text('Start now'),
                ),
              ),
            ],
          ),
        ],
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
        if (_activeBookingData?['patient_report_id'] != null) ...[
          const SizedBox(height: 16),
          PatientReportAttachmentsPanel(
            patientReportId: _activeBookingData!['patient_report_id'].toString(),
            inlinePreview: true,
            accentColor: primaryBlue,
          ),
        ],
        const SizedBox(height: 25),

        _buildEvidenceStrip(),

        if (status.contains('pending') || status.contains('assigned')) ...[
          ElevatedButton(
            onPressed: () async => _acknowledgeAndNavigate(_activeBookingData!),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              "ACKNOWLEDGE & NAVIGATE",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
        ],

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
          if (!hasSceneEvidence)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                "Capture scene evidence first to proceed.",
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ),
          if (hasSceneEvidence) ...[
            ElevatedButton(
              onPressed: _securePatient,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 5,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text('SECURE PATIENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          ],
        ],

        // --- 🏥 PHASE 2: HOSPITAL DISCHARGE ---
        if (isPhase2) ...[
          if (_bookingDestinationSummary() != null) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.local_hospital_outlined, color: primaryBlue, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Clinic destination: ${_bookingDestinationSummary()}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ] else ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Waiting for clinic to confirm hospital destination on the portal.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ),
          ],
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
                final nowIso = DateTime.now().toUtc().toIso8601String();
                final completePatch = <String, dynamic>{
                  'status': 'Completed',
                  'discharge_completed_at': nowIso,
                };
                if (_activeBookingData?['ambulance_departed_at'] == null) {
                  completePatch['ambulance_departed_at'] = nowIso;
                }
                if (_activeBookingData?['patient_picked_up_at'] == null) {
                  completePatch['patient_picked_up_at'] = nowIso;
                }
                await supabase
                    .from('bookings')
                    .update(completePatch)
                    .eq('id', _activeBookingId!);
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
              _navIcon(Icons.home_filled, _navTab == _DriverNavTab.home, () => setState(() => _navTab = _DriverNavTab.home)),
              _navIcon(Icons.description_outlined, _navTab == _DriverNavTab.records, () => setState(() => _navTab = _DriverNavTab.records)),
              GestureDetector(
                onTap: () {
                  if (_activeBookingData != null) {
                    _launchMaps(_activeBookingData!['latitude'], _activeBookingData!['longitude']);
                  } else {
                    _showSnackBar("No active mission to navigate.");
                  }
                },
                child: Container(
                  height: 55,
                  width: 55,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(Icons.navigation_rounded, color: darkBlue, size: 30),
                ),
              ),
              _navIcon(Icons.message_outlined, _navTab == _DriverNavTab.chat, () => setState(() => _navTab = _DriverNavTab.chat)),
              _navIcon(Icons.person_outline, _navTab == _DriverNavTab.profile, () => setState(() => _navTab = _DriverNavTab.profile)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Icon(icon, color: isActive ? Colors.white : Colors.white54, size: 26),
      ),
    );
  }
}