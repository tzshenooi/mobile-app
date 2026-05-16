import 'package:flutter/material.dart';

/// Shared colors for driver module (matches [DriverHome] tactical theme).
abstract final class DriverUi {
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color darkBlue = Color(0xFF1E40AF);
  static const Color bgGray = Color(0xFFF8FAFC);

  static String formatWhen(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} $h:$m';
  }
}
