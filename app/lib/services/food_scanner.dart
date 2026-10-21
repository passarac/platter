import 'package:flutter/services.dart';

/// How sure the scan is that a photo shows a meal.
enum MealVerdict {
  food,

  /// Might not be food; the user is asked to check it.
  maybe,
}

/// A photo the scan thinks is a meal.
class FoundMeal {
  const FoundMeal({
    required this.id,
    required this.taken,
    required this.verdict,
  });

  /// The photo's id in the photo library.
  final String id;
  final DateTime? taken;
  final MealVerdict verdict;
}

/// How far the scan has got. Counts cover every photo Platter can see,
/// including ones checked by earlier scans.
class ScanProgress {
  const ScanProgress({
    this.total = 0,
    this.checked = 0,
    this.meals = 0,
    this.maybes = 0,
    this.waitingForWifi = 0,
    this.unavailable = 0,
    this.running = false,
    this.preview = const [],
  });

  factory ScanProgress.fromMap(Map<Object?, Object?> map) => ScanProgress(
    total: map['total']! as int,
    checked: map['checked']! as int,
    meals: map['meals']! as int,
    maybes: map['maybes']! as int,
    waitingForWifi: map['waitingForWiFi']! as int,
    unavailable: map['unavailable']! as int,
    running: map['running']! as bool,
    preview: (map['preview']! as List<Object?>).cast<String>(),
  );

  /// Photos Platter can see, not counting screenshots.
  final int total;
  final int checked;
  final int meals;
  final int maybes;

  /// Only in iCloud, waiting for Wi-Fi to download.
  final int waitingForWifi;

  /// Couldn't be loaded; tried again by the next scan.
  final int unavailable;

  final bool running;

  /// Ids of the newest meals, at most 12, for the scanning screen.
  final List<String> preview;
}

/// Finds the meals among the user's photos. The scan itself runs natively,
/// so it carries on while Platter is in the background.
abstract interface class FoodScanner {
  /// The current progress, then every change.
  Stream<ScanProgress> get progress;

  /// Starts a scan unless one is already running. Only photos not checked
  /// before are looked at.
  Future<void> start();

  Future<void> stop();

  /// Meals and maybes found so far, newest first.
  Future<List<FoundMeal>> meals();
}

class DeviceFoodScanner implements FoodScanner {
  const DeviceFoodScanner();

  static const _methods = MethodChannel('platter/food_scan');
  static const _events = EventChannel('platter/food_scan/progress');

  @override
  Stream<ScanProgress> get progress => _events.receiveBroadcastStream().map(
    (event) => ScanProgress.fromMap(event as Map<Object?, Object?>),
  );

  @override
  Future<void> start() => _methods.invokeMethod<void>('start');

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');

  @override
  Future<List<FoundMeal>> meals() async {
    final meals = await _methods.invokeListMethod<Map<Object?, Object?>>(
      'meals',
    );
    return [
      for (final meal in meals ?? const <Map<Object?, Object?>>[])
        FoundMeal(
          id: meal['id']! as String,
          taken: switch (meal['taken']) {
            final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
            _ => null,
          },
          verdict: MealVerdict.values.byName(meal['verdict']! as String),
        ),
    ];
  }
}
