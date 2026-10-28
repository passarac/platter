import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/food_scanner.dart';
import '../../services/meal_calendar.dart';
import '../../theme/platter_theme.dart';
import '../../widgets/coming_soon.dart';
import '../../widgets/sketch.dart';
import 'calendar_bits.dart';

/// A month of days (`monthBody` in the mockup): a cell for every day
/// showing that day's first meal, and a card with the chosen day's meals.
class MonthView extends StatelessWidget {
  const MonthView({
    super.key,
    required this.month,
    required this.selected,
    required this.today,
    required this.meals,
    required this.thumbs,
    required this.reveal,
    required this.revealLength,
    required this.pop,
    required this.onSelect,
    required this.onOpenDay,
  });

  /// The first of the month.
  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final MealCalendar meals;
  final Thumbs thumbs;

  /// The first reveal, while this month takes part in it (`.cal.reveal`).
  final Animation<double>? reveal;
  final Duration revealLength;

  /// The chosen day was just tapped, so its cell gives a little bounce.
  final bool pop;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onOpenDay;

  static const cellHeight = 62.0;
  static const revealDuration = Duration(milliseconds: 400);
  static const revealStagger = Duration(milliseconds: 28);

  /// Leading blanks before the 1st, with weeks starting on Monday.
  static int leadingBlanks(DateTime month) => month.weekday - DateTime.monday;

  /// Cells in the grid, blanks included.
  static int slots(DateTime month) =>
      leadingBlanks(month) + DateUtils.getDaysInMonth(month.year, month.month);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        compactText(const _WeekdayRow()),
        compactText(_grid(context)),
        _DayCard(
          day: selected,
          meals: meals.on(selected),
          calendarEmpty: meals.isEmpty,
          thumbs: thumbs,
          onOpen: () => onOpenDay(selected),
        ),
      ],
    );
  }

  Widget _grid(BuildContext context) {
    final lead = leadingBlanks(month);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final rows = ((lead + days) / 7).ceil();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          for (var row = 0; row < rows; row++)
            Padding(
              padding: EdgeInsets.only(top: row == 0 ? 0 : 5),
              child: SizedBox(
                height: cellHeight,
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

  Widget _cell(DateTime day, {required int slot}) {
    final onDay = meals.on(day);
    final isSelected = day == selected;
    final cover = onDay.isEmpty ? null : onDay.first.id;
    Widget cell = _DayCell(
      key: ValueKey(day),
      day: day,
      meals: onDay.length,
      thumb: cover == null ? null : thumbs[cover],
      selected: isSelected,
      today: day == today,
      future: day.isAfter(today),
      pop: isSelected && pop,
      onTap: () => onSelect(day),
    );
    if (reveal case final reveal?) {
      // Each cell's turn, as a slice of the whole reveal.
      final start = revealStagger * slot;
      cell = _Reveal(
        animation: reveal,
        start: start.inMicroseconds / revealLength.inMicroseconds,
        end:
            (start + revealDuration).inMicroseconds /
            revealLength.inMicroseconds,
        child: cell,
      );
    }
    return cell;
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
            for (final (i, name) in weekdayShort.indexed) ...[
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
  final bool pop;
  final VoidCallback onTap;

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

    final month = monthNames[day.month - 1];
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
          : '$month ${day.day}, ${plural(meals, 'meal')}',
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
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: PhotoBox(bytes: thumb, radius: 8),
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
          Positioned(right: 4, bottom: 4, child: CountBadge(text: '$meals')),
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

  /// Overshoots, like the mockup's `cubic-bezier(.3,1.5,.5,1)`.
  static const _popCurve = Cubic(0.3, 1.5, 0.5, 1);

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
            scale: 0.5 + 0.5 * _popCurve.transform(t),
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
    required this.onOpen,
  });

  final DateTime day;
  final List<FoundMeal> meals;
  final bool calendarEmpty;
  final Thumbs thumbs;
  final VoidCallback onOpen;

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
            const Baobie(size: 54),
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
            AddMealPill(onPressed: () => comingSoon(context, 'Adding a meal')),
          ],
        ),
      ],
    );
  }

  Widget _day(BuildContext context) {
    final label = shortDate(day);
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
              label: 'See $label, ${plural(meals.length, 'meal')}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpen,
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
                        calIcon(CalIcons.chevron, 17),
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
                  icon: calIcon(CalIcons.edit, 14),
                  onPressed: () => comingSoon(context, 'Editing a day'),
                ),
                AddMealPill(
                  onPressed: () => comingSoon(context, 'Adding a meal'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (meals.isEmpty)
          Row(
            children: [
              const Baobie(size: 50),
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
                    child: _MealTile(meal: meal, thumb: thumbs[meal.id]),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The small blue "+ Add" pill.
class AddMealPill extends StatelessWidget {
  const AddMealPill({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => PillButton(
    label: 'Add',
    small: true,
    blue: true,
    icon: calIcon(CalIcons.plus, 14, color: Colors.white),
    onPressed: onPressed,
  );
}

/// One meal in the day card (`.meal`): its photo, which meal of the day it
/// looks like, and when it was taken.
class _MealTile extends StatelessWidget {
  const _MealTile({required this.meal, required this.thumb});

  final FoundMeal meal;
  final Uint8List? thumb;

  @override
  Widget build(BuildContext context) {
    final taken = meal.taken!;
    final slot = MealSlot.of(taken).label;
    final time = formatTime(context, taken);
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
                  child: PhotoBox(bytes: thumb, radius: 8),
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
