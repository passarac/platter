import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/platter_theme.dart';
import '../widgets/paper_grid.dart';
import '../widgets/primary_button.dart';

/// Onboarding step 1: sells the calendar idea before asking for anything.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, this.onGetStarted, this.onRestore});

  final VoidCallback? onGetStarted;

  /// Restores from a local backup file (there are no accounts).
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PaperGrid(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Platter', style: PlatterText.head(size: 22)),
              ),
              const Expanded(child: _FloatingArt()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    Text(
                      'Your meals, as a calendar of memories.',
                      textAlign: TextAlign.center,
                      style: PlatterText.head(size: 33),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No calories, no tracking.',
                      textAlign: TextAlign.center,
                      style: PlatterText.body(weight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
                child: Column(
                  children: [
                    PrimaryButton(label: 'Get started', onPressed: onGetStarted),
                    const SizedBox(height: 10),
                    _RestoreLine(onRestore: onRestore),
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

/// The calendar illustration, bobbing gently up and down.
class _FloatingArt extends StatefulWidget {
  const _FloatingArt();

  @override
  State<_FloatingArt> createState() => _FloatingArtState();
}

class _FloatingArtState extends State<_FloatingArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offset = Tween(begin: Offset.zero, end: const Offset(0, -6)).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    return Center(
      child: AnimatedBuilder(
        animation: offset,
        builder: (context, child) =>
            Transform.translate(offset: offset.value, child: child),
        child: SvgPicture.asset(
          'assets/illustrations/welcome_calendar.svg',
          fit: BoxFit.contain,
          semanticsLabel:
              'A month calendar filled with little meal photos, with Doughtie '
              'the donut peeking over the top corner',
        ),
      ),
    );
  }
}

class _RestoreLine extends StatelessWidget {
  const _RestoreLine({this.onRestore});

  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final base = PlatterText.body(size: 14, color: PlatterColors.ink3);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'Have a backup file? '),
          TextSpan(
            text: 'Restore it',
            style: base.copyWith(
              fontWeight: FontWeight.w800,
              color: PlatterColors.blueInk,
              decoration: TextDecoration.underline,
              decorationColor: PlatterColors.blueInk,
            ),
            recognizer: TapGestureRecognizer()..onTap = onRestore,
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
