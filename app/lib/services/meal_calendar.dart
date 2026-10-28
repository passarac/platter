import 'food_scanner.dart';

/// [t]'s day, at midnight local time.
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// The first day of [t]'s month.
DateTime monthOf(DateTime t) => DateTime(t.year, t.month);

/// The meals that belong on the calendar, by the day they were taken. Only
/// meals the scan is sure of count: maybes stay off until the user keeps
/// them. Meals with no date can't be placed, so they're left out too.
class MealCalendar {
  MealCalendar(Iterable<FoundMeal> found) {
    for (final meal in found) {
      final taken = meal.taken;
      if (meal.verdict != MealVerdict.food || taken == null) continue;
      _days.putIfAbsent(dayOf(taken), () => []).add(meal);
      count++;
    }
    for (final meals in _days.values) {
      meals.sort((a, b) => a.taken!.compareTo(b.taken!));
    }
  }

  final _days = <DateTime, List<FoundMeal>>{};

  /// Meals on the calendar.
  int count = 0;

  bool get isEmpty => _days.isEmpty;

  /// The first and last days with a meal.
  DateTime? get earliest =>
      _days.isEmpty ? null : _days.keys.reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get latest =>
      _days.isEmpty ? null : _days.keys.reduce((a, b) => a.isAfter(b) ? a : b);

  /// The meals on [day], earliest first.
  List<FoundMeal> on(DateTime day) => _days[dayOf(day)] ?? const [];

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
  /// and the 1st elsewhere.
  DateTime defaultDay(DateTime month, DateTime today) {
    final thisMonth = monthOf(today) == monthOf(month);
    if (thisMonth && on(today).isNotEmpty) return dayOf(today);
    final days = daysIn(month);
    if (days.isNotEmpty) return days.last;
    return thisMonth ? dayOf(today) : monthOf(month);
  }
}
