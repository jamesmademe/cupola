import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// Settings on a touch build (the test's Android) at [size]: its root and two
/// sections, each a page of its own with its bar, as the router builds them.
Future<GoRouter> _pump(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  Widget page(String name) => Scaffold(
    appBar: AppBar(title: Text(name)),
    body: SettingsMasterDetail(child: Text('the $name page')),
  );
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) => page('Overview'),
        routes: [
          for (final name in ['appearance', 'region'])
            GoRoute(
              path: name,
              pageBuilder: (_, state) => SettingsSectionPage(
                key: state.pageKey,
                name: state.matchedLocation,
                child: page(name),
              ),
            ),
        ],
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
  return router;
}

class _Operator extends ShellAudienceNotifier {
  @override
  Audience build() => Audience.operator;
}

void main() {
  testWidgets('a tablet on its side lists the sections beside the page', (
    tester,
  ) async {
    await _pump(tester, const Size(1180, 820));
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('the Overview page'), findsOneWidget);
  });

  testWidgets('a tablet upright keeps the phone\'s drill-down', (tester) async {
    await _pump(tester, const Size(820, 1180));
    expect(find.text('Appearance'), findsNothing);
  });

  testWidgets('beside the list a section takes the place of the last one: '
      'no slide, and no back button', (tester) async {
    final router = await _pump(tester, const Size(1180, 820));
    router.go('/settings/appearance');
    await tester.pump();
    // No transition: the page is there on the next frame.
    expect(find.text('the appearance page'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    router.go('/settings/region');
    await tester.pump();
    expect(find.text('the region page'), findsOneWidget);
    expect(find.text('the appearance page'), findsNothing);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('without the list a section is a drill-down with its back '
      'button', (tester) async {
    final router = await _pump(tester, const Size(390, 844));
    router.go('/settings/appearance');
    await tester.pumpAndSettle();
    expect(find.text('the appearance page'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });
}
