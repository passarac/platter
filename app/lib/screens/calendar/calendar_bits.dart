import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/platter_theme.dart';
import '../../widgets/crayon.dart';

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

/// Fixed-size controls can only take so much text growth.
Widget compactText(Widget child) =>
    MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child);

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
