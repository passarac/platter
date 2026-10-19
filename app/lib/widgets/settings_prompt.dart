import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/photo_library.dart';

/// Once photo access has been set, only Settings can change it, so this
/// explains what to tap there. Returns whether the user chose to go; the
/// caller opens Settings. [want] is the access they're after:
/// [PhotoAccess.full] or [PhotoAccess.limited].
Future<bool> askToOpenSettings(
  BuildContext context, {
  required String title,
  required PhotoAccess want,
}) async {
  final go = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      // Large text would otherwise push the buttons off a Material dialog;
      // the iOS alert scrolls on its own.
      scrollable: true,
      title: Text(title),
      content: Text(
        "Your phone only lets you change this in Settings. We'll open "
        "Platter's settings for you: ${_settingsSteps(context, want)}",
      ),
      actions: [
        _DialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context, false),
        ),
        _DialogAction(
          label: 'Go to Settings',
          isDefault: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return go ?? false;
}

/// Where [want] lives on Platter's settings page.
String _settingsSteps(BuildContext context, PhotoAccess want) {
  final full = want == PhotoAccess.full;
  if (Theme.of(context).platform == TargetPlatform.android) {
    final option = full ? 'Allow all' : 'Allow limited access';
    return 'tap Permissions, then Photos and videos, and choose $option.';
  }
  // iOS 17 renamed "All Photos" and "Selected Photos" to "Full Access" and
  // "Limited Access".
  final major = Platform.isIOS
      ? int.tryParse(
          RegExp(r'\d+').stringMatch(Platform.operatingSystemVersion) ?? '',
        )
      : null;
  final legacy = major != null && major < 17;
  final option = full
      ? (legacy ? 'All Photos' : 'Full Access')
      : (legacy ? 'Selected Photos' : 'Limited Access');
  return 'tap Photos, then choose $option.';
}

/// A dialog button in the platform's style: a Cupertino action on iOS, a
/// text button elsewhere.
class _DialogAction extends StatelessWidget {
  const _DialogAction({
    required this.label,
    required this.onPressed,
    this.isDefault = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return CupertinoDialogAction(
        isDefaultAction: isDefault,
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return TextButton(onPressed: onPressed, child: Text(label));
  }
}
