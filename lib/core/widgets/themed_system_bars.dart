import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The system bars drawn in the room's ink: light glyphs over the dark room,
/// dark glyphs over the light one.
///
/// Wraps the whole app once (`CupolaApp`'s builder). Most screens have no
/// `AppBar`, the only widget that tells the system on its own, so without this
/// the light room kept the dark room's white clock and battery on cream. A
/// screen with an `AppBar` still answers for the strip under it.
class ThemedSystemBars extends StatelessWidget {
  const ThemedSystemBars({super.key, required this.child});

  final Widget child;

  /// The style for a room of [brightness]. The status bar stays clear (the
  /// room shows through it); only the glyphs change.
  static SystemUiOverlayStyle styleFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      // iOS reads the bar's brightness (dark bar, light glyphs); Android
      // reads the glyphs' own.
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    );
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: styleFor(Theme.of(context).brightness),
    child: child,
  );
}
