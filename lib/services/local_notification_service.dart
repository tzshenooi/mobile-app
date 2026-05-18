import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shared local notifications for driver dispatch, patient mission updates, and chat.
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

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
    );
    await _plugin.initialize(initSettings);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channelDispatch);
    await android?.createNotificationChannel(_channelMission);
    await android?.createNotificationChannel(_channelChat);
    await android?.createNotificationChannel(_channelScheduled);
    await android?.requestNotificationsPermission();
    _initialized = true;
  }

  int _scheduledNotificationId(String bookingId) =>
      5000 + bookingId.hashCode.abs() % 20000;

  /// Repeating alert until the driver opens the app and acknowledges.
  Future<void> showScheduledPickupReminder({
    required Map<String, dynamic> booking,
  }) async {
    await initialize();
    final id = booking['id']?.toString() ?? 'scheduled';
    final patient = (booking['patient_name'] ?? 'Patient').toString();
    final location = (booking['location'] ?? 'Open app to acknowledge').toString();
    final pickup = booking['scheduled_at']?.toString() ?? '';
    await _plugin.show(
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
    await initialize();
    final location =
        (booking['location'] ?? 'Open app to acknowledge dispatch').toString();
    await _plugin.show(
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
    await initialize();
    final id = notificationId ?? status.hashCode.abs() % 100000 + 2000;
    await _plugin.show(
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
      ),
    );
  }

  Future<void> showChatMessage({
    required String senderLabel,
    required String preview,
    required int idSeed,
  }) async {
    await initialize();
    final body =
        preview.length > 120 ? '${preview.substring(0, 117)}...' : preview;
    await _plugin.show(
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
      ),
    );
  }
}
