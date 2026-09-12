import 'package:flutter/material.dart';

/// The lightning-bolt brand mark, drawn from the design's SVG path
/// (`M13 2L3 14H12L11 22L21 10H12L13 2Z` on a 24x24 view box) so it matches
/// exactly rather than approximating with a Material icon.
class BrandBolt extends StatelessWidget {
  const BrandBolt({super.key, required this.color, this.size = 24});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BoltPainter(color)),
    );
  }
}

class _BoltPainter extends CustomPainter {
  const _BoltPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0;
    final path = Path()
      ..moveTo(13 * s, 2 * s)
      ..lineTo(3 * s, 14 * s)
      ..lineTo(12 * s, 14 * s)
      ..lineTo(11 * s, 22 * s)
      ..lineTo(21 * s, 10 * s)
      ..lineTo(12 * s, 10 * s)
      ..lineTo(13 * s, 2 * s)
      ..close();

    // drop-shadow(0 0 8px rgba(16,183,127,0.8)) from the design.
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BoltPainter oldDelegate) => oldDelegate.color != color;
}
