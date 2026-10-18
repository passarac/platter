import 'package:flutter/material.dart';

import '../theme/platter_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
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
          constraints: const BoxConstraints(minHeight: 56),
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? PlatterColors.blue : const Color(0xFFB9C4DA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PlatterColors.ink, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: PlatterColors.ink,
                offset: Offset(0, _pressed ? 1 : 4),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: PlatterText.head(size: 19, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
