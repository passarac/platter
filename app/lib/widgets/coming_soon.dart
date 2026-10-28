import 'package:flutter/material.dart';

/// Says that [what] isn't built yet, in place of the screen it will open.
void comingSoon(BuildContext context, String what) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$what is coming soon.')));
}
