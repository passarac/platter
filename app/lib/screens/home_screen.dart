import 'dart:async';

import 'package:flutter/material.dart';

import '../services/food_scanner.dart';
import '../services/meal_store.dart';
import '../services/photo_library.dart';
import '../theme/platter_theme.dart';
import '../widgets/coming_soon.dart';
import '../widgets/sketch.dart';
import '../widgets/tab_bar.dart';
import 'calendar_screen.dart';
import 'timeline_screen.dart';

/// The app once onboarding is over: the tab bar, and the tab it shows. The
/// calendar comes first. Tabs keep their place when switched away from.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.scanner,
    required this.library,
    this.today,
  });

  /// Where the meals come from. Without a scanner the tabs are empty.
  final FoodScanner? scanner;
  final PhotoLibrary library;

  /// Today's date, for tests; by default the clock's.
  final DateTime? today;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final _store = MealStore(
    scanner: widget.scanner,
    library: widget.library,
  );

  AppTab _tab = AppTab.calendar;

  /// Tabs that have been opened, which stay built from then on.
  final _opened = {AppTab.calendar};

  final _calendar = GlobalKey<CalendarScreenState>();

  @override
  void initState() {
    super.initState();
    unawaited(_store.start());
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  void _select(AppTab tab) {
    switch (tab) {
      case AppTab.calendar || AppTab.timeline:
        setState(() {
          _tab = tab;
          _opened.add(tab);
        });
      case AppTab.map || AppTab.rediscover || AppTab.plated:
        comingSoon(context, tab.label);
    }
  }

  /// A day picked elsewhere opens in the calendar's day view.
  void _openDay(DateTime day) {
    _select(AppTab.calendar);
    _calendar.currentState?.openDay(day);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PlatterColors.paper,
      body: IndexedStack(
        index: _tab == AppTab.calendar ? 0 : 1,
        children: [
          _TabPage(
            active: _tab == AppTab.calendar,
            child: CalendarScreen(
              key: _calendar,
              store: _store,
              today: widget.today,
            ),
          ),
          if (_opened.contains(AppTab.timeline))
            _TabPage(
              active: _tab == AppTab.timeline,
              child: TimelineScreen(
                store: _store,
                today: widget.today,
                onOpenDay: _openDay,
              ),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: compactText(
        PlatterTabBar(current: _tab, onSelect: _select),
      ),
    );
  }
}

/// A tab's page, which fades in over the paper each time it's chosen (the
/// mockup's `fade` swap) and keeps its state in between.
class _TabPage extends StatefulWidget {
  const _TabPage({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<_TabPage>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: 1,
  );
  late final _opacity = CurvedAnimation(parent: _fade, curve: Curves.easeOut);

  @override
  void didUpdateWidget(_TabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _fade.value = 1;
      } else {
        _fade.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _opacity.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}
