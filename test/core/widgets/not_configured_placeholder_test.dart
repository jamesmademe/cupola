import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Where the "is not set up" button lands.
///
/// This is the invariant that was silently lost when five dashboards' private
/// not-configured cards were collapsed onto the shared widget: each private copy
/// deep-linked to `/settings/service/<routeParam>`, and the generic constructor
/// goes to the Settings root. A user who taps "Open Settings" from the SABnzbd
/// dashboard should land on the SABnzbd form, not on a list to search.
void main() {
  Future<String> pumpAndTap(WidgetTester tester, Widget placeholder) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (context, state) => placeholder),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: 'service/:service',
              builder: (context, state) => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    return router.state.uri.toString();
  }

  testWidgets('the service form opens that service settings page', (
    tester,
  ) async {
    final location = await pumpAndTap(
      tester,
      NotConfiguredPlaceholder.forService(ServiceKey.sabnzbd),
    );

    expect(location, '/settings/service/${ServiceKey.sabnzbd.routeParam}');
  });

  testWidgets('the service form names the service it was given', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: NotConfiguredPlaceholder.forService(ServiceKey.nzbget)),
    );

    expect(find.textContaining(ServiceKey.nzbget.title), findsOneWidget);
  });

  testWidgets('the generic form falls back to the settings root', (
    tester,
  ) async {
    // AsyncValueWidget and MediaDetailPlaceholderView reach this state from a
    // `<Service> not configured` throw and hold only the name, so the root is
    // the only honest destination for them.
    final location = await pumpAndTap(
      tester,
      const NotConfiguredPlaceholder(serviceName: 'Radarr'),
    );

    expect(location, '/settings');
  });

  group('on a service page the action takes the service light', () {
    for (final (name, theme) in [
      ('dark', AppTheme.darkTheme()),
      ('light', AppTheme.lightTheme()),
    ]) {
      for (final service in ServiceKey.values) {
        testWidgets('${service.name}, $name: a tonal accent fill whose label '
            'reads at 4.5:1', (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: NotConfiguredPlaceholder.forService(service),
              ),
            ),
          );
          final button = tester.widget<ButtonStyleButton>(
            find.byWidgetPredicate((w) => w is FilledButton),
          );
          final fill = button.style!.backgroundColor!.resolve({})!;
          final ink = button.style!.foregroundColor!.resolve({})!;
          expect(fill.a, lessThan(1), reason: 'a tonal fill, not the accent');
          final ground = Color.alphaBlend(fill, theme.colorScheme.surface);
          expect(_contrast(ink, ground), greaterThanOrEqualTo(4.5));
        });
      }
    }
  });

  testWidgets('the generic form keeps the theme primary', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NotConfiguredPlaceholder(serviceName: 'Bazarr')),
      ),
    );
    final button = tester.widget<ButtonStyleButton>(
      find.byWidgetPredicate((w) => w is FilledButton),
    );
    expect(button.style, isNull);
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
