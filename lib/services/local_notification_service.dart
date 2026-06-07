import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shared local notifications for driver dispatch, patient mission updates, and chat.
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool? _canNotify;

  static const _channelDispatch = AndroidNotificationChannel(
    'dispatch_alerts',
    'Dispatch Alerts',
    description: 'Emergency dispatch alerts for drivers',
    importance: Importance.max,
  );

  static const _channelMission = AndroidNotificationChannel(
    'mission_updates',
    'Mission Updates',
    description: 'Ambulance mission status for patients',
    importance: Importance.high,
  );

  static const _channelChat = AndroidNotificationChannel(
    'chat_messages',
    'Mission Chat',
    description: 'Messages from driver or clinic',
    importance: Importance.high,
  );

  static const _channelScheduled = AndroidNotificationChannel(
    'scheduled_pickup',
    'Scheduled pickup',
    description: 'Upcoming bedridden / scheduled transport for drivers',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  Future<void> initialize() async {
    if (_initialized) return;
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(initSettings);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channelDispatch);
    await android?.createNotificationChannel(_channelMission);
    await android?.createNotificationChannel(_channelChat);
    await android?.createNotificationChannel(_channelScheduled);
    _initialized = true;
  }

  /// Call after the first frame so Android 13+ shows the system permission dialog.
  Future<bool> ensureCanNotify({bool requestIfNeeded = true}) async {
    if (_canNotify == true) return true;
    await initialize();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      var enabled = await android.areNotificationsEnabled() ?? false;
      if (!enabled && requestIfNeeded) {
        enabled = await android.requestNotificationsPermission() ?? false;
      }
      _canNotify = enabled;
      if (!enabled) {
        debugPrint('LocalNotificationService: notifications disabled on Android');
      }
      return enabled;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      if (requestIfNeeded) {
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        _canNotify = granted ?? false;
      } else {
        _canNotify = true;
      }
      return _canNotify ?? false;
    }

    _canNotify = true;
    return true;
  }

  Future<bool> _showIfAllowed(
    int id,
    String? title,
    String? body,
    NotificationDetails details,
  ) async {
    if (!await ensureCanNotify()) return false;
    await _plugin.show(id, title, body, details);
    return true;
  }

  int _scheduledNotificationId(String bookingId) =>
      5000 + bookingId.hashCode.abs() % 20000;

  /// Repeating alert until the driver opens the app and acknowledges.
  Future<void> showScheduledPickupReminder({
    required Map<String, dynamic> booking,
  }) async {
    final id = booking['id']?.toString() ?? 'scheduled';
    final patient = (booking['patient_name'] ?? 'Patient').toString();
    final location = (booking['location'] ?? 'Open app to acknowledge').toString();
    final pickup = booking['scheduled_at']?.toString() ?? '';
    await _showIfAllowed(
      _scheduledNotificationId(id),
      'Scheduled pickup — acknowledge',
      '$patient · $location${pickup.isNotEmpty ? '\nPickup: $pickup' : ''}',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelScheduled.id,
          _channelScheduled.name,
          channelDescription: _channelScheduled.description,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          ongoing: true,
          category: AndroidNotificationCategory.alarm,
          ticker: 'scheduled_pickup',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  Future<void> cancelScheduledReminder(String bookingId) async {
    await initialize();
    await _plugin.cancel(_scheduledNotificationId(bookingId));
  }

  Future<void> showDriverDispatch({
    required Map<String, dynamic> booking,
  }) async {
    final location =
        (booking['location'] ?? 'Open app to acknowledge dispatch').toString();
    await _showIfAllowed(
      1001,
      'New Mission Assigned',
      location,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelDispatch.id,
          _channelDispatch.name,
          channelDescription: _channelDispatch.description,
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'dispatch',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// Clinic assigned hospital destination after patient secured.
  Future<void> showHospitalDestination({
    required String hospitalName,
  }) async {
    await _showIfAllowed(
      1002,
      'Hospital destination assigned',
      'Navigate to $hospitalName',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelDispatch.id,
          _channelDispatch.name,
          channelDescription: _channelDispatch.description,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          ticker: 'hospital_destination',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  String messageForPatientStatus(String status, {String? driverName}) {
    switch (status) {
      case 'Pending':
      case 'Assigned':
        return driverName != null
            ? '$driverName has been assigned to your case'
            : 'An ambulance has been assigned to your case';
      case 'Accepted':
        return 'Your ambulance crew accepted the mission';
      case 'En Route':
        return 'Ambulance is on the way to you';
      case 'Picked Up':
        return 'You have been picked up. En route to hospital';
      case 'Completed':
        return 'Mission completed. Thank you';
      case 'Cancelled':
        return 'This mission was cancelled';
      default:
        return 'Mission update: $status';
    }
  }

  String titleForPatientStatus(String status) {
    switch (status) {
      case 'Pending':
      case 'Assigned':
        return 'Ambulance assigned';
      case 'Accepted':
        return 'Mission accepted';
      case 'En Route':
        return 'Ambulance en route';
      case 'Picked Up':
        return 'Picked up';
      case 'Completed':
        return 'Mission complete';
      case 'Cancelled':
        return 'Mission cancelled';
      default:
        return 'Mission update';
    }
  }

  Future<void> showPatientMissionStatus({
    required String status,
    String? driverName,
    int? notificationId,
  }) async {
    final id = notificationId ?? status.hashCode.abs() % 100000 + 2000;
    await _showIfAllowed(
      id,
      titleForPatientStatus(status),
      messageForPatientStatus(status, driverName: driverName),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelMission.id,
          _channelMission.name,
          channelDescription: _channelMission.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  Future<void> showChatMessage({
    required String senderLabel,
    required String preview,
    required int idSeed,
  }) async {
    final body =
        preview.length > 120 ? '${preview.substring(0, 117)}...' : preview;
    await _showIfAllowed(
      idSeed % 100000 + 3000,
      'Message from $senderLabel',
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelChat.id,
          _channelChat.name,
          channelDescription: _channelChat.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
