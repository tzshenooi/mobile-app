import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'emergency_alert_sound_service.dart';
import 'driver_scheduled_missions_service.dart';

class _AppLifecycleBinder extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LocalNotificationService.instance._appLifecycleState = state;
  }
}

/// Shared local notifications for driver dispatch, patient mission updates, and chat.
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool? _canNotify;
  bool _lifecycleObserverRegistered = false;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  String? _lastEmergencyAlertKey;
  DateTime? _lastEmergencyAlertAt;
  static const _emergencyDebounce = Duration(seconds: 8);

  static const AndroidNotificationSound _dispatchAlertSound =
      RawResourceAndroidNotificationSound('dispatch_alert');

  static const AndroidNotificationSound _destinationAlertSound =
      RawResourceAndroidNotificationSound('destination_alert');

  static const _insistentFlag = 4;

  static const driverDispatchNotificationId = 1001;
  static const hospitalDestinationNotificationId = 1002;

  static final Int64List _destinationVibrationPattern = Int64List.fromList([
    0,
    500,
    200,
    500,
    200,
    500,
    300,
    900,
  ]);

  static final Int64List _emergencyVibrationPattern = Int64List.fromList([
    0,
    1200,
    400,
    1200,
    400,
    1200,
    400,
    1800,
    400,
    1800,
    400,
    1800,
  ]);

  static final _channelDispatch = AndroidNotificationChannel(
    'dispatch_alerts_emergency_v2',
    'Emergency Dispatch Alerts',
    description: 'Loud emergency dispatch alerts for drivers',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    sound: _dispatchAlertSound,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    vibrationPattern: _emergencyVibrationPattern,
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

  static final _channelDestination = AndroidNotificationChannel(
    'destination_updates_v5',
    'Destination updates',
    description: 'Loud alert when clinic or hospital is assigned',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    sound: _destinationAlertSound,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    vibrationPattern: _destinationVibrationPattern,
  );

  static final _channelScheduled = AndroidNotificationChannel(
    'scheduled_pickup_v3',
    'Scheduled pickup',
    description: 'Planned bedridden / scheduled transport for drivers',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static AndroidNotificationDetails _destinationAndroidDetails() {
    return AndroidNotificationDetails(
      _channelDestination.id,
      _channelDestination.name,
      channelDescription: _channelDestination.description,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      sound: _destinationAlertSound,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      vibrationPattern: _destinationVibrationPattern,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ticker: 'hospital_destination',
    );
  }

  static AndroidNotificationDetails _dispatchAndroidDetails({
    String? ticker,
    bool ongoing = false,
  }) {
    return AndroidNotificationDetails(
      _channelDispatch.id,
      _channelDispatch.name,
      channelDescription: _channelDispatch.description,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      sound: _dispatchAlertSound,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      vibrationPattern: _emergencyVibrationPattern,
      category: AndroidNotificationCategory.alarm,
      additionalFlags: Int32List.fromList([_insistentFlag]),
      visibility: NotificationVisibility.public,
      ticker: ticker,
      ongoing: ongoing,
    );
  }

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
    if (android != null) {
      // Remove experimental channels that broke alert sounds during testing.
      for (final id in [
        'driver_alerts_loud_v1',
        'destination_updates',
        'destination_updates_v2',
        'destination_updates_v3',
        'destination_updates_v4',
        'destination_alerts_loud',
        'dispatch_alerts',
        'scheduled_pickup',
        'scheduled_pickup_emergency_v2',
      ]) {
        await android.deleteNotificationChannel(id);
      }
      // Recreate dispatch channel so the bundled custom alert sound is applied.
      await android.deleteNotificationChannel(_channelDispatch.id);
      await android.createNotificationChannel(_channelDispatch);
      await android.createNotificationChannel(_channelMission);
      await android.createNotificationChannel(_channelChat);
      await android.deleteNotificationChannel(_channelDestination.id);
      await android.createNotificationChannel(_channelDestination);
      await android.deleteNotificationChannel(_channelScheduled.id);
      await android.createNotificationChannel(_channelScheduled);
    }
    if (!_lifecycleObserverRegistered) {
      WidgetsBinding.instance.addObserver(_AppLifecycleBinder());
      _lifecycleObserverRegistered = true;
    }
    _appLifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _initialized = true;
  }

  /// True only while the driver app is actively on screen.
  bool get isAppInForeground {
    final live = WidgetsBinding.instance.lifecycleState;
    if (live != null) return live == AppLifecycleState.resumed;
    return _appLifecycleState == AppLifecycleState.resumed;
  }

  bool _shouldPlayEmergencyAlert(String key) {
    final now = DateTime.now();
    if (_lastEmergencyAlertKey == key &&
        _lastEmergencyAlertAt != null &&
        now.difference(_lastEmergencyAlertAt!) < _emergencyDebounce) {
      return false;
    }
    _lastEmergencyAlertKey = key;
    _lastEmergencyAlertAt = now;
    return true;
  }

  NotificationDetails _detailsWithoutSound(NotificationDetails details) {
    final android = details.android;
    if (android == null) return details;

    return NotificationDetails(
      android: AndroidNotificationDetails(
        android.channelId,
        android.channelName,
        channelDescription: android.channelDescription,
        importance: android.importance,
        priority: android.priority,
        playSound: false,
        enableVibration: android.enableVibration,
        vibrationPattern: android.vibrationPattern,
        audioAttributesUsage: android.audioAttributesUsage,
        category: android.category,
        additionalFlags: android.additionalFlags,
        visibility: android.visibility,
        ticker: android.ticker,
        ongoing: android.ongoing,
      ),
      iOS: details.iOS == null
          ? null
          : DarwinNotificationDetails(
              presentAlert: details.iOS!.presentAlert,
              presentBadge: details.iOS!.presentBadge,
              presentSound: false,
            ),
    );
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

  Future<bool> _showEmergencyAlert(
    int id,
    String? title,
    String? body,
    NotificationDetails details, {
    required String dedupeKey,
    bool muteSound = false,
  }) async {
    if (!_shouldPlayEmergencyAlert(dedupeKey)) return false;

    return _showIfAllowed(
      id,
      title,
      body,
      muteSound ? _detailsWithoutSound(details) : details,
    );
  }

  static AndroidNotificationDetails _scheduledAndroidDetails() {
    return AndroidNotificationDetails(
      _channelScheduled.id,
      _channelScheduled.name,
      channelDescription: _channelScheduled.description,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      ticker: 'scheduled_pickup',
    );
  }

  int _scheduledNotificationId(String bookingId) =>
      5000 + bookingId.hashCode.abs() % 20000;

  /// Quiet notice when clinic assigns a scheduled transport (no dispatch siren).
  Future<void> showScheduledAssignment({
    required Map<String, dynamic> booking,
    bool muteSound = false,
  }) async {
    final id = booking['id']?.toString() ?? 'scheduled';
    final patient = (booking['patient_name'] ?? 'Patient').toString();
    final pickupLabel = DriverScheduledMissionsService.formatPickupLabel(booking);
    final location = (booking['location'] ?? '').toString();
    final body = location.isNotEmpty
        ? '$patient · Pickup $pickupLabel\n$location'
        : '$patient · Pickup $pickupLabel';

    await _showIfAllowed(
      _scheduledNotificationId(id),
      'Scheduled transport assigned',
      body,
      muteSound
          ? _detailsWithoutSound(
              NotificationDetails(
                android: _scheduledAndroidDetails(),
                iOS: const DarwinNotificationDetails(
                  presentAlert: true,
                  presentBadge: true,
                  presentSound: false,
                ),
              ),
            )
          : NotificationDetails(
              android: _scheduledAndroidDetails(),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
    );
  }

  /// Reminder during the pre-pickup alert window (no dispatch siren).
  Future<void> showScheduledPickupReminder({
    required Map<String, dynamic> booking,
    bool muteSound = false,
  }) async {
    final id = booking['id']?.toString() ?? 'scheduled';
    final patient = (booking['patient_name'] ?? 'Patient').toString();
    final location = (booking['location'] ?? 'Open app to acknowledge').toString();
    final pickup = DriverScheduledMissionsService.formatPickupLabel(booking);
    await _showIfAllowed(
      _scheduledNotificationId(id),
      'Scheduled pickup — acknowledge',
      '$patient · $location\nPickup: $pickup',
      muteSound
          ? _detailsWithoutSound(
              NotificationDetails(
                android: _scheduledAndroidDetails(),
                iOS: const DarwinNotificationDetails(
                  presentAlert: true,
                  presentBadge: true,
                  presentSound: false,
                ),
              ),
            )
          : NotificationDetails(
              android: _scheduledAndroidDetails(),
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

  /// Stops dispatch siren / insistent notification when the driver acknowledges.
  Future<void> cancelDriverDispatchAlert() async {
    await initialize();
    await EmergencyAlertSoundService.instance.stop();
    await _plugin.cancel(driverDispatchNotificationId);
  }

  Future<void> cancelHospitalDestinationAlert() async {
    await initialize();
    await _plugin.cancel(hospitalDestinationNotificationId);
  }

  Future<void> showDriverDispatch({
    required Map<String, dynamic> booking,
    bool muteSound = false,
  }) async {
    if (DriverScheduledMissionsService.isScheduledTransportBooking(booking)) {
      await showScheduledAssignment(booking: booking, muteSound: muteSound);
      return;
    }

    final bookingId = booking['id']?.toString() ?? 'unknown';
    final location =
        (booking['location'] ?? 'Open app to acknowledge dispatch').toString();
    await _showEmergencyAlert(
      driverDispatchNotificationId,
      'New Mission Assigned',
      location,
      NotificationDetails(
        android: _dispatchAndroidDetails(ticker: 'dispatch'),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      dedupeKey: 'dispatch:$bookingId',
      muteSound: muteSound,
    );
  }

  /// Clinic assigned hospital destination after patient secured.
  /// Loud custom alert tone — not the emergency dispatch siren.
  Future<void> showHospitalDestination({
    required String hospitalName,
  }) async {
    await _showIfAllowed(
      hospitalDestinationNotificationId,
      'Hospital destination assigned',
      'Navigate to $hospitalName',
      NotificationDetails(
        android: _destinationAndroidDetails(),
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
        return 'You have been picked up. En route to destination';
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
    bool driverAlert = false,
  }) async {
    final body =
        preview.length > 120 ? '${preview.substring(0, 117)}...' : preview;
    final notificationId = idSeed % 100000 + 3000;
    final details = NotificationDetails(
        android: driverAlert
            ? _dispatchAndroidDetails(ticker: 'chat_message')
            : AndroidNotificationDetails(
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
      );
    if (driverAlert) {
      await _showEmergencyAlert(
        notificationId,
        'Message from $senderLabel',
        body,
        details,
        dedupeKey: 'chat:$idSeed',
      );
    } else {
      await _showIfAllowed(
        notificationId,
        'Message from $senderLabel',
        body,
        details,
      );
    }
  }
}
