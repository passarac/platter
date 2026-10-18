import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Gives [child] the mockup's hand-drawn crayon texture (`filter:url(#ob-crayon)`).
///
/// Wrap only fills, borders and illustrations; keep text outside so it stays
/// crisp. Falls back to the plain child where shader filters aren't supported
/// (non-Impeller backends, widget tests).
class Crayon extends StatefulWidget {
  const Crayon({super.key, required this.child});

  final Widget child;

  @override
  State<Crayon> createState() => _CrayonState();
}

class _CrayonState extends State<Crayon> {
  static Future<ui.FragmentProgram?>? _program;

  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _program ??= _load();
    _program!.then((program) {
      if (program != null && mounted) {
        setState(() => _shader = program.fragmentShader());
      }
    });
  }

  static Future<ui.FragmentProgram?> _load() async {
    if (!ui.ImageFilter.isShaderFilterSupported) return null;
    try {
      return await ui.FragmentProgram.fromAsset('shaders/crayon.frag');
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null) return widget.child;
    // Index 0–1 is uSize, filled in by the engine.
    shader.setFloat(2, MediaQuery.devicePixelRatioOf(context));
    return ImageFiltered(
      imageFilter: ui.ImageFilter.shader(shader),
      child: widget.child,
    );
  }
}
