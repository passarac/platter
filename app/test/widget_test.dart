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
  });
}
