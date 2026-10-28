import 'package:flutter/material.dart';

import '../../services/meal_calendar.dart';
import '../../theme/platter_theme.dart';
import '../../widgets/sketch.dart';
import 'calendar_bits.dart';

/// A week as a grid (`weekBody` in the mockup): a row per day, a column per
/// meal of the day, each cell the first photo taken in that slot. Tapping
/// a day or a photo opens the day.
class WeekView extends StatelessWidget {
  const WeekView({
    super.key,
    required this.monday,
    required this.today,
    required this.meals,
    required this.thumbs,
    required this.onOpenDay,
  });

  final DateTime monday;
  final DateTime today;
  final MealCalendar meals;
  final Thumbs thumbs;
  final ValueChanged<DateTime> onOpenDay;

  static const rowHeight = 62.0;
  static const _labelWidth = 56.0;

  /// The seven days from [monday].
  List<DateTime> get days => [for (var i = 0; i < 7; i++) addDays(monday, i)];

  @override
  Widget build(BuildContext context) {
    final days = this.days;
    final total = meals.countOn(days);
    return Column(
      children: [
        compactText(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                ExcludeSemantics(
                  child: Row(
                    children: [
                      const SizedBox(width: _labelWidth),
                      for (final slot in MealSlot.values) ...[
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            slot.label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                for (final day in days)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: SizedBox(
                      height: rowHeight,
                      child: Row(
                        children: [
                          SizedBox(width: _labelWidth, child: _dayLabel(day)),
                          for (final slot in MealSlot.values) ...[
                            const SizedBox(width: 5),
                            Expanded(child: _slotCell(context, day, slot)),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          // Clear of the camera button in the corner.
          padding: const EdgeInsets.fromLTRB(14, 22, 88, 16),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              SketchBox(
                fill: PlatterColors.yellow,
                radius: 999,
                borderWidth: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 5, 13, 5),
                  child: Text(
                    '${plural(total, 'meal')} this week',
                    style: PlatterText.body(
                      size: 14,
                      weight: FontWeight.w800,
                      color: PlatterColors.ink,
                    ),
                  ),
                ),
              ),
              Text(
                'Columns show your habits',
                style: PlatterText.body(size: 13, color: PlatterColors.ink3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The weekday and date down the side (`.wday`); today sits in a red box.
  Widget _dayLabel(DateTime day) {
    final isToday = day == today;
    final future = day.isAfter(today);
    final color = future
        ? PlatterColors.muted
        : isToday
        ? PlatterColors.red
        : PlatterColors.ink;
    final words = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          weekdayShort[day.weekday - 1],
          style: PlatterText.body(
            size: 12,
            weight: FontWeight.w800,
            color: color,
          ).copyWith(height: 1.05),
        ),
        Text(
          '${day.day}',
          style: PlatterText.head(
            size: 20,
            color: color,
          ).copyWith(height: 1.05),
        ),
      ],
    );
    final label = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: isToday
          ? SketchBox(
              fill: Colors.white,
              border: PlatterColors.red,
              borderWidth: 3,
              radius: 12,
              child: Center(child: words),
            )
          : Center(child: words),
    );
    if (future) return ExcludeSemantics(child: label);
    return Semantics(
      button: true,
      label: '${longDate(day)}, open day',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onOpenDay(day),
          child: label,
        ),
      ),
    );
  }

  /// One day's meals in one slot (`.wphoto`), or the empty dashed slot.
  Widget _slotCell(BuildContext context, DateTime day, MealSlot slot) {
    final inSlot = meals.bySlot(day)[slot] ?? const [];
    final future = day.isAfter(today);
    if (inSlot.isEmpty) {
      return SketchBox(
        fill: future ? PlatterColors.paper : PlatterColors.empty,
        border: future ? const Color(0xFFE3E9F2) : PlatterColors.emptyLine,
        borderWidth: 1.5,
        radius: 11,
        dashed: true,
      );
    }
    final name = weekdayLong[day.weekday - 1];
    return Semantics(
      button: true,
      label: '$name ${slot.label}, ${plural(inSlot.length, 'meal')}, open day',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onOpenDay(day),
          child: SketchBox(
            radius: 11,
            borderWidth: 2,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: PhotoBox(bytes: thumbs[inSlot.first.id], radius: 8),
                  ),
                ),
                if (inSlot.length > 1)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: CountBadge(text: '+${inSlot.length - 1}'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
