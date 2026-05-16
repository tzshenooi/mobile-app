import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'patient_ui.dart';

/// OSM map with pin — reliable in lists & bottom sheets (GoogleMap often renders blank there).
class PatientLocationMap extends StatefulWidget {
  const PatientLocationMap({
    super.key,
    required this.center,
    required this.height,
    this.borderRadius = 12,
    this.onPositionChanged,
    this.zoom = 16,
  });

  final LatLng center;
  final double height;
  final double borderRadius;
  final void Function(LatLng position)? onPositionChanged;
  final double zoom;

  @override
  State<PatientLocationMap> createState() => _PatientLocationMapState();
}

class _PatientLocationMapState extends State<PatientLocationMap> {
  final MapController _mapController = MapController();

  /// Must match Android `applicationId` or OSM may block tiles.
  static const _osmUserAgent = 'com.example.flutter_application_1';

  @override
  void didUpdateWidget(PatientLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.center.latitude != widget.center.latitude ||
        oldWidget.center.longitude != widget.center.longitude) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(widget.center, widget.zoom);
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: widget.zoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
            ),
            onTap: widget.onPositionChanged == null
                ? null
                : (tap, latlng) => widget.onPositionChanged!(latlng),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: _osmUserAgent,
              maxZoom: 19,
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: widget.center,
                  width: 48,
                  height: 48,
                  child: const Icon(Icons.place, color: PatientUi.accentRed, size: 44),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
