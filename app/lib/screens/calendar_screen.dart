import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/food_scanner.dart';
import '../services/meal_calendar.dart';
import '../services/photo_library.dart';
import '../theme/platter_theme.dart';
import '../widgets/coming_soon.dart';
import '../widgets/crayon.dart';
import '../widgets/sketch.dart';
import 'calendar/calendar_bits.dart';
import 'calendar/day_view.dart';
import 'calendar/month_view.dart';
import 'calendar/week_view.dart';
import 'calendar/year_view.dart';

/// The zoom levels of the calendar, widest first.
enum CalendarView {
  year('Year'),
  month('Month'),
  week('Week'),
  day('Day');

  const CalendarView(this.label);

  final String label;
}

/// The calendar (`#v-cal` in the mockup): the user's meals by year, month,
/// week or day, with one header and zoom bar over all four. The month
/// comes first, and its days pop in one by one the first time.
///
/// The scan carries on while this screen is up (and is started again on
/// relaunch, in case it was cut short), so new meals land on their days as
/// they're found.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.scanner,
    required this.library,
    this.today,
  });

  /// Where the meals come from. Without a scanner the calendar is empty.
  final FoodScanner? scanner;
  final PhotoLibrary library;

  /// Today's date, for tests; by default the clock's.
  final DateTime? today;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

/// How the next page arrives (the mockup's `slideNext`, `slidePrev`,
/// `zoomIn`, `zoomOut` and `viewIn`).
enum _Entrance { fade, slideNext, slidePrev, zoomIn, zoomOut }

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  /// Null until the first load is in.
  MealCalendar? _meals;

  CalendarView _view = CalendarView.month;

  /// The day the views are centred on: the chosen day in the month, the
  /// week around it, the day itself, or its year.
  late DateTime _cursor = _today;

  _Entrance _entrance = _Entrance.fade;

  /// The chosen day was tapped, so its cell gives a little bounce.
  bool _selectedByTap = false;

  /// Small renders for the grids, and larger ones for the day view's
  /// cards, which would blur the small ones.
  final Thumbs _thumbs = {};
  final Thumbs _photos = {};

  static const _thumbSize = 240;
  static const _photoSize = 900;

  StreamSubscription<ScanProgress>? _updates;
  int? _knownMeals;
  bool _wasRunning = false;
  Timer? _reloadTimer;
  int _loads = 0;

  /// Drives the first reveal; the month it revealed keeps using it.
  late final _reveal = AnimationController(vsync: this);
  DateTime? _revealMonth;
  Duration _revealLength = Duration.zero;

  DateTime get _today => dayOf(widget.today ?? DateTime.now());

  DateTime get _month => monthOf(_cursor);

  DateTime get _lastMonth => monthOf(_today);

  /// The earliest month that can be shown: the first meal's, or this one.
  DateTime get _firstMonth {
    final earliest = _meals?.earliest;
    final thisMonth = _lastMonth;
    if (earliest == null || !earliest.isBefore(thisMonth)) return thisMonth;
    return monthOf(earliest);
  }

  bool get _canGoBack => _target(-1) != null;
  bool get _canGoForward => _target(1) != null;

  @override
  void initState() {
    super.initState();
    // After the first frame, so a load that completes at once (no scanner)
    // still finds the screen in the tree when it starts the reveal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
    unawaited(_watchScan());
  }

  @override
  void dispose() {
    _updates?.cancel();
    _reloadTimer?.cancel();
    _reveal.dispose();
    super.dispose();
  }

  Future<void> _watchScan() async {
    final scanner = widget.scanner;
    if (scanner == null) return;
    _updates = scanner.progress.listen((progress) {
      // New meals, or the scan finishing (when the last groupings settle),
      // mean the calendar may have changed.
      final changed =
          progress.meals != _knownMeals || (_wasRunning && !progress.running);
      _knownMeals = progress.meals;
      _wasRunning = progress.running;
      if (changed && _meals != null) _scheduleReload();
    });
    final access = await widget.library.currentAccess();
    if (!mounted) return;
    if (access != PhotoAccess.full && access != PhotoAccess.limited) return;
    try {
      await scanner.start();
    } catch (error, stack) {
      // The calendar shows what's been found so far.
      _report(error, stack, 'while starting the food scan');
    }
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
    if (widget.scanner case final scanner?) {
      try {
        found = await scanner.meals();
      } catch (error, stack) {
        _report(error, stack, 'while loading the meals');
      }
    }
    // A newer load has started since; let it set the state.
    if (!mounted || load != _loads) return;
    final meals = MealCalendar(found);
    final first = _meals == null;
    setState(() {
      _meals = meals;
      if (first) _cursor = meals.defaultDay(meals.startMonth(_today), _today);
    });
    _loadThumbs();
    if (first) _startReveal();
  }

  void _startReveal() {
    _revealMonth = _month;
    _revealLength =
        MonthView.revealDuration +
        MonthView.revealStagger * (MonthView.slots(_month) - 1);
    _reveal.duration = _revealLength;
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
    } else {
      _reveal.forward(from: 0);
    }
  }

  /// Fetches the thumbnails the current view needs.
  void _loadThumbs() {
    final meals = _meals;
    if (meals == null) return;
    final days = switch (_view) {
      CalendarView.year => const <DateTime>[],
      CalendarView.month => meals.daysIn(_month),
      CalendarView.week => [
        for (var i = 0; i < 7; i++) addDays(mondayOf(_cursor), i),
      ],
      CalendarView.day => [_cursor],
    };
    final large = _view == CalendarView.day;
    for (final day in days) {
      for (final meal in meals.on(day)) {
        if (!_thumbs.containsKey(meal.id)) {
          unawaited(_loadThumb(meal.id, _thumbs, _thumbSize));
        }
        if (large && !_photos.containsKey(meal.id)) {
          unawaited(_loadThumb(meal.id, _photos, _photoSize));
        }
      }
    }
  }

  Future<void> _loadThumb(String id, Thumbs into, int size) async {
    into[id] = null;
    Uint8List? bytes;
    try {
      bytes = await widget.library.thumbnail(id, size: size);
    } catch (_) {
      // A photo that's gone keeps its empty cell.
    }
    if (bytes != null && mounted) setState(() => into[id] = bytes);
  }

  /// The day view's photos: the large render, or the small one until it
  /// arrives.
  Thumbs _dayPhotos(MealCalendar meals) => {
    for (final meal in meals.on(_cursor))
      meal.id: _photos[meal.id] ?? _thumbs[meal.id],
  };

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

  /// Keeps [day] between the first month and today.
  DateTime _clamp(DateTime day) => day.isAfter(_today)
      ? _today
      : day.isBefore(_firstMonth)
      ? _firstMonth
      : day;

  /// Where the cursor lands one page back or forward in the current view,
  /// or null at the edge of the calendar.
  DateTime? _target(int direction) {
    switch (_view) {
      case CalendarView.year:
        final year = _cursor.year + direction;
        if (year < _firstMonth.year || year > _today.year) return null;
        return _clamp(DateTime(year, _cursor.month, _cursor.day));
      case CalendarView.month:
        final month = DateTime(_cursor.year, _cursor.month + direction);
        if (month.isBefore(_firstMonth) || month.isAfter(_lastMonth)) {
          return null;
        }
        return _meals?.defaultDay(month, _today) ?? month;
      case CalendarView.week:
        final monday = addDays(mondayOf(_cursor), 7 * direction);
        if (monday.isAfter(mondayOf(_today))) return null;
        if (addDays(monday, 6).isBefore(_firstMonth)) return null;
        return _clamp(addDays(_cursor, 7 * direction));
      case CalendarView.day:
        final day = addDays(_cursor, direction);
        if (day.isBefore(_firstMonth) || day.isAfter(_today)) return null;
        return day;
    }
  }

  void _step(int direction) {
    final target = _target(direction);
    if (target == null) return;
    _show(
      _view,
      target,
      direction > 0 ? _Entrance.slideNext : _Entrance.slidePrev,
    );
  }

  void _show(CalendarView view, DateTime cursor, _Entrance entrance) {
    setState(() {
      _view = view;
      _cursor = cursor;
      _entrance = entrance;
      _selectedByTap = false;
    });
    _loadThumbs();
  }

  /// Switches zoom level, growing into a closer view or shrinking back out.
  void _zoomTo(CalendarView view, {DateTime? at}) {
    if (view == _view && at == null) return;
    _show(
      view,
      at ?? _cursor,
      view.index > _view.index ? _Entrance.zoomIn : _Entrance.zoomOut,
    );
  }

  /// Today always opens today's day view, whichever view is up.
  void _goToday() {
    if (_view == CalendarView.day) {
      if (_cursor != _today) _show(_view, _today, _Entrance.slideNext);
      return;
    }
    _zoomTo(CalendarView.day, at: _today);
  }

  void _select(DateTime day) {
    setState(() {
      _cursor = day;
      _selectedByTap = true;
    });
  }

  Future<void> _jump() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _clamp(_cursor),
      firstDate: _firstMonth,
      lastDate: _today,
      helpText: 'Jump to a day',
    );
    if (picked == null || !mounted) return;
    // The year view has no single day to show, so jumping lands on its month.
    final view = _view == CalendarView.year ? CalendarView.month : _view;
    _show(view, dayOf(picked), _Entrance.fade);
  }

  void _swipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -200) {
      _step(1);
    } else if (velocity > 200) {
      _step(-1);
    }
  }

  /// What the title and its eyebrow say for the current page.
  (String eyebrow, String title) get _heading {
    final cursor = _cursor;
    switch (_view) {
      case CalendarView.year:
        return ('Your year', '${cursor.year}');
      case CalendarView.month:
        return ('${cursor.year}', monthNames[cursor.month - 1]);
      case CalendarView.week:
        final monday = mondayOf(cursor), sunday = addDays(monday, 6);
        final eyebrow = monday.month == sunday.month
            ? monthNames[monday.month - 1]
            : '${shortMonth(monday.month)} – ${shortMonth(sunday.month)}';
        return (eyebrow, '${monday.day}–${sunday.day}');
      case CalendarView.day:
        final meals = _meals?.on(cursor).length ?? 0;
        return (
          '${weekdayLong[cursor.weekday - 1]} · ${plural(meals, 'meal')}',
          '${cursor.day} ${monthNames[cursor.month - 1]}',
        );
    }
  }

  /// Which page the body shows, so a new one animates in.
  Object get _pageKey => switch (_view) {
    CalendarView.year => (_view, _cursor.year),
    CalendarView.month => (_view, _month),
    CalendarView.week => (_view, mondayOf(_cursor)),
    CalendarView.day => (_view, _cursor),
  };

  /// The camera button floats over the month and week, which have no Add
  /// of their own in every state.
  bool get _showsAddButton =>
      _view == CalendarView.month || _view == CalendarView.week;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PlatterColors.paper,
      body: Column(
        children: [
          compactText(_header(context)),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragEnd: _swipe,
                    child: SingleChildScrollView(
                      key: ValueKey(_pageKey),
                      // Room for the add button over the end of the page.
                      padding: EdgeInsets.only(
                        bottom: _showsAddButton ? 76 : 0,
                      ),
                      child: _body(context),
                    ),
                  ),
                ),
                if (_showsAddButton)
                  Positioned(
                    right: 16,
                    bottom: 14,
                    child: compactText(
                      _AddMealButton(
                        onPressed: () => comingSoon(context, 'Adding a meal'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: compactText(
        _TabBar(
          current: 'Calendar',
          onOther: (tab) => comingSoon(context, tab),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final (eyebrow, title) = _heading;
    final unit = _view.name;
    return _Paper(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        SquareButton(
                          icon: calIcon(CalIcons.prev, 18),
                          label: 'Previous $unit',
                          onPressed: _canGoBack ? () => _step(-1) : null,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _TitleButton(
                            key: ValueKey((eyebrow, title)),
                            eyebrow: eyebrow,
                            title: title,
                            entrance: _entrance,
                            onTap: _jump,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SquareButton(
                          icon: calIcon(CalIcons.next, 18),
                          label: 'Next $unit',
                          onPressed: _canGoForward ? () => _step(1) : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  PillButton(label: 'Today', onPressed: _goToday),
                  const SizedBox(width: 6),
                  SquareButton(
                    icon: calIcon(CalIcons.gear, 21),
                    label: 'Settings',
                    onPressed: () => comingSoon(context, 'Settings'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ZoomBar(current: _view, onChange: _zoomTo),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final meals = _meals;
    if (meals == null) return const SizedBox.shrink();
    final today = _today;
    final page = switch (_view) {
      CalendarView.year => YearView(
        year: _cursor.year,
        today: today,
        meals: meals,
        onOpenMonth: (month) =>
            _zoomTo(CalendarView.month, at: meals.defaultDay(month, today)),
      ),
      CalendarView.month => MonthView(
        month: _month,
        selected: _cursor,
        today: today,
        meals: meals,
        thumbs: _thumbs,
        reveal: _month == _revealMonth ? _reveal : null,
        revealLength: _revealLength,
        pop: _selectedByTap,
        onSelect: _select,
        onOpenDay: (day) => _zoomTo(CalendarView.day, at: day),
      ),
      CalendarView.week => WeekView(
        monday: mondayOf(_cursor),
        today: today,
        meals: meals,
        thumbs: _thumbs,
        onOpenDay: (day) => _zoomTo(CalendarView.day, at: day),
      ),
      CalendarView.day => DayView(
        day: _cursor,
        meals: meals,
        thumbs: _dayPhotos(meals),
      ),
    };
    return _Arrival(key: ValueKey(_pageKey), entrance: _entrance, child: page);
  }
}

/// Brings a new page in: sliding from the side it came from, growing from
/// or shrinking to the view it replaced, or simply fading.
class _Arrival extends StatelessWidget {
  const _Arrival({super.key, required this.entrance, required this.child});

  final _Entrance entrance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final zoom = entrance == _Entrance.zoomIn || entrance == _Entrance.zoomOut;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: zoom ? 340 : 280),
      curve: platterEase,
      builder: (context, t, child) {
        final (dx, dy, scale) = switch (entrance) {
          _Entrance.slideNext => (28.0, 0.0, 1.0),
          _Entrance.slidePrev => (-28.0, 0.0, 1.0),
          _Entrance.zoomIn => (0.0, 0.0, 0.88),
          _Entrance.zoomOut => (0.0, 0.0, 1.08),
          _Entrance.fade => (0.0, 6.0, 1.0),
        };
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(dx * (1 - t), dy * (1 - t)),
            child: Transform.scale(
              scale: scale + (1 - scale) * t,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

/// Yellow paper with an ink line along the bottom (`.app-head::before`).
class _Paper extends StatelessWidget {
  const _Paper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        const Positioned(
          left: -6,
          top: -6,
          right: -6,
          bottom: 0,
          child: Crayon(child: CustomPaint(painter: _PaperPainter.header)),
        ),
        child,
      ],
    );
  }
}

/// A filled strip with a single ink edge, top or bottom.
class _PaperPainter extends CustomPainter {
  const _PaperPainter({required this.color, required this.edgeAtTop});

  static const header = _PaperPainter(
    color: PlatterColors.yellow,
    edgeAtTop: false,
  );
  static const tabBar = _PaperPainter(
    color: PlatterColors.nav,
    edgeAtTop: true,
  );

  final Color color;
  final bool edgeAtTop;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final y = edgeAtTop ? 1.25 : size.height - 1.25;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = PlatterColors.ink
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_PaperPainter old) =>
      color != old.color || edgeAtTop != old.edgeAtTop;
}

/// The page's name, tappable to jump to a date (`.title-btn`). The words
/// come in with the page they belong to (`tNext`, `tPrev`, `tSwap`).
class _TitleButton extends StatelessWidget {
  const _TitleButton({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.entrance,
    required this.onTap,
  });

  final String eyebrow;
  final String title;
  final _Entrance entrance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (dx, dy) = switch (entrance) {
      _Entrance.slideNext => (18.0, 0.0),
      _Entrance.slidePrev => (-18.0, 0.0),
      _Entrance.zoomIn || _Entrance.zoomOut => (0.0, 8.0),
      _Entrance.fade => (0.0, 0.0),
    };
    return Semantics(
      button: true,
      label: '$eyebrow $title. Jump to date',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 300),
          curve: platterEase,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(dx * (1 - t), dy * (1 - t)),
              child: child,
            ),
          ),
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // A long eyebrow ("Wednesday · 3 meals") shrinks a little
                  // rather than being cut short.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      eyebrow,
                      maxLines: 1,
                      style: PlatterText.body(
                        size: 14,
                        weight: FontWeight.w800,
                        color: PlatterColors.ink3,
                      ).copyWith(height: 1),
                    ),
                  ),
                  // Long titles (September) shrink to fit between the arrows.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: PlatterText.head(size: 28).copyWith(height: 1),
                        ),
                        const SizedBox(width: 3),
                        Opacity(
                          opacity: 0.55,
                          child: calIcon(CalIcons.caret, 16),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Year · Month · Week · Day (`.zoom`), with one highlight that slides
/// between them.
class _ZoomBar extends StatelessWidget {
  const _ZoomBar({required this.current, required this.onChange});

  final CalendarView current;
  final ValueChanged<CalendarView> onChange;

  @override
  Widget build(BuildContext context) {
    return SketchBox(
      radius: 999,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 9) / 4;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 320),
                  curve: platterEase,
                  left: current.index * (width + 3),
                  top: 0,
                  bottom: 0,
                  width: width,
                  child: const Crayon(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: PlatterColors.ink,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final view in CalendarView.values)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: view == current,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onChange(view),
                            child: SizedBox(
                              height: 40,
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 250),
                                    style: PlatterText.body(
                                      size: 14,
                                      weight: FontWeight.w800,
                                      color: view == current
                                          ? Colors.white
                                          : PlatterColors.ink,
                                    ),
                                    child: Text(view.label),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The orange camera button over the calendar (`.fab`).
class _AddMealButton extends StatelessWidget {
  const _AddMealButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add a meal',
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onPressed,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SketchBox(
                fill: const Color(0xFFFF8A5B),
                radius: 18,
                shadow: 4,
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: Center(child: calIcon(CalIcons.camera, 26)),
                ),
              ),
              Positioned(
                top: -7,
                right: -7,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: PlatterColors.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: PlatterColors.ink, width: 2),
                  ),
                  child: Text(
                    '+',
                    style: PlatterText.body(
                      size: 16,
                      weight: FontWeight.w800,
                      color: PlatterColors.ink,
                    ).copyWith(height: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The five tabs along the bottom (`.tabbar`). Only Calendar exists so far.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onOther});

  final String current;
  final ValueChanged<String> onOther;

  static const _tabs = [
    ('Calendar', CalIcons.tabCalendar),
    ('Timeline', CalIcons.tabTimeline),
    ('Map', CalIcons.tabMap),
    ('Rediscover', CalIcons.tabRediscover),
    ('Plated', CalIcons.tabPlated),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        const Positioned(
          left: -6,
          top: 0,
          right: -6,
          bottom: -6,
          child: Crayon(child: CustomPaint(painter: _PaperPainter.tabBar)),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
            child: Row(
              children: [
                for (final (name, icon) in _tabs)
                  Expanded(
                    child: _Tab(
                      name: name,
                      icon: icon,
                      selected: name == current,
                      onTap: name == current ? null : () => onOther(name),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.name,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PlatterColors.blue : PlatterColors.ink3;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Crayon(child: calIcon(icon, 24, color: color)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    name,
                    style: PlatterText.body(
                      size: 12,
                      weight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
