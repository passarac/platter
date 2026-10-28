import 'package:flutter/material.dart';

import '../../services/meal_calendar.dart';
import '../../theme/platter_theme.dart';
import '../../widgets/sketch.dart';
import 'calendar_bits.dart';

/// The year as twelve cards of dots, one per day (`yearBody` in the
/// mockup, without its home/out and cuisine colouring, which the scan
/// doesn't know yet). Tapping a month opens it.
class YearView extends StatelessWidget {
  const YearView({
    super.key,
    required this.year,
    required this.today,
    required this.meals,
    required this.onOpenMonth,
  });

  final int year;
  final DateTime today;
  final MealCalendar meals;
  final ValueChanged<DateTime> onOpenMonth;

  @override
  Widget build(BuildContext context) {
    final days = [
      for (var m = 1; m <= 12; m++) meals.daysIn(DateTime(year, m)).length,
    ].fold(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              ExcludeSemantics(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: const [
                    _Legend(kind: _Dot.meals, label: 'Meals'),
                    _Legend(kind: _Dot.none, label: 'No photos'),
                    _Legend(kind: _Dot.today, label: 'Today'),
                  ],
                ),
              ),
              Text(
                '${plural(days, 'day')} with meals',
                style: PlatterText.body(
                  size: 13,
                  weight: FontWeight.w800,
                  color: PlatterColors.ink3,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              for (var row = 0; row < 4; row++)
                Padding(
                  padding: EdgeInsets.only(top: row == 0 ? 0 : 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var column = 0; column < 3; column++) ...[
                        if (column > 0) const SizedBox(width: 10),
                        Expanded(
                          child: _MonthCard(
                            month: DateTime(year, row * 3 + column + 1),
                            today: today,
                            meals: meals,
                            onOpen: onOpenMonth,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _Dot { meals, none, future, today }

class _Legend extends StatelessWidget {
  const _Legend({required this.kind, required this.label});

  final _Dot kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(size: const Size(11, 11), painter: _DotPainter(kind)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: PlatterText.body(size: 13, color: PlatterColors.ink3),
          ),
        ),
      ],
    );
  }
}

/// One month (`.ymonth`): its name, how many days had meals, and a dot for
/// every day. This month is on nav yellow with a blue border.
class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.month,
    required this.today,
    required this.meals,
    required this.onOpen,
  });

  final DateTime month;
  final DateTime today;
  final MealCalendar meals;
  final ValueChanged<DateTime> onOpen;

  @override
  Widget build(BuildContext context) {
    final now = month == monthOf(today);
    final future = month.isAfter(today);
    final days = meals.daysIn(month).length;
    final name = monthNames[month.month - 1];
    final card = SketchBox(
      fill: now ? PlatterColors.nav : Colors.white,
      border: now ? PlatterColors.blue : PlatterColors.ink,
      radius: 14,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 7, 7, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      shortMonth(month.month),
                      style: PlatterText.head(size: 14),
                    ),
                  ),
                  if (!future)
                    Text(
                      '$days',
                      style: PlatterText.body(
                        size: 11,
                        weight: FontWeight.w800,
                        color: PlatterColors.ink3,
                      ),
                    ),
                ],
              ),
            ),
            Center(
              child: CustomPaint(
                size: const Size(_DotsPainter.width, _DotsPainter.height),
                painter: _DotsPainter(month: month, today: today, meals: meals),
              ),
            ),
          ],
        ),
      ),
    );
    if (future) {
      return Semantics(
        label: name,
        child: ExcludeSemantics(child: card),
      );
    }
    return Semantics(
      button: true,
      label: '$name, ${plural(days, 'day')} with meals',
      child: ExcludeSemantics(
        child: Pressable(onTap: () => onOpen(month), child: card),
      ),
    );
  }
}

/// A month's days as dots in weeks (`.ydots`): filled where there were
/// meals, hollow where not, faint for days to come, today ringed red.
class _DotsPainter extends CustomPainter {
  const _DotsPainter({
    required this.month,
    required this.today,
    required this.meals,
  });

  final DateTime month;
  final DateTime today;
  final MealCalendar meals;

  static const _size = 10.0;
  static const _gap = 3.0;
  static const width = 7 * _size + 6 * _gap;

  /// Six rows: the most any month needs, so every card is the same height.
  static const height = 6 * _size + 5 * _gap;

  @override
  void paint(Canvas canvas, Size size) {
    final lead = month.weekday - DateTime.monday;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    for (var d = 1; d <= days; d++) {
      final slot = lead + d - 1;
      final day = DateTime(month.year, month.month, d);
      final kind = day == today
          ? _Dot.today
          : day.isAfter(today)
          ? _Dot.future
          : meals.on(day).isEmpty
          ? _Dot.none
          : _Dot.meals;
      final center = Offset(
        slot % 7 * (_size + _gap) + _size / 2,
        slot ~/ 7 * (_size + _gap) + _size / 2,
      );
      _DotPainter.draw(
        canvas,
        center,
        _size / 2,
        kind,
        filled: kind == _Dot.today && meals.on(day).isNotEmpty,
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      month != old.month || today != old.today || meals != old.meals;
}

class _DotPainter extends CustomPainter {
  const _DotPainter(this.kind);

  final _Dot kind;

  @override
  void paint(Canvas canvas, Size size) => draw(
    canvas,
    size.center(Offset.zero),
    size.shortestSide / 2,
    kind,
    filled: kind == _Dot.meals,
  );

  /// Draws one day. [filled] says whether today's dot has meals.
  static void draw(
    Canvas canvas,
    Offset center,
    double radius,
    _Dot kind, {
    required bool filled,
  }) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final r = radius - 0.75;
    switch (kind) {
      case _Dot.meals:
        canvas.drawCircle(center, r, Paint()..color = PlatterColors.blue);
        canvas.drawCircle(center, r, stroke..color = PlatterColors.ink);
      case _Dot.none:
        canvas.drawCircle(center, r, stroke..color = PlatterColors.emptyLine);
      case _Dot.future:
        // A faint dotted ring for a day still to come.
        final ring = Path()
          ..addOval(Rect.fromCircle(center: center, radius: r));
        final dots = Path();
        for (final metric in ring.computeMetrics()) {
          for (var d = 0.0; d < metric.length; d += 4) {
            dots.addPath(metric.extractPath(d, d + 2), Offset.zero);
          }
        }
        canvas.drawPath(dots, stroke..color = const Color(0xFFE3E9F2));
      case _Dot.today:
        if (filled) {
          canvas.drawCircle(center, r, Paint()..color = PlatterColors.blue);
          canvas.drawCircle(center, r, stroke..color = PlatterColors.ink);
        } else {
          canvas.drawCircle(center, r, stroke..color = PlatterColors.emptyLine);
        }
        // `box-shadow: 0 0 0 1.5px paper, 0 0 0 3.5px red`.
        canvas.drawCircle(
          center,
          radius + 0.75,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = PlatterColors.paper,
        );
        canvas.drawCircle(
          center,
          radius + 2.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = PlatterColors.red,
        );
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => kind != old.kind;
}
