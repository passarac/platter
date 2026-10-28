import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/platter_theme.dart';
import 'crayon.dart';

/// A box drawn the mockup's way (`.sk`): a crayon-textured fill and ink
/// border, optionally with a hard drop-shadow, a dashed border or an outer
/// ring, with [child] crisp on top.
///
/// Without a [child] it fills whatever space it's given.
class SketchBox extends StatelessWidget {
  const SketchBox({
    super.key,
    this.fill = PlatterColors.paper,
    this.border = PlatterColors.ink,
    this.borderWidth = 2.5,
    this.radius = 16,
    this.shadow = 0,
    this.dashed = false,
    this.ring = 0,
    this.ringColor = PlatterColors.blue,
    this.child,
  });

  final Color fill;
  final Color border;
  final double borderWidth;
  final double radius;

  /// Height of the hard drop-shadow under the box, drawn outside it.
  final double shadow;
  final bool dashed;

  /// Width of a ring drawn just outside the border (`box-shadow: 0 0 0 Npx`).
  final double ring;
  final Color ringColor;
  final Widget? child;

  /// Room around the crayon layer so its wobble isn't clipped at the edges.
  static const _bleed = 4.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        Positioned(
          left: -_bleed,
          top: -_bleed,
          right: -_bleed,
          bottom: -_bleed - shadow,
          child: Crayon(
            child: Padding(
              padding: const EdgeInsets.all(_bleed),
              child: CustomPaint(
                painter: _SketchPainter(
                  fill: fill,
                  border: border,
                  borderWidth: borderWidth,
                  radius: radius,
                  shadow: shadow,
                  dashed: dashed,
                  ring: ring,
                  ringColor: ringColor,
                ),
              ),
            ),
          ),
        ),
        ?child,
      ],
    );
  }
}

class _SketchPainter extends CustomPainter {
  const _SketchPainter({
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.radius,
    required this.shadow,
    required this.dashed,
    required this.ring,
    required this.ringColor,
  });

  final Color fill;
  final Color border;
  final double borderWidth;
  final double radius;
  final double shadow;
  final bool dashed;
  final double ring;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromLTWH(0, 0, size.width, size.height - shadow);
    final outer = RRect.fromRectAndRadius(box, Radius.circular(radius));
    if (shadow > 0) {
      canvas.drawRRect(
        outer.shift(Offset(0, shadow)),
        Paint()..color = PlatterColors.ink,
      );
    }
    if (ring > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          box.inflate(ring / 2),
          Radius.circular(radius + ring / 2),
        ),
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring,
      );
    }
    canvas.drawRRect(outer, Paint()..color = fill);
    if (borderWidth <= 0) return;
    // CSS borders sit inside the box.
    final inner = RRect.fromRectAndRadius(
      box.deflate(borderWidth / 2),
      Radius.circular(math.max(0, radius - borderWidth / 2)),
    );
    final stroke = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;
    if (!dashed) {
      canvas.drawRRect(inner, stroke);
      return;
    }
    final outline = Path()..addRRect(inner);
    final dashes = Path();
    final dash = borderWidth * 3, gap = borderWidth * 2;
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        dashes.addPath(metric.extractPath(d, d + dash), Offset.zero);
      }
    }
    canvas.drawPath(dashes, stroke);
  }

  @override
  bool shouldRepaint(_SketchPainter old) =>
      fill != old.fill ||
      border != old.border ||
      borderWidth != old.borderWidth ||
      radius != old.radius ||
      shadow != old.shadow ||
      dashed != old.dashed ||
      ring != old.ring ||
      ringColor != old.ringColor;
}

/// Shrinks [child] a touch while it's pressed (the mockup's `:active`
/// `scale(.96)`).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    this.scale = 0.96,
    required this.child,
  });

  final VoidCallback? onTap;
  final double scale;
  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _set(bool value) {
    if (widget.onTap != null && _pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: platterEase,
        child: widget.child,
      ),
    );
  }
}

/// Controls of a fixed height can only take so much text growth.
Widget _compact(Widget child) =>
    MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child);

/// A 44-point square icon button on paper (`.sq-btn`).
class SquareButton extends StatelessWidget {
  const SquareButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Widget icon;

  /// What the button does, for screen readers.
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Pressable(
          onTap: onPressed,
          child: SketchBox(
            radius: 12,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(child: ExcludeSemantics(child: icon)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded pill button with a short label (`.pill-btn`), on paper or, with
/// [blue], filled blue with a small drop-shadow.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.blue = false,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool blue;

  /// 40 points tall with a thinner border (`.pill-btn.sm`).
  final bool small;

  @override
  Widget build(BuildContext context) {
    final color = blue ? Colors.white : PlatterColors.ink;
    return Semantics(
      button: true,
      child: Pressable(
        onTap: onPressed,
        child: SketchBox(
          radius: 999,
          fill: blue ? PlatterColors.blue : PlatterColors.paper,
          borderWidth: small ? 2 : 2.5,
          shadow: blue ? 2 : 0,
          child: _compact(
            Container(
              height: small ? 40 : 44,
              padding: EdgeInsets.symmetric(horizontal: small ? 12 : 14),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon case final icon?) ...[
                    IconTheme(
                      data: IconThemeData(color: color, size: 14),
                      child: icon,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    style: PlatterText.body(
                      size: 14,
                      weight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
