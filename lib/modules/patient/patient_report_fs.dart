import 'dart:io' show File;

Future<void> patientReportFsDelete(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
