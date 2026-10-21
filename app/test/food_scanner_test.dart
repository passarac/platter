import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:platter/services/food_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel('platter/food_scan');
  const events = EventChannel('platter/food_scan/progress');
  const scanner = DeviceFoodScanner();

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
  });

  test('Reads meals sent from iOS', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      expect(call.method, 'meals');
      return [
        {
          'id': 'A/L0/001',
          'photos': ['C/L0/001', 'A/L0/001'],
          'taken': DateTime.utc(2026, 10, 1, 12).millisecondsSinceEpoch,
          'verdict': 'food',
        },
        {
          'id': 'B/L0/001',
          'photos': ['B/L0/001'],
          'taken': null,
          'verdict': 'maybe',
        },
      ];
    });

    final meals = await scanner.meals();

    expect(meals.map((m) => m.id), ['A/L0/001', 'B/L0/001']);
    expect(meals[0].photos, ['C/L0/001', 'A/L0/001']);
    expect(meals[0].taken, DateTime.utc(2026, 10, 1, 12).toLocal());
    expect(meals[1].taken, isNull);
    expect(meals.map((m) => m.verdict), [MealVerdict.food, MealVerdict.maybe]);
  });

  test('Reads progress sent from iOS', () async {
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, sink) => sink.success({
          'total': 3412,
          'checked': 1200,
          'meals': 140,
          'maybes': 9,
          'waitingForWiFi': 31,
          'unavailable': 2,
          'running': true,
          'preview': ['A/L0/001'],
        }),
      ),
    );

    final progress = await scanner.progress.first;

    expect(progress.total, 3412);
    expect(progress.checked, 1200);
    expect(progress.meals, 140);
    expect(progress.maybes, 9);
    expect(progress.waitingForWifi, 31);
    expect(progress.unavailable, 2);
    expect(progress.running, isTrue);
    expect(progress.preview, ['A/L0/001']);
  });
}
