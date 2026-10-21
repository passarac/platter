import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart';

import 'flows/photo_access_flow.dart';
import 'screens/find_meals_screen.dart';
import 'screens/scanning_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/food_scanner.dart';
import 'services/onboarding_progress.dart';
import 'services/photo_library.dart';
import 'theme/platter_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const photos = DevicePhotoLibrary();
  const progress = SavedOnboardingProgress();
  var resumeAt = OnboardingStep.welcome;
  try {
    resumeAt = await resumeStep(progress, photos);
  } catch (error, stack) {
    // Never let saved progress stop the app opening: report it, start over.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'platter',
        context: ErrorDescription('while resuming onboarding'),
      ),
    );
  }
  runApp(
    PlatterApp(
      photos: photos,
      progress: progress,
      // Only iOS has a scanner so far.
      scanner: defaultTargetPlatform == TargetPlatform.iOS
          ? const DeviceFoodScanner()
          : null,
      resumeAt: resumeAt,
    ),
  );
}

class PlatterApp extends StatefulWidget {
  const PlatterApp({
    super.key,
    required this.photos,
    required this.progress,
    this.scanner,
    this.resumeAt = OnboardingStep.welcome,
  });

  final PhotoLibrary photos;
  final OnboardingProgress progress;

  /// Finds meals among the photos. Without one, the scan is "coming soon".
  final FoodScanner? scanner;

  /// Where onboarding picks up, from [resumeStep].
  final OnboardingStep resumeAt;

  @override
  State<PlatterApp> createState() => _PlatterAppState();
}

class _PlatterAppState extends State<PlatterApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final _saveStep = _StepSaver(widget.progress);
  late final _photoAccess = PhotoAccessFlow(
    library: widget.photos,
    progress: widget.progress,
    onScan: (context) {
      final scanner = widget.scanner;
      if (scanner == null) return _comingSoon(context, 'Scanning for meals');
      Navigator.of(context).push(_scanning(scanner));
    },
    onEmptyCalendar: (context) => _comingSoon(context, 'The calendar'),
  );

  @override
  void initState() {
    super.initState();
    if (widget.resumeAt == OnboardingStep.scan) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _navigator.currentContext;
        if (context != null) _photoAccess.onScan(context);
      });
    }
  }

  @override
  void dispose() {
    _photoAccess.dispose();
    super.dispose();
  }

  Route<void> _welcome() => onboardingRoute(
    OnboardingStep.welcome,
    (context) => WelcomeScreen(
      onGetStarted: () => Navigator.of(context).push(_findMeals()),
    ),
  );

  Route<void> _findMeals() => onboardingRoute(
    OnboardingStep.findMeals,
    (context) => FindMealsScreen(
      onFullAccess: () => _photoAccess.askFull(context),
      onSelectedPhotos: () => _photoAccess.askSelected(context),
    ),
  );

  Route<void> _scanning(FoodScanner scanner) => onboardingRoute(
    OnboardingStep.scan,
    (context) => ScanningScreen(
      scanner: scanner,
      library: widget.photos,
      onSeeCalendar: () => _comingSoon(context, 'The calendar'),
      onEmptyCalendar: () => _comingSoon(context, 'The calendar'),
    ),
  );

  /// The screens up to [PlatterApp.resumeAt], so back still walks through
  /// onboarding after a relaunch.
  List<Route<void>> _initialRoutes(String _) {
    final resumeAt = widget.resumeAt;
    final next = switch (resumeAt) {
      OnboardingStep.selectedPhotos => _photoAccess.routeFor(
        PhotoAccess.limited,
      ),
      OnboardingStep.noAccess => _photoAccess.routeFor(PhotoAccess.none),
      _ => null,
    };
    return [
      _welcome(),
      if (resumeAt != OnboardingStep.welcome) _findMeals(),
      ?next,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Platter',
      debugShowCheckedModeBanner: false,
      theme: buildPlatterTheme(),
      navigatorKey: _navigator,
      navigatorObservers: [_saveStep],
      onGenerateInitialRoutes: _initialRoutes,
      onGenerateRoute: (_) => _welcome(),
    );
  }

  static void _comingSoon(BuildContext context, String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what is coming soon.')));
  }
}

/// Saves the onboarding step whenever an onboarding screen ends up on top,
/// including going back. Dialogs and other unnamed routes are ignored.
class _StepSaver extends NavigatorObserver {
  _StepSaver(this.progress);

  final OnboardingProgress progress;

  void _save(Route<dynamic>? route) {
    final step = OnboardingStep.values.asNameMap()[route?.settings.name];
    if (step != null) unawaited(progress.setStep(step));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _save(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _save(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _save(newRoute);
}
