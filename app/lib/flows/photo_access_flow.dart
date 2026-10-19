import 'package:flutter/material.dart';

import '../screens/no_access_screen.dart';
import '../screens/selected_photos_screen.dart';
import '../services/photo_library.dart';

/// Asks for photo access from the find-your-meals screen and routes to the
/// right next step for whatever the user chose in the system prompt.
class PhotoAccessFlow {
  const PhotoAccessFlow({
    required this.library,
    required this.onScan,
    required this.onEmptyCalendar,
  });

  final PhotoLibrary library;

  /// Next step once there are photos to look through.
  final void Function(BuildContext context) onScan;
  final void Function(BuildContext context) onEmptyCalendar;

  /// "Full access": the system prompt offers full, limited or none; follow
  /// whichever the user picked.
  Future<void> askFull(BuildContext context) async {
    final access = await library.requestAccess();
    if (context.mounted) _route(context, access);
  }

  /// "Selected photos". iOS has no way to ask for limited access directly, so
  /// a first-time user still sees the system prompt (where "Limit Access"
  /// opens the picker). Someone already limited gets the picker again.
  Future<void> askSelected(BuildContext context) async {
    var access = await library.currentAccess();
    if (access == PhotoAccess.notAsked) {
      access = await library.requestAccess();
    } else if (access == PhotoAccess.limited) {
      await library.changeSelection();
    }
    if (context.mounted) _route(context, access);
  }

  void _route(
    BuildContext context,
    PhotoAccess access, {
    bool replace = false,
  }) {
    final Widget next;
    switch (access) {
      case PhotoAccess.full:
        if (replace) Navigator.of(context).pop();
        onScan(context);
        return;
      case PhotoAccess.limited:
        next = SelectedPhotosScreen(
          library: library,
          onContinue: () => onScan(context),
          onAccessChanged: (a) => _route(context, a, replace: true),
        );
      case PhotoAccess.none:
        next = NoAccessScreen(
          library: library,
          onEmptyCalendar: () => onEmptyCalendar(context),
          onAccessChanged: (a) => _route(context, a, replace: true),
        );
      case PhotoAccess.notAsked:
        // The prompt was dismissed without an answer; stay put.
        return;
    }
    final route = MaterialPageRoute<void>(builder: (_) => next);
    final navigator = Navigator.of(context);
    replace ? navigator.pushReplacement(route) : navigator.push(route);
  }
}
