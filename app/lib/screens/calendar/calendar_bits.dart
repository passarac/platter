import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/food_scanner.dart';
import '../../services/meal_calendar.dart';
import '../../theme/platter_theme.dart';
import '../../widgets/coming_soon.dart';
import '../../widgets/crayon.dart';
import '../../widgets/sketch.dart';

/// Words, icons and small pieces the calendar views share.

const monthNames = [
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

/// "Oct".
String shortMonth(int month) => monthNames[month - 1].substring(0, 3);

/// "October 2026", or just "October" when the year is [unless].
String monthYear(DateTime month, {int? unless}) =>
    '${monthNames[month.month - 1]}'
    '${month.year == unless ? '' : ' ${month.year}'}';

const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdayLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

/// "Sat 17 Oct".
String shortDate(DateTime day) =>
    '${weekdayShort[day.weekday - 1]} ${day.day} ${shortMonth(day.month)}';

/// "Saturday 17 October".
String longDate(DateTime day) =>
    '${weekdayLong[day.weekday - 1]} ${day.day} ${monthNames[day.month - 1]}';

/// "7:42 PM", or 24-hour if the phone is set that way.
String formatTime(BuildContext context, DateTime t) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(t),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// Loaded thumbnails by photo id; null while one is still loading.
typedef Thumbs = Map<String, Uint8List?>;

/// A photo filling its box with rounded corners, or the empty-cell colour
/// until it loads.
class PhotoBox extends StatelessWidget {
  const PhotoBox({super.key, required this.bytes, required this.radius});

  final Uint8List? bytes;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bytes = this.bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: bytes == null
          ? const ColoredBox(color: PlatterColors.empty)
          : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}

/// The small ink circle with a count (`.badge`).
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PlatterColors.ink,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PlatterColors.paper, width: 1.5),
      ),
      child: Text(
        text,
        style: PlatterText.body(
          size: 11,
          weight: FontWeight.w800,
          color: Colors.white,
        ).copyWith(height: 1),
      ),
    );
  }
}

class Baobie extends StatelessWidget {
  const Baobie({super.key, required this.size});

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

/// The mockup's line icons, as SVG so they match it stroke for stroke.
Widget calIcon(String svg, double size, {Color color = PlatterColors.ink}) =>
    SvgPicture.string(
      svg,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: color),
    );

abstract final class CalIcons {
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
}

/// A meal's photo with when it was taken and how many shots there are
/// (`.mcard`, `.mcard.wide`).
class MealCard extends StatelessWidget {
  const MealCard({
    super.key,
    required this.meal,
    required this.thumb,
    required this.wide,
  });

  final FoundMeal meal;
  final Uint8List? thumb;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final time = formatTime(context, meal.taken!);
    final shots = plural(meal.photos.length, 'photo');
    return Semantics(
      button: true,
      label: '${MealSlot.of(meal.taken!).label} at $time, $shots, open details',
      child: ExcludeSemantics(
        child: Pressable(
          onTap: () => comingSoon(context, 'Meal details'),
          child: SketchBox(
            fill: Colors.white,
            radius: wide ? 18 : 16,
            shadow: wide ? 4 : 0,
            child: Padding(
              padding: EdgeInsets.all(wide ? 5 : 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: wide ? 148 : 100,
                    width: double.infinity,
                    child: PhotoBox(bytes: thumb, radius: wide ? 13 : 12),
                  ),
                  if (wide)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(7, 7, 7, 4),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 8,
                        children: [
                          Text(time, style: PlatterText.head(size: 17)),
                          Text(
                            shots,
                            style: PlatterText.body(
                              size: 13,
                              color: PlatterColors.ink3,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 6, 5, 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            time,
                            style: PlatterText.body(
                              size: 14,
                              weight: FontWeight.w800,
                              color: PlatterColors.ink,
                            ).copyWith(height: 1.2),
                          ),
                          Text(
                            shots,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PlatterText.body(
                              size: 12,
                              color: PlatterColors.ink3,
                            ),
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
