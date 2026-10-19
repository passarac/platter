import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/platter_theme.dart';
import '../widgets/crayon.dart';
import '../widgets/paper_grid.dart';
import '../widgets/primary_button.dart';

/// Onboarding step 1: sells the calendar idea before asking for anything.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, this.onGetStarted});

  final VoidCallback? onGetStarted;

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
                child: PrimaryButton(
                  label: 'Get started',
                  onPressed: onGetStarted,
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
  late final _offset = _controller
      .drive(CurveTween(curve: Curves.easeInOut))
      .drive(Tween(begin: Offset.zero, end: const Offset(0, -6)));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _offset,
        builder: (context, child) =>
            Transform.translate(offset: _offset.value, child: child),
        child: Crayon(
          child: SvgPicture.asset(
            'assets/illustrations/welcome_calendar.svg',
            fit: BoxFit.contain,
            semanticsLabel:
                'A month calendar filled with little meal photos, with '
                'Doughtie the donut peeking over the top corner',
          ),
        ),
      ),
    );
  }
}
