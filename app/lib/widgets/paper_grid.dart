import 'package:flutter/material.dart';

import '../theme/platter_theme.dart';

/// Yellow graph-paper background used on the onboarding screens
/// (`.paper-grid` in the mockup).
class PaperGrid extends StatelessWidget {
  const PaperGrid({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _GridPainter(),
      child: child,
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const _cell = 39.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = PlatterColors.yellow);
    final line = Paint()
      ..color = PlatterColors.ink.withValues(alpha: 0.07)
      ..strokeWidth = 1.5;
    for (var x = 0.0; x <= size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = 0.0; y <= size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
