import 'package:flutter/material.dart';

/// Ambulance vehicle marker (white van, red cross, blue siren).
class AmbulanceMapMarker extends StatelessWidget {
  const AmbulanceMapMarker({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    final w = size;
    final h = size * 0.72;
    return SizedBox(
      width: w,
      height: size,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: w * 0.28,
              height: w * 0.28,
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(Icons.flare, size: 10, color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: w * 0.08,
                    top: h * 0.22,
                    child: Container(
                      width: w * 0.38,
                      height: h * 0.42,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: w * 0.22,
                      height: w * 0.22,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const Icon(Icons.add, size: 14, color: Colors.white),
                    ),
                  ),
                  Positioned(
                    right: w * 0.1,
                    bottom: h * 0.18,
                    child: Container(
                      width: w * 0.2,
                      height: h * 0.28,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
