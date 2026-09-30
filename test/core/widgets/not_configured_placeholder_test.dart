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
/// went to the Settings root. A user who taps "Set up SABnzbd" from the
/// SABnzbd dashboard lands on the SABnzbd form, not on a list to search —
/// the one place every `Set up X` goes.
void main() {
  Future<String> pumpAndTap(
    WidgetTester tester,
    Widget placeholder, {
    required String label,
  }) async {
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
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();

    return router.state.uri.toString();
  }

  testWidgets('the service form opens that service settings page', (
    tester,
  ) async {
    final location = await pumpAndTap(
      tester,
      NotConfiguredPlaceholder.forService(ServiceKey.sabnzbd),
      label: 'Set up SABnzbd',
    );

    expect(location, '/settings/service/${ServiceKey.sabnzbd.routeParam}');
  });

  testWidgets('the service form names the service it was given', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: NotConfiguredPlaceholder.forService(ServiceKey.nzbget)),
    );

    expect(find.text('NZBGet is not set up'), findsOneWidget);
    expect(find.text('Set up NZBGet'), findsOneWidget);
  });

  testWidgets('the generic form resolves the name to the same setup form', (
    tester,
  ) async {
    // AsyncValueWidget and MediaDetailPlaceholderView reach this state from a
    // `<Service> not configured` throw and hold only the name; the name is a
    // service's title, so the way in is that service's form like any other.
    final location = await pumpAndTap(
      tester,
      const NotConfiguredPlaceholder(serviceName: 'Radarr'),
      label: 'Set up Radarr',
    );

    expect(location, '/settings/service/${ServiceKey.radarr.routeParam}');
  });

  testWidgets('a name that is no service falls back to the settings root', (
    tester,
  ) async {
    final location = await pumpAndTap(
      tester,
      const NotConfiguredPlaceholder(serviceName: 'This page'),
      label: 'Open Settings',
    );

    expect(location, '/settings');
  });

  group('on a service page the action is the ink button', () {
    // The brand book: the one action on the page is the primary, and the primary is ink —
    // the theme's own FilledButton, the same for every service. It used to be
    // a tonal wash of the service's accent with a walked label.
    for (final (name, theme) in [
      ('dark', AppTheme.darkTheme()),
      ('light', AppTheme.lightTheme()),
    ]) {
      for (final service in ServiceKey.values) {
        testWidgets('${service.name}, $name: no style of its own, and the '
            'label reads at 4.5:1 on the ink', (tester) async {
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
          expect(button.style, isNull);
          final themed = theme.filledButtonTheme.style!;
          final fill = themed.backgroundColor!.resolve({})!;
          final ink = themed.foregroundColor!.resolve({})!;
          expect(fill, theme.colorScheme.primary);
          expect(_contrast(ink, fill), greaterThanOrEqualTo(4.5));
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
