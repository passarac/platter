import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/platter_theme.dart';
import '../widgets/crayon.dart';
import '../widgets/paper_grid.dart';
import '../widgets/primary_button.dart';

/// Onboarding step 2: explains the on-device photo scan before the system
/// photo-access prompt appears.
class FindMealsScreen extends StatelessWidget {
  const FindMealsScreen({
    super.key,
    this.onBack,
    this.onFullAccess,
    this.onSelectedPhotos,
  });

  final VoidCallback? onBack;
  final VoidCallback? onFullAccess;
  final VoidCallback? onSelectedPhotos;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PaperGrid(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(onBack: onBack, step: 0, steps: 3),
              Expanded(
                child: Center(
                  child: Crayon(
                    child: SvgPicture.asset(
                      'assets/illustrations/find_meals_phone.svg',
                      fit: BoxFit.contain,
                      semanticsLabel:
                          'A phone full of photos with a magnifying glass '
                          'finding a meal, and a padlock badge reading '
                          'on-device',
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 6, 28, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Let's find your meals",
                      style: PlatterText.head(size: 32),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We look through your photo library on your phone to '
                      'find meals. The scan happens on-device.',
                      style: PlatterText.body().copyWith(height: 1.45),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Next, your phone will ask how much access to give.',
                      style: PlatterText.body(
                        size: 14,
                        color: PlatterColors.ink3,
                      ).copyWith(height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    PrimaryButton(
                      label: 'Full access',
                      subtitle: 'Recommended',
                      onPressed: onFullAccess,
                    ),
                    const SizedBox(height: 10),
                    SecondaryButton(
                      label: 'Selected photos',
                      onPressed: onSelectedPhotos,
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
