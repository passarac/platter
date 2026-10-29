import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:platter/main.dart';
import 'package:platter/screens/home_screen.dart';
import 'package:platter/services/food_scanner.dart';
import 'package:platter/services/meal_calendar.dart';
import 'package:platter/services/onboarding_progress.dart';
import 'package:platter/services/photo_library.dart';

import 'fake_food_scanner.dart';
import 'fake_onboarding_progress.dart';
import 'fake_photo_library.dart';

/// A Saturday, as in the mockup.
final today = DateTime(2026, 10, 17);

FoundMeal meal(
  String id,
  DateTime taken, {
  MealVerdict verdict = MealVerdict.food,
}) => FoundMeal(id: id, photos: [id], taken: taken, verdict: verdict);

/// October as the tests see it: two meals today, one earlier in the month,
/// one in September, and a maybe that stays off the calendar.
List<FoundMeal> october() => [
  meal('dinner', DateTime(2026, 10, 17, 19, 42)),
  meal('lunch', DateTime(2026, 10, 17, 12, 10)),
  meal('maybe', DateTime(2026, 10, 10, 13), verdict: MealVerdict.maybe),
  meal('breakfast', DateTime(2026, 10, 5, 8, 30)),
  meal('september', DateTime(2026, 9, 14, 20)),
];

/// A 1×1 transparent PNG.
final tinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

/// An iPhone 17 Pro's screen, so the whole page is on screen to tap.
void useIPhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> openCalendar(
  WidgetTester tester, {
  FakeFoodScanner? scanner,
  FakePhotoLibrary? photos,
  DateTime? on,
}) async {
  useIPhoneSize(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        scanner: scanner,
        library: photos ?? FakePhotoLibrary(access: PhotoAccess.full),
        today: on ?? today,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The label of a day's cell: "October 17, 2 meals".
Finder day(String label) => find.bySemanticsLabel(label);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('MealCalendar', () {
    test('keeps only dated meals the scan is sure of, by day', () {
      final calendar = MealCalendar([
        ...october(),
        FoundMeal(
          id: 'undated',
          photos: const ['undated'],
          taken: null,
          verdict: MealVerdict.food,
        ),
      ]);
      expect(calendar.count, 4);
      expect(calendar.on(DateTime(2026, 10, 17)).map((m) => m.id), [
        'lunch',
        'dinner',
      ]);
      expect(calendar.on(DateTime(2026, 10, 10)), isEmpty);
      expect(calendar.daysIn(DateTime(2026, 10)), [
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 17),
      ]);
      expect(calendar.earliest, DateTime(2026, 9, 14));
      expect(calendar.latest, DateTime(2026, 10, 17));
    });

    test(
      'opens on this month, or the newest meal\'s when this one is bare',
      () {
        expect(MealCalendar(october()).startMonth(today), DateTime(2026, 10));
        expect(
          MealCalendar([meal('old', DateTime(2026, 7, 4, 12))])
              .startMonth(today),
          DateTime(2026, 7),
        );
        expect(MealCalendar(const []).startMonth(today), DateTime(2026, 10));
      },
    );

    test('picks today, else the last day with meals, else the start', () {
      final calendar = MealCalendar(october());
      expect(calendar.defaultDay(DateTime(2026, 10), today), today);
      expect(
        calendar.defaultDay(DateTime(2026, 9), today),
        DateTime(2026, 9, 14),
      );
      expect(
        calendar.defaultDay(DateTime(2026, 8), today),
        DateTime(2026, 8, 1),
      );
      // A photo dated ahead of today can't be the day to open on.
      final ahead = MealCalendar([
        meal('ahead', DateTime(2026, 10, 20, 12)),
        meal('before', DateTime(2026, 10, 5, 12)),
      ]);
      expect(
        ahead.defaultDay(DateTime(2026, 10), today),
        DateTime(2026, 10, 5),
      );
      expect(
        MealCalendar(const []).defaultDay(DateTime(2026, 10), today),
        today,
      );
    });
  });

  testWidgets('Shows the month with meals on their days, and today\'s card', (
    tester,
  ) async {
    final photos = FakePhotoLibrary(access: PhotoAccess.full)
      ..thumbnailBytes = tinyPng;
    await openCalendar(
      tester,
      scanner: FakeFoodScanner(found: october()),
      photos: photos,
    );

    expect(find.text('October'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(day('October 17, 2 meals'), findsOneWidget);
    expect(day('October 5, 1 meal'), findsOneWidget);
    // The maybe isn't on the calendar.
    expect(day('October 10, 0 meals'), findsOneWidget);
    // Days still to come aren't buttons.
    expect(day('October 31'), findsOneWidget);

    expect(find.text('Sat 17 Oct'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('12:10 PM'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('7:42 PM'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(4));
  });

  testWidgets('Tapping a day shows its meals; future days don\'t respond', (
    tester,
  ) async {
    await openCalendar(tester, scanner: FakeFoodScanner(found: october()));

    await tester.tap(day('October 5, 1 meal'));
    await tester.pumpAndSettle();
    expect(find.text('Mon 5 Oct'), findsOneWidget);
    expect(find.text('Breakfast'), findsOneWidget);

    await tester.tap(day('October 13, 0 meals'));
    await tester.pumpAndSettle();
    expect(find.text('Tue 13 Oct'), findsOneWidget);
    expect(find.text('No meals on this day.'), findsOneWidget);

    await tester.tap(day('October 31'));
    await tester.pumpAndSettle();
    expect(find.text('Tue 13 Oct'), findsOneWidget);
  });

  testWidgets('Pages between the first month with meals and this one', (
    tester,
  ) async {
    await openCalendar(tester, scanner: FakeFoodScanner(found: october()));

    await tester.tap(find.bySemanticsLabel('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('September'), findsOneWidget);
    expect(find.text('Mon 14 Sep'), findsOneWidget);

    // Nothing before September.
    await tester.tap(find.bySemanticsLabel('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('September'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('October'), findsOneWidget);
    expect(find.text('Sat 17 Oct'), findsOneWidget);

    // Nothing after this month.
    await tester.tap(find.bySemanticsLabel('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('October'), findsOneWidget);

    // A swipe pages too.
    await tester.fling(find.text('Mon'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('September'), findsOneWidget);
  });

  testWidgets('Pages back into the calendar from before its first month', (
    tester,
  ) async {
    await openCalendar(tester, scanner: FakeFoodScanner(found: october()));

    // The year view can open the empty months before the first meal.
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('January, 0 days with meals'));
    await tester.pumpAndSettle();
    expect(find.text('January'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('January'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('September'), findsOneWidget);
    expect(find.text('Mon 14 Sep'), findsOneWidget);

    // So can the week that the first month starts in.
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Previous week'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Previous week'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Monday 31 August, open day'));
    await tester.pumpAndSettle();
    expect(find.text('31 August'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Previous day'));
    await tester.pumpAndSettle();
    expect(find.text('31 August'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Next day'));
    await tester.pumpAndSettle();
    expect(find.text('1 September'), findsOneWidget);
  });

  testWidgets('Paging a year keeps the day within its month', (tester) async {
    final leapDay = DateTime(2028, 2, 29);
    await openCalendar(
      tester,
      scanner: FakeFoodScanner(found: [meal('a', DateTime(2027, 1, 10, 12))]),
      on: leapDay,
    );
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Previous year'));
    await tester.pumpAndSettle();
    expect(find.text('2027'), findsOneWidget);
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(find.text('28 February'), findsOneWidget);
  });

  testWidgets('Today opens today in the day view from anywhere', (
    tester,
  ) async {
    await openCalendar(tester, scanner: FakeFoodScanner(found: october()));
    await tester.tap(find.bySemanticsLabel('Previous month'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('17 October'), findsOneWidget);
    expect(find.text('Saturday · 2 meals'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
  });

  group('Day view', () {
    testWidgets('asks for larger photos than the grids do', (tester) async {
      final photos = FakePhotoLibrary(access: PhotoAccess.full);
      await openCalendar(
        tester,
        scanner: FakeFoodScanner(found: october()),
        photos: photos,
      );
      expect(photos.thumbnailSizes.toSet(), {240});

      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(photos.thumbnailSizes.toSet(), {240, 900});
    });

    testWidgets('asks again for photos that didn\'t load', (tester) async {
      final photos = FakePhotoLibrary(access: PhotoAccess.full);
      await openCalendar(
        tester,
        scanner: FakeFoodScanner(found: october()),
        photos: photos,
      );
      // The month's three meals, none of which loaded.
      expect(photos.thumbnailSizes, [240, 240, 240]);

      photos.thumbnailBytes = tinyPng;
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      // Today's two meals, large; the small ones aren't asked for again
      // straight away.
      expect(photos.thumbnailSizes.length, 5);
      expect(find.byType(Image), findsNWidgets(2));

      // A while later, they are.
      await tester.pump(const Duration(seconds: 31));
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      expect(photos.thumbnailSizes.length, 8);
      // Two cells in the grid, two tiles in the day's card.
      expect(find.byType(Image), findsNWidgets(4));
    });

    testWidgets('shows the meals by slot and pages a day at a time', (
      tester,
    ) async {
      await openCalendar(tester, scanner: FakeFoodScanner(found: october()));
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();

      expect(find.text('17 October'), findsOneWidget);
      // One meal in a slot gets the wide card; both show time and shots.
      expect(find.text('12:10 PM'), findsNWidgets(2));
      expect(find.text('7:42 PM'), findsNWidgets(2));
      expect(find.text('1 photo'), findsNWidgets(2));
      expect(find.text("That's the day."), findsOneWidget);
      expect(find.text('Edit day'), findsOneWidget);

      // Nothing after today.
      await tester.tap(find.bySemanticsLabel('Next day'));
      await tester.pumpAndSettle();
      expect(find.text('17 October'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Previous day'));
      await tester.pumpAndSettle();
      expect(find.text('16 October'), findsOneWidget);
      expect(find.text('Friday · 0 meals'), findsOneWidget);
      expect(find.text('Nothing on this day'), findsOneWidget);
      expect(
        find.text('No meal photos from Friday 16 October.'),
        findsOneWidget,
      );
    });

    testWidgets('opens from a day in the month and from the week', (
      tester,
    ) async {
      await openCalendar(tester, scanner: FakeFoodScanner(found: october()));
      await tester.tap(find.bySemanticsLabel('See Sat 17 Oct, 2 meals'));
      await tester.pumpAndSettle();
      expect(find.text('17 October'), findsOneWidget);

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Monday 12 October, open day'));
      await tester.pumpAndSettle();
      expect(find.text('12 October'), findsOneWidget);
    });

    testWidgets('gives an odd number of meals a wide first card', (
      tester,
    ) async {
      await openCalendar(
        tester,
        scanner: FakeFoodScanner(
          found: [
            for (final minute in [0, 20, 40])
              FoundMeal(
                id: 'd$minute',
                photos: ['d$minute', 'd$minute-b'],
                taken: DateTime(2026, 10, 17, 19, minute),
                verdict: MealVerdict.food,
              ),
          ],
        ),
      );
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(find.text('Saturday · 3 meals'), findsOneWidget);
      expect(find.text('2 photos'), findsNWidgets(3));
      expect(find.text('7:00 PM'), findsNWidgets(2));
    });
  });

  group('Week view', () {
    testWidgets('lays the week out by meal of the day', (tester) async {
      await openCalendar(tester, scanner: FakeFoodScanner(found: october()));
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();

      expect(find.text('12–18'), findsOneWidget);
      expect(find.text('2 meals this week'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Saturday Lunch, 1 meal, open day'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Saturday Dinner, 1 meal, open day'),
        findsOneWidget,
      );
      for (final slot in ['Breakfast', 'Lunch', 'Dinner', 'Late night']) {
        expect(find.text(slot), findsOneWidget);
      }

      // Back to the week of the first meal, and no further.
      await tester.tap(find.bySemanticsLabel('Previous week'));
      await tester.pumpAndSettle();
      expect(find.text('5–11'), findsOneWidget);
      expect(find.text('1 meal this week'), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.bySemanticsLabel('Previous week'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Aug – Sep'), findsOneWidget);
      expect(find.text('31–6'), findsOneWidget);

      // Not into the future either.
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Next week'));
      await tester.pumpAndSettle();
      expect(find.text('12–18'), findsOneWidget);
    });
  });

  group('Year view', () {
    testWidgets('counts each month\'s days and opens a month', (tester) async {
      await openCalendar(tester, scanner: FakeFoodScanner(found: october()));
      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();

      expect(find.text('Your year'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('3 days with meals'), findsOneWidget);
      expect(
        find.bySemanticsLabel('October, 2 days with meals'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('September, 1 day with meals'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('November'), findsOneWidget);

      // Only this year has meals.
      await tester.tap(find.bySemanticsLabel('Previous year'));
      await tester.pumpAndSettle();
      expect(find.text('2026'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('September, 1 day with meals'));
      await tester.pumpAndSettle();
      expect(find.text('September'), findsOneWidget);
      expect(find.text('Mon 14 Sep'), findsOneWidget);
    });

    testWidgets('jumping to a date from the year lands on its month', (
      tester,
    ) async {
      await openCalendar(tester, scanner: FakeFoodScanner(found: october()));
      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Your year 2026. Jump to date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('October'), findsOneWidget);
      expect(find.text('Mon 5 Oct'), findsOneWidget);
    });
  });

  testWidgets('Opens on the newest meal\'s month when this one is bare', (
    tester,
  ) async {
    await openCalendar(
      tester,
      scanner: FakeFoodScanner(found: [meal('old', DateTime(2026, 7, 4, 12))]),
    );
    expect(find.text('July'), findsOneWidget);
    expect(find.text('Sat 4 Jul'), findsOneWidget);
  });

  testWidgets('With no meals at all, says the calendar is ready', (
    tester,
  ) async {
    await openCalendar(tester, scanner: null);
    expect(find.text('October'), findsOneWidget);
    expect(find.text('Your calendar is ready'), findsOneWidget);
    expect(
      find.text('Add meals as you go. Each one lands on its day.'),
      findsOneWidget,
    );
    expect(find.text('Sat 17 Oct'), findsNothing);
  });

  testWidgets('Fills in as the scan finds more, and starts it if need be', (
    tester,
  ) async {
    final scanner = FakeFoodScanner();
    await openCalendar(tester, scanner: scanner);
    expect(scanner.starts, 1);
    expect(find.text('Your calendar is ready'), findsOneWidget);

    scanner.found = october();
    scanner.emit(const ScanProgress(total: 100, checked: 40, meals: 4));
    // The reload waits a moment for more progress to come in.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Your calendar is ready'), findsNothing);
    expect(day('October 17, 2 meals'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
  });

  testWidgets('Moves to the first meals to land, wherever they are', (
    tester,
  ) async {
    final scanner = FakeFoodScanner();
    await openCalendar(tester, scanner: scanner);
    expect(find.text('October'), findsOneWidget);

    scanner.found = [meal('old', DateTime(2026, 7, 4, 12))];
    scanner.emit(const ScanProgress(total: 100, checked: 40, meals: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('July'), findsOneWidget);
    expect(find.text('Sat 4 Jul'), findsOneWidget);

    // Later finds leave the user where they are.
    await tester.tap(find.bySemanticsLabel('Next month'));
    await tester.pumpAndSettle();
    scanner.found = [...scanner.found, meal('new', DateTime(2026, 6, 1, 12))];
    scanner.emit(const ScanProgress(total: 100, checked: 60, meals: 2));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('August'), findsOneWidget);
  });

  testWidgets('Catches a find that came in during the first load', (
    tester,
  ) async {
    final scanner = FakeFoodScanner()..holdMeals = Completer();
    await openCalendar(tester, scanner: scanner);
    expect(find.text('Your calendar is ready'), findsNothing);

    // Found while the first load is still on its way back, empty.
    scanner.found = october();
    scanner.emit(const ScanProgress(total: 100, checked: 40, meals: 4));
    await tester.pump();
    scanner.holdMeals!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Your calendar is ready'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Your calendar is ready'), findsNothing);
    expect(day('October 17, 2 meals'), findsOneWidget);
  });

  testWidgets('Without photo access the scan is left alone', (tester) async {
    final scanner = FakeFoodScanner();
    await openCalendar(
      tester,
      scanner: scanner,
      photos: FakePhotoLibrary(access: PhotoAccess.none),
    );
    expect(scanner.starts, 0);
  });

  testWidgets('Taps on what isn\'t built yet say so', (tester) async {
    await openCalendar(tester, scanner: FakeFoodScanner(found: october()));
    await tester.tap(find.text('Map'));
    await tester.pump();
    expect(find.text('Map is coming soon.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Add a meal'));
    await tester.pump();
    expect(find.text('Adding a meal is coming soon.'), findsOneWidget);
  });

  testWidgets('See my calendar leaves onboarding behind for good', (
    tester,
  ) async {
    useIPhoneSize(tester);
    final now = DateTime.now();
    final scanner = FakeFoodScanner(
      found: [meal('a', DateTime(now.year, now.month, now.day, 13))],
    );
    final progress = FakeOnboardingProgress();
    await tester.pumpWidget(
      PlatterApp(
        photos: FakePhotoLibrary(answer: PhotoAccess.full),
        progress: progress,
        scanner: scanner,
      ),
    );
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full access'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    scanner.emit(const ScanProgress(total: 10, checked: 10, meals: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('See my calendar'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(progress.saved, OnboardingStep.calendar);
    expect(Navigator.of(tester.element(find.text('Today'))).canPop(), isFalse);
  });

  testWidgets('Relaunching on the calendar picks the scan back up', (
    tester,
  ) async {
    useIPhoneSize(tester);
    final scanner = FakeFoodScanner();
    await tester.pumpWidget(
      PlatterApp(
        photos: FakePhotoLibrary(access: PhotoAccess.limited),
        progress: FakeOnboardingProgress(saved: OnboardingStep.calendar),
        scanner: scanner,
        resumeAt: OnboardingStep.calendar,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(scanner.starts, 1);
  });
}
