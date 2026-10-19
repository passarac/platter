import 'package:platter/services/onboarding_progress.dart';

/// Keeps onboarding progress in memory instead of on the device.
class FakeOnboardingProgress implements OnboardingProgress {
  FakeOnboardingProgress({
    this.saved = OnboardingStep.welcome,
    this.inSettings = false,
  });

  OnboardingStep saved;
  bool inSettings;

  @override
  Future<OnboardingStep> step() async => saved;

  @override
  Future<void> setStep(OnboardingStep step) async => saved = step;

  @override
  Future<bool> wentToSettings() async => inSettings;

  @override
  Future<void> setWentToSettings(bool value) async => inSettings = value;
}
