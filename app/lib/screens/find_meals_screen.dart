import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/platter_theme.dart';
import '../widgets/crayon.dart';
import '../widgets/onboarding_page.dart';
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
    return OnboardingPage(
      onBack: onBack,
      art: Crayon(
        child: SvgPicture.asset(
          'assets/illustrations/find_meals_phone.svg',
          fit: BoxFit.contain,
          semanticsLabel:
              'A phone full of photos with a magnifying glass finding a '
              'meal, and a padlock badge reading on-device',
        ),
      ),
      children: [
        Text("Let's find your meals", style: PlatterText.head(size: 32)),
        const SizedBox(height: 12),
        Text(
          'We look through your photo library on your phone to find meals. '
          'The scan happens on-device.',
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
        SecondaryButton(label: 'Selected photos', onPressed: onSelectedPhotos),
      ],
    );
  }
}
