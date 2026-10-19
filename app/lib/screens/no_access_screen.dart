import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/photo_library.dart';
import '../theme/platter_theme.dart';
import '../widgets/crayon.dart';
import '../widgets/onboarding_page.dart';
import '../widgets/primary_button.dart';
import '../widgets/settings_prompt.dart';

/// Shown when photo access is denied: offers Settings, or an empty calendar.
class NoAccessScreen extends StatefulWidget {
  const NoAccessScreen({
    super.key,
    required this.library,
    this.onEmptyCalendar,
    this.onAccessChanged,
  });

  final PhotoLibrary library;
  final VoidCallback? onEmptyCalendar;

  /// Called when the user comes back from Settings having allowed access.
  final ValueChanged<PhotoAccess>? onAccessChanged;

  @override
  State<NoAccessScreen> createState() => _NoAccessScreenState();
}

class _NoAccessScreenState extends State<NoAccessScreen>
    with WidgetsBindingObserver {
  /// [NoAccessScreen.onAccessChanged] has fired and this screen is on its way
  /// out; later resumes mustn't navigate again.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }

  Future<void> _onResume() async {
    final access = await widget.library.currentAccess();
    if (!mounted || _leaving) return;
    if (access == PhotoAccess.full || access == PhotoAccess.limited) {
      _leaving = true;
      widget.onAccessChanged?.call(access);
    }
  }

  Future<void> _allowAccess() async {
    final go = await askToOpenSettings(
      context,
      title: 'Allow photo access in Settings',
      want: PhotoAccess.full,
    );
    if (go) await widget.library.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingPage(
      art: Crayon(
        child: SvgPicture.asset(
          'assets/illustrations/baobie_wave.svg',
          width: 170,
          semanticsLabel: 'Baobie the bao waving hello',
        ),
      ),
      children: [
        Text('No photos? No problem.', style: PlatterText.head(size: 32)),
        const SizedBox(height: 12),
        Text(
          "Platter builds your calendar from meal photos. Without access, "
          "you'll start with an empty calendar and add meals yourself.",
          style: PlatterText.body().copyWith(height: 1.45),
        ),
        const SizedBox(height: 12),
        Text(
          'You can turn on photo access later in Settings.',
          style: PlatterText.body(
            size: 14,
            color: PlatterColors.ink3,
          ).copyWith(height: 1.4),
        ),
        const SizedBox(height: 28),
        PrimaryButton(
          label: 'Allow access in Settings',
          onPressed: _allowAccess,
        ),
        const SizedBox(height: 10),
        SecondaryButton(
          label: 'Start with an empty calendar',
          onPressed: widget.onEmptyCalendar,
        ),
      ],
    );
  }
}
