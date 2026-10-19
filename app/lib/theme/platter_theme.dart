import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colour tokens, mirroring the `:root` variables in html-mockups/platter.html.
abstract final class PlatterColors {
  static const ink = Color(0xFF1F2A44);
  static const ink2 = Color(0xFF2E3B5C);
  static const ink3 = Color(0xFF3B4868);
  static const muted = Color(0xFF8A97AE);
  static const yellow = Color(0xFFFFE07A);
  static const cream = Color(0xFFFFF8DC);
  static const nav = Color(0xFFFFF4C9);
  static const paper = Color(0xFFFFFDF6);
  static const blue = Color(0xFF2F5FD0);
  static const blueInk = Color(0xFF2450B8);
  static const red = Color(0xFFE5483B);
  static const mint = Color(0xFF9FDDC4);
  static const pink = Color(0xFFFF8FB8);
  static const empty = Color(0xFFF3F8FF);
  static const emptyLine = Color(0xFFA9BBD6);
}

/// Text styles: Bricolage Grotesque for headings, Nunito for body copy.
abstract final class PlatterText {
  static TextStyle head({double size = 32, Color color = PlatterColors.ink}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1.05,
        letterSpacing: -0.01 * size,
        color: color,
      );

  static TextStyle body({
    double size = 17,
    FontWeight weight = FontWeight.w700,
    Color color = PlatterColors.ink2,
  }) =>
      GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

ThemeData buildPlatterTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: PlatterColors.blue,
      primary: PlatterColors.blue,
      surface: PlatterColors.cream,
      onSurface: PlatterColors.ink,
    ),
    scaffoldBackgroundColor: PlatterColors.cream,
    fontFamily: GoogleFonts.nunito().fontFamily,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: PaperPageTransitionsBuilder(),
        TargetPlatform.android: PaperPageTransitionsBuilder(),
      },
    ),
  );
}

/// Easing for screen changes (the mockup's `cubic-bezier(.2,.8,.2,1)`).
const platterEase = Cubic(0.2, 0.8, 0.2, 1);

/// Every screen sits on the same paper, so instead of sliding the whole page
/// across, the new screen just fades in over the old one and the paper looks
/// still. [PaperGrid] drifts the content on top.
class PaperPageTransitionsBuilder extends PageTransitionsBuilder {
  const PaperPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 380);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: platterEase,
        reverseCurve: platterEase.flipped,
      ),
      child: child,
    );
  }
}
