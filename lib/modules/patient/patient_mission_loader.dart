import 'package:supabase_flutter/supabase_flutter.dart';

/// Loads patient report + linked booking (direct query — reliable with patient RLS).
abstract final class PatientMissionLoader {
  PatientMissionLoader._();

  static const bookingSelect = '''
id, status, driver_id, patient_report_id, latitude, longitude, location,
scene_photo, handover_photo, discharge_completed_at,
destination_clinic_id, ambulance_departed_at, requested_at, created_at,
drivers(id, name, current_lat, current_lng, status)
''';

  static Map<String, dynamic>? parseNestedMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return null;
  }

  static Future<({
    Map<String, dynamic> report,
    Map<String, dynamic>? booking,
    Map<String, dynamic>? driver,
  })> load({
    required SupabaseClient client,
    required String patientReportId,
    required String userId,
  }) async {
    final reportFuture = client
        .from('patient_reports')
        .select('id, incident_category, location_label, latitude, longitude, status, created_at')
        .eq('id', patientReportId)
        .eq('reporter_user_id', userId)
        .maybeSingle();

    final bookingFuture = client
        .from('bookings')
        .select(bookingSelect)
        .eq('patient_report_id', patientReportId)
        .order('created_at', ascending: false)
        .limit(1);

    final reportRow = await reportFuture;
    if (reportRow == null) {
      throw Exception('Report not found.');
    }
    final report = Map<String, dynamic>.from(reportRow);

    Map<String, dynamic>? booking;
    final bookingRows = await bookingFuture;
    if (bookingRows.isNotEmpty) {
      booking = Map<String, dynamic>.from(bookingRows.first as Map);
    }

    Map<String, dynamic>? driver = parseNestedMap(booking?['drivers']);
    final driverId = booking?['driver_id']?.toString();
    if (driverId != null && driver == null) {
      final driverRow = await client
          .from('drivers')
          .select('id, name, current_lat, current_lng, status')
          .eq('id', driverId)
          .maybeSingle();
      if (driverRow != null) {
        driver = Map<String, dynamic>.from(driverRow);
      }
    }

    return (report: report, booking: booking, driver: driver);
  }
}
