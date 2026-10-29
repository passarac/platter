import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../services/meal_calendar.dart';
import '../services/meal_store.dart';
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
/// New meals land on their days as the [store] hears of them.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.store, this.today});

  /// Where the meals and their thumbnails come from.
  final MealStore store;

  /// Today's date, for tests; by default the clock's.
  final DateTime? today;

  @override
  State<CalendarScreen> createState() => CalendarScreenState();
}

/// How the next page arrives (the mockup's `slideNext`, `slidePrev`,
/// `zoomIn`, `zoomOut` and `viewIn`).
enum _Entrance { fade, slideNext, slidePrev, zoomIn, zoomOut }

class CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  /// The meals last taken from the store; null until its first load is in.
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
  static const _thumbSize = 240;
  static const _photoSize = 900;

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
    widget.store.addListener(_onStore);
    // After the first frame, so meals the store already has still find the
    // screen in the tree when they start the reveal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onStore();
    });
  }

  @override
  void didUpdateWidget(CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStore);
      widget.store.addListener(_onStore);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _reveal.dispose();
    super.dispose();
  }

  /// The store changed: new meals, or a thumbnail landing.
  void _onStore() {
    final meals = widget.store.meals;
    if (meals == null) return;
    if (identical(meals, _meals)) {
      setState(() {});
      return;
    }
    final first = _meals == null;
    // The first meals to land, now or as the scan finds them, decide where
    // the calendar opens; there was nowhere worth being before them.
    final settle = first || (_meals!.isEmpty && !meals.isEmpty);
    setState(() {
      _meals = meals;
      if (settle) _cursor = meals.defaultDay(meals.startMonth(_today), _today);
    });
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

  /// Small renders of the meals on [days], fetched as they're first asked
  /// for.
  Thumbs _thumbsOn(Iterable<DateTime> days, MealCalendar meals) => {
    for (final day in days)
      for (final meal in meals.on(day))
        meal.id: widget.store.thumbnail(meal.id, size: _thumbSize),
  };

  /// The day view's photos: the large render, or the small one until it
  /// arrives.
  Thumbs _dayPhotos(MealCalendar meals) => {
    for (final meal in meals.on(_cursor))
      meal.id:
          widget.store.thumbnail(meal.id, size: _photoSize) ??
          widget.store.thumbnail(meal.id, size: _thumbSize),
  };

  /// Shows [day] in the day view, from wherever the calendar was.
  void openDay(DateTime day) {
    final target = _clamp(dayOf(day));
    if (_view == CalendarView.day) {
      if (target != _cursor) _show(_view, target, _Entrance.fade);
    } else {
      _zoomTo(CalendarView.day, at: target);
    }
  }

  /// Keeps [day] between the first month and today.
  DateTime _clamp(DateTime day) => day.isAfter(_today)
      ? _today
      : day.isBefore(_firstMonth)
      ? _firstMonth
      : day;

  /// Where the cursor lands one page back or forward in the current view,
  /// or null at the edge of the calendar. A page outside the calendar (the
  /// year view can open the empty months before the first meal) pages back
  /// into it rather than nowhere.
  DateTime? _target(int direction) {
    final cursor = _cursor;
    final next = switch (_view) {
      CalendarView.year => () {
        final year = cursor.year + direction;
        final days = DateUtils.getDaysInMonth(year, cursor.month);
        return DateTime(year, cursor.month, min(cursor.day, days));
      }(),
      CalendarView.month => DateTime(cursor.year, cursor.month + direction),
      CalendarView.week => addDays(cursor, 7 * direction),
      CalendarView.day => addDays(cursor, direction),
    };
    // Nothing past today, or before the first month, that way.
    final (start, end) = _pageSpan(next);
    if (direction > 0 && start.isAfter(_today)) return null;
    if (direction < 0 && end.isBefore(_firstMonth)) return null;
    final target = _clamp(next);
    if (_view != CalendarView.month) return target;
    return _meals?.defaultDay(target, _today) ?? monthOf(target);
  }

  /// The first and last day of the page [day] is on in the current view.
  (DateTime, DateTime) _pageSpan(DateTime day) => switch (_view) {
    CalendarView.year => (DateTime(day.year), DateTime(day.year, 12, 31)),
    CalendarView.month => (monthOf(day), DateTime(day.year, day.month + 1, 0)),
    CalendarView.week => (mondayOf(day), addDays(mondayOf(day), 6)),
    CalendarView.day => (day, day),
  };

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
    );
  }

  Widget _header(BuildContext context) {
    final (eyebrow, title) = _heading;
    final unit = _view.name;
    return PaperBand(
      fill: PlatterColors.yellow,
      edgeAtTop: false,
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
        thumbs: _thumbsOn(meals.daysIn(_month), meals),
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
        thumbs: _thumbsOn([
          for (var i = 0; i < 7; i++) addDays(mondayOf(_cursor), i),
        ], meals),
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
