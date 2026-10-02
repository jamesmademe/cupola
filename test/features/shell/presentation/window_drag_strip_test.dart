import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/platform/desktop_window.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/shell/presentation/desktop/window_chrome.dart';

/// The strip above a screen the shell does not host — onboarding, and the flows
/// that live with it on the root navigator.
///
/// Annotation `onb1` is explicit that it is load-bearing rather than decoration,
/// and each of its three jobs is a test below.
Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  List<String>? trail,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Column(
          children: [
            trail == null
                ? const WindowDragStrip()
                : WindowDragStrip(trail: trail),
          ],
        ),
      ),
    ),
  );
}

Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) {
  debugDefaultTargetPlatformOverride = platform;
  return body().whenComplete(() {
    debugDefaultTargetPlatformOverride = null;
  });
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('WindowDragStrip', () {
    // The strip carries the same breadcrumb the shell prints everywhere else —
    // "Cupola › Setup" — which is what makes the strip above a beat recognisably
    // the strip above a page. It carries no window *title*; the Chrome sheet
    // forbids one, and the trail is the title.
    testWidgets('carries the trail on all three desktop shells', (
      tester,
    ) async {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        await _onPlatform(platform, () async {
          await _pump(tester);

          expect(find.text(kAppName), findsOneWidget, reason: '$platform');
          expect(find.text('Setup'), findsOneWidget, reason: '$platform');
        });
      }
    });

    // The bug this replaced: the old guard bailed on `!drawsOwnButtons`, which
    // is exactly the Mac — so on macOS the strip rendered *nothing*, and the
    // onboarding walk drew its content under AppKit's traffic lights. The
    // gutter is the whole reason the strip exists on that platform.
    testWidgets('reserves the traffic-light gutter on macOS', (tester) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        await _pump(tester);

        expect(find.byType(SizedBox), findsWidgets);
        final gutter = tester
            .widgetList<SizedBox>(find.byType(SizedBox))
            .where((box) => box.width == DesktopWindow.leadingButtonGutter)
            .toList(growable: false);
        expect(gutter, isNotEmpty);
        expect(DesktopWindow.leadingButtonGutter, greaterThan(0));
      });
    });

    // On Windows and Linux the strip is the only thing that can move a frameless
    // window *and* the only place its caption buttons can be: without them the
    // window cannot be moved and, worse, cannot be closed.
    testWidgets('keeps the caption buttons where the OS has none', (
      tester,
    ) async {
      await _onPlatform(TargetPlatform.windows, () async {
        await _pump(tester);
        expect(find.bySemanticsLabel('Close'), findsOneWidget);
        expect(find.bySemanticsLabel('Minimise'), findsOneWidget);
      });

      // macOS draws its own, so ours must not appear beside them.
      await _onPlatform(TargetPlatform.macOS, () async {
        await _pump(tester);
        expect(find.bySemanticsLabel('Close'), findsNothing);
      });
    });

    // The shell's own heights, through the shell's own helper. A strip that
    // agreed with the shell by coincidence would stop agreeing the first time
    // one of the two numbers moved.
    testWidgets('is 44pt full and 38pt compact', (tester) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        await _pump(tester);
        expect(
          tester.getSize(find.byType(WindowDragStrip)).height,
          WindowChrome.height,
        );

        await _pump(tester, size: const Size(720, 450));
        expect(
          tester.getSize(find.byType(WindowDragStrip)).height,
          WindowChrome.compactHeight,
        );
      });
    });

    // A phone has no window to move and no gutter to reserve.
    testWidgets('renders nothing on a touch build', (tester) async {
      await _onPlatform(TargetPlatform.android, () async {
        await _pump(tester);

        expect(find.text(kAppName), findsNothing);
        expect(tester.getSize(find.byType(WindowDragStrip)).height, 0);
      });
    });

    // The trail is a parameter, not a hardcode: a second flow above the shell
    // passes its own rather than teaching the strip about routes it cannot
    // reach.
    testWidgets('prints whatever trail it is given', (tester) async {
      await _onPlatform(TargetPlatform.linux, () async {
        await _pump(tester, trail: const ['Cupola', 'Manual import']);

        expect(find.text('Manual import'), findsOneWidget);
        expect(find.text('Setup'), findsNothing);
      });
    });
  });

  // The Close button's hover is the room's own error, the one its `onError`
  // glyph is paired with. It once painted the dark room's error byte raw, so on
  // paper the glyph sat on a pale salmon fill it could not be read against.
  group('the Close button hover', () {
    for (final theme in [AppTheme.darkTheme(), AppTheme.lightTheme()]) {
      final scheme = theme.colorScheme;
      final room = theme.brightness.name;

      testWidgets('is the $room room\'s error under its own glyph', (
        tester,
      ) async {
        await _onPlatform(TargetPlatform.windows, () async {
          await _pump(tester, theme: theme);
          final close = find.widgetWithIcon(IconButton, Icons.close_rounded);

          Color? fill() => tester
              .widget<IconButton>(close)
              .style!
              .backgroundColor!
              .resolve(const {});

          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(close));
          await tester.pump();

          expect(fill(), statusToneFill(scheme, StatusTone.error));
          final glyph = tester.widget<Icon>(
            find.descendant(of: close, matching: find.byType(Icon)),
          );
          expect(glyph.color, scheme.onError);
        });
      });
    }
  });
}
