import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:platter/main.dart';
import 'package:platter/services/photo_library.dart';

import 'fake_photo_library.dart';

Future<void> openFindMeals(WidgetTester tester, PhotoLibrary photos) async {
  await tester.pumpWidget(PlatterApp(photos: photos));
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
    expect(photos.settingsOpens, 1);

    photos.access = PhotoAccess.limited;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('No photos? No problem.'), findsNothing);
    expect(find.text('Just your selected photos'), findsOneWidget);
  });
}
