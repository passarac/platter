import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/food_scanner.dart';
import '../services/meal_calendar.dart';
import '../services/photo_library.dart';
import '../theme/platter_theme.dart';
import '../widgets/coming_soon.dart';
import '../widgets/crayon.dart';
import '../widgets/sketch.dart';

/// The month calendar (`#v-cal` in the mockup): a cell for every day of the
/// month showing that day's first meal, and a card with the chosen day's
/// meals. The first time it opens, the days pop in one after another.
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

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  /// Null until the first load is in.
  MealCalendar? _meals;

  /// The month on screen (its first day) and the day whose card shows.
  late DateTime _month = monthOf(_today);
  late DateTime _selected = _today;

  /// Which way the last month change went, for the slide: 1 forward, -1
  /// back, 0 for none.
  int _direction = 0;

  /// The chosen day was tapped, so its cell gives a little bounce.
  bool _selectedByTap = false;

  final _thumbs = <String, Uint8List?>{};

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

  DateTime get _lastMonth => monthOf(_today);

  /// The earliest month that can be shown: the first meal's, or this one.
  DateTime get _firstMonth {
    final earliest = _meals?.earliest;
    final thisMonth = _lastMonth;
    if (earliest == null || !earliest.isBefore(thisMonth)) return thisMonth;
    return monthOf(earliest);
  }

  bool get _canGoBack => _month.isAfter(_firstMonth);
  bool get _canGoForward => _month.isBefore(_lastMonth);

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
      if (first) {
        _month = meals.startMonth(_today);
        _selected = meals.defaultDay(_month, _today);
      }
    });
    _loadThumbs(meals, _month);
    if (first) _startReveal();
  }

  void _startReveal() {
    _revealMonth = _month;
    final slots =
        _leadingBlanks(_month) +
        DateUtils.getDaysInMonth(_month.year, _month.month);
    _revealLength =
        _DayCell.revealDuration + _DayCell.revealStagger * (slots - 1);
    _reveal.duration = _revealLength;
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
    } else {
      _reveal.forward(from: 0);
    }
  }

  void _loadThumbs(MealCalendar meals, DateTime month) {
    for (final day in meals.daysIn(month)) {
      for (final meal in meals.on(day)) {
        if (!_thumbs.containsKey(meal.id)) unawaited(_loadThumb(meal.id));
      }
    }
  }

  Future<void> _loadThumb(String id) async {
    _thumbs[id] = null;
    Uint8List? bytes;
    try {
      bytes = await widget.library.thumbnail(id);
    } catch (_) {
      // A photo that's gone keeps its empty cell.
    }
    if (bytes != null && mounted) setState(() => _thumbs[id] = bytes);
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

  /// Shows [month] with [day] chosen, sliding in from the side the change
  /// is heading.
  void _show(DateTime month, DateTime day) {
    final direction = month.isAfter(_month)
        ? 1
        : month.isBefore(_month)
        ? -1
        : 0;
    setState(() {
      _month = month;
      _selected = day;
      _direction = direction;
      _selectedByTap = false;
    });
    if (_meals case final meals?) _loadThumbs(meals, month);
  }

  void _step(int direction) {
    if (direction > 0 ? !_canGoForward : !_canGoBack) return;
    final month = DateTime(_month.year, _month.month + direction);
    final meals = _meals;
    _show(month, meals?.defaultDay(month, _today) ?? monthOf(month));
  }

  void _goToday() => _show(_lastMonth, _today);

  void _select(DateTime day) {
    setState(() {
      _selected = day;
      _selectedByTap = true;
    });
  }

  Future<void> _jump() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected.isAfter(_today) ? _today : _selected,
      firstDate: _firstMonth,
      lastDate: _today,
      helpText: 'Jump to a day',
    );
    if (picked == null || !mounted) return;
    _show(monthOf(picked), dayOf(picked));
  }

  void _swipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -200) {
      _step(1);
    } else if (velocity > 200) {
      _step(-1);
    }
  }

  static int _leadingBlanks(DateTime month) => month.weekday - DateTime.monday;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PlatterColors.paper,
      body: Column(
        children: [
          _compact(_header(context)),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragEnd: _swipe,
                    child: SingleChildScrollView(
                      // Room for the add button over the end of the page.
                      padding: const EdgeInsets.only(bottom: 76),
                      child: _body(context),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 14,
                  child: _compact(
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
      bottomNavigationBar: _compact(
        _TabBar(
          current: 'Calendar',
          onOther: (tab) => comingSoon(context, tab),
        ),
      ),
    );
  }

  /// Fixed-size controls can only take so much text growth; the day card
  /// below still grows with the user's text size.
  Widget _compact(Widget child) =>
      MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child);

  Widget _header(BuildContext context) {
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
                          icon: _icon(_Icons.prev, 18),
                          label: 'Previous month',
                          onPressed: _canGoBack ? () => _step(-1) : null,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _TitleButton(
                            key: ValueKey(_month),
                            eyebrow: '${_month.year}',
                            title: _monthNames[_month.month - 1],
                            slideFrom: _direction,
                            onTap: _jump,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SquareButton(
                          icon: _icon(_Icons.next, 18),
                          label: 'Next month',
                          onPressed: _canGoForward ? () => _step(1) : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  PillButton(label: 'Today', onPressed: _goToday),
                  const SizedBox(width: 6),
                  SquareButton(
                    icon: _icon(_Icons.gear, 21),
                    label: 'Settings',
                    onPressed: () => comingSoon(context, 'Settings'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ZoomBar(
                onOther: (view) => comingSoon(context, 'The $view view'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final meals = _meals;
    if (meals == null) return const SizedBox.shrink();
    final slideFrom = _direction;
    // A new month slides in from the side it came from (`slideNext`,
    // `slidePrev`); the first one just fades in (`view-in`).
    return TweenAnimationBuilder<double>(
      key: ValueKey(_month),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: platterEase,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(28 * slideFrom * (1 - t), 0),
          child: child,
        ),
      ),
      child: Column(
        children: [
          _compact(const _WeekdayRow()),
          _compact(_grid(context, meals)),
          _DayCard(
            day: _selected,
            meals: meals.on(_selected),
            calendarEmpty: meals.isEmpty,
            thumbs: _thumbs,
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, MealCalendar meals) {
    final month = _month;
    final lead = _leadingBlanks(month);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final rows = ((lead + days) / 7).ceil();
    final today = _today;
    final reveal = month == _revealMonth ? _reveal : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          for (var row = 0; row < rows; row++)
            Padding(
              padding: EdgeInsets.only(top: row == 0 ? 0 : 5),
              child: SizedBox(
                height: _DayCell.height,
                child: Row(
                  children: [
                    for (var column = 0; column < 7; column++) ...[
                      if (column > 0) const SizedBox(width: 5),
                      Expanded(
                        child: switch (row * 7 + column - lead + 1) {
                          final d when d < 1 || d > days =>
                            const SizedBox.shrink(),
                          final d => _cell(
                            DateTime(month.year, month.month, d),
                            slot: row * 7 + column,
                            meals: meals,
                            today: today,
                            reveal: reveal,
                          ),
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(
    DateTime day, {
    required int slot,
    required MealCalendar meals,
    required DateTime today,
    required Animation<double>? reveal,
  }) {
    final onDay = meals.on(day);
    final selected = day == _selected;
    final cover = onDay.isEmpty ? null : onDay.first.id;
    Widget cell = _DayCell(
      key: ValueKey(day),
      day: day,
      meals: onDay.length,
      thumb: cover == null ? null : _thumbs[cover],
      selected: selected,
      today: day == today,
      future: day.isAfter(today),
      pop: selected && _selectedByTap,
      onTap: () => _select(day),
    );
    if (reveal != null) {
      // Each cell's turn, as a slice of the whole reveal.
      final start = _DayCell.revealStagger * slot;
      cell = _Reveal(
        animation: reveal,
        start: start.inMicroseconds / _revealLength.inMicroseconds,
        end:
            (start + _DayCell.revealDuration).inMicroseconds /
            _revealLength.inMicroseconds,
        child: cell,
      );
    }
    return cell;
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

/// "Sat 17 Oct".
String _shortDate(DateTime day) =>
    '${_weekdayNames[day.weekday - 1]} ${day.day} '
    '${_monthNames[day.month - 1].substring(0, 3)}';

/// Which meal of the day a photo's time suggests.
String _mealSlot(DateTime taken) => switch (taken.hour) {
  >= 4 && < 11 => 'Breakfast',
  >= 11 && < 16 => 'Lunch',
  >= 16 && < 23 => 'Dinner',
  _ => 'Late night',
};

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

/// The month and year, tappable to jump to a date (`.title-btn`). The words
/// slide in with the page they belong to (`tNext`, `tPrev`).
class _TitleButton extends StatelessWidget {
  const _TitleButton({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.slideFrom,
    required this.onTap,
  });

  final String eyebrow;
  final String title;
  final int slideFrom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              offset: Offset(18 * slideFrom * (1 - t), 0),
              child: child,
            ),
          ),
          child: ExcludeSemantics(
            child: SizedBox(
              height: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    eyebrow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PlatterText.body(
                      size: 14,
                      weight: FontWeight.w800,
                      color: PlatterColors.ink3,
                    ).copyWith(height: 1),
                  ),
                  // Long months (September) shrink to fit between the arrows.
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
                        Opacity(opacity: 0.55, child: _icon(_Icons.caret, 16)),
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

/// Year · Month · Week · Day (`.zoom`). Only Month exists so far.
class _ZoomBar extends StatelessWidget {
  const _ZoomBar({required this.onOther});

  final ValueChanged<String> onOther;

  static const _views = ['Year', 'Month', 'Week', 'Day'];
  static const _current = 1;

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
                Positioned(
                  left: _current * (width + 3),
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
                    for (final (i, view) in _views.indexed)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == _current,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: i == _current ? null : () => onOther(view),
                            child: SizedBox(
                              height: 40,
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    view,
                                    style: PlatterText.body(
                                      size: 14,
                                      weight: FontWeight.w800,
                                      color: i == _current
                                          ? Colors.white
                                          : PlatterColors.ink,
                                    ),
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

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(
          children: [
            for (final (i, name) in _weekdayNames.indexed) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: PlatterText.body(
                    size: 12,
                    weight: FontWeight.w800,
                    color: PlatterColors.ink3,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One day of the month (`.cell`): the day's first meal photo with the date
/// in the corner and a count when there's more than one, or just the date on
/// an empty day. Today is ringed red, the chosen day blue.
class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.meals,
    required this.thumb,
    required this.selected,
    required this.today,
    required this.future,
    required this.pop,
    required this.onTap,
  });

  final DateTime day;
  final int meals;
  final Uint8List? thumb;
  final bool selected;
  final bool today;
  final bool future;

  /// Bounce once, having just been tapped (`selPop`).
  final bool pop;
  final VoidCallback onTap;

  static const height = 62.0;
  static const revealDuration = Duration(milliseconds: 400);
  static const revealStagger = Duration(milliseconds: 28);

  /// Overshoots, like the mockup's `cubic-bezier(.3,1.5,.5,1)`.
  static const _popCurve = Cubic(0.3, 1.5, 0.5, 1);

  @override
  Widget build(BuildContext context) {
    final hasPhoto = meals > 0;
    Color fill;
    Color border;
    double borderWidth;
    var dashed = false;
    var ring = 0.0;
    if (hasPhoto) {
      fill = PlatterColors.paper;
      border = PlatterColors.ink;
      borderWidth = 2;
    } else if (future) {
      fill = PlatterColors.paper;
      border = PlatterColors.emptyLine;
      borderWidth = 1.5;
      dashed = true;
    } else {
      fill = selected ? const Color(0xFFE4EDFF) : PlatterColors.empty;
      border = PlatterColors.emptyLine;
      borderWidth = 1.5;
    }
    if (today) {
      // Today's red border stays; a blue selection becomes an outer ring.
      border = PlatterColors.red;
      borderWidth = 3.5;
      if (selected) ring = 2.5;
    } else if (selected) {
      border = PlatterColors.blue;
      borderWidth = 3.5;
    }

    final month = _monthNames[day.month - 1];
    Widget cell = SketchBox(
      fill: fill,
      border: border,
      borderWidth: borderWidth,
      radius: 11,
      dashed: dashed,
      ring: ring,
      child: hasPhoto ? _photo() : _number(),
    );
    if (pop) cell = _Pop(key: ValueKey(day), child: cell);
    return Semantics(
      button: !future,
      selected: selected,
      label: future
          ? '$month ${day.day}'
          : '$month ${day.day}, ${_plural(meals, 'meal')}',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: future ? null : onTap,
          child: cell,
        ),
      ),
    );
  }

  Widget _photo() {
    final thumb = this.thumb;
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: thumb == null
                  ? const ColoredBox(color: PlatterColors.empty)
                  : Image.memory(
                      thumb,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
          ),
        ),
        Positioned(
          top: 5,
          left: 5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: today
                  ? PlatterColors.red
                  : PlatterColors.paper.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '${day.day}',
              style: PlatterText.body(
                size: 10,
                weight: FontWeight.w800,
                color: today ? Colors.white : PlatterColors.ink,
              ).copyWith(height: 1.4),
            ),
          ),
        ),
        if (meals > 1)
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PlatterColors.ink,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: PlatterColors.paper, width: 1.5),
              ),
              child: Text(
                '$meals',
                style: PlatterText.body(
                  size: 11,
                  weight: FontWeight.w800,
                  color: Colors.white,
                ).copyWith(height: 1),
              ),
            ),
          ),
      ],
    );
  }

  Widget _number() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          '${day.day}',
          style: PlatterText.body(
            size: 11,
            weight: FontWeight.w800,
            color: future
                ? PlatterColors.muted
                : today
                ? PlatterColors.red
                : PlatterColors.ink3,
          ),
        ),
      ),
    );
  }
}

/// Scales and fades [child] in during its slice ([start] to [end], as
/// fractions) of the reveal (`.cal.reveal`, `pop`).
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.animation,
    required this.start,
    required this.end,
    required this.child,
  });

  final Animation<double> animation;
  final double start;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = ((animation.value - start) / (end - start)).clamp(0.0, 1.0);
        if (t >= 1) return child!;
        return Opacity(
          opacity: Curves.easeOut.transform(t),
          child: Transform.scale(
            scale: 0.5 + 0.5 * _DayCell._popCurve.transform(t),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// A quick bounce to 1.1× and back (`selPop`), once, when first built.
class _Pop extends StatelessWidget {
  const _Pop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (context, t, child) => Transform.scale(
        scale: t < 0.4 ? 1 + 0.1 * (t / 0.4) : 1.1 - 0.1 * ((t - 0.4) / 0.6),
        child: child,
      ),
      child: child,
    );
  }
}

/// The chosen day's meals (`.daycard`), or a word of welcome while the
/// calendar has none at all.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.meals,
    required this.calendarEmpty,
    required this.thumbs,
  });

  final DateTime day;
  final List<FoundMeal> meals;
  final bool calendarEmpty;
  final Map<String, Uint8List?> thumbs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
      child: SketchBox(
        fill: Colors.white,
        radius: 18,
        shadow: 4,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          // The card's words change with the day (`fadeQuick`).
          child: TweenAnimationBuilder<double>(
            key: ValueKey(calendarEmpty ? null : day),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 4 * (1 - t)),
                child: child,
              ),
            ),
            child: calendarEmpty ? _welcome(context) : _day(context),
          ),
        ),
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your calendar is ready',
          style: PlatterText.head(size: 18).copyWith(height: 1.2),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const _Baobie(size: 54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Add meals as you go. Each one lands on its day.',
                style: PlatterText.body(
                  size: 14,
                  color: PlatterColors.ink2,
                ).copyWith(height: 1.4),
              ),
            ),
            const SizedBox(width: 12),
            _addButton(context),
          ],
        ),
      ],
    );
  }

  Widget _day(BuildContext context) {
    final label = _shortDate(day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Semantics(
              button: true,
              label: 'See $label, ${_plural(meals.length, 'meal')}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => comingSoon(context, 'The day view'),
                child: ExcludeSemantics(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            style: PlatterText.head(size: 18)
                                .copyWith(height: 1.1),
                          ),
                        ),
                        const SizedBox(width: 3),
                        _icon(_Icons.chevron, 17),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                PillButton(
                  label: 'Edit',
                  small: true,
                  icon: _icon(_Icons.edit, 14),
                  onPressed: () => comingSoon(context, 'Editing a day'),
                ),
                _addButton(context),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (meals.isEmpty)
          Row(
            children: [
              const _Baobie(size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No meals on this day.',
                  style: PlatterText.body(
                    size: 14,
                    color: PlatterColors.ink2,
                  ).copyWith(height: 1.4),
                ),
              ),
            ],
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, meal) in meals.indexed)
                  Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                    child: _MealCard(meal: meal, thumb: thumbs[meal.id]),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _addButton(BuildContext context) => PillButton(
    label: 'Add',
    small: true,
    blue: true,
    icon: _icon(_Icons.plus, 14, color: Colors.white),
    onPressed: () => comingSoon(context, 'Adding a meal'),
  );
}

/// One meal in the day card (`.meal`): its photo, which meal of the day it
/// looks like, and when it was taken.
class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.thumb});

  final FoundMeal meal;
  final Uint8List? thumb;

  @override
  Widget build(BuildContext context) {
    final taken = meal.taken!;
    final slot = _mealSlot(taken);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(taken),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final thumb = this.thumb;
    // Wider with larger text, so the words beneath the photo still fit.
    final width = 74 * MediaQuery.textScalerOf(context).scale(12) / 12;
    return Semantics(
      button: true,
      label: '$slot at $time, open details',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => comingSoon(context, 'Meal details'),
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 74,
                  height: 62,
                  decoration: BoxDecoration(
                    color: PlatterColors.empty,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: PlatterColors.ink, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: thumb == null
                      ? null
                      : Image.memory(
                          thumb,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  slot,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PlatterText.body(
                    size: 12,
                    weight: FontWeight.w800,
                    color: PlatterColors.ink,
                  ).copyWith(height: 1.2),
                ),
                Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PlatterText.body(
                    size: 11,
                    color: PlatterColors.ink3,
                  ).copyWith(height: 1.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Baobie extends StatelessWidget {
  const _Baobie({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Crayon(
      child: SvgPicture.asset(
        'assets/illustrations/baobie_wave.svg',
        width: size,
        height: size * 170 / 160,
        semanticsLabel: 'Baobie the bao waving hello',
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
                  child: Center(child: _icon(_Icons.camera, 26)),
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
    ('Calendar', _Icons.tabCalendar),
    ('Timeline', _Icons.tabTimeline),
    ('Map', _Icons.tabMap),
    ('Rediscover', _Icons.tabRediscover),
    ('Plated', _Icons.tabPlated),
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
                Crayon(child: _icon(icon, 24, color: color)),
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

/// The mockup's line icons, as SVG so they match it stroke for stroke.
Widget _icon(String svg, double size, {Color color = PlatterColors.ink}) =>
    SvgPicture.string(
      svg,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: color),
    );

abstract final class _Icons {
  static const _stroke =
      'fill="none" stroke="currentColor" stroke-linecap="round" '
      'stroke-linejoin="round"';

  static const prev =
      '<svg viewBox="0 0 24 24" $_stroke stroke-width="3">'
      '<path d="M15 5l-7 7 7 7"/></svg>';
  static const next =
      '<svg viewBox="0 0 24 24" $_stroke stroke-width="3">'
      '<path d="M9 5l7 7-7 7"/></svg>';
  static const caret =
      '<svg viewBox="0 0 24 24" $_stroke stroke-width="3.2">'
      '<path d="M6 9l6 6 6-6"/></svg>';
  static const chevron =
      '<svg viewBox="0 0 24 24" fill="none" stroke="#2450B8" stroke-width="3" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M9 5l7 7-7 7"/></svg>';
  static const edit =
      '<svg viewBox="0 0 24 24" $_stroke stroke-width="2.6">'
      '<path d="M4 20h4L19 9l-4-4L4 16v4z"/><path d="M13.5 6.5l4 4"/></svg>';
  static const plus =
      '<svg viewBox="0 0 24 24" $_stroke stroke-width="3">'
      '<path d="M12 5v14M5 12h14"/></svg>';
  static const camera =
      '<svg viewBox="0 0 24 24" $_stroke stroke-width="2.4">'
      '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>'
      '</svg>';
  static const gear =
      '<svg viewBox="0 0 24 24" $_stroke stroke-width="2.2">'
      '<circle cx="12" cy="12" r="3"/>'
      '<path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 '
      '2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 '
      '0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 '
      '2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 '
      '0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 '
      '0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 '
      '4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 '
      '1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 '
      '1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 '
      '1.65 0 0 0-1.51 1z"/></svg>';
  static const tabCalendar =
      '<svg viewBox="0 0 24 24" $_stroke stroke-width="2.4">'
      '<rect x="3" y="5" width="18" height="16" rx="3"/>'
      '<path d="M3 10h18M8 3v4M16 3v4"/></svg>';
  static const tabTimeline =
      '<svg viewBox="0 0 24 24" $_stroke stroke-width="2.4">'
      '<rect x="4" y="3" width="16" height="7" rx="2"/>'
      '<rect x="4" y="12" width="16" height="4" rx="1.5"/>'
      '<rect x="4" y="18" width="16" height="3" rx="1.5"/></svg>';
  static const tabMap =
      '<svg viewBox="0 0 24 24" $_stroke stroke-width="2.4">'
      '<path d="M9 4l-6 2v14l6-2 6 2 6-2V4l-6 2-6-2zM9 4v14M15 6v14"/></svg>';
  static const tabRediscover =
      '<svg viewBox="0 0 24 24" $_stroke stroke-width="2.4">'
      '<path d="M4 7h3l10 10h3M4 17h3l3-3M14 10l3-3h3M18 4l2 3-2 3M18 14l2 '
      '3-2 3"/></svg>';
  static const tabPlated =
      '<svg viewBox="0 0 24 24" $_stroke stroke-width="2.4">'
      '<circle cx="12" cy="12" r="9"/>'
      '<path d="M12 7.6l1.3 2.7 2.9.4-2.1 2 .5 2.9-2.6-1.4-2.6 1.4.5-2.9-2.1-2 '
      '2.9-.4z"/></svg>';
}
