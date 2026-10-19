import 'package:flutter/material.dart';

import '../screens/no_access_screen.dart';
import '../screens/selected_photos_screen.dart';
import '../services/onboarding_progress.dart';
import '../services/photo_library.dart';
import '../widgets/settings_prompt.dart';

/// A route for an onboarding screen, named after its [step] so the step is
/// saved whenever it becomes the top route.
Route<void> onboardingRoute(OnboardingStep step, WidgetBuilder builder) =>
    MaterialPageRoute<void>(
      settings: RouteSettings(name: step.name),
      builder: builder,
    );

/// Asks for photo access from the find-your-meals screen and routes to the
/// right next step for whatever the user chose in the system prompt, or, if
/// access was already set to something else, guides them to Settings.
class PhotoAccessFlow {
  PhotoAccessFlow({
    required this.library,
    required this.progress,
    required this.onScan,
    required this.onEmptyCalendar,
  });

  final PhotoLibrary library;
  final OnboardingProgress progress;

  /// Next step once there are photos to look through.
  final void Function(BuildContext context) onScan;
  final void Function(BuildContext context) onEmptyCalendar;

  /// Waits for the user to come back from Settings; see [_openSettings].
  AppLifecycleListener? _settingsReturn;

  /// Set while a button's request is in flight, so a second tap (say, while
  /// the system prompt is loading) can't ask twice and push two screens.
  bool _asking = false;

  void dispose() => _settingsReturn?.dispose();

  /// "Full access".
  Future<void> askFull(BuildContext context) => _ask(context, PhotoAccess.full);

  /// "Selected photos". iOS has no way to ask for limited access directly, so
  /// a first-time user still sees the system prompt (where "Limit Access"
  /// opens the picker). Someone already limited gets the picker again.
  Future<void> askSelected(BuildContext context) =>
      _ask(context, PhotoAccess.limited);

  /// The screen that follows once [access] is chosen, or null when there
  /// isn't one: full access goes on to [onScan], and not asked stays put.
  Route<void>? routeFor(PhotoAccess access) => switch (access) {
    PhotoAccess.limited => onboardingRoute(
      OnboardingStep.selectedPhotos,
      (context) => SelectedPhotosScreen(
        library: library,
        onContinue: () => onScan(context),
        onAccessChanged: (a) => _route(context, a, replace: true),
      ),
    ),
    PhotoAccess.none => onboardingRoute(
      OnboardingStep.noAccess,
      (context) => NoAccessScreen(
        library: library,
        onEmptyCalendar: () => onEmptyCalendar(context),
        onAccessChanged: (a) => _route(context, a, replace: true),
      ),
    ),
    PhotoAccess.full || PhotoAccess.notAsked => null,
  };

  Future<void> _ask(BuildContext context, PhotoAccess want) async {
    // Also ignore taps on a screen that's already on its way out.
    if (_asking || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _asking = true;
    try {
      await _askOnce(context, want);
    } finally {
      _asking = false;
    }
  }

  Future<void> _askOnce(BuildContext context, PhotoAccess want) async {
    final access = await library.currentAccess();
    if (!context.mounted) return;
    if (access == PhotoAccess.notAsked) {
      // The system prompt offers full, limited or none; whatever the user
      // picks there is their answer, even if it differs from the button.
      final answer = await library.requestAccess();
      if (context.mounted) _route(context, answer);
    } else if (access == want) {
      if (want == PhotoAccess.limited) await library.changeSelection();
      if (context.mounted) _route(context, access);
    } else {
      // Already set (maybe in Settings before onboarding) to something other
      // than the button asks for, and the prompt won't show again.
      final go = await askToOpenSettings(
        context,
        title: switch (access) {
          PhotoAccess.limited => 'Platter can only see selected photos',
          PhotoAccess.full => 'Platter can see all your photos',
          PhotoAccess.none ||
          PhotoAccess.notAsked => 'Photo access is turned off',
        },
        want: want,
      );
      if (go && context.mounted) await _openSettings(context, access);
    }
  }

  /// iOS quits the app when access changes in Settings, so the trip is noted
  /// first for [resumeStep] to act on at relaunch. If the app is still
  /// running when the user comes back (nothing changed, or Android granting
  /// access), carry on from here instead.
  Future<void> _openSettings(BuildContext context, PhotoAccess before) async {
    await progress.setWentToSettings(true);
    _settingsReturn?.dispose();
    _settingsReturn = AppLifecycleListener(
      onResume: () async {
        _settingsReturn?.dispose();
        _settingsReturn = null;
        await progress.setWentToSettings(false);
        final now = await library.currentAccess();
        if (now != before && context.mounted) _route(context, now);
      },
    );
    await library.openSettings();
  }

  void _route(
    BuildContext context,
    PhotoAccess access, {
    bool replace = false,
  }) {
    if (access == PhotoAccess.full) {
      if (replace) Navigator.of(context).pop();
      onScan(context);
      return;
    }
    final route = routeFor(access);
    // Not asked: the prompt was dismissed without an answer; stay put.
    if (route == null) return;
    final navigator = Navigator.of(context);
    replace ? navigator.pushReplacement(route) : navigator.push(route);
  }
}
