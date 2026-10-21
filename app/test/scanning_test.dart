import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:platter/main.dart';
import 'package:platter/screens/scanning_screen.dart';
import 'package:platter/services/food_scanner.dart';
import 'package:platter/services/onboarding_progress.dart';
import 'package:platter/services/photo_library.dart';

import 'fake_food_scanner.dart';
import 'fake_onboarding_progress.dart';
import 'fake_photo_library.dart';

/// An iPhone 17 Pro's screen, so the whole page is on screen to tap.
void useIPhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Opens the scanning screen; the burger runs while the scan does, so this
/// pumps a fixed time rather than settling.
Future<void> openScanning(
  WidgetTester tester,
  FakeFoodScanner scanner, {
  PhotoAccess access = PhotoAccess.full,
  FakePhotoLibrary? photos,
  VoidCallback? onSeeCalendar,
  VoidCallback? onEmptyCalendar,
}) async {
  useIPhoneSize(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: ScanningScreen(
        scanner: scanner,
        library: photos ?? FakePhotoLibrary(access: access),
        onSeeCalendar: onSeeCalendar,
        onEmptyCalendar: onEmptyCalendar,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

FoundMeal meal(String id, DateTime taken) =>
    FoundMeal(id: id, photos: [id], taken: taken, verdict: MealVerdict.food);

bool enabled(WidgetTester tester, String label) => tester
    .widget<Semantics>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Semantics))
          .first,
    )
    .properties
    .enabled!;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Counts meals as they are found, then opens the calendar', (
    tester,
  ) async {
    var opened = 0;
    final scanner = FakeFoodScanner(
      found: [
        meal('a', DateTime(2026, 10, 2)),
        meal('b', DateTime(2026, 9, 14)),
        meal('c', DateTime(2026, 9, 1)),
      ],
    );
    await openScanning(tester, scanner, onSeeCalendar: () => opened++);

    expect(find.text('FINDING YOUR MEALS'), findsOneWidget);
    expect(find.text('Looking through your photos…'), findsOneWidget);
    expect(enabled(tester, 'Scanning…'), isFalse);

    scanner.emit(
      const ScanProgress(
        total: 11191,
        checked: 1754,
        meals: 2,
        running: true,
        preview: ['a', 'b'],
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Found 2 meals…'), findsOneWidget);
    expect(find.text('1,754 of 11,191 photos checked'), findsOneWidget);

    scanner.emit(
      const ScanProgress(
        total: 11191,
        checked: 11191,
        meals: 3,
        maybes: 1,
        preview: ['a', 'b', 'c'],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ALL DONE'), findsOneWidget);
    expect(find.text('Found 3 meals across 2 months'), findsOneWidget);
    expect(
      find.text('Plus 1 that might be meals, to check later'),
      findsOneWidget,
    );

    await tester.tap(find.text('See my calendar'));
    expect(opened, 1);
  });

  testWidgets('After a minute the calendar opens while the scan carries on', (
    tester,
  ) async {
    var opened = 0;
    final scanner = FakeFoodScanner();
    await openScanning(tester, scanner, onSeeCalendar: () => opened++);
    scanner.emit(
      const ScanProgress(
        total: 20000,
        checked: 9000,
        meals: 400,
        running: true,
      ),
    );

    await tester.pump(const Duration(seconds: 59));
    expect(find.text('See my calendar'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('STILL LOOKING'), findsOneWidget);
    expect(find.text('Found 400 meals so far'), findsOneWidget);
    expect(find.textContaining('carry on in the background'), findsOneWidget);
    await tester.tap(find.text('See my calendar'));
    expect(opened, 1);
  });

  testWidgets('Finding nothing in selected photos offers to choose others', (
    tester,
  ) async {
    final photos = FakePhotoLibrary(access: PhotoAccess.limited);
    final scanner = FakeFoodScanner();
    await openScanning(tester, scanner, photos: photos);
    scanner.emit(const ScanProgress(total: 3, checked: 3));
    await tester.pumpAndSettle();

    expect(find.text('No meals in those photos'), findsOneWidget);
    expect(find.text('Continue with an empty calendar'), findsOneWidget);

    await tester.tap(find.text('Choose different photos'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(photos.pickerOpens, 1);
    expect(scanner.starts, 2);
    expect(find.text('Looking through your photos…'), findsOneWidget);
  });

  testWidgets(
    'Finding nothing with full access only offers an empty calendar',
    (tester) async {
      var empty = 0;
      final scanner = FakeFoodScanner();
      await openScanning(tester, scanner, onEmptyCalendar: () => empty++);
      scanner.emit(const ScanProgress(total: 40, checked: 40));
      await tester.pumpAndSettle();

      expect(find.text('No meals in those photos'), findsOneWidget);
      expect(find.text('Choose different photos'), findsNothing);
      await tester.tap(find.text('Continue with an empty calendar'));
      expect(empty, 1);
    },
  );

  testWidgets('Selected photos are counted in the title', (tester) async {
    final scanner = FakeFoodScanner();
    await openScanning(tester, scanner, access: PhotoAccess.limited);
    scanner.emit(const ScanProgress(total: 12, checked: 12, meals: 2));
    await tester.pumpAndSettle();

    expect(find.text('Found 2 meals in your 12 photos'), findsOneWidget);
  });

  testWidgets('Says when iCloud photos are waiting for Wi-Fi', (tester) async {
    final scanner = FakeFoodScanner();
    await openScanning(tester, scanner);
    scanner.emit(
      const ScanProgress(
        total: 500,
        checked: 469,
        meals: 30,
        waitingForWifi: 31,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('31 photos in iCloud will be checked on Wi-Fi'),
      findsOneWidget,
    );
  });

  testWidgets("Doesn't mistake the last scan's result for this one", (
    tester,
  ) async {
    final scanner = FakeFoodScanner(
      current: const ScanProgress(total: 40, checked: 40),
    )..holdStart = Completer();
    await openScanning(tester, scanner);

    expect(find.text('Looking through your photos…'), findsOneWidget);
    expect(find.text('No meals in those photos'), findsNothing);

    scanner.holdStart!.complete();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Looking through your photos…'), findsOneWidget);
  });

  testWidgets('Full access goes on to the scanning screen', (tester) async {
    final scanner = FakeFoodScanner();
    useIPhoneSize(tester);
    await tester.pumpWidget(
      PlatterApp(
        photos: FakePhotoLibrary(answer: PhotoAccess.full),
        progress: FakeOnboardingProgress(),
        scanner: scanner,
      ),
    );
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full access'));
    // One frame for the push, then let the screen fade in.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('FINDING YOUR MEALS'), findsOneWidget);
    expect(scanner.starts, 1);
  });

  testWidgets("A scan that can't start says so and offers to try again", (
    tester,
  ) async {
    var empty = 0;
    final scanner = FakeFoodScanner()
      ..startError = PlatformException(code: 'scan_failed');
    await openScanning(tester, scanner, onEmptyCalendar: () => empty++);
    expect(tester.takeException(), isA<PlatformException>());

    expect(find.text('SOMETHING WENT WRONG'), findsOneWidget);
    expect(find.text("Couldn't look through your photos"), findsOneWidget);
    await tester.tap(find.text('Continue with an empty calendar'));
    expect(empty, 1);

    scanner.startError = null;
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(scanner.starts, 2);
    expect(find.text('FINDING YOUR MEALS'), findsOneWidget);
    expect(find.text('Looking through your photos…'), findsOneWidget);
  });

  group('Relaunching mid-scan', () {
    testWidgets('with selected photos puts their screen back under the scan', (
      tester,
    ) async {
      useIPhoneSize(tester);
      final scanner = FakeFoodScanner();
      await tester.pumpWidget(
        PlatterApp(
          photos: FakePhotoLibrary(access: PhotoAccess.limited),
          progress: FakeOnboardingProgress(saved: OnboardingStep.scan),
          scanner: scanner,
          resumeAt: OnboardingStep.scan,
        ),
      );
      // One frame for the pushes, then let the screens fade in.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('FINDING YOUR MEALS'), findsOneWidget);
      expect(scanner.starts, 1);

      Navigator.of(tester.element(find.byType(ScanningScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Just your selected photos'), findsOneWidget);
    });

    test('with selected photos returns to the scan', () async {
      final step = await resumeStep(
        FakeOnboardingProgress(saved: OnboardingStep.scan),
        FakePhotoLibrary(access: PhotoAccess.limited),
      );
      expect(step, OnboardingStep.scan);
    });

    test('after a trip to Settings returns to the selected photos', () async {
      final step = await resumeStep(
        FakeOnboardingProgress(saved: OnboardingStep.scan, inSettings: true),
        FakePhotoLibrary(access: PhotoAccess.limited),
      );
      expect(step, OnboardingStep.selectedPhotos);
    });
  });
}
