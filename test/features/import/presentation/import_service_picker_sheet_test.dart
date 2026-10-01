import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/features/import/presentation/import_service_picker_sheet.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The Activity app bar's way into the manual import wizard.
///
/// A service with no connection keeps its row, because hiding it hides the
/// fact, but the row is dimmed but tappable and its tap is the fix. It used to
/// look like the others and open the wizard against no connection, which
/// could only fail and offer a Retry that asked nobody.
void main() {
  Future<ProfileHarness> pumpPicker(
    WidgetTester tester,
    ConfigProfile profile,
  ) async {
    final harness = await ProfileHarness.start(profile);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showImportServicePickerSheet(context),
                child: const Text('Import'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/service/:service',
          builder: (context, state) =>
              Text('setup of ${state.pathParameters['service']}'),
        ),
      ],
      // Any other place — the wizard — is named by where it went.
      errorBuilder: (context, state) => Text('went to ${state.uri.path}'),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp.router(
          theme: AppTheme.darkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    return harness;
  }

  Finder dimmed(String service) => find.ancestor(
    of: find.text(service),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Opacity && widget.opacity == GatedAffordance.dimmedOpacity,
    ),
  );

  // P5 has Seerr and Jellyfin and no arr of its own.
  testWidgets('P5: a service that is not set up is dimmed, tappable, and '
      'opens its setup', (tester) async {
    final handle = tester.ensureSemantics();
    final harness = await pumpPicker(tester, Profiles.p5);

    for (final service in ['Radarr', 'Sonarr', 'Lidarr']) {
      expect(dimmed(service), findsOneWidget, reason: service);
    }
    expect(find.text('Not set up'), findsNWidgets(3));
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'^Radarr, Not set up')),
      ),
      containsSemantics(
        label: 'Radarr, Not set up',
        hint: 'requires Radarr, opens its setup',
        isButton: true,
        hasTapAction: true,
      ),
    );
    // The dim never takes height off the row.
    final row = tester.getRect(
      find.ancestor(of: find.text('Radarr'), matching: find.byType(InkWell)),
    );
    expect(row.height, greaterThanOrEqualTo(44));

    await tester.tap(find.text('Radarr'));
    await tester.pumpAndSettle();
    expect(find.text('setup of radarr'), findsOneWidget);

    handle.dispose();
    await harness.unmount(tester);
  });

  // P4 has Radarr, Sonarr and Lidarr, and nothing to dim.
  testWidgets('P4: a service that is set up starts its import', (tester) async {
    final harness = await pumpPicker(tester, Profiles.p4);

    for (final service in ['Radarr', 'Sonarr', 'Lidarr']) {
      expect(dimmed(service), findsNothing, reason: service);
    }
    expect(find.text('Not set up'), findsNothing);
    expect(find.text('Manual import movies'), findsOneWidget);

    await tester.tap(find.text('Radarr'));
    await tester.pumpAndSettle();
    expect(find.textContaining('went to /'), findsOneWidget);
    expect(find.textContaining('setup of'), findsNothing);

    await harness.unmount(tester);
  });
}
