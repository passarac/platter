import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/platter_theme.dart';
import 'crayon.dart';
import 'sketch.dart';

/// The five tabs along the bottom of the app, in order.
enum AppTab {
  calendar('Calendar', _TabIcons.calendar),
  timeline('Timeline', _TabIcons.timeline),
  map('Map', _TabIcons.map),
  rediscover('Rediscover', _TabIcons.rediscover),
  plated('Plated', _TabIcons.plated);

  const AppTab(this.label, this.icon);

  final String label;
  final String icon;
}

/// The tab bar (`.tabbar`): the mockup's line icons on nav yellow, the
/// current one in blue with a little bounce as it's chosen.
class PlatterTabBar extends StatelessWidget {
  const PlatterTabBar({
    super.key,
    required this.current,
    required this.onSelect,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return PaperBand(
      fill: PlatterColors.nav,
      edgeAtTop: true,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
          child: Row(
            children: [
              for (final tab in AppTab.values)
                Expanded(
                  child: _Tab(
                    tab: tab,
                    selected: tab == current,
                    onTap: tab == current ? null : () => onSelect(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.tab, required this.selected, required this.onTap});

  final AppTab tab;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PlatterColors.blue : PlatterColors.ink3;
    final icon = Crayon(
      child: SvgPicture.string(
        tab.icon,
        width: 24,
        height: 24,
        theme: SvgTheme(currentColor: color),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Pop(selected: selected, child: icon),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    tab.label,
                    style: PlatterText.body(
                      size: 12,
                      weight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The chosen tab's icon hops up and back (`tabPop`) as it's chosen: not
/// when the bar first appears with it already chosen.
class _Pop extends StatefulWidget {
  const _Pop({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> with SingleTickerProviderStateMixin {
  static const _spring = Cubic(0.3, 1.4, 0.5, 1);

  late final _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    value: 1,
  );
  late final _eased = CurvedAnimation(parent: _hop, curve: _spring);

  @override
  void didUpdateWidget(_Pop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected &&
        !oldWidget.selected &&
        !MediaQuery.disableAnimationsOf(context)) {
      _hop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _eased.dispose();
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _eased,
      builder: (context, child) {
        final t = _eased.value;
        // Up to the 40% mark, then back.
        final peak = t < 0.4 ? t / 0.4 : 1 - (t - 0.4) / 0.6;
        return Transform.translate(
          offset: Offset(0, -4 * peak),
          child: Transform.scale(scale: 1 + 0.12 * peak, child: child),
        );
      },
      child: widget.child,
    );
  }
}

abstract final class _TabIcons {
  static const _stroke =
      'fill="none" stroke="currentColor" stroke-width="2.4" '
      'stroke-linecap="round" stroke-linejoin="round"';

  static const calendar =
      '<svg viewBox="0 0 24 24" $_stroke>'
      '<rect x="3" y="5" width="18" height="16" rx="3"/>'
      '<path d="M3 10h18M8 3v4M16 3v4"/></svg>';
  static const timeline =
      '<svg viewBox="0 0 24 24" $_stroke>'
      '<rect x="4" y="3" width="16" height="7" rx="2"/>'
      '<rect x="4" y="12" width="16" height="4" rx="1.5"/>'
      '<rect x="4" y="18" width="16" height="3" rx="1.5"/></svg>';
  static const map =
      '<svg viewBox="0 0 24 24" $_stroke>'
      '<path d="M9 4l-6 2v14l6-2 6 2 6-2V4l-6 2-6-2zM9 4v14M15 6v14"/></svg>';
  static const rediscover =
      '<svg viewBox="0 0 24 24" $_stroke>'
      '<path d="M4 7h3l10 10h3M4 17h3l3-3M14 10l3-3h3M18 4l2 3-2 3M18 14l2 '
      '3-2 3"/></svg>';
  static const plated =
      '<svg viewBox="0 0 24 24" $_stroke>'
      '<circle cx="12" cy="12" r="9"/>'
      '<path d="M12 7.6l1.3 2.7 2.9.4-2.1 2 .5 2.9-2.6-1.4-2.6 1.4.5-2.9-2.1-2 '
      '2.9-.4z"/></svg>';
}
