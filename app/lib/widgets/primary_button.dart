import 'package:flutter/material.dart';

import '../theme/platter_theme.dart';
import 'crayon.dart';

/// Chunky blue button with a hard ink drop-shadow that presses down on tap
/// (`.btn.primary` in the mockup).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.subtitle,
  });

  final String label;

  /// Small second line under the label, e.g. "Recommended".
  final String? subtitle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return _SketchButton(
      label: label,
      subtitle: subtitle,
      onPressed: onPressed,
      fill: enabled ? PlatterColors.blue : const Color(0xFFB9C4DA),
      textColor: Colors.white,
      minHeight: 56,
      fontSize: 19,
      shadow: 4,
      pressDepth: 3,
    );
  }
}

/// Paper-coloured outline button without a drop-shadow (`.btn.secondary`).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _SketchButton(
      label: label,
      onPressed: onPressed,
      fill: PlatterColors.paper,
      textColor: PlatterColors.ink,
      minHeight: 52,
      fontSize: 18,
      shadow: 0,
      pressDepth: 2,
    );
  }
}

class _SketchButton extends StatefulWidget {
  const _SketchButton({
    required this.label,
    required this.onPressed,
    required this.fill,
    required this.textColor,
    required this.minHeight,
    required this.fontSize,
    required this.shadow,
    required this.pressDepth,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final VoidCallback? onPressed;
  final Color fill;
  final Color textColor;
  final double minHeight;
  final double fontSize;

  /// Drop-shadow depth at rest; it shrinks to 1 while pressed.
  final double shadow;

  /// How far the button moves down while pressed.
  final double pressDepth;

  @override
  State<_SketchButton> createState() => _SketchButtonState();
}

class _SketchButtonState extends State<_SketchButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed != null) setState(() => _pressed = value);
  }

  /// Room around the crayon layer so its wobble isn't clipped at the edges.
  static const _bleed = 4.0;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final maxShadow = widget.shadow;
    final shadow = _pressed && maxShadow > 0 ? 1.0 : maxShadow;
    final radius = BorderRadius.circular(16);
    final subtitle = widget.subtitle;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: Matrix4.translationValues(
            0,
            _pressed ? widget.pressDepth : 0,
            0,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Fill, border and drop-shadow get the crayon texture; the
              // label sits above it so it stays crisp (`.sk::before`).
              Positioned(
                left: -_bleed,
                top: -_bleed,
                right: -_bleed,
                bottom: -_bleed - maxShadow,
                child: Crayon(
                  child: Padding(
                    padding: const EdgeInsets.all(_bleed),
                    child: Stack(
                      children: [
                        if (maxShadow > 0)
                          Positioned.fill(
                            top: shadow,
                            bottom: maxShadow - shadow,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: PlatterColors.ink,
                                borderRadius: radius,
                              ),
                            ),
                          ),
                        Positioned.fill(
                          bottom: maxShadow,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: widget.fill,
                              borderRadius: radius,
                              border: Border.all(
                                color: PlatterColors.ink,
                                width: 2.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                constraints: BoxConstraints(minHeight: widget.minHeight),
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: PlatterText.head(
                        size: widget.fontSize,
                        color: widget.textColor,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          subtitle,
                          style: PlatterText.body(
                            size: 13,
                            color: widget.textColor.withValues(alpha: 0.92),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
