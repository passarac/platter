import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'food_scanner.dart';
import 'meal_calendar.dart';
import 'photo_library.dart';

/// The meals the scan has found, kept fresh while it runs, and their
/// thumbnails, shared by every tab that shows them.
///
/// [start] loads what's been found so far and, when photo access allows,
/// starts the scan again (so one cut short carries on). New meals land in
/// [meals] as the scan finds them. Listeners hear about every change,
/// including thumbnails arriving.
class MealStore extends ChangeNotifier {
  MealStore({required this.scanner, required this.library});

  /// Where the meals come from. Without a scanner there are none.
  final FoodScanner? scanner;
  final PhotoLibrary library;

  /// Null until the first load is in.
  MealCalendar? get meals => _meals;
  MealCalendar? _meals;

  StreamSubscription<ScanProgress>? _updates;
  int? _knownMeals;
  bool _wasRunning = false;
  Timer? _reloadTimer;
  int _loads = 0;

  /// The scan reported a change while the first load was still fetching,
  /// which that load may have missed.
  bool _changedWhileLoading = false;

  /// Renders by size, then by photo id; null while one is on its way. Each
  /// size keeps its most recently read renders up to [_caps].
  final _thumbs = <int, LinkedHashMap<String, Uint8List?>>{};

  /// How many renders of each size to keep. Larger ones are kept fewer.
  static int _capFor(int size) => size >= 600 ? 60 : 600;

  bool _disposed = false;

  Future<void> start() async {
    final scanner = this.scanner;
    if (scanner == null) {
      await _load();
      return;
    }
    _updates = scanner.progress.listen((progress) {
      // New meals, or the scan finishing (when the last groupings settle),
      // mean the meals may have changed. The first report is the state the
      // first load fetches anyway.
      final known = _knownMeals;
      final changed =
          known != null &&
          (progress.meals != known || (_wasRunning && !progress.running));
      _knownMeals = progress.meals;
      _wasRunning = progress.running;
      if (!changed) return;
      if (_meals == null) {
        _changedWhileLoading = true;
      } else {
        _scheduleReload();
      }
    });
    unawaited(_load());
    final access = await library.currentAccess();
    if (_disposed) return;
    if (access != PhotoAccess.full && access != PhotoAccess.limited) return;
    try {
      await scanner.start();
    } catch (error, stack) {
      // What's been found so far still shows.
      _report(error, stack, 'while starting the food scan');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _updates?.cancel();
    _reloadTimer?.cancel();
    super.dispose();
  }

  /// Progress comes thick and fast mid-scan; one reload a little after the
  /// last change is plenty.
  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _load() async {
    final load = ++_loads;
    var found = const <FoundMeal>[];
    if (scanner case final scanner?) {
      try {
        found = await scanner.meals();
      } catch (error, stack) {
        _report(error, stack, 'while loading the meals');
      }
    }
    // A newer load has started since; let it set the state.
    if (_disposed || load != _loads) return;
    final first = _meals == null;
    _meals = MealCalendar(found);
    notifyListeners();
    if (first && _changedWhileLoading) _scheduleReload();
  }

  /// The render of photo [id] at [size] pixels across, or null while it's
  /// fetched: asking for one that isn't cached starts the fetch, and
  /// listeners hear when it lands. A fetch that fails leaves nothing behind,
  /// so the next ask tries again (the photo may be back online, say).
  Uint8List? thumbnail(String id, {required int size}) {
    final cache = _thumbs.putIfAbsent(size, LinkedHashMap.new);
    if (cache.containsKey(id)) {
      // Most recently read goes last, so it's the last to be dropped.
      final bytes = cache.remove(id);
      cache[id] = bytes;
      return bytes;
    }
    cache[id] = null;
    _trim(cache, size);
    unawaited(_fetch(id, size, cache));
    return null;
  }

  void _trim(LinkedHashMap<String, Uint8List?> cache, int size) {
    final cap = _capFor(size);
    while (cache.length > cap) {
      cache.remove(cache.keys.first);
    }
  }

  Future<void> _fetch(
    String id,
    int size,
    LinkedHashMap<String, Uint8List?> cache,
  ) async {
    Uint8List? bytes;
    try {
      bytes = await library.thumbnail(id, size: size);
    } catch (_) {
      // Handled below, like a photo that's gone.
    }
    // Dropped from the cache meanwhile, or the store's gone.
    if (_disposed || !cache.containsKey(id)) return;
    if (bytes == null) {
      cache.remove(id);
      return;
    }
    cache[id] = bytes;
    notifyListeners();
  }

  void _report(Object error, StackTrace stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'platter',
        context: ErrorDescription(context),
      ),
    );
  }
}
