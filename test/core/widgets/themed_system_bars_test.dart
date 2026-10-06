import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/themed_system_bars.dart';

/// The status bar follows the room: a screen with no AppBar (most of them)
/// used to leave the dark room's white clock on the light room's cream.
void main() {
  Future<SystemUiOverlayStyle?> styleIn(
    WidgetTester tester,
    Brightness brightness, {
    bool appBar = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        builder: (context, child) => ThemedSystemBars(child: child!),
        // No AppBar, like the media page and the shelf page; or the
        // transparent one most screens have.
        home: Scaffold(
          appBar: appBar ? AppBar(title: const Text('Dashboard')) : null,
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    return SystemChrome.latestStyle;
  }

  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets('the light room gets dark glyphs', (tester) async {
    final style = await styleIn(tester, Brightness.light);
    expect(style?.statusBarBrightness, Brightness.light);
    expect(style?.statusBarIconBrightness, Brightness.dark);
  }, variant: ios);

  testWidgets('a transparent AppBar in the light room gets dark glyphs too', (
    tester,
  ) async {
    final style = await styleIn(tester, Brightness.light, appBar: true);
    expect(style?.statusBarBrightness, Brightness.light);
    expect(style?.statusBarIconBrightness, Brightness.dark);
  }, variant: ios);

  testWidgets('the dark room gets light glyphs', (tester) async {
    final style = await styleIn(tester, Brightness.dark);
    expect(style?.statusBarBrightness, Brightness.dark);
    expect(style?.statusBarIconBrightness, Brightness.light);
  }, variant: ios);

  test('the bar itself stays clear: the room shows through it', () {
    for (final brightness in Brightness.values) {
      expect(
        ThemedSystemBars.styleFor(brightness).statusBarColor,
        const Color(0x00000000),
      );
    }
  });
}
