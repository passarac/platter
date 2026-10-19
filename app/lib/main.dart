import 'package:flutter/material.dart';

import 'screens/find_meals_screen.dart';
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
          onGetStarted: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => FindMealsScreen(
                onFullAccess: () => _comingSoon(context, 'Full photo access'),
                onSelectedPhotos: () =>
                    _comingSoon(context, 'Selected photo access'),
              ),
            ),
          ),
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
