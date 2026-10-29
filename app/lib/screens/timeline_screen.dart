import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/food_scanner.dart';
import '../services/meal_calendar.dart';
import '../services/meal_store.dart';
import '../theme/platter_theme.dart';
import '../widgets/coming_soon.dart';
import '../widgets/crayon.dart';
import '../widgets/sketch.dart';
import 'calendar/calendar_bits.dart';

/// The timeline (`#v-timeline` in the mockup): every meal, newest first,
/// grouped by day under its month, as a compact grid or large photos. A rail
/// down the right side jumps to a month or scrubs through them all. Tapping
/// a day's pill opens that day in the calendar.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.store,
    required this.onOpenDay,
    this.today,
  });

  /// Where the meals and their thumbnails come from.
  final MealStore store;

  /// Opens a day in the calendar.
  final ValueChanged<DateTime> onOpenDay;

  /// Today's date, for tests; by default the clock's.
  final DateTime? today;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

/// One row of the list: a month's heading, a day's meals, or the card at
/// the end. [month] is the index of the month it belongs to, newest first.
sealed class _Item {
  const _Item(this.month);

  final int month;
}

class _MonthHeading extends _Item {
  const _MonthHeading(super.month, this.date, this.meals);

  final DateTime date;
  final int meals;
}

class _DayItem extends _Item {
  const _DayItem(super.month, this.day, this.meals);

  final DateTime day;
  final List<FoundMeal> meals;
}

class _EndCard extends _Item {
  const _EndCard(super.month, this.first);

  /// The first day with a meal.
  final DateTime first;
}

class _TimelineScreenState extends State<TimelineScreen>
    with SingleTickerProviderStateMixin {
  /// The meals last taken from the store; null until its first load is in.
  MealCalendar? _meals;

  /// Large photos, one per row, rather than the compact grid.
  bool _large = false;

  /// The months with meals, newest first, and the rows of the list.
  List<DateTime> _months = const [];
  List<_Item> _items = const [];

  /// Which row each month's heading is.
  List<int> _headingRows = const [];

  final _scroll = ScrollController();
  final _listKey = GlobalKey();

  /// The rows that are built right now, by row, so the rail can tell which
  /// month is at the top and jump to a heading that's on screen.
  final _built = <int, BuildContext>{};

  /// The month at the top of the list, and how far down the list is. Only
  /// the rail listens, so scrolling doesn't rebuild the list.
  final _rail = ValueNotifier<(int month, double fraction)>((0, 0));
  bool _syncPending = false;

  int get _current => _rail.value.$1;

  /// Counts seeks and jumps, so one still homing in gives way to a newer
  /// one rather than pulling the list back.
  int _scrollRequest = 0;

  /// The first days rise in one after another when the list first shows.
  bool _entering = false;
  Timer? _enterTimer;

  /// Fades the list in again when the photo size changes (`.resize`).
  late final _resize = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: 1,
  );

  static const _gridThumb = 360;
  static const _largePhoto = 900;

  /// Rows past this many have no entrance; only the first few are seen.
  static const _entranceRows = 7;

  DateTime get _today => dayOf(widget.today ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  bool _synced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The first look at the store happens here rather than in initState, as
    // the entrance asks whether animations are turned off.
    if (!_synced) {
      _synced = true;
      _onStore();
    }
  }

  @override
  void didUpdateWidget(TimelineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStore);
      widget.store.addListener(_onStore);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _enterTimer?.cancel();
    _resize.dispose();
    _scroll.dispose();
    _rail.dispose();
    super.dispose();
  }

  /// The store changed: new meals, or a thumbnail landing.
  void _onStore() {
    final meals = widget.store.meals;
    if (meals == null) return;
    if (identical(meals, _meals)) {
      if (mounted) setState(() {});
      return;
    }
    final wasEmpty = _meals?.isEmpty ?? true;
    _meals = meals;
    _layOut(meals);
    if (wasEmpty && !meals.isEmpty) _enter();
    if (mounted) setState(() {});
    _scheduleSync();
  }

  /// Groups the days into months, newest first, as rows of the list.
  void _layOut(MealCalendar meals) {
    final days = meals.days.reversed.toList();
    final months = <DateTime>[];
    final items = <_Item>[];
    final headings = <int>[];
    for (final day in days) {
      final month = monthOf(day);
      if (months.isEmpty || months.last != month) {
        months.add(month);
        headings.add(items.length);
        items.add(
          _MonthHeading(
            months.length - 1,
            month,
            meals.countOn(meals.daysIn(month)),
          ),
        );
      }
      items.add(_DayItem(months.length - 1, day, meals.on(day)));
    }
    if (days.isNotEmpty) items.add(_EndCard(months.length - 1, days.last));
    _months = months;
    _items = items;
    _headingRows = headings;
    final (current, fraction) = _rail.value;
    _rail.value = (
      current.clamp(0, months.isEmpty ? 0 : months.length - 1),
      fraction,
    );
  }

  void _enter() {
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    _entering = true;
    _enterTimer?.cancel();
    _enterTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _entering = false);
    });
  }

  void _setLarge(bool large) {
    if (large == _large) return;
    // The same month stays at the top in the new size.
    final month = _current;
    setState(() => _large = large);
    if (!MediaQuery.disableAnimationsOf(context)) _resize.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_jumpToMonth(month));
    });
  }

  /// A jump far down (or up) a lazily laid-out list lands short: each frame
  /// the list learns the real heights of a few more rows and corrects the
  /// offset, so a jump homes in over several frames, up to this many.
  static const _homingFrames = 60;

  /// Scrolls so [month]'s heading is at the top. A heading that isn't built
  /// yet is guessed at from the rows that are, then homed in on once the
  /// list has laid out around the guess.
  Future<void> _jumpToMonth(int month) async {
    if (month < 0 || month >= _headingRows.length) return;
    final row = _headingRows[month];
    final request = ++_scrollRequest;
    for (var tries = 0; tries < _homingFrames; tries++) {
      if (!mounted || !_scroll.hasClients || request != _scrollRequest) {
        return;
      }
      final context = _built[row];
      if (context != null && context.mounted) {
        await Scrollable.ensureVisible(context, alignment: 0);
        _scheduleSync();
        return;
      }
      final guess = _guessOffset(row);
      if (guess == null) break;
      _scroll.jumpTo(guess);
      await WidgetsBinding.instance.endOfFrame;
    }
    _scheduleSync();
  }

  /// Where [row] probably starts: as far past the built rows as it is in
  /// rows, at their average height. Rows differ in height (a day with four
  /// large photos is many headings tall), so it's a guess to home in from.
  double? _guessOffset(int row) {
    final list = _listKey.currentContext?.findRenderObject();
    if (list is! RenderBox || !list.hasSize) return null;
    final position = _scroll.position;
    int? first, last;
    var top = 0.0, bottom = 0.0;
    for (final MapEntry(key: r, value: context) in _built.entries) {
      if (!context.mounted) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero, ancestor: list).dy;
      if (first == null || r < first) {
        first = r;
        top = y;
      }
      if (last == null || r > last) {
        last = r;
        bottom = y + box.size.height;
      }
    }
    final double guess;
    if (first == null) {
      final length = position.maxScrollExtent + position.viewportDimension;
      guess = row / _items.length * length;
    } else {
      final average = (bottom - top) / (last! - first + 1);
      guess = position.pixels + top + (row - first) * average;
    }
    return guess.clamp(0.0, position.maxScrollExtent);
  }

  /// Scrolls to [fraction] of the way down the list. How long the list is
  /// is only an estimate until it's laid out around the new spot, so the
  /// jump is checked against the fresh estimate frame by frame while it
  /// still gets closer.
  void _seek(double fraction) =>
      _seekAgain(fraction, ++_scrollRequest, _homingFrames, null);

  void _seekAgain(double fraction, int request, int tries, double? was) {
    if (!mounted || !_scroll.hasClients || request != _scrollRequest) return;
    final position = _scroll.position;
    final target = fraction * position.maxScrollExtent;
    final pixels = position.pixels;
    if ((pixels - target).abs() < 1 || pixels == was) return;
    _scroll.jumpTo(target);
    if (tries > 1) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _seekAgain(fraction, request, tries - 1, pixels),
      );
    }
  }

  /// Works out the rail's position once the frame is laid out.
  void _scheduleSync() {
    if (_syncPending) return;
    _syncPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPending = false;
      if (mounted) _syncRail();
    });
  }

  /// The month at the top is the one of the row nearest above the fold.
  void _syncRail() {
    final list = _listKey.currentContext?.findRenderObject();
    if (list is! RenderBox || !list.hasSize || !_scroll.hasClients) return;
    final position = _scroll.position;
    final max = position.maxScrollExtent;
    final fraction = max > 0 ? (position.pixels / max).clamp(0.0, 1.0) : 0.0;
    int? month;
    var best = double.negativeInfinity;
    for (final MapEntry(key: row, value: context) in _built.entries) {
      if (!context.mounted) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero, ancestor: list).dy;
      if (top <= 40 && top > best) {
        best = top;
        month = _items[row].month;
      }
    }
    _rail.value = (month ?? 0, fraction);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PlatterColors.paper,
      body: Column(
        children: [
          compactText(_header(context)),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final meals = _meals;
    final first = meals?.earliest;
    var count = plural(meals?.count ?? 0, 'meal');
    if (first != null) {
      count += ' · since ${shortMonth(first.month)} ${first.year}';
    }
    return PaperBand(
      fill: PlatterColors.yellow,
      edgeAtTop: false,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Timeline',
                      style: PlatterText.head(size: 32).copyWith(height: 1),
                    ),
                  ),
                  SquareButton(
                    icon: calIcon(CalIcons.gear, 21),
                    label: 'Settings',
                    onPressed: () => comingSoon(context, 'Settings'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SketchBox(
                        radius: 999,
                        borderWidth: 2,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(13, 4, 13, 4),
                          child: Text(
                            count,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PlatterText.body(
                              size: 14,
                              weight: FontWeight.w800,
                              color: PlatterColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Sizer(large: _large, onChange: _setLarge),
                ],
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
    if (meals.isEmpty) return _empty(context);
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: _resize,
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                _scheduleSync();
                return false;
              },
              child: ListView.builder(
                key: _listKey,
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 50, 28),
                itemCount: _items.length,
                itemBuilder: _row,
              ),
            ),
          ),
        ),
        Positioned(
          right: 2,
          top: 10,
          bottom: 10,
          width: _Rail.width,
          child: compactText(
            ValueListenableBuilder(
              valueListenable: _rail,
              builder: (context, rail, _) => _Rail(
                months: _months,
                thisYear: _today.year,
                current: rail.$1,
                fraction: rail.$2,
                onSeek: _seek,
                onJump: (month) => unawaited(_jumpToMonth(month)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, int row) {
    final item = _items[row];
    final today = _today;
    Widget child = switch (item) {
      _MonthHeading() => _MonthHeadingRow(month: item.date, meals: item.meals),
      _DayItem() => _DayRow(
        day: item.day,
        meals: item.meals,
        today: item.day == today,
        large: _large,
        thumbs: _thumbsFor(item.meals),
        onOpen: () => widget.onOpenDay(item.day),
      ),
      _EndCard() => _EndRow(first: item.first, thisYear: today.year),
    };
    if (_entering && row < _entranceRows) {
      // The heading rises first, then the days one after another.
      child = _RiseIn(
        delay: Duration(milliseconds: row == 0 ? 0 : 50 * (row - 1)),
        child: child,
      );
    }
    // Keyed by what the row shows, so a day keeps its element (and the
    // rail's record of it) when a new month lands above it.
    final key = switch (item) {
      _MonthHeading() => ('month', item.date),
      _DayItem() => ('day', item.day),
      _EndCard() => ('end', item.first),
    };
    return _Built(
      key: ValueKey(key),
      row: row,
      onBuilt: (row, context) => _built[row] = context,
      onGone: (row, context) {
        if (identical(_built[row], context)) _built.remove(row);
      },
      child: child,
    );
  }

  /// The renders a day's photos need: grid-sized, or large with the
  /// grid-sized one standing in until the large one arrives.
  Thumbs _thumbsFor(List<FoundMeal> meals) => {
    for (final meal in meals)
      meal.id: _large
          ? widget.store.thumbnail(meal.id, size: _largePhoto) ??
                widget.store.thumbnail(meal.id, size: _gridThumb)
          : widget.store.thumbnail(meal.id, size: _gridThumb),
  };

  Widget _empty(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: SketchBox(
        fill: Colors.white,
        border: PlatterColors.emptyLine,
        dashed: true,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
          child: Column(
            children: [
              Text(
                'No meals yet',
                textAlign: TextAlign.center,
                style: PlatterText.head(size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                'Meals you add show up here, newest first.',
                textAlign: TextAlign.center,
                style: PlatterText.body(
                  size: 15,
                  color: PlatterColors.ink2,
                ).copyWith(height: 1.4),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'Add a meal',
                small: true,
                blue: true,
                icon: calIcon(CalIcons.plus, 14, color: Colors.white),
                onPressed: () => comingSoon(context, 'Adding a meal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tells the screen while this row is in the tree, so it can be found.
class _Built extends StatefulWidget {
  const _Built({
    super.key,
    required this.row,
    required this.onBuilt,
    required this.onGone,
    required this.child,
  });

  final int row;
  final void Function(int row, BuildContext context) onBuilt;
  final void Function(int row, BuildContext context) onGone;
  final Widget child;

  @override
  State<_Built> createState() => _BuiltState();
}

class _BuiltState extends State<_Built> {
  @override
  void initState() {
    super.initState();
    widget.onBuilt(widget.row, context);
  }

  @override
  void didUpdateWidget(_Built oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row != widget.row) {
      oldWidget.onGone(oldWidget.row, context);
      widget.onBuilt(widget.row, context);
    }
  }

  @override
  void dispose() {
    widget.onGone(widget.row, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Rises into place after [delay] (`riseIn`).
class _RiseIn extends StatelessWidget {
  const _RiseIn({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  static const _length = Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    final total = delay + _length;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: platterEase,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Compact grid or large photos (`.sizer`).
class _Sizer extends StatelessWidget {
  const _Sizer({required this.large, required this.onChange});

  final bool large;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Photo size',
      child: SketchBox(
        radius: 14,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SizerButton(
                icon: _TimelineIcons.grid,
                label: 'Compact grid, 3 photos per row',
                selected: !large,
                onTap: () => onChange(false),
              ),
              const SizedBox(width: 2),
              _SizerButton(
                icon: _TimelineIcons.large,
                label: 'Large photos, one per row',
                selected: large,
                onTap: () => onChange(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SizerButton extends StatelessWidget {
  const _SizerButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 38,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (selected)
                  const Crayon(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: PlatterColors.ink,
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                    ),
                  ),
                Center(
                  child: calIcon(
                    icon,
                    20,
                    color: selected ? Colors.white : PlatterColors.ink,
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

/// "October 2026 · 12 meals" (`.tl-month h2`).
class _MonthHeadingRow extends StatelessWidget {
  const _MonthHeadingRow({required this.month, required this.meals});

  final DateTime month;
  final int meals;

  @override
  Widget build(BuildContext context) {
    final name = monthYear(month);
    return Semantics(
      header: true,
      label: '$name, ${plural(meals, 'meal')}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 2),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                name,
                style: PlatterText.head(size: 22).copyWith(height: 1.1),
              ),
              Text(
                plural(meals, 'meal'),
                style: PlatterText.body(
                  size: 13,
                  weight: FontWeight.w800,
                  color: PlatterColors.ink3,
                ).copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One day (`article`): its pill, then its photos as a grid or large cards.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.meals,
    required this.today,
    required this.large,
    required this.thumbs,
    required this.onOpen,
  });

  final DateTime day;
  final List<FoundMeal> meals;
  final bool today;
  final bool large;
  final Thumbs thumbs;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${longDate(day)}, ${plural(meals.length, 'meal')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Align(alignment: Alignment.centerLeft, child: _pill()),
          ),
          if (large) _big() else _grid(),
        ],
      ),
    );
  }

  Widget _pill() {
    return Semantics(
      button: true,
      label: 'Open ${longDate(day)} in the calendar',
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onOpen,
          child: SketchBox(
            radius: 999,
            fill: PlatterColors.yellow,
            border: today ? PlatterColors.red : PlatterColors.ink,
            borderWidth: today ? 3 : 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
              child: Text(
                '${today ? 'Today · ' : ''}${shortDate(day)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PlatterText.body(
                  size: 14,
                  weight: FontWeight.w800,
                  color: PlatterColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Three photos to a row (`.tl-grid`).
  Widget _grid() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
          for (var i = 0; i < meals.length; i += 3)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: Row(
                children: [
                  for (var column = 0; column < 3; column++) ...[
                    if (column > 0) const SizedBox(width: 6),
                    Expanded(
                      child: i + column < meals.length
                          ? _Photo(
                              meal: meals[i + column],
                              thumb: thumbs[meals[i + column].id],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// One wide card per meal (`.tl-big`).
  Widget _big() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, meal) in meals.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: MealCard(meal: meal, thumb: thumbs[meal.id], wide: true),
            ),
        ],
      ),
    );
  }
}

/// A square photo in the grid (`.tl-photo`).
class _Photo extends StatelessWidget {
  const _Photo({required this.meal, required this.thumb});

  final FoundMeal meal;
  final Uint8List? thumb;

  @override
  Widget build(BuildContext context) {
    final taken = meal.taken!;
    final time = formatTime(context, taken);
    return Semantics(
      button: true,
      label: '${MealSlot.of(taken).label} at $time, open details',
      child: ExcludeSemantics(
        child: Pressable(
          onTap: () => comingSoon(context, 'Meal details'),
          child: SketchBox(
            radius: 11,
            borderWidth: 2,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: AspectRatio(
                aspectRatio: 1,
                child: PhotoBox(bytes: thumb, radius: 8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card after the oldest day (`.tl-end`).
class _EndRow extends StatelessWidget {
  const _EndRow({required this.first, required this.thisYear});

  final DateTime first;
  final int thisYear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 26, 0, 8),
      child: SketchBox(
        fill: PlatterColors.empty,
        border: PlatterColors.emptyLine,
        dashed: true,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Baobie(size: 84),
              const SizedBox(height: 4),
              Text(
                "That's where it all began",
                textAlign: TextAlign.center,
                style: PlatterText.head(size: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'Your first photographed meal: ${longDate(first)}'
                '${first.year == thisYear ? '' : ' ${first.year}'}.',
                textAlign: TextAlign.center,
                style: PlatterText.body(
                  size: 14,
                  color: PlatterColors.ink2,
                ).copyWith(height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The scrubber down the right (`.rail`): a mark per month to tap, a thumb
/// that shows how far down the list is, and dragging anywhere along it
/// scrolls the list, with the month at the top named beside the thumb.
class _Rail extends StatefulWidget {
  const _Rail({
    required this.months,
    required this.thisYear,
    required this.current,
    required this.fraction,
    required this.onSeek,
    required this.onJump,
  });

  /// Newest first.
  final List<DateTime> months;

  /// Months in other years are named with their year.
  final int thisYear;
  final int current;
  final double fraction;
  final ValueChanged<double> onSeek;
  final ValueChanged<int> onJump;

  static const width = 46.0;
  static const _markHeight = 24.0;

  /// The thumb's travel stops short of the ends by this much.
  static const _inset = 12.0;

  @override
  State<_Rail> createState() => _RailState();
}

class _RailState extends State<_Rail> {
  bool _dragging = false;

  double _fractionAt(double y, double height) =>
      ((y - _Rail._inset) / (height - 2 * _Rail._inset)).clamp(0.0, 1.0);

  /// The months that get a mark: all of them while they fit down the rail,
  /// otherwise every second, third... so they still do.
  List<int> _marked(double height) {
    final n = widget.months.length;
    final fit = (height / _Rail._markHeight).floor().clamp(1, n);
    final step = (n / fit).ceil();
    return [for (var i = 0; i < n; i += step) i];
  }

  /// Whether [y] is on a month's mark, which jumps on a tap rather than
  /// starting a drag.
  bool _onMark(double y, double height) {
    final n = _marked(height).length;
    for (var i = 0; i < n; i++) {
      final top = n == 1 ? 0.0 : i * (height - _Rail._markHeight) / (n - 1);
      if (y >= top && y <= top + _Rail._markHeight) return true;
    }
    return false;
  }

  void _down(DragDownDetails details, double height) {
    final y = details.localPosition.dy;
    if (_onMark(y, height)) return;
    setState(() => _dragging = true);
    widget.onSeek(_fractionAt(y, height));
  }

  /// A drag that began on a mark skipped [_down]; it scrubs all the same.
  void _start(DragStartDetails details, double height) {
    if (!_dragging) setState(() => _dragging = true);
    widget.onSeek(_fractionAt(details.localPosition.dy, height));
  }

  void _end() {
    if (_dragging) setState(() => _dragging = false);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.current.clamp(0, widget.months.length - 1);
    final month = widget.months[current];
    String nameOf(int i) => monthYear(widget.months[i]);
    final name = nameOf(current);
    final older = current < widget.months.length - 1;
    final newer = current > 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final travel = height - 2 * _Rail._inset;
        final thumbTop = _Rail._inset + widget.fraction * travel - 17;
        return Semantics(
          slider: true,
          label: 'Scroll through months',
          value: name,
          increasedValue: older ? nameOf(current + 1) : name,
          decreasedValue: newer ? nameOf(current - 1) : name,
          onIncrease: older ? () => widget.onJump(current + 1) : null,
          onDecrease: newer ? () => widget.onJump(current - 1) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragDown: (details) => _down(details, height),
            onVerticalDragStart: (details) => _start(details, height),
            onVerticalDragUpdate: (details) =>
                widget.onSeek(_fractionAt(details.localPosition.dy, height)),
            onVerticalDragEnd: (_) => _end(),
            onVerticalDragCancel: _end,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned(
                  right: 9,
                  top: 4,
                  bottom: 4,
                  width: 5,
                  child: Crayon(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFFBFDBFF),
                        border: Border.fromBorderSide(
                          BorderSide(color: PlatterColors.ink, width: 1.5),
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(3)),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final i in _marked(height))
                        _Mark(
                          month: widget.months[i],
                          on: i == current,
                          onTap: () => widget.onJump(i),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  right: 3,
                  top: thumbTop,
                  child: const IgnorePointer(child: _Thumb()),
                ),
                Positioned(
                  right: 50,
                  top: thumbTop,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _dragging ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: PlatterColors.ink,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x4D1F2A44),
                              offset: Offset(0, 6),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Text(
                          monthYear(month, unless: widget.thisYear),
                          maxLines: 1,
                          style: PlatterText.head(
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A month on the rail (`.rail .mark`): its name and a tick on the line.
class _Mark extends StatelessWidget {
  const _Mark({required this.month, required this.on, required this.onTap});

  final DateTime month;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Jump to ${monthYear(month)}',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: _Rail.width,
            height: _Rail._markHeight,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 22,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      shortMonth(month.month),
                      maxLines: 1,
                      style: PlatterText.body(
                        size: 10,
                        weight: FontWeight.w800,
                        color: on ? PlatterColors.ink : PlatterColors.ink3,
                      ).copyWith(height: 1),
                    ),
                  ),
                ),
                Positioned(
                  right: 7,
                  top: (_Rail._markHeight - 2.5) / 2,
                  child: Container(
                    width: 9,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: PlatterColors.ink,
                      borderRadius: BorderRadius.circular(2),
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

/// The blue grip on the rail (`.thumb`).
class _Thumb extends StatelessWidget {
  const _Thumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 17,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PlatterColors.blue,
        border: Border.all(color: PlatterColors.ink, width: 2),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 1),
              child: Container(width: 7, height: 2, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

abstract final class _TimelineIcons {
  static const grid =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" '
      'stroke-width="2.2" stroke-linejoin="round">'
      '<rect x="3" y="3" width="5" height="5" rx="1"/>'
      '<rect x="9.5" y="3" width="5" height="5" rx="1"/>'
      '<rect x="16" y="3" width="5" height="5" rx="1"/>'
      '<rect x="3" y="9.5" width="5" height="5" rx="1"/>'
      '<rect x="9.5" y="9.5" width="5" height="5" rx="1"/>'
      '<rect x="16" y="9.5" width="5" height="5" rx="1"/>'
      '<rect x="3" y="16" width="5" height="5" rx="1"/>'
      '<rect x="9.5" y="16" width="5" height="5" rx="1"/>'
      '<rect x="16" y="16" width="5" height="5" rx="1"/></svg>';
  static const large =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" '
      'stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">'
      '<rect x="3" y="3" width="18" height="13" rx="2.5"/>'
      '<path d="M4 20h12"/></svg>';
}
