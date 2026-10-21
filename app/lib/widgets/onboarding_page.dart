import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/platter_theme.dart';
import 'paper_grid.dart';

/// Layout shared by the onboarding steps after Welcome: a top bar with back
/// button and progress dots, an illustration filling the free space, then
/// left-aligned copy and actions.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    super.key,
    required this.art,
    required this.children,
    this.step = 0,
    this.steps = 3,
    this.onBack,
  });

  final Widget art;

  /// Headline, copy and buttons, top to bottom.
  final List<Widget> children;
  final int step;
  final int steps;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PaperGrid(
        child: SafeArea(
          child: ArtLayout(
            header: OnboardingTopBar(onBack: onBack, step: step, steps: steps),
            art: Center(child: art),
            footer: Padding(
              padding: const EdgeInsets.fromLTRB(28, 6, 28, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stacks [header], [art] and [footer] to fill the screen, the art taking
/// whatever room is left. Where that would leave the art under
/// [minArtHeight] (small phones, landscape, large text), the art stops
/// shrinking and the page scrolls instead, so copy and buttons are never cut
/// off.
class ArtLayout extends StatelessWidget {
  const ArtLayout({
    super.key,
    this.header,
    required this.art,
    required this.footer,
    this.minArtHeight = 120,
  });

  final Widget? header;
  final Widget art;
  final Widget footer;
  final double minArtHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) => SingleChildScrollView(
        child: _ArtColumn(
          viewportHeight: viewport.maxHeight,
          minArtHeight: minArtHeight,
          children: [header ?? const SizedBox.shrink(), art, footer],
        ),
      ),
    );
  }
}

/// [ArtLayout]'s column, laid out in a single pass from the header's and
/// footer's real sizes. (An IntrinsicHeight-based Column relies on cached
/// size estimates, which go stale when fonts finish loading after the first
/// frame and leave the art too tall.)
class _ArtColumn extends MultiChildRenderObjectWidget {
  const _ArtColumn({
    required this.viewportHeight,
    required this.minArtHeight,
    required super.children,
  }) : assert(children.length == 3);

  final double viewportHeight;
  final double minArtHeight;

  @override
  _RenderArtColumn createRenderObject(BuildContext context) =>
      _RenderArtColumn(viewportHeight, minArtHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderArtColumn renderObject) {
    renderObject
      ..viewportHeight = viewportHeight
      ..minArtHeight = minArtHeight;
  }
}

class _ArtColumnParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderArtColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ArtColumnParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ArtColumnParentData> {
  _RenderArtColumn(this._viewportHeight, this._minArtHeight);

  double get viewportHeight => _viewportHeight;
  double _viewportHeight;
  set viewportHeight(double value) {
    if (value == _viewportHeight) return;
    _viewportHeight = value;
    markNeedsLayout();
  }

  double get minArtHeight => _minArtHeight;
  double _minArtHeight;
  set minArtHeight(double value) {
    if (value == _minArtHeight) return;
    _minArtHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ArtColumnParentData) {
      child.parentData = _ArtColumnParentData();
    }
  }

  /// Header, art and footer heights for [width], using [measure] to size
  /// the header and footer at their natural height.
  (double, double, double) _heights(
    double width,
    Size Function(RenderBox child, BoxConstraints constraints) measure,
  ) {
    final header = firstChild!;
    final footer = lastChild!;
    final natural = BoxConstraints.tightFor(width: width);
    final top = measure(header, natural).height;
    final bottom = measure(footer, natural).height;
    final art = math.max(minArtHeight, viewportHeight - top - bottom);
    return (top, art, bottom);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final (top, art, bottom) = _heights(
      constraints.maxWidth,
      (child, c) => child.getDryLayout(c),
    );
    return constraints.constrain(
      Size(constraints.maxWidth, top + art + bottom),
    );
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final (top, art, bottom) = _heights(width, (child, c) {
      child.layout(c, parentUsesSize: true);
      return child.size;
    });
    final artChild = childAfter(firstChild!)!;
    artChild.layout(BoxConstraints.tight(Size(width, art)));
    (artChild.parentData! as _ArtColumnParentData).offset = Offset(0, top);
    (lastChild!.parentData! as _ArtColumnParentData).offset = Offset(
      0,
      top + art,
    );
    size = constraints.constrain(Size(width, top + art + bottom));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Underlined blue text button (`.link` in the mockup).
class TextLink extends StatelessWidget {
  const TextLink({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          child: Text(
            label,
            style:
                PlatterText.body(
                  size: 15,
                  weight: FontWeight.w800,
                  color: PlatterColors.blueInk,
                ).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: PlatterColors.blueInk,
                ),
          ),
        ),
      ),
    );
  }
}

/// Back button and onboarding progress dots (`.topbar` in the mockup).
class OnboardingTopBar extends StatelessWidget {
  const OnboardingTopBar({
    super.key,
    required this.step,
    this.steps = 3,
    this.onBack,
    this.showBack = true,
  });

  final int step;
  final int steps;
  final VoidCallback? onBack;

  /// Without the back button the dots stay centred.
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (showBack)
            Semantics(
              button: true,
              label: 'Back',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBack ?? () => Navigator.maybePop(context),
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: CustomPaint(painter: _ChevronPainter()),
                ),
              ),
            )
          else
            const SizedBox(width: 44, height: 44),
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < steps; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                    width: i == step ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == step
                          ? PlatterColors.ink
                          : PlatterColors.ink.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// The mockup's chunky back chevron (`M15 5l-7 7 7 7` on a 24px grid).
class _ChevronPainter extends CustomPainter {
  const _ChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final o = Offset((size.width - 24) / 2, (size.height - 24) / 2);
    final path = Path()
      ..moveTo(o.dx + 15, o.dy + 5)
      ..lineTo(o.dx + 8, o.dy + 12)
      ..lineTo(o.dx + 15, o.dy + 19);
    canvas.drawPath(
      path,
      Paint()
        ..color = PlatterColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => false;
}
