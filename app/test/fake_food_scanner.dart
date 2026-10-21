import 'dart:async';

import 'package:platter/services/food_scanner.dart';

/// Stands in for the native scan: tests [emit] its progress by hand.
class FakeFoodScanner implements FoodScanner {
  FakeFoodScanner({this.current = const ScanProgress(), this.found = const []});

  /// What a new listener hears first, like the real scan's last report.
  ScanProgress current;
  List<FoundMeal> found;
  int starts = 0;

  /// While set, [start] doesn't return until it completes.
  Completer<void>? holdStart;

  /// While set, [start] throws it, like a scan that can't begin.
  Object? startError;

  final _updates = StreamController<ScanProgress>.broadcast();

  void emit(ScanProgress progress) {
    current = progress;
    _updates.add(progress);
  }

  @override
  Stream<ScanProgress> get progress => Stream.multi((listener) {
    listener.add(current);
    final sub = _updates.stream.listen(listener.add);
    listener.onCancel = sub.cancel;
  });

  @override
  Future<void> start() async {
    starts++;
    await holdStart?.future;
    if (startError != null) throw startError!;
    emit(
      ScanProgress(
        total: current.total,
        checked: current.checked,
        meals: current.meals,
        maybes: current.maybes,
        preview: current.preview,
        running: true,
      ),
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<List<FoundMeal>> meals() async => found;
}
