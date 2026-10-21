import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:platter/main.dart';
import 'package:platter/screens/find_meals_screen.dart';
import 'package:platter/services/food_scanner.dart';
import 'package:platter/services/onboarding_progress.dart';
import 'package:platter/services/photo_library.dart';
import 'package:platter/widgets/onboarding_page.dart';

import 'fake_food_scanner.dart';
import 'fake_onboarding_progress.dart';
import 'fake_photo_library.dart';

/// The system prompt stays up until [choose] is called.
class _SlowPromptLibrary extends FakePhotoLibrary {
  final _prompt = Completer<PhotoAccess>();

  @override
  Future<PhotoAccess> requestAccess() {
    requests++;
    return _prompt.future.then((answer) => access = answer);
  }

  void choose(PhotoAccess answer) => _prompt.complete(answer);
}

/// The picker stays open until [close] is called, like the real one.
class _SlowPickerLibrary extends FakePhotoLibrary {
  _SlowPickerLibrary() : super(access: PhotoAccess.limited);

  final _picker = Completer<void>();

  @override
  Future<void> changeSelection() {
    pickerOpens++;
    return _picker.future;
  }

  void close() => _picker.complete();
}

Future<void> launchAt(
  WidgetTester tester,
  OnboardingStep step,
  PhotoLibrary photos, {
  FakeFoodScanner? scanner,
}) async {
  await tester.pumpWidget(
    PlatterApp(
      photos: photos,
      progress: FakeOnboardingProgress(saved: step),
      scanner: scanner,
      resumeAt: step,
    ),
  );
  // The welcome art bobs forever, so pumpAndSettle would never return there.
  await tester.pump(const Duration(seconds: 1));
}

/// Names of the onboarding routes on the stack, in onboarding order; a
/// screen pushed twice shows up twice.
List<String> routeStack(WidgetTester tester) {
  final routes = {
    for (final page in find.byType(Scaffold, skipOffstage: false).evaluate())
      ?ModalRoute.of(page),
  };
  return [for (final route in routes) route.settings.name!]..sort(
    (a, b) => OnboardingStep.values
        .byName(a)
        .index
        .compareTo(OnboardingStep.values.byName(b).index),
  );
}

/// Two resumes in quick succession, as some devices report.
void resumeTwice(WidgetTester tester) {
  for (var i = 0; i < 2; i++) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Repeated taps and events act once', () {
    testWidgets('a second tap while the system prompt is up', (tester) async {
      final photos = _SlowPromptLibrary();
      await launchAt(tester, OnboardingStep.findMeals, photos);

      await tester.tap(find.text('Selected photos'));
      await tester.pump();
      await tester.tap(find.text('Selected photos'));
      await tester.pump();
      photos.choose(PhotoAccess.limited);
      await tester.pumpAndSettle();

      expect(photos.requests, 1);
      expect(routeStack(tester), ['welcome', 'findMeals', 'selectedPhotos']);
    });

    testWidgets('a tap on find your meals while the next screen fades in', (
      tester,
    ) async {
      final photos = FakePhotoLibrary(access: PhotoAccess.limited);
      await launchAt(tester, OnboardingStep.findMeals, photos);

      await tester.tap(find.text('Selected photos'));
      await tester.pump(const Duration(milliseconds: 100));
      // Whether a real tap reaches the outgoing screen depends on what the
      // incoming one has at that spot, so press its button directly.
      tester
          .widget<FindMealsScreen>(find.byType(FindMealsScreen))
          .onFullAccess!();
      await tester.pumpAndSettle();

      expect(photos.pickerOpens, 1);
      expect(find.text('Platter can only see selected photos'), findsNothing);
      expect(routeStack(tester), ['welcome', 'findMeals', 'selectedPhotos']);
    });

    testWidgets('a double tap on a clashing option shows one popup', (
      tester,
    ) async {
      await launchAt(
        tester,
        OnboardingStep.findMeals,
        FakePhotoLibrary(access: PhotoAccess.none),
      );
      await tester.tap(find.text('Full access'));
      await tester.tap(find.text('Full access'));
      await tester.pumpAndSettle();

      expect(find.text('Photo access is turned off'), findsOneWidget);
    });

    testWidgets('a double tap on Change selection opens one picker', (
      tester,
    ) async {
      final photos = _SlowPickerLibrary();
      await launchAt(tester, OnboardingStep.selectedPhotos, photos);

      await tester.tap(find.text('Change selection'));
      await tester.tap(find.text('Change selection'));
      await tester.pump();
      expect(photos.pickerOpens, 1);

      photos.close();
      await tester.pumpAndSettle();
    });

    testWidgets('two quick resumes with full access leave selected photos '
        'once', (tester) async {
      final photos = FakePhotoLibrary(access: PhotoAccess.limited);
      await launchAt(tester, OnboardingStep.selectedPhotos, photos);

      photos.access = PhotoAccess.full;
      resumeTwice(tester);
      await tester.pumpAndSettle();

      expect(routeStack(tester), ['welcome', 'findMeals']);
    });

    testWidgets('two quick resumes with access leave no access once', (
      tester,
    ) async {
      final photos = FakePhotoLibrary(access: PhotoAccess.none);
      await launchAt(tester, OnboardingStep.noAccess, photos);

      photos.access = PhotoAccess.full;
      resumeTwice(tester);
      await tester.pumpAndSettle();

      expect(routeStack(tester), ['welcome', 'findMeals']);
    });
  });

  group('The art gets the leftover space', () {
    Future<(double art, double scroll)> measure(
      WidgetTester tester,
      Size size,
      double textScale,
    ) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await launchAt(tester, OnboardingStep.findMeals, FakePhotoLibrary());
      final layout = find.byType(ArtLayout);
      final art = tester.getSize(
        find.descendant(of: layout, matching: find.byType(SvgPicture)),
      );
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(of: layout, matching: find.byType(Scrollable)),
          )
          .position
          .maxScrollExtent;
      return (art.height, scroll);
    }

    testWidgets('and fills the screen when everything fits', (tester) async {
      final (art, scroll) = await measure(tester, const Size(402, 874), 1);
      expect(scroll, 0);
      expect(art, greaterThan(300));
    });

    testWidgets('shrinking to its minimum before the page scrolls', (
      tester,
    ) async {
      final (art, scroll) = await measure(tester, const Size(320, 568), 1);
      expect(art, lessThanOrEqualTo(120));
      expect(scroll, greaterThan(0));
    });

    testWidgets('even with the largest text', (tester) async {
      final (art, scroll) = await measure(tester, const Size(402, 874), 3.1);
      expect(art, lessThanOrEqualTo(120));
      expect(scroll, greaterThan(0));
    });
  });

  // Every onboarding screen and popup must fit or scroll, never overflow:
  // on every size of iPhone (the app is iPhone-only and portrait-only), from
  // default text up to iOS's largest accessibility size.
  group('Layout never overflows', () {
    const sizes = {
      'iPhone SE (1st gen)': Size(320, 568),
      'iPhone SE (3rd gen)': Size(375, 667),
      'iPhone 17 Pro': Size(402, 874),
      'iPhone 17 Pro Max': Size(440, 956),
    };
    const textScales = [1.0, 1.35, 2.0, 3.1];
    final screens = <String, Future<void> Function(WidgetTester)>{
      'welcome': (t) => launchAt(t, OnboardingStep.welcome, FakePhotoLibrary()),
      'find your meals': (t) =>
          launchAt(t, OnboardingStep.findMeals, FakePhotoLibrary()),
      'selected photos': (t) => launchAt(
        t,
        OnboardingStep.selectedPhotos,
        FakePhotoLibrary(access: PhotoAccess.limited),
      ),
      'no access': (t) => launchAt(
        t,
        OnboardingStep.noAccess,
        FakePhotoLibrary(access: PhotoAccess.none),
      ),
      // The longest copy the scanning screen shows, mid-scan and done.
      'scanning': (t) async {
        final scanner = FakeFoodScanner();
        await launchAt(
          t,
          OnboardingStep.scan,
          FakePhotoLibrary(access: PhotoAccess.full),
          scanner: scanner,
        );
        scanner.emit(
          const ScanProgress(
            total: 112345,
            checked: 61234,
            meals: 4567,
            running: true,
            preview: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'],
          ),
        );
        await t.pump(const Duration(seconds: 61));
      },
      'scan done': (t) async {
        final scanner = FakeFoodScanner();
        await launchAt(
          t,
          OnboardingStep.scan,
          FakePhotoLibrary(access: PhotoAccess.limited),
          scanner: scanner,
        );
        scanner.emit(
          const ScanProgress(
            total: 112345,
            checked: 112000,
            meals: 4567,
            maybes: 1234,
            waitingForWifi: 345,
            preview: [
              'a',
              'b',
              'c',
              'd',
              'e',
              'f',
              'g',
              'h',
              'i',
              'j',
              'k',
              'l',
            ],
          ),
        );
        await t.pumpAndSettle();
      },
      'scan failed': (t) async {
        final scanner = FakeFoodScanner()..startError = StateError('no store');
        await launchAt(
          t,
          OnboardingStep.scan,
          FakePhotoLibrary(access: PhotoAccess.full),
          scanner: scanner,
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isA<StateError>());
      },
      'Settings popup': (t) async {
        await launchAt(
          t,
          OnboardingStep.findMeals,
          FakePhotoLibrary(access: PhotoAccess.none),
        );
        await t.ensureVisible(find.text('Full access'));
        await t.tap(find.text('Full access'));
        await t.pumpAndSettle();
      },
    };
    for (final MapEntry(key: device, value: size) in sizes.entries) {
      for (final scale in textScales) {
        for (final MapEntry(key: screen, value: open) in screens.entries) {
          testWidgets(
            '$screen on $device at ${scale}x text',
            (tester) async {
              tester.view.physicalSize = size * 3;
              tester.view.devicePixelRatio = 3;
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              addTearDown(tester.view.reset);
              addTearDown(tester.platformDispatcher.clearAllTestValues);

              await open(tester);

              expect(tester.takeException(), isNull);
            },
            variant: screen == 'Settings popup'
                // The popup is a Material dialog on Android, a Cupertino one on iOS.
                ? TargetPlatformVariant(const {
                    TargetPlatform.iOS,
                    TargetPlatform.android,
                  })
                : TargetPlatformVariant.only(TargetPlatform.iOS),
          );
        }
      }
    }
  });
}
