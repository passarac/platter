import 'package:flutter/material.dart';

import 'screens/welcome_screen.dart';
import 'theme/platter_theme.dart';

void main() {
  runApp(const PlatterApp());
}

class PlatterApp extends StatelessWidget {
  const PlatterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Platter',
      debugShowCheckedModeBanner: false,
      theme: buildPlatterTheme(),
      home: Builder(
        builder: (context) => WelcomeScreen(
          onGetStarted: () => _comingSoon(context, 'Photo access'),
          onRestore: () => _comingSoon(context, 'Restore from backup'),
        ),
      ),
    );
  }

  static void _comingSoon(BuildContext context, String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what is coming soon.')));
  }
}
