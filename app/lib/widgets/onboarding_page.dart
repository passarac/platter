import 'package:flutter/material.dart';

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(onBack: onBack, step: step, steps: steps),
              Expanded(child: Center(child: art)),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 6, 28, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
class _TopBar extends StatelessWidget {
  const _TopBar({required this.step, required this.steps, this.onBack});

  final int step;
  final int steps;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
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
          ),
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
