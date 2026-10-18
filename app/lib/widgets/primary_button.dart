import 'package:flutter/material.dart';

import '../theme/platter_theme.dart';
import 'crayon.dart';

/// Chunky blue button with a hard ink drop-shadow that presses down on tap
/// (`.btn.primary` in the mockup).
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed != null) setState(() => _pressed = value);
  }

  static const _maxShadow = 4.0;

  /// Room around the crayon layer so its wobble isn't clipped at the edges.
  static const _bleed = 4.0;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final shadow = _pressed ? 1.0 : _maxShadow;
    final radius = BorderRadius.circular(16);
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
          transform: Matrix4.translationValues(0, _pressed ? 3 : 0, 0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Fill, border and drop-shadow get the crayon texture; the
              // label sits above it so it stays crisp (`.sk::before`).
              Positioned(
                left: -_bleed,
                top: -_bleed,
                right: -_bleed,
                bottom: -_bleed - _maxShadow,
                child: Crayon(
                  child: Padding(
                    padding: const EdgeInsets.all(_bleed),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          top: shadow,
                          bottom: _maxShadow - shadow,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: PlatterColors.ink,
                              borderRadius: radius,
                            ),
                          ),
                        ),
                        Positioned.fill(
                          bottom: _maxShadow,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: enabled
                                  ? PlatterColors.blue
                                  : const Color(0xFFB9C4DA),
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
                constraints: const BoxConstraints(minHeight: 56),
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  widget.label,
                  style: PlatterText.head(size: 19, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
