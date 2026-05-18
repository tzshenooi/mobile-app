import 'driver_scheduled_missions_service.dart';

/// Repeats scheduled pickup alerts until the driver acknowledges.
class DriverScheduledAlertCoordinator {
  static const repeatEvery = Duration(seconds: 90);

  final Map<String, DateTime> _lastAlertAt = {};
  String? _dialogBookingId;

  Future<void> process({
    required List<Map<String, dynamic>> bookings,
    required bool inForeground,
    required Future<void> Function(Map<String, dynamic> booking) onNotify,
    required Future<void> Function(Map<String, dynamic> booking) onShowDialog,
    required Future<void> Function(String bookingId) onCancelNotify,
  }) async {
    final now = DateTime.now();
    final activeIds = <String>{};

    for (final booking in bookings) {
      final id = booking['id']?.toString();
      if (id == null) continue;

      if (DriverScheduledMissionsService.isAcknowledged(booking)) {
        await onCancelNotify(id);
        _lastAlertAt.remove(id);
        if (_dialogBookingId == id) _dialogBookingId = null;
        continue;
      }

      activeIds.add(id);

      if (!DriverScheduledMissionsService.isInAlertWindow(booking)) {
        await onCancelNotify(id);
        _lastAlertAt.remove(id);
        continue;
      }

      final last = _lastAlertAt[id];
      if (last != null && now.difference(last) < repeatEvery) {
        continue;
      }
      _lastAlertAt[id] = now;

      await onNotify(booking);

      if (inForeground && _dialogBookingId != id) {
        _dialogBookingId = id;
        await onShowDialog(booking);
        _dialogBookingId = null;
      }
    }

    for (final id in _lastAlertAt.keys.toList()) {
      if (!activeIds.contains(id)) {
        _lastAlertAt.remove(id);
        await onCancelNotify(id);
      }
    }
  }

  void clear(String bookingId) {
    _lastAlertAt.remove(bookingId);
    _dialogBookingId = null;
  }
}
