import 'package:flutter/material.dart';

import '../theme/platter_theme.dart';
import 'crayon.dart';

/// Yellow graph-paper background used on the onboarding screens
/// (`.paper-grid` in the mockup).
class PaperGrid extends StatelessWidget {
  const PaperGrid({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          // Bleeds past the edges so the crayon wobble never shows a border.
          const Positioned(
            left: -8,
            top: -8,
            right: -8,
            bottom: -8,
            child: Crayon(child: CustomPaint(painter: _GridPainter())),
          ),
          Positioned.fill(child: _RouteDrift(child: child)),
        ],
      ),
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

/// Nudges the content sideways while its route comes and goes (the mockup's
/// `slideNext`), so screen changes have direction without moving the paper.
class _RouteDrift extends StatefulWidget {
  const _RouteDrift({required this.child});

  final Widget child;

  @override
  State<_RouteDrift> createState() => _RouteDriftState();
}

class _RouteDriftState extends State<_RouteDrift> {
  static const _distance = 28.0;

  ModalRoute<Object?>? _route;
  CurvedAnimation? _enter;
  CurvedAnimation? _cover;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    _disposeCurves();
    _route = route;
    if (route?.animation case final enter?) _enter = easeScreenChange(enter);
    if (route?.secondaryAnimation case final cover?) {
      _cover = easeScreenChange(cover);
    }
  }

  @override
  void dispose() {
    _disposeCurves();
    super.dispose();
  }

  void _disposeCurves() {
    _enter?.dispose();
    _cover?.dispose();
    _enter = _cover = null;
  }

  @override
  Widget build(BuildContext context) {
    final enter = _enter;
    final cover = _cover;
    if (enter == null || cover == null) return widget.child;
    return AnimatedBuilder(
      animation: Listenable.merge([enter, cover]),
      builder: (context, child) => Transform.translate(
        offset: Offset(((1 - enter.value) - cover.value) * _distance, 0),
        child: child,
      ),
      child: widget.child,
    );
  }
}
