import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:platter/screens/home_screen.dart';
import 'package:platter/services/food_scanner.dart';
import 'package:platter/services/photo_library.dart';

import 'calendar_test.dart' show meal, october, tinyPng, today, useIPhoneSize;
import 'fake_food_scanner.dart';
import 'fake_photo_library.dart';

/// Meals on every day from the 1st of August to today, one to three a day,
/// enough to scroll and to span three months.
List<FoundMeal> summer() => [
  for (
    var day = DateTime(2026, 8);
    !day.isAfter(today);
    day = day.add(const Duration(days: 1))
  )
    for (final hour in [8, 13, 20].take(day.day % 3 + 1))
      meal(
        '${day.month}-${day.day}-$hour',
        DateTime(day.year, day.month, day.day, hour),
      ),
];

Future<void> openTimeline(
  WidgetTester tester, {
  FakeFoodScanner? scanner,
  FakePhotoLibrary? photos,
}) async {
  useIPhoneSize(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        scanner: scanner,
        library: photos ?? FakePhotoLibrary(access: PhotoAccess.full),
        today: today,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Timeline'));
  await tester.pumpAndSettle();
}

/// The rail's slider, which says which month is at the top.
String monthAtTop(WidgetTester tester) =>
    tester.getSemantics(find.bySemanticsLabel('Scroll through months')).value;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Lists every meal by day under its month, newest first', (
    tester,
  ) async {
    await openTimeline(tester, scanner: FakeFoodScanner(found: october()));

    expect(find.text('4 meals · since Sep 2026'), findsOneWidget);
    expect(find.bySemanticsLabel('October 2026, 3 meals'), findsOneWidget);
    expect(find.bySemanticsLabel('September 2026, 1 meal'), findsOneWidget);
    expect(find.text('Today · Sat 17 Oct'), findsOneWidget);
    expect(find.text('Mon 5 Oct'), findsOneWidget);
    expect(find.text('Mon 14 Sep'), findsOneWidget);
    // Newest first, top to bottom.
    expect(
      tester.getTopLeft(find.text('Today · Sat 17 Oct')).dy,
      lessThan(tester.getTopLeft(find.text('Mon 5 Oct')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Mon 5 Oct')).dy,
      lessThan(tester.getTopLeft(find.text('Mon 14 Sep')).dy),
    );
    // Today's two meals, breakfast on the 5th and dinner in September.
    expect(find.bySemanticsLabel(RegExp(r', open details$')), findsNWidgets(4));
    expect(
      find.text('Your first photographed meal: Monday 14 September.'),
      findsOneWidget,
    );
    // The maybe stays off.
    expect(find.text('Sat 10 Oct'), findsNothing);
  });

  testWidgets('Switches between the grid and large photos', (tester) async {
    final photos = FakePhotoLibrary(access: PhotoAccess.full)
      ..thumbnailBytes = tinyPng;
    await openTimeline(
      tester,
      scanner: FakeFoodScanner(found: october()),
      photos: photos,
    );
    expect(photos.thumbnailSizes.toSet(), {240, 360});
    expect(find.text('1 photo'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Large photos, one per row'));
    await tester.pumpAndSettle();
    expect(photos.thumbnailSizes.toSet(), {240, 360, 900});
    // The large cards say when and how many shots (the list only builds
    // what's on screen, so not every card is there to find).
    expect(find.text('1 photo'), findsWidgets);
    expect(find.text('7:42 PM'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Compact grid, 3 photos per row'));
    await tester.pumpAndSettle();
    expect(find.text('1 photo'), findsNothing);
  });

  testWidgets('A day\'s pill opens that day in the calendar', (tester) async {
    await openTimeline(tester, scanner: FakeFoodScanner(found: october()));
    await tester.tap(
      find.bySemanticsLabel('Open Monday 5 October in the calendar'),
    );
    await tester.pumpAndSettle();
    expect(find.text('5 October'), findsOneWidget);
    expect(find.text('Monday · 1 meal'), findsOneWidget);
    expect(find.text('Breakfast'), findsOneWidget);

    // And back to the timeline where it was.
    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(find.text('Today · Sat 17 Oct'), findsOneWidget);
  });

  testWidgets('The rail jumps to a month and scrubs through them', (
    tester,
  ) async {
    await openTimeline(tester, scanner: FakeFoodScanner(found: summer()));
    expect(find.text('Oct'), findsOneWidget);
    expect(find.text('Sep'), findsOneWidget);
    expect(find.text('Aug'), findsOneWidget);
    expect(monthAtTop(tester), 'October 2026');
    expect(find.text('August 2026'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Jump to August 2026'));
    await tester.pumpAndSettle();
    expect(monthAtTop(tester), 'August 2026');
    final list = tester.getTopLeft(find.byType(ListView));
    expect(
      tester.getTopLeft(find.text('August 2026')).dy,
      closeTo(list.dy + 18, 1),
    );

    // Dragging the rail all the way up goes back to the top.
    final rail = find.bySemanticsLabel('Scroll through months');
    await tester.drag(rail, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(monthAtTop(tester), 'October 2026');
    expect(find.text('Today · Sat 17 Oct'), findsOneWidget);

    // And all the way down to where it all began.
    await tester.drag(rail, const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(monthAtTop(tester), 'August 2026');
    expect(find.text("That's where it all began"), findsOneWidget);
  });

  testWidgets('With nothing found yet, says so, then fills in', (tester) async {
    final scanner = FakeFoodScanner();
    await openTimeline(tester, scanner: scanner);
    expect(find.text('No meals yet'), findsOneWidget);
    expect(find.text('0 meals'), findsOneWidget);
    expect(find.bySemanticsLabel('Scroll through months'), findsNothing);

    scanner.found = october();
    scanner.emit(const ScanProgress(total: 100, checked: 40, meals: 4));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('No meals yet'), findsNothing);
    expect(find.text('4 meals · since Sep 2026'), findsOneWidget);
    expect(find.text('Today · Sat 17 Oct'), findsOneWidget);
  });

  testWidgets('Taps on what isn\'t built yet say so', (tester) async {
    await openTimeline(tester, scanner: FakeFoodScanner(found: october()));
    await tester.tap(
      find.bySemanticsLabel(RegExp(r'^Breakfast at .*, open details$')),
    );
    await tester.pump();
    expect(find.text('Meal details is coming soon.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pump();
    expect(find.text('Settings is coming soon.'), findsOneWidget);
  });
}
