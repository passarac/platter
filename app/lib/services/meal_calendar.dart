import 'dart:ui' show Color;

import 'food_scanner.dart';

/// [t]'s day, at midnight local time.
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// The first day of [t]'s month.
DateTime monthOf(DateTime t) => DateTime(t.year, t.month);

/// The Monday of [t]'s week.
DateTime mondayOf(DateTime t) =>
    DateTime(t.year, t.month, t.day - (t.weekday - DateTime.monday));

/// [t]'s day plus [n] days (negative to go back), safe across clock changes.
DateTime addDays(DateTime t, int n) => DateTime(t.year, t.month, t.day + n);

/// Which meal of the day a photo's time suggests, and the week view's
/// columns (`SLOT_ORDER` and `SLOT_COLOR` in the mockup, with the
/// unknowable "Sweet" swapped for the small hours).
enum MealSlot {
  breakfast('Breakfast', Color(0xFFFFC93C)),
  lunch('Lunch', Color(0xFF9FDDC4)),
  dinner('Dinner', Color(0xFFBFDBFF)),
  lateNight('Late night', Color(0xFFFF8FB8));

  const MealSlot(this.label, this.color);

  final String label;
  final Color color;

  static MealSlot of(DateTime taken) => switch (taken.hour) {
    >= 4 && < 11 => breakfast,
    >= 11 && < 16 => lunch,
    >= 16 && < 23 => dinner,
    _ => lateNight,
  };
}

/// The meals that belong on the calendar, by the day they were taken. Only
/// meals the scan is sure of count: maybes stay off until the user keeps
/// them. Meals with no date can't be placed, so they're left out too.
class MealCalendar {
  MealCalendar(Iterable<FoundMeal> found) {
    for (final meal in found) {
      final taken = meal.taken;
      if (meal.verdict != MealVerdict.food || taken == null) continue;
      _days.putIfAbsent(dayOf(taken), () => []).add(meal);
    }
    for (final meals in _days.values) {
      meals.sort((a, b) => a.taken!.compareTo(b.taken!));
    }
  }

  final _days = <DateTime, List<FoundMeal>>{};

  /// Meals on the calendar.
  int get count => _days.values.fold(0, (n, meals) => n + meals.length);

  bool get isEmpty => _days.isEmpty;

  /// The first and last days with a meal.
  DateTime? get earliest =>
      _days.isEmpty ? null : _days.keys.reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get latest =>
      _days.isEmpty ? null : _days.keys.reduce((a, b) => a.isAfter(b) ? a : b);

  /// Days with at least one meal.
  int get daysWithMeals => _days.length;

  /// The meals on [day], earliest first.
  List<FoundMeal> on(DateTime day) => _days[dayOf(day)] ?? const [];

  /// The meals on [day] in each slot, earliest first, slots without any
  /// left out.
  Map<MealSlot, List<FoundMeal>> bySlot(DateTime day) {
    final slots = <MealSlot, List<FoundMeal>>{};
    for (final meal in on(day)) {
      slots.putIfAbsent(MealSlot.of(meal.taken!), () => []).add(meal);
    }
    return slots;
  }

  /// How many meals fall on [days].
  int countOn(Iterable<DateTime> days) =>
      days.fold(0, (n, day) => n + on(day).length);

  /// The days in [month] with a meal, in order.
  List<DateTime> daysIn(DateTime month) => [
    for (final day in _days.keys)
      if (day.year == month.year && day.month == month.month) day,
  ]..sort();

  /// The month to open on: this month if it has meals, otherwise the newest
  /// meal's month, otherwise this month.
  DateTime startMonth(DateTime today) {
    final thisMonth = monthOf(today);
    if (daysIn(thisMonth).isNotEmpty) return thisMonth;
    return switch (latest) {
      final newest? when newest.isBefore(thisMonth) => monthOf(newest),
      _ => thisMonth,
    };
  }

  /// The day to pick when [month] opens: today if it has meals, otherwise
  /// the month's last day with meals, otherwise today in the current month
  /// and the 1st elsewhere. Never a day to come: a photo dated ahead (a
  /// camera's clock can be wrong) can't be paged away from.
  DateTime defaultDay(DateTime month, DateTime today) {
    final thisMonth = monthOf(today) == monthOf(month);
    if (thisMonth && on(today).isNotEmpty) return dayOf(today);
    final days = daysIn(month).where((day) => !day.isAfter(today));
    if (days.isNotEmpty) return days.last;
    return thisMonth ? dayOf(today) : monthOf(month);
  }
}
