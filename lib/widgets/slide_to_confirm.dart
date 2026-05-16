import 'package:flutter/material.dart';

/// Horizontal slide-to-confirm (prevents accidental emergency actions).
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.icon,
    required this.subtitle,
    required this.onConfirmed,
    this.trackColor,
    this.knobColor = Colors.white,
  });

  final String label;
  final IconData icon;
  final String subtitle;
  final VoidCallback onConfirmed;
  final Color? trackColor;
  final Color knobColor;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> {
  double _dx = 0;
  static const double _knobSize = 48;

  @override
  Widget build(BuildContext context) {
    final accent = widget.trackColor ?? Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDx = (constraints.maxWidth - _knobSize - 8).clamp(0.0, double.infinity);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) {
                setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, maxDx));
              },
              onHorizontalDragEnd: (_) {
                if (_dx >= maxDx * 0.92) {
                  widget.onConfirmed();
                }
                setState(() => _dx = 0);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 56,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(color: accent),
                        child: Center(
                          child: AnimatedOpacity(
                            opacity: maxDx <= 0 ? 1 : (1 - (_dx / maxDx)).clamp(0.15, 1),
                            duration: Duration.zero,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(widget.icon, color: Colors.white70, size: 22),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    widget.label.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      letterSpacing: 0.8,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 80),
                        curve: Curves.easeOut,
                        left: 4 + _dx,
                        top: 4,
                        child: Container(
                          width: _knobSize - 8,
                          height: _knobSize - 8,
                          decoration: BoxDecoration(
                            color: widget.knobColor,
                            shape: BoxShape.circle,
                            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.chevron_right_rounded, color: accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    );
  }
}
