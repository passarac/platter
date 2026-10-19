import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/photo_library.dart';
import '../theme/platter_theme.dart';
import '../widgets/crayon.dart';
import '../widgets/onboarding_page.dart';
import '../widgets/primary_button.dart';
import '../widgets/settings_prompt.dart';

/// Shown after the user picks "Limit Access": confirms what the calendar will
/// contain and lets them change the selection.
class SelectedPhotosScreen extends StatefulWidget {
  const SelectedPhotosScreen({
    super.key,
    required this.library,
    this.onContinue,
    this.onAccessChanged,
  });

  final PhotoLibrary library;
  final VoidCallback? onContinue;

  /// Called when the user comes back from Settings with access other than
  /// limited.
  final ValueChanged<PhotoAccess>? onAccessChanged;

  @override
  State<SelectedPhotosScreen> createState() => _SelectedPhotosScreenState();
}

class _SelectedPhotosScreenState extends State<SelectedPhotosScreen>
    with WidgetsBindingObserver {
  int? _count;
  List<Uint8List> _thumbs = const [];

  /// The picker is open; iOS can only show one.
  bool _picking = false;

  /// [SelectedPhotosScreen.onAccessChanged] has fired and this screen is on
  /// its way out; later resumes mustn't navigate again.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The selection can also be changed from Settings while we're backgrounded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }

  Future<void> _onResume() async {
    final access = await widget.library.currentAccess();
    if (!mounted || _leaving) return;
    if (access == PhotoAccess.limited) {
      await _refresh();
    } else {
      _leaving = true;
      widget.onAccessChanged?.call(access);
    }
  }

  Future<void> _refresh() async {
    final count = await widget.library.photoCount();
    final thumbs = await widget.library.recentThumbnails(4);
    if (!mounted) return;
    setState(() {
      _count = count;
      _thumbs = thumbs;
    });
  }

  Future<void> _changeSelection() async {
    if (_picking) return;
    _picking = true;
    try {
      await widget.library.changeSelection();
    } finally {
      _picking = false;
    }
    await _refresh();
  }

  Future<void> _allowAllPhotos() async {
    final go = await askToOpenSettings(
      context,
      title: 'Allow all photos in Settings',
      want: PhotoAccess.full,
    );
    if (go) await widget.library.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return OnboardingPage(
      art: Crayon(
        child: SvgPicture.asset(
          'assets/illustrations/selected_photos.svg',
          fit: BoxFit.contain,
          semanticsLabel: 'A grid of photos where only three are ticked',
        ),
      ),
      children: [
        Text('Just your selected photos', style: PlatterText.head(size: 32)),
        const SizedBox(height: 12),
        _CountPill(count: count, thumbs: _thumbs),
        const SizedBox(height: 12),
        Text(
          "Your calendar will only contain the photos you've selected. You "
          'can widen access anytime in Settings.',
          style: PlatterText.body().copyWith(height: 1.45),
        ),
        const SizedBox(height: 28),
        PrimaryButton(
          label: 'Continue',
          onPressed: count != null && count > 0 ? widget.onContinue : null,
        ),
        const SizedBox(height: 10),
        // iOS only shows the access prompt once, so going from selected to
        // all photos has to happen in Settings; _onResume picks it up.
        Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 16,
          children: [
            TextLink(label: 'Change selection', onPressed: _changeSelection),
            TextLink(label: 'Allow all photos', onPressed: _allowAllPhotos),
          ],
        ),
      ],
    );
  }
}

/// "▣▣▣ 12 photos selected" (`.count-pill` in the mockup).
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.thumbs});

  final int? count;
  final List<Uint8List> thumbs;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    final label = count == null
        ? 'Counting photos…'
        : '$count photo${count == 1 ? '' : 's'} selected';
    final radius = BorderRadius.circular(999);
    return Stack(
      children: [
        Positioned.fill(
          child: Crayon(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: PlatterColors.paper,
                borderRadius: radius,
                border: Border.all(color: PlatterColors.ink, width: 2),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (thumbs.isNotEmpty) ...[
                // Each thumbnail overlaps the previous one by 6px.
                SizedBox(
                  width: 22 + 16.0 * (thumbs.length - 1),
                  height: 22,
                  child: Stack(
                    children: [
                      for (final (i, bytes) in thumbs.indexed)
                        Positioned(
                          left: 16.0 * i,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: PlatterColors.paper,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: PlatterColors.ink,
                                width: 1.5,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.memory(bytes, fit: BoxFit.cover),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  style: PlatterText.body(
                    size: 14,
                    weight: FontWeight.w800,
                    color: PlatterColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
