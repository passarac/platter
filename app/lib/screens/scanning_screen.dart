import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/food_scanner.dart';
import '../services/photo_library.dart';
import '../theme/platter_theme.dart';
import '../widgets/crayon.dart';
import '../widgets/onboarding_page.dart';
import '../widgets/paper_grid.dart';
import '../widgets/primary_button.dart';

/// Onboarding step 3: scans the photo library for meals, filling a grid with
/// the newest ones as they're found (`#s-scan` in the mockup).
///
/// The scan carries on without this screen, so nobody waits here longer
/// than [patience]: after that they can go on to their calendar while the
/// rest of their photos are checked.
class ScanningScreen extends StatefulWidget {
  const ScanningScreen({
    super.key,
    required this.scanner,
    required this.library,
    this.onSeeCalendar,
    this.onEmptyCalendar,
    this.patience = const Duration(minutes: 1),
  });

  final FoodScanner scanner;
  final PhotoLibrary library;
  final VoidCallback? onSeeCalendar;
  final VoidCallback? onEmptyCalendar;
  final Duration patience;

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen>
    with SingleTickerProviderStateMixin {
  ScanProgress _progress = const ScanProgress();
  StreamSubscription<ScanProgress>? _updates;

  /// [FoodScanner.start] has returned. Until then [_progress] may still be
  /// the last scan's.
  bool _started = false;

  late final Timer _patience;
  bool _waitedLongEnough = false;

  /// Only selected photos are visible, so a scan that finds nothing can
  /// offer to choose different ones.
  bool _limited = false;

  /// Months with a meal in them, counted once the scan finishes.
  int? _months;

  /// The picker is open; iOS can only show one.
  bool _picking = false;

  final _thumbs = <String, Uint8List?>{};

  late final _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  bool get _running => !_started || _progress.running;

  @override
  void initState() {
    super.initState();
    _updates = widget.scanner.progress.listen(_onProgress);
    _patience = Timer(widget.patience, () {
      if (mounted) setState(() => _waitedLongEnough = true);
    });
    widget.library.currentAccess().then((access) {
      if (mounted) setState(() => _limited = access == PhotoAccess.limited);
    });
    _scan();
  }

  @override
  void dispose() {
    // The scan itself keeps going: the calendar fills in as it finds more.
    _updates?.cancel();
    _patience.cancel();
    _run.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animateRunning();
  }

  Future<void> _scan() async {
    try {
      await widget.scanner.start();
    } catch (error, stack) {
      // Nothing to show for it, but after [ScanningScreen.patience] the
      // user can still go on to their calendar.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'platter',
          context: ErrorDescription('while starting the food scan'),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _started = true);
    _settle();
  }

  void _onProgress(ScanProgress progress) {
    setState(() => _progress = progress);
    for (final id in progress.preview) {
      if (!_thumbs.containsKey(id)) _loadThumb(id);
    }
    _settle();
  }

  /// Once the scan is done: stop running, and count the months for the
  /// title.
  void _settle() {
    _animateRunning();
    if (!_running && _months == null) _countMonths();
  }

  void _animateRunning() {
    final animate = _running && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_run.isAnimating) {
      _run.repeat(reverse: true);
    } else if (!animate && _run.isAnimating) {
      _run.stop();
    }
  }

  Future<void> _loadThumb(String id) async {
    _thumbs[id] = null;
    final bytes = await widget.library.thumbnail(id);
    if (mounted) setState(() => _thumbs[id] = bytes);
  }

  Future<void> _countMonths() async {
    _months = 0;
    final meals = await widget.scanner.meals();
    final months = {
      for (final meal in meals)
        if (meal.verdict == MealVerdict.food && meal.taken != null)
          (meal.taken!.year, meal.taken!.month),
    };
    if (mounted) setState(() => _months = months.length);
  }

  Future<void> _chooseDifferentPhotos() async {
    if (_picking) return;
    _picking = true;
    try {
      await widget.library.changeSelection();
    } finally {
      _picking = false;
    }
    if (!mounted) return;
    setState(() {
      _started = false;
      _months = null;
    });
    await _scan();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final running = _running;
    final meals = progress.meals;
    final empty = !running && meals == 0 && progress.maybes == 0;

    final String eyebrow;
    final String title;
    final List<String> notes;
    final List<Widget> actions;
    if (running && !_waitedLongEnough) {
      eyebrow = 'Finding your meals';
      title = meals == 0
          ? 'Looking through your photos…'
          : 'Found ${_plural(meals, 'meal')}…';
      notes = [if (progress.total > 0) _checked(progress)];
      actions = [const PrimaryButton(label: 'Scanning…', onPressed: null)];
    } else if (running) {
      eyebrow = 'Still looking';
      title = meals == 0
          ? 'Still looking through your photos'
          : 'Found ${_plural(meals, 'meal')} so far';
      notes = [
        _checked(progress),
        'The rest carry on in the background, and your calendar fills in '
            'as they do.',
      ];
      actions = [
        PrimaryButton(
          label: 'See my calendar',
          onPressed: widget.onSeeCalendar,
        ),
      ];
    } else if (empty) {
      eyebrow = 'All done';
      title = 'No meals in those photos';
      notes = [?_waitingNote(progress)];
      actions = _limited
          ? [
              PrimaryButton(
                label: 'Choose different photos',
                onPressed: _chooseDifferentPhotos,
              ),
              const SizedBox(height: 10),
              TextLink(
                label: 'Continue with an empty calendar',
                onPressed: widget.onEmptyCalendar,
              ),
            ]
          : [
              PrimaryButton(
                label: 'Continue with an empty calendar',
                onPressed: widget.onEmptyCalendar,
              ),
            ];
    } else {
      eyebrow = 'All done';
      final months = _months ?? 0;
      title = meals == 0
          ? 'Found ${_plural(progress.maybes, 'photo')} that might be meals'
          : _limited
          ? 'Found ${_plural(meals, 'meal')} in your '
                '${_plural(progress.total, 'photo')}'
          : months > 1
          ? 'Found ${_plural(meals, 'meal')} across $months months'
          : 'Found ${_plural(meals, 'meal')}';
      notes = [
        if (meals > 0 && progress.maybes > 0)
          'Plus ${_count(progress.maybes)} that might be meals, to check '
              'later',
        ?_waitingNote(progress),
      ];
      actions = [
        PrimaryButton(
          label: 'See my calendar',
          onPressed: widget.onSeeCalendar,
        ),
      ];
    }

    return Scaffold(
      body: PaperGrid(
        child: SafeArea(
          child: ArtLayout(
            minArtHeight: 12,
            header: Column(
              children: [
                const OnboardingTopBar(step: 1, showBack: false),
                _Burger(
                  pose: running
                      ? _Pose.search
                      : empty
                      ? _Pose.sit
                      : _Pose.cheer,
                  run: _run,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
                  child: Column(
                    children: [
                      Text(
                        eyebrow.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: PlatterText.body(
                          size: 15,
                          weight: FontWeight.w800,
                          color: PlatterColors.ink3,
                        ).copyWith(letterSpacing: 0.6),
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 66),
                        child: Center(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              style: PlatterText.head(size: 30)
                                  .copyWith(height: 1.1),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ProgressBar(
                        value: progress.total == 0
                            ? (running ? 0 : 1)
                            : progress.checked / progress.total,
                      ),
                      const SizedBox(height: 8),
                      for (final note in notes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            note,
                            textAlign: TextAlign.center,
                            style: PlatterText.body(
                              size: 14,
                              color: PlatterColors.ink3,
                            ).copyWith(height: 1.35),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: _FoundGrid(ids: progress.preview, thumbs: _thumbs),
                ),
              ],
            ),
            art: const SizedBox.shrink(),
            footer: Padding(
              padding: const EdgeInsets.fromLTRB(28, 6, 28, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: actions,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "1,754 of 11,191 photos checked".
String _checked(ScanProgress progress) =>
    '${_count(progress.checked)} of ${_plural(progress.total, 'photo')} '
    'checked';

String? _waitingNote(ScanProgress progress) => progress.waitingForWifi == 0
    ? null
    : '${_plural(progress.waitingForWifi, 'photo')} in iCloud will be '
          'checked on Wi-Fi';

String _plural(int n, String word) => '${_count(n)} $word${n == 1 ? '' : 's'}';

/// [n] with thousands separators: 11191 → "11,191".
String _count(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

enum _Pose { search, cheer, sit }

/// Bunjamin the burger: running with a magnifying glass while the scan
/// runs, then cheering, or sitting if nothing turned up.
class _Burger extends StatelessWidget {
  const _Burger({required this.pose, required this.run});

  final _Pose pose;

  /// Drives the running wobble (`@keyframes run` in the mockup).
  final Animation<double> run;

  @override
  Widget build(BuildContext context) {
    final (asset, label) = switch (pose) {
      _Pose.search => (
        'burger_search',
        'Bunjamin the burger running with a magnifying glass, searching for '
            'meals',
      ),
      _Pose.cheer => ('burger_cheer', 'Bunjamin the burger cheering'),
      _Pose.sit => ('burger_sit', 'Bunjamin the burger sitting down'),
    };
    final art = Crayon(
      child: SvgPicture.asset(
        'assets/illustrations/$asset.svg',
        width: 150,
        height: 160,
        semanticsLabel: label,
      ),
    );
    return SizedBox(
      width: 150,
      height: 160,
      child: pose != _Pose.search
          ? art
          : AnimatedBuilder(
              animation: run,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(run.value);
                return Transform.translate(
                  offset: Offset(-3 + 6 * t, -5 * t),
                  child: Transform.rotate(
                    angle: (-2 + 4 * t) * math.pi / 180,
                    child: child,
                  ),
                );
              },
              child: art,
            ),
    );
  }
}

/// The sketchy progress pill (`.progress` in the mockup).
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final percent = (value.clamp(0, 1) * 100).round();
    return Semantics(
      label: 'Scan progress',
      value: '$percent%',
      child: SizedBox(
        height: 16,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Crayon(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: PlatterColors.paper,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: PlatterColors.ink, width: 2.5),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(3),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: value.clamp(0, 1)),
                duration: const Duration(milliseconds: 200),
                builder: (context, value, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: PlatterColors.blue,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Twelve slots that fill with the newest meals as they're found, each
/// popping in at a slight tilt (`.found` in the mockup).
class _FoundGrid extends StatelessWidget {
  const _FoundGrid({required this.ids, required this.thumbs});

  final List<String> ids;
  final Map<String, Uint8List?> thumbs;

  static const _tilts = [-3, 2, -2, 3, 2, -3, 1, -2, 3, -1, 2, -2];

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: GridView.count(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          for (var i = 0; i < _tilts.length; i++)
            if (i < ids.length)
              _Tile(
                key: ValueKey(ids[i]),
                bytes: thumbs[ids[i]],
                tilt: _tilts[i],
              )
            else
              const CustomPaint(painter: _GhostPainter()),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.bytes, required this.tilt});

  final Uint8List? bytes;
  final int tilt;

  /// Overshoots, like the mockup's `cubic-bezier(.3,1.6,.5,1)`.
  static const _pop = Cubic(0.3, 1.6, 0.5, 1);

  @override
  Widget build(BuildContext context) {
    final bytes = this.bytes;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      builder: (context, t, child) => Opacity(
        opacity: math.min(1, t * 1.75),
        child: Transform.rotate(
          angle: tilt * math.pi / 180,
          child: Transform.scale(
            scale: 0.4 + 0.6 * _pop.transform(t),
            child: child,
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Crayon(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: PlatterColors.paper,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: PlatterColors.ink, width: 2.5),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: bytes == null
                  ? const ColoredBox(color: PlatterColors.empty)
                  : Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An empty slot: a dashed rounded square (`.found .ghost`).
class _GhostPainter extends CustomPainter {
  const _GhostPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          const Radius.circular(14),
        ),
      );
    final dashes = Path();
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        dashes.addPath(metric.extractPath(d, d + 6), Offset.zero);
      }
    }
    canvas.drawPath(
      dashes,
      Paint()
        ..color = PlatterColors.ink.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_GhostPainter oldDelegate) => false;
}
