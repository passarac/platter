import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:platter/main.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Welcome screen shows headline and actions', (tester) async {
    await tester.pumpWidget(const PlatterApp());

    expect(find.text('Platter'), findsOneWidget);
    expect(find.text('Your meals, as a calendar of memories.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.textContaining('backup'), findsNothing);
  });

  testWidgets('Get started opens the find-your-meals screen', (tester) async {
    await tester.pumpWidget(const PlatterApp());

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text("Let's find your meals"), findsOneWidget);
    expect(find.text('Full access'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Selected photos'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    // The welcome art bobs forever, so pumpAndSettle would never return.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Get started'), findsOneWidget);
  });
}
