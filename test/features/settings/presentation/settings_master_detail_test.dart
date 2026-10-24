import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';

/// The settings rail: which row it lights, and what it calls the first one.
///
/// Both are rules rather than renderings: the rail's whole job is to say where
/// you are, so neither assertion touches a colour or a width.
void main() {
  testWidgets('the row you are standing on is the marked one', (tester) async {
    // The regression: Connections pointed at `/settings/services`, a legacy
    // path that only ever redirects here. No section matched the real
    // location, the longest match fell back to the root, and the rail marked
    // *Overview* while the user was on Connections.
    await _onDesktop(() async {
      await _pumpRail(tester, location: '/settings/connections');

      expect(
        find.semantics.byLabel('Connections'),
        isSemantics(isSelected: true),
      );
      expect(
        find.semantics.byLabel('Overview'),
        isSemantics(isSelected: false),
      );
    });
  });

  testWidgets('a page under a section keeps that section marked', (
    tester,
  ) async {
    await _onDesktop(() async {
      await _pumpRail(tester, location: '/settings/connections/radarr');

      expect(
        find.semantics.byLabel('Connections'),
        isSemantics(isSelected: true),
      );
    });
  });

  testWidgets('the root row is the one readout, and is called Overview', (
    tester,
  ) async {
    // Not "Settings": the rail already sits under a Settings eyebrow, and a
    // first row repeating it reads as the parent of the ones below it.
    await _onDesktop(() async {
      await _pumpRail(tester, location: '/settings');

      expect(SettingsMasterDetail.sections.first.label, 'Overview');
      expect(find.text('Settings'), findsNothing);
      expect(find.semantics.byLabel('Overview'), isSemantics(isSelected: true));
    });
  });

  testWidgets('every section is a door, and none is a dead legacy path', (
    tester,
  ) async {
    // A section whose location is a redirect can never be marked, so each one
    // has to be able to mark itself when it is the location.
    await _onDesktop(() async {
      for (final section in SettingsMasterDetail.sections) {
        await _pumpRail(tester, location: section.location);
        expect(
          find.semantics.byLabel(section.label),
          isSemantics(isSelected: true),
          reason: '${section.label} cannot light itself',
        );
      }
    });
  });
}

/// The rail draws on a desktop build only, and the override has to be undone
/// inside the test body: `flutter_test` asserts on it before tear-downs run.
Future<void> _onDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// Pumps the rail on a desktop-sized window, which is the only place it draws.
Future<void> _pumpRail(WidgetTester tester, {required String location}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/:rest(.*)',
        builder: (_, _) =>
            const Scaffold(body: SettingsMasterDetail(child: Text('the page'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [shellAudienceProvider.overrideWith(_Operator.new)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// The rail is drawn for whoever the app is for; these tests read the
/// operator's.
class _Operator extends ShellAudienceNotifier {
  @override
  Audience build() => Audience.operator;
}
