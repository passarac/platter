import 'package:flutter/material.dart';

import 'flows/photo_access_flow.dart';
import 'screens/find_meals_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/photo_library.dart';
import 'theme/platter_theme.dart';

void main() {
  runApp(const PlatterApp());
}

class PlatterApp extends StatelessWidget {
  const PlatterApp({super.key, this.photos = const DevicePhotoLibrary()});

  final PhotoLibrary photos;

  @override
  Widget build(BuildContext context) {
    final photoAccess = PhotoAccessFlow(
      library: photos,
      onScan: (context) => _comingSoon(context, 'Scanning for meals'),
      onEmptyCalendar: (context) => _comingSoon(context, 'The calendar'),
    );
    return MaterialApp(
      title: 'Platter',
      debugShowCheckedModeBanner: false,
      theme: buildPlatterTheme(),
      home: Builder(
        builder: (context) => WelcomeScreen(
          onGetStarted: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => FindMealsScreen(
                onFullAccess: () => photoAccess.askFull(context),
                onSelectedPhotos: () => photoAccess.askSelected(context),
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
