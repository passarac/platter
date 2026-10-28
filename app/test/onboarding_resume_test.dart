import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:platter/main.dart';
import 'package:platter/services/onboarding_progress.dart';
import 'package:platter/services/photo_library.dart';

import 'fake_onboarding_progress.dart';
import 'fake_photo_library.dart';

/// What iOS reports while the user pops out to Settings and back.
Future<void> visitSettings(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

/// The welcome art bobs forever, so pumpAndSettle never returns on Welcome.
Future<void> settleOnWelcome(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 1));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('resumeStep', () {
    const welcome = OnboardingStep.welcome;
    const findMeals = OnboardingStep.findMeals;
    const selectedPhotos = OnboardingStep.selectedPhotos;
    const noAccess = OnboardingStep.noAccess;
    const scan = OnboardingStep.scan;
    const calendar = OnboardingStep.calendar;
    for (final (saved, fromSettings, access, expected) in [
      (welcome, false, PhotoAccess.full, welcome),
      // Access set before onboarding doesn't choose for them.
      (findMeals, false, PhotoAccess.none, findMeals),
      (findMeals, false, PhotoAccess.full, findMeals),
      // Back from Settings: what they chose there decides.
      (findMeals, true, PhotoAccess.full, scan),
      (findMeals, true, PhotoAccess.limited, selectedPhotos),
      (findMeals, true, PhotoAccess.none, noAccess),
      (findMeals, true, PhotoAccess.notAsked, findMeals),
      // Past the choice: current access decides.
      (selectedPhotos, false, PhotoAccess.limited, selectedPhotos),
      (selectedPhotos, false, PhotoAccess.full, scan),
      (selectedPhotos, false, PhotoAccess.notAsked, findMeals),
      (noAccess, false, PhotoAccess.none, noAccess),
      (noAccess, false, PhotoAccess.limited, selectedPhotos),
      // Onboarding's done: the calendar opens whatever access is now.
      (calendar, false, PhotoAccess.none, calendar),
      (calendar, true, PhotoAccess.full, calendar),
    ]) {
      test('${saved.name}${fromSettings ? ' after Settings' : ''} with '
          '${access.name} access → ${expected.name}', () async {
        final progress = FakeOnboardingProgress(
          saved: saved,
          inSettings: fromSettings,
        );
        final photos = FakePhotoLibrary(access: access);

        expect(await resumeStep(progress, photos), expected);
        expect(progress.inSettings, isFalse);
      });
    }
  });

  group('Relaunching', () {
    Future<void> launchAt(
      WidgetTester tester,
      OnboardingStep step, {
      PhotoAccess access = PhotoAccess.notAsked,
    }) async {
      await tester.pumpWidget(
        PlatterApp(
          photos: FakePhotoLibrary(access: access),
          progress: FakeOnboardingProgress(saved: step),
          resumeAt: step,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('at selected photos rebuilds the screens behind it', (
      tester,
    ) async {
      await launchAt(
        tester,
        OnboardingStep.selectedPhotos,
        access: PhotoAccess.limited,
      );
      expect(find.text('Just your selected photos'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text("Let's find your meals"), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await settleOnWelcome(tester);
      expect(find.text('Get started'), findsOneWidget);
    });

    testWidgets('at no access shows it', (tester) async {
      await launchAt(tester, OnboardingStep.noAccess, access: PhotoAccess.none);
      expect(find.text('No photos? No problem.'), findsOneWidget);
    });

    testWidgets('at find meals shows it', (tester) async {
      await launchAt(tester, OnboardingStep.findMeals);
      expect(find.text("Let's find your meals"), findsOneWidget);
    });

    testWidgets('at the scan carries on to it', (tester) async {
      await launchAt(tester, OnboardingStep.scan, access: PhotoAccess.full);
      expect(find.text("Let's find your meals"), findsOneWidget);
      expect(find.text('Scanning for meals is coming soon.'), findsOneWidget);
    });

    testWidgets('at the calendar opens it with nothing behind', (tester) async {
      await launchAt(tester, OnboardingStep.calendar, access: PhotoAccess.full);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Your calendar is ready'), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.text('Today'))).canPop(),
        isFalse,
      );
    });
  });

  testWidgets('The step is saved as the user moves through onboarding, '
      'including going back', (tester) async {
    final progress = FakeOnboardingProgress();
    await tester.pumpWidget(
      PlatterApp(
        photos: FakePhotoLibrary(answer: PhotoAccess.limited),
        progress: progress,
      ),
    );
    expect(progress.saved, OnboardingStep.welcome);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(progress.saved, OnboardingStep.findMeals);

    await tester.tap(find.text('Selected photos'));
    await tester.pumpAndSettle();
    expect(progress.saved, OnboardingStep.selectedPhotos);

    // A dialog on top doesn't count as a step.
    await tester.tap(find.text('Allow all photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(progress.saved, OnboardingStep.selectedPhotos);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(progress.saved, OnboardingStep.findMeals);

    await tester.tap(find.bySemanticsLabel('Back'));
    await settleOnWelcome(tester);
    expect(progress.saved, OnboardingStep.welcome);
  });

  group('Going to Settings from find your meals', () {
    Future<(FakePhotoLibrary, FakeOnboardingProgress)> goToSettings(
      WidgetTester tester,
    ) async {
      final photos = FakePhotoLibrary(access: PhotoAccess.none);
      final progress = FakeOnboardingProgress();
      await tester.pumpWidget(PlatterApp(photos: photos, progress: progress));
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Full access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go to Settings'));
      await tester.pumpAndSettle();
      expect(photos.settingsOpens, 1);
      return (photos, progress);
    }

    testWidgets('notes the trip before leaving', (tester) async {
      final (_, progress) = await goToSettings(tester);
      expect(progress.inSettings, isTrue);
      expect(progress.saved, OnboardingStep.findMeals);
    });

    testWidgets('and coming back unchanged stays put', (tester) async {
      final (_, progress) = await goToSettings(tester);
      await visitSettings(tester);

      expect(progress.inSettings, isFalse);
      expect(find.text("Let's find your meals"), findsOneWidget);
      expect(find.text('No photos? No problem.'), findsNothing);
    });

    testWidgets('and coming back with new access, still running, moves on', (
      tester,
    ) async {
      final (photos, progress) = await goToSettings(tester);
      photos.access = PhotoAccess.full;
      await visitSettings(tester);

      expect(progress.inSettings, isFalse);
      expect(find.text('Scanning for meals is coming soon.'), findsOneWidget);
    });

    testWidgets('and being relaunched by iOS picks up where they left off', (
      tester,
    ) async {
      final (photos, progress) = await goToSettings(tester);
      // iOS quits the app as access changes; the next launch starts fresh.
      photos.access = PhotoAccess.limited;
      final resumeAt = await resumeStep(progress, photos);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        PlatterApp(photos: photos, progress: progress, resumeAt: resumeAt),
      );
      await tester.pumpAndSettle();

      expect(find.text('Just your selected photos'), findsOneWidget);
      expect(progress.saved, OnboardingStep.selectedPhotos);
    });
  });
}
