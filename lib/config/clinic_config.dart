/// Single clinic row UUID (same as web Auth `clinic_id`).
/// Build with: `--dart-define=CLINIC_ID=<uuid>` (legacy: `CLINIC_HOSPITAL_ID`)
class ClinicConfig {
  ClinicConfig._();

  static const String clinicId = String.fromEnvironment(
    'CLINIC_ID',
    defaultValue: String.fromEnvironment('CLINIC_HOSPITAL_ID', defaultValue: ''),
  );

  static bool get hasClinicId => clinicId.isNotEmpty;

  /// Clinic dispatch line for patient app (fallback if `clinics.phone` is empty).
  /// Build with: `--dart-define=CLINIC_PHONE=+60123456789`
  static const String clinicPhone = String.fromEnvironment('CLINIC_PHONE', defaultValue: '');

  @Deprecated('Use clinicId')
  static String get hospitalId => clinicId;

  @Deprecated('Use hasClinicId')
  static bool get hasHospitalId => hasClinicId;
}
