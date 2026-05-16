import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'ambulance_map_marker.dart';
import 'ambulance_route_service.dart';
import 'patient_ui.dart';

/// Read-only map: blue driving route, destination pin, ambulance marker.
class PatientTrackingMap extends StatefulWidget {
  const PatientTrackingMap({
    super.key,
    required this.destination,
    this.ambulancePosition,
    this.height = 240,
  });

  final LatLng destination;
  final LatLng? ambulancePosition;
  final double height;

  @override
  State<PatientTrackingMap> createState() => _PatientTrackingMapState();
}

class _PatientTrackingMapState extends State<PatientTrackingMap> {
  final MapController _mapController = MapController();

  static const _osmUserAgent = 'com.example.flutter_application_1';
  static const _routeColor = Color(AmbulanceRouteService.routeBlue);

  List<LatLng> _routePoints = [];
  Timer? _routeDebounce;
  int _routeGeneration = 0;
  bool _loadingRoute = false;

  @override
  void initState() {
    super.initState();
    _scheduleRouteFetch(immediate: true);
  }

  @override
  void didUpdateWidget(PatientTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final destMoved = oldWidget.destination != widget.destination;
    final ambMoved = oldWidget.ambulancePosition != widget.ambulancePosition;
    if (destMoved || ambMoved) {
      _scheduleRouteFetch(immediate: destMoved);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
    }
  }

  @override
  void dispose() {
    _routeDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _scheduleRouteFetch({required bool immediate}) {
    _routeDebounce?.cancel();
    if (immediate) {
      _fetchRoute();
      return;
    }
    _routeDebounce = Timer(const Duration(milliseconds: 1500), _fetchRoute);
  }

  Future<void> _fetchRoute() async {
    final amb = widget.ambulancePosition;
    if (amb == null) {
      if (mounted) {
        setState(() {
          _routePoints = [];
          _loadingRoute = false;
        });
      }
      return;
    }

    final gen = ++_routeGeneration;
    if (mounted) setState(() => _loadingRoute = true);

    final points = await AmbulanceRouteService.fetchDrivingRoute(
      origin: amb,
      destination: widget.destination,
    );

    if (!mounted || gen != _routeGeneration) return;
    setState(() {
      _routePoints = points;
      _loadingRoute = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
  }

  void _fitBounds() {
    if (!mounted) return;
    final points = <LatLng>[widget.destination];
    final amb = widget.ambulancePosition;
    if (amb != null) points.add(amb);
    if (_routePoints.isNotEmpty) points.addAll(_routePoints);

    try {
      if (points.length == 1) {
        _mapController.move(points.first, 14);
        return;
      }
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(52)),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final amb = widget.ambulancePosition;
    final markers = <Marker>[
      Marker(
        point: widget.destination,
        width: 40,
        height: 40,
        alignment: Alignment.bottomCenter,
        child: const Icon(Icons.location_on, color: PatientUi.accentRed, size: 40),
      ),
      if (amb != null)
        Marker(
          point: amb,
          width: 48,
          height: 52,
          alignment: Alignment.bottomCenter,
          child: const AmbulanceMapMarker(size: 48),
        ),
    ];

    final polylines = _routePoints.length >= 2
        ? [
            Polyline(
              points: _routePoints,
              color: _routeColor,
              strokeWidth: 6,
              borderColor: _routeColor.withValues(alpha: 0.35),
              borderStrokeWidth: 2,
            ),
          ]
        : <Polyline>[];

    final center = amb ?? widget.destination;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
                ),
                onMapReady: _fitBounds,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: _osmUserAgent,
                  maxZoom: 19,
                ),
                if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
                MarkerLayer(markers: markers),
              ],
            ),
            if (_loadingRoute && amb != null)
              Positioned(
                top: 10,
                right: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
                    ],
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
