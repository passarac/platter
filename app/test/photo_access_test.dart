import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:platter/main.dart';
import 'package:platter/services/photo_library.dart';

import 'fake_onboarding_progress.dart';
import 'fake_photo_library.dart';

Future<void> openFindMeals(WidgetTester tester, PhotoLibrary photos) async {
  await tester.pumpWidget(
    PlatterApp(photos: photos, progress: FakeOnboardingProgress()),
  );
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Full access goes on to the scan', (tester) async {
    final photos = FakePhotoLibrary(answer: PhotoAccess.full);
    await openFindMeals(tester, photos);

    await tester.tap(find.text('Full access'));
    await tester.pumpAndSettle();

    expect(photos.requests, 1);
    expect(find.text('Scanning for meals is coming soon.'), findsOneWidget);
  });

  testWidgets('Limiting access shows the selected-photos screen', (
    tester,
  ) async {
    final photos = FakePhotoLibrary(answer: PhotoAccess.limited);
    await openFindMeals(tester, photos);

    await tester.tap(find.text('Selected photos'));
    await tester.pumpAndSettle();

    expect(photos.requests, 1);
    expect(find.text('Just your selected photos'), findsOneWidget);
    expect(find.text('3 photos selected'), findsOneWidget);

    photos.count = 1;
    await tester.tap(find.text('Change selection'));
    await tester.pumpAndSettle();

    expect(photos.pickerOpens, 1);
    expect(find.text('1 photo selected'), findsOneWidget);
  });

  testWidgets(
    'Allow all photos explains, goes via Settings, then on to the '
    'scan',
    (tester) async {
      final photos = FakePhotoLibrary(answer: PhotoAccess.limited);
      await openFindMeals(tester, photos);

      await tester.tap(find.text('Selected photos'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Allow all photos'));
      await tester.pumpAndSettle();
      expect(find.text('Allow all photos in Settings'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(photos.settingsOpens, 0);
      expect(find.text('Allow all photos in Settings'), findsNothing);

      await tester.tap(find.text('Allow all photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go to Settings'));
      await tester.pumpAndSettle();
      expect(photos.settingsOpens, 1);

      photos.access = PhotoAccess.full;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Just your selected photos'), findsNothing);
      expect(find.text('Scanning for meals is coming soon.'), findsOneWidget);
    },
    variant: TargetPlatformVariant(const {
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('Selected photos reopens the picker when already limited', (
    tester,
  ) async {
    final photos = FakePhotoLibrary(access: PhotoAccess.limited);
    await openFindMeals(tester, photos);

    await tester.tap(find.text('Selected photos'));
    await tester.pumpAndSettle();

    expect(photos.requests, 0);
    expect(photos.pickerOpens, 1);
    expect(find.text('Just your selected photos'), findsOneWidget);
  });

  testWidgets('Denying access offers Settings, and returning with access '
      'moves on', (tester) async {
    final photos = FakePhotoLibrary(answer: PhotoAccess.none);
    await openFindMeals(tester, photos);

    await tester.tap(find.text('Full access'));
    await tester.pumpAndSettle();

    expect(find.text('No photos? No problem.'), findsOneWidget);

    await tester.tap(find.text('Allow access in Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Allow photo access in Settings'), findsOneWidget);
    expect(photos.settingsOpens, 0);

    await tester.tap(find.text('Go to Settings'));
    await tester.pumpAndSettle();
    expect(photos.settingsOpens, 1);

    photos.access = PhotoAccess.limited;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('No photos? No problem.'), findsNothing);
    expect(find.text('Just your selected photos'), findsOneWidget);
  });

  group('Tapping an option that clashes with access already set in Settings '
      'explains the way to Settings instead of moving on', () {
    for (final (set, button, title) in [
      (PhotoAccess.none, 'Full access', 'Photo access is turned off'),
      (PhotoAccess.none, 'Selected photos', 'Photo access is turned off'),
      (
        PhotoAccess.limited,
        'Full access',
        'Platter can only see selected photos',
      ),
      (PhotoAccess.full, 'Selected photos', 'Platter can see all your photos'),
    ]) {
      testWidgets('$button when access is ${set.name}', (tester) async {
        final photos = FakePhotoLibrary(access: set);
        await openFindMeals(tester, photos);

        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsNothing);
        expect(photos.settingsOpens, 0);

        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Go to Settings'));
        await tester.pumpAndSettle();
        expect(photos.settingsOpens, 1);

        // Stays put: no prompt, no picker, no next screen.
        expect(photos.requests, 0);
        expect(photos.pickerOpens, 0);
        expect(find.text("Let's find your meals"), findsOneWidget);
        expect(find.text('No photos? No problem.'), findsNothing);
        expect(find.text('Just your selected photos'), findsNothing);
        expect(find.textContaining('coming soon'), findsNothing);
      });
    }
  });

  testWidgets('Full access when already full goes straight to the scan', (
    tester,
  ) async {
    final photos = FakePhotoLibrary(access: PhotoAccess.full);
    await openFindMeals(tester, photos);

    await tester.tap(find.text('Full access'));
    await tester.pumpAndSettle();

    expect(photos.requests, 0);
    expect(find.text('Scanning for meals is coming soon.'), findsOneWidget);
  });
}
