import '../../utils/ambulance_eta.dart';

/// Active ambulance mission statuses (aligned with clinic portal).
const kPatientActiveMissionStatuses = [
  'Pending',
  'Assigned',
  'Accepted',
  'En Route',
  'Picked Up',
];

class MissionDestination {
  const MissionDestination({
    required this.lat,
    required this.lng,
    required this.label,
  });

  final double lat;
  final double lng;
  final String label;
}

/// Status + ETA labels for the patient tracking UI.
class PatientMissionProgressView {
  const PatientMissionProgressView({
    required this.statusLabel,
    required this.etaLabel,
    required this.etaMinutes,
    required this.hasDriverGps,
    required this.isActive,
    required this.stepIndex,
    this.destination,
    this.driverName,
  });

  final String statusLabel;
  final String etaLabel;
  final int? etaMinutes;
  final bool hasDriverGps;
  final bool isActive;
  final int stepIndex;
  final MissionDestination? destination;
  final String? driverName;
}

abstract final class PatientMissionProgress {
  PatientMissionProgress._();

  static bool isActiveStatus(String? status) =>
      kPatientActiveMissionStatuses.contains(status);

  static double? _num(dynamic v) {
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (n == null || !n.isFinite) return null;
    return n;
  }

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is List && v.isNotEmpty && v.first is Map) {
      return Map<String, dynamic>.from(v.first as Map);
    }
    return null;
  }

  static MissionDestination? destinationFor({
    required Map<String, dynamic>? booking,
    Map<String, dynamic>? clinic,
  }) {
    if (booking == null) return null;
    final status = booking['status']?.toString() ?? '';

    if (status == 'Picked Up') {
      if (clinic != null) {
        final lat = _num(clinic['latitude']);
        final lng = _num(clinic['longitude']);
        if (lat != null && lng != null) {
          return MissionDestination(
            lat: lat,
            lng: lng,
            label: clinic['name']?.toString() ?? 'Hospital',
          );
        }
      }
      final dLat = _num(booking['destination_latitude']);
      final dLng = _num(booking['destination_longitude']);
      if (dLat != null && dLng != null) {
        return MissionDestination(
          lat: dLat,
          lng: dLng,
          label: booking['hospital_name']?.toString() ?? 'Hospital',
        );
      }
    }

    final lat = _num(booking['latitude']);
    final lng = _num(booking['longitude']);
    if (lat != null && lng != null) {
      return MissionDestination(
        lat: lat,
        lng: lng,
        label: booking['location']?.toString() ?? 'Incident location',
      );
    }
    return null;
  }

  static PatientMissionProgressView build({
    Map<String, dynamic>? booking,
    Map<String, dynamic>? driver,
    Map<String, dynamic>? clinic,
  }) {
    if (booking == null) {
      return const PatientMissionProgressView(
        statusLabel: 'Report sent',
        etaLabel: 'Waiting for clinic dispatch',
        etaMinutes: null,
        hasDriverGps: false,
        isActive: true,
        stepIndex: 0,
      );
    }

    final status = booking['status']?.toString() ?? '';
    final driverId = booking['driver_id'];
    final driverMap = driver ?? _asMap(booking['drivers']);
    final driverName = driverMap?['name']?.toString();

    final dLat = _num(driverMap?['current_lat']);
    final dLng = _num(driverMap?['current_lng']);
    final hasGps = dLat != null && dLng != null;
    final dest = destinationFor(booking: booking, clinic: clinic);

    int? etaMinutes;
    if (driverId != null && dest != null && hasGps) {
      etaMinutes = AmbulanceEta.computeEtaMinutes(
        driverLat: dLat,
        driverLng: dLng,
        destLat: dest.lat,
        destLng: dest.lng,
      );
    }

    String statusLabel;
    String etaLabel;
    int stepIndex;

    if (driverId == null) {
      statusLabel = 'With clinic dispatch';
      etaLabel = 'Waiting for ambulance assignment';
      stepIndex = 0;
    } else {
      switch (status) {
        case 'Pending':
        case 'Assigned':
          statusLabel = 'Ambulance assigned';
          etaLabel = 'Awaiting driver confirmation';
          stepIndex = 1;
          break;
        case 'Accepted':
        case 'En Route':
          statusLabel = status == 'En Route' ? 'En route to you' : 'Accepted';
          if (etaMinutes != null) {
            etaLabel = 'ETA ${AmbulanceEta.formatEtaLabel(etaMinutes)}';
          } else if (!hasGps) {
            etaLabel = 'GPS unavailable';
          } else {
            etaLabel = AmbulanceEta.formatEtaLabel(null);
          }
          stepIndex = 2;
          break;
        case 'Picked Up':
          statusLabel = 'Patient picked up';
          if (etaMinutes != null) {
            etaLabel = 'ETA to hospital ${AmbulanceEta.formatEtaLabel(etaMinutes)}';
          } else if (!hasGps) {
            etaLabel = 'En route to hospital · GPS unavailable';
          } else {
            etaLabel = 'En route to hospital';
          }
          stepIndex = 3;
          break;
        case 'Completed':
          statusLabel = 'Completed';
          etaLabel = 'Ambulance has arrived';
          stepIndex = 4;
          break;
        default:
          statusLabel = status;
          etaLabel = 'In progress';
          stepIndex = 2;
      }
    }

    return PatientMissionProgressView(
      statusLabel: statusLabel,
      etaLabel: etaLabel,
      etaMinutes: etaMinutes,
      hasDriverGps: hasGps,
      isActive: isActiveStatus(status) || driverId == null,
      stepIndex: stepIndex,
      destination: dest,
      driverName: driverName,
    );
  }
}
