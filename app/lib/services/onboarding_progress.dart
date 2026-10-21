import 'package:shared_preferences/shared_preferences.dart';

import 'photo_library.dart';

/// The onboarding screens, in order. Each screen's route is named after its
/// step so the step can be saved whenever the top route changes.
enum OnboardingStep {
  welcome,
  findMeals,
  selectedPhotos,
  noAccess,

  /// The scanning screen. Resuming here starts the scan again, which picks
  /// up where it stopped.
  scan,
}

/// Remembers how far the user got through onboarding. iOS quits the app
/// whenever photo access changes in Settings, so without this a trip to
/// Settings would land them back on Welcome.
abstract interface class OnboardingProgress {
  Future<OnboardingStep> step();
  Future<void> setStep(OnboardingStep step);

  /// Whether the user left "find your meals" for Settings to change photo
  /// access, so a relaunch should act on whatever they chose there.
  Future<bool> wentToSettings();
  Future<void> setWentToSettings(bool value);
}

class SavedOnboardingProgress implements OnboardingProgress {
  const SavedOnboardingProgress();

  static const _stepKey = 'onboarding.step';
  static const _settingsKey = 'onboarding.wentToSettings';
  static final _prefs = SharedPreferencesAsync();

  @override
  Future<OnboardingStep> step() async {
    final name = await _prefs.getString(_stepKey);
    return OnboardingStep.values.asNameMap()[name] ?? OnboardingStep.welcome;
  }

  @override
  Future<void> setStep(OnboardingStep step) =>
      _prefs.setString(_stepKey, step.name);

  @override
  Future<bool> wentToSettings() async =>
      await _prefs.getBool(_settingsKey) ?? false;

  @override
  Future<void> setWentToSettings(bool value) =>
      _prefs.setBool(_settingsKey, value);
}

/// Where to pick onboarding back up at launch. Clears the Settings trip, so
/// call it once per launch.
Future<OnboardingStep> resumeStep(
  OnboardingProgress progress,
  PhotoLibrary photos,
) async {
  final step = await progress.step();
  if (step == OnboardingStep.welcome) return step;
  final fromSettings = await progress.wentToSettings();
  if (fromSettings) await progress.setWentToSettings(false);
  // Still choosing: access set before onboarding shouldn't choose for them.
  if (step == OnboardingStep.findMeals && !fromSettings) return step;
  // Past the choice, or just back from Settings: their access decides.
  return switch (await photos.currentAccess()) {
    PhotoAccess.full => OnboardingStep.scan,
    // Back to the selected photos, unless they'd already moved on to the
    // scan and haven't been to Settings since.
    PhotoAccess.limited =>
      step == OnboardingStep.scan && !fromSettings
          ? OnboardingStep.scan
          : OnboardingStep.selectedPhotos,
    PhotoAccess.none => OnboardingStep.noAccess,
    PhotoAccess.notAsked => OnboardingStep.findMeals,
  };
}
