import 'package:flutter/material.dart';

import '../../services/food_scanner.dart';
import '../../services/meal_calendar.dart';
import '../../theme/platter_theme.dart';
import '../../widgets/coming_soon.dart';
import '../../widgets/sketch.dart';
import 'calendar_bits.dart';
import 'month_view.dart';

/// One day's meals (`dayBody` in the mockup), a section per meal of the
/// day. An odd number of meals in a section gives the first a wide card.
class DayView extends StatelessWidget {
  const DayView({
    super.key,
    required this.day,
    required this.meals,
    required this.thumbs,
  });

  final DateTime day;
  final MealCalendar meals;
  final Thumbs thumbs;

  @override
  Widget build(BuildContext context) {
    final onDay = meals.on(day);
    final bySlot = meals.bySlot(day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `.day-tools`: there are no places to show yet, so just the pills.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 4,
            children: [
              PillButton(
                label: 'Edit day',
                small: true,
                icon: calIcon(CalIcons.edit, 14),
                onPressed: () => comingSoon(context, 'Editing a day'),
              ),
              AddMealPill(
                onPressed: () => comingSoon(context, 'Adding a meal'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (onDay.isEmpty)
            _EmptyDay(day: day)
          else ...[
            for (final slot in MealSlot.values)
              if (bySlot[slot] case final list?) ...[
                _SlotSection(slot: slot, meals: list, thumbs: thumbs),
                const SizedBox(height: 16),
              ],
            _SignOff(meals: onDay.length),
          ],
        ],
      ),
    );
  }
}

class _SlotSection extends StatelessWidget {
  const _SlotSection({
    required this.slot,
    required this.meals,
    required this.thumbs,
  });

  final MealSlot slot;
  final List<FoundMeal> meals;
  final Thumbs thumbs;

  @override
  Widget build(BuildContext context) {
    // An odd number of meals gives the first one the full-width card.
    final hero = meals.length % 2 == 1 && meals.length > 1 ? meals.first : null;
    final rest = hero == null ? meals : meals.sublist(1);
    return Semantics(
      container: true,
      label: '${slot.label}, ${plural(meals.length, 'meal')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              compactText(
                SketchBox(
                  fill: slot.color,
                  radius: 999,
                  borderWidth: 2,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 3, 11, 3),
                    child: Text(
                      slot.label,
                      style: PlatterText.body(
                        size: 13,
                        weight: FontWeight.w800,
                        color: PlatterColors.ink,
                      ).copyWith(letterSpacing: 0.4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatTime(context, meals.first.taken!),
                  style: PlatterText.body(size: 13, color: PlatterColors.ink3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (hero != null) ...[
            MealCard(meal: hero, thumb: thumbs[hero.id], wide: true),
            const SizedBox(height: 8),
          ],
          if (rest.length == 1 && hero == null)
            MealCard(meal: rest.first, thumb: thumbs[rest.first.id], wide: true)
          else
            for (var i = 0; i < rest.length; i += 2)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: MealCard(
                        meal: rest[i],
                        thumb: thumbs[rest[i].id],
                        wide: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: i + 1 < rest.length
                          ? MealCard(
                              meal: rest[i + 1],
                              thumb: thumbs[rest[i + 1].id],
                              wide: false,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// A dashed card for a day without meals (`.empty-day`).
class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return SketchBox(
      fill: Colors.white,
      border: PlatterColors.emptyLine,
      radius: 18,
      dashed: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
        child: Column(
          children: [
            const Baobie(size: 96),
            const SizedBox(height: 10),
            Text(
              'Nothing on this day',
              textAlign: TextAlign.center,
              style: PlatterText.head(size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              'No meal photos from ${longDate(day)}.',
              textAlign: TextAlign.center,
              style: PlatterText.body(
                size: 15,
                color: PlatterColors.ink2,
              ).copyWith(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Baobie signs the day off (`.signoff`).
class _SignOff extends StatelessWidget {
  const _SignOff({required this.meals});

  final int meals;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Baobie(size: 58),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            meals >= 4 ? 'What a day. Food coma.' : "That's the day.",
            style: PlatterText.body(
              size: 13,
              weight: FontWeight.w800,
              color: PlatterColors.ink3,
            ),
          ),
        ),
      ],
    );
  }
}
