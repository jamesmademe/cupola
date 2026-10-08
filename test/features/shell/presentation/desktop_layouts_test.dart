import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/desktop_content_well.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/media_detail_slot.dart';
import 'package:cupola/core/widgets/media_detail_view.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';

/// The layouts the window shell hosts: a well, a two-track spine, and the two
/// master-detail consoles.
///
/// All four are the same argument in four places — a desktop window is wide
/// enough to hold two thoughts at once — so all four are tested the same way:
/// once on a window, once on a phone, and the phone case must come back
/// byte-identical to what it was before any of this existed.
void main() {
  group('DesktopContentWell', () {
    testWidgets('centres the body at reading width on a window', (
      tester,
    ) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        await _pump(
          tester,
          const Size(1600, 900),
          const DesktopContentWell(child: SizedBox.expand()),
        );

        final box = tester.getRect(find.byType(SizedBox));
        expect(box.width, AppBreakpoints.contentWell);
        // Centred, so the eye travels the same distance either way.
        expect(box.center.dx, closeTo(800, 0.5));
      });
    });

    testWidgets('passes the body straight through on a phone', (tester) async {
      await _onPlatform(TargetPlatform.android, () async {
        await _pump(
          tester,
          const Size(400, 900),
          const DesktopContentWell(child: SizedBox.expand()),
        );

        expect(tester.getRect(find.byType(SizedBox)).width, 400);
      });
    });

    testWidgets('never widens a narrow window', (tester) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        await _pump(
          tester,
          const Size(720, 450),
          const DesktopContentWell(child: SizedBox.expand()),
        );

        expect(tester.getRect(find.byType(SizedBox)).width, 720);
      });
    });
  });

  group('a glass app bar over a well', () {
    Widget page({bool welled = true}) => AmbientScaffold(
      contentWell: welled,
      appBar: GlassAppBar(
        title: const Text('Discover'),
        actions: [const SizedBox(key: Key('action'), width: 44, height: 44)],
      ),
      body: const SizedBox.expand(),
    );

    testWidgets('lines its title and actions up with the well on a window, '
        'and keeps its glass full-bleed', (tester) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        await _pump(tester, const Size(1600, 900), page());

        const inset = (1600 - AppBreakpoints.contentWell) / 2;
        expect(
          tester.getTopLeft(find.text('Discover')).dx,
          inset + NavigationToolbar.kMiddleSpacing,
        );
        expect(
          tester.getTopRight(find.byKey(const Key('action'))).dx,
          1600 - inset,
        );
        expect(tester.getRect(find.byType(GlassSurface)).width, 1600);
      });
    });

    testWidgets('leaves its title at the gutter on a phone', (tester) async {
      await _onPlatform(TargetPlatform.android, () async {
        await _pump(tester, const Size(400, 900), page());

        expect(
          tester.getTopLeft(find.text('Discover')).dx,
          NavigationToolbar.kMiddleSpacing,
        );
        // The bar it always was: the glass is the app bar's own.
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byType(GlassSurface),
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('leaves its title at the gutter over a page that owns the '
        'window', (tester) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        await _pump(tester, const Size(1600, 900), page(welled: false));

        expect(
          tester.getTopLeft(find.text('Discover')).dx,
          NavigationToolbar.kMiddleSpacing,
        );
      });
    });
  });

  group('the media spine', () {
    testWidgets('moves operate and related into a side track on a window', (
      tester,
    ) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        await _pump(tester, const Size(1440, 900), _spine());

        // The side track exists, and the two regions that moved are in it.
        expect(find.byType(SliverCrossAxisGroup), findsOneWidget);
        final operate = tester.getRect(find.text('operate region'));
        final synopsis = tester.getRect(find.text('synopsis region'));
        expect(
          operate.left,
          greaterThan(synopsis.right),
          reason: 'operate belongs to the right-hand track',
        );
        expect(
          operate.top,
          lessThan(synopsis.bottom),
          reason: 'and beside the spine rather than under it',
        );
      });
    });

    testWidgets('keeps one column on a phone', (tester) async {
      await _onPlatform(TargetPlatform.android, () async {
        await _pump(tester, const Size(400, 900), _spine());

        expect(find.byType(SliverCrossAxisGroup), findsNothing);
      });
    });

    testWidgets('keeps one column on a narrow window', (tester) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        // Below the two-track threshold the side track would be narrower than
        // the 300 its content is drawn for.
        await _pump(tester, const Size(900, 700), _spine());

        expect(find.byType(SliverCrossAxisGroup), findsNothing);
      });
    });
  });

  group('the settings and TrueNAS consoles', () {
    testWidgets('settings shows its sections beside the page', (tester) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        await _pump(
          tester,
          const Size(1440, 900),
          const SettingsMasterDetail(child: Text('the page')),
          location: '/settings/services',
        );

        // Every section is a door, and the one you are on is the only one
        // marked.
        for (final section in SettingsMasterDetail.sections) {
          expect(find.text(section.label), findsOneWidget);
        }
        final list = tester.getRect(find.text('Connections'));
        final page = tester.getRect(find.text('the page'));
        expect(list.right, lessThan(page.left));
      });
    });

    testWidgets('settings stays a drill-down on a phone', (tester) async {
      await _onPlatform(TargetPlatform.android, () async {
        await _pump(
          tester,
          const Size(400, 900),
          const SettingsMasterDetail(child: Text('the page')),
          location: '/settings/services',
        );

        expect(find.text('Appearance'), findsNothing);
        expect(find.text('the page'), findsOneWidget);
      });
    });

    testWidgets('TrueNAS trades its section list for a chip row when narrow', (
      tester,
    ) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        await _pump(
          tester,
          const Size(1440, 900),
          const TrueNasConsoleShell(child: Text('an area')),
          location: '/dashboard/truenas/storage',
        );
        // Full window: the list carries each area's second line.
        expect(find.text('Pools & topology'), findsOneWidget);

        await _pump(
          tester,
          const Size(720, 450),
          const TrueNasConsoleShell(child: Text('an area')),
          location: '/dashboard/truenas/storage',
        );
        // Compact: the same nine doors, one line, no subtitles.
        expect(find.text('Storage'), findsOneWidget);
        expect(find.text('Pools & topology'), findsNothing);
      });
    });
  });
}

/// A spine with something identifiable in each region that matters.
Widget _spine() => const MediaDetailView(
  title: 'A title',
  heroFallbackIcon: Icons.movie_rounded,
  body: MediaDetailBody(
    readout: Text('readout region'),
    operate: [MediaDetailSlot.box(child: Text('operate region'))],
    synopsis: [MediaDetailSlot.box(child: Text('synopsis region'))],
    reference: [MediaDetailSlot.box(child: Text('reference region'))],
    related: [MediaDetailSlot.box(child: Text('related region'))],
  ),
);

Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// Pumps [child] at [size], inside a router so a location-aware layout can ask
/// where it is.
Future<void> _pump(
  WidgetTester tester,
  Size size,
  Widget child, {
  String location = '/dashboard',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/:section(.*)',
        builder: (_, _) => Scaffold(body: child),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: router)),
  );
  await tester.pumpAndSettle();
}
