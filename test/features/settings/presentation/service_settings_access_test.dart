/// The Access row of a connection's form: the four choices, their fields,
/// the clashes it settles, the connection test's three outcomes for a
/// Cloudflare service token, the offer to share a token that passed, and the
/// gateway remedies that open the form on it.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _surface = Size(430, 2600);

/// The form for [id] on [profile], pushed over a launcher so a save can pop.
Future<(ProfileHarness, ProviderContainer)> _pumpForm(
  WidgetTester tester,
  ConfigProfile profile,
  String id, {
  AccessKind? initialAccess,
  Future<void> Function(ProviderContainer container)? before,
  Size surface = _surface,
}) async {
  final harness = await ProfileHarness.start(profile);
  final container = harness.container();
  if (before != null) await tester.runAsync(() => before(container));
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final service = profile.connection(id).service;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ServiceSettingsScreen(
                  service: service,
                  instanceId: id,
                  initialAccess: initialAccess,
                  certificateProber: (_, {pinnedFingerprint = ''}) async =>
                      null,
                  localNetworkProbe: (_, {timeout = Duration.zero}) async =>
                      LocalNetworkAccess.unrestricted,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await harness.settle(tester);
  return (harness, container);
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _choose(WidgetTester tester, String choice) async {
  // The pills scroll sideways on a phone.
  await tester.ensureVisible(find.bySemanticsLabel(choice));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel(choice));
  await tester.pump();
}

Future<void> _test(WidgetTester tester, ProfileHarness harness) async {
  // P1's first Radarr has a sibling and no name, which the form asks for.
  if (_field('Name').evaluate().isNotEmpty) {
    await tester.enterText(_field('Name'), 'HD');
  }
  await tester.ensureVisible(find.text('Test connection'));
  await tester.tap(find.text('Test connection'));
  await harness.settle(tester);
}

Future<void> _save(WidgetTester tester, ProfileHarness harness) async {
  await tester.tap(find.text('Save'));
  await harness.settle(tester);
}

bool _selected(WidgetTester tester, String choice) =>
    tester
        .getSemantics(find.bySemanticsLabel(choice))
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

/// Every Access choice drawn inside the [width] of the screen, its label on
/// one line and uncut.
void _expectChoicesWhole(WidgetTester tester, double width) {
  for (final choice in const [
    'None',
    'Cloudflare Access',
    'Password',
    'Custom headers',
  ]) {
    final rect = tester.getRect(find.bySemanticsLabel(choice));
    expect(rect.left, greaterThanOrEqualTo(0), reason: choice);
    expect(rect.right, lessThanOrEqualTo(width), reason: choice);
    final label = tester.renderObject<RenderParagraph>(find.text(choice));
    expect(label.didExceedMaxLines, isFalse, reason: choice);
    // A pill as wide as its label and its inset, never stretched across the
    // line.
    expect(
      rect.width,
      lessThanOrEqualTo(tester.getSize(find.text(choice)).width + 34),
      reason: choice,
    );
  }
  // On a 390pt phone the first two choices share a line. (The test font is
  // wider than the app's, so at 320pt it is allowed a line each.)
  if (width >= 390) {
    expect(
      tester.getRect(find.bySemanticsLabel('None')).top,
      tester.getRect(find.bySemanticsLabel('Cloudflare Access')).top,
    );
  }
}

void main() {
  group('the Access row', () {
    testWidgets('offers four choices, None by default', (tester) async {
      final (harness, _) = await _pumpForm(
        tester,
        Profiles.p3,
        WorldIds.radarr,
      );

      expect(find.text('Access'), findsOneWidget);
      for (final choice in [
        'None',
        'Cloudflare Access',
        'Password',
        'Custom headers',
      ]) {
        expect(find.bySemanticsLabel(choice), findsOneWidget, reason: choice);
      }
      expect(_selected(tester, 'None'), isTrue);
      expect(_field('Client ID'), findsNothing);

      await harness.unmount(tester);
    });

    for (final width in [320.0, 390.0]) {
      testWidgets('at ${width.round()}pt every choice is whole on screen, '
          'none behind a scroll', (tester) async {
        final (harness, _) = await _pumpForm(
          tester,
          Profiles.p3,
          WorldIds.radarr,
          surface: Size(width, 2600),
        );

        _expectChoicesWhole(tester, width);

        await harness.unmount(tester);
      });
    }

    testWidgets('has no Password where the service signs in with '
        'Authorization, and says why', (tester) async {
      final (harness, _) = await _pumpForm(
        tester,
        Profiles.p1.withConnection(WorldConnections.nzbget),
        WorldConnections.nzbget.id,
      );

      expect(find.bySemanticsLabel('Password'), findsNothing);
      expect(
        find.text(
          "NZBGet signs in with its own Authorization header, so a proxy "
          "password cannot travel with it.",
        ),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('Cloudflare Access: labelled fields, the secret hidden with '
        'Paste, the help line, and the token saved', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return {'text': ' pasted-secret '};
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final (harness, container) = await _pumpForm(
        tester,
        Profiles.p3,
        WorldIds.radarr,
      );

      await _choose(tester, 'Cloudflare Access');
      expect(_selected(tester, 'Cloudflare Access'), isTrue);
      expect(
        find.text(
          'On Cloudflare: create a service token, then add a Service Auth '
          'policy for it to this application.',
        ),
        findsOneWidget,
      );
      final secret = tester.widget<TextField>(_field('Client secret'));
      expect(secret.obscureText, isTrue);

      await tester.enterText(_field('Client ID'), 'abc.access');
      await tester.tap(
        find.descendant(
          of: _field('Client secret'),
          matching: find.byTooltip('Paste'),
        ),
      );
      await tester.pump();
      expect(secret.controller?.text, 'pasted-secret');

      await _save(tester, harness);
      expect(
        container.read(settingsProvider).instanceById(WorldIds.radarr)?.access,
        const CloudflareServiceToken(
          clientId: 'abc.access',
          clientSecret: 'pasted-secret',
        ),
      );

      await harness.unmount(tester);
    });

    testWidgets('a half-filled token is not saved', (tester) async {
      final (harness, container) = await _pumpForm(
        tester,
        Profiles.p3,
        WorldIds.radarr,
      );

      await _choose(tester, 'Cloudflare Access');
      await tester.enterText(_field('Client ID'), 'abc.access');
      await _save(tester, harness);

      expect(find.text('Add the client secret'), findsOneWidget);
      expect(
        container.read(settingsProvider).instanceById(WorldIds.radarr)?.access,
        const NoAccess(),
      );

      await harness.unmount(tester);
    });

    testWidgets('Password saves a proxy password', (tester) async {
      final (harness, container) = await _pumpForm(
        tester,
        Profiles.p3,
        WorldIds.radarr,
      );

      await _choose(tester, 'Password');
      await tester.enterText(_field('Proxy username'), 'matt');
      await tester.enterText(_field('Proxy password'), 'pw');
      await _save(tester, harness);

      expect(
        container.read(settingsProvider).instanceById(WorldIds.radarr)?.access,
        const ProxyPassword(username: 'matt', password: 'pw'),
      );

      await harness.unmount(tester);
    });

    testWidgets('a custom header named like the key offers to move it, and '
        'the tap moves it', (tester) async {
      final (harness, container) = await _pumpForm(
        tester,
        Profiles.p3,
        WorldIds.radarr,
      );

      await _choose(tester, 'Custom headers');
      await tester.enterText(_field('Header name'), 'X-Api-Key');
      await tester.enterText(_field('Header value'), 'moved-key');
      await tester.pump();

      expect(
        find.text(
          "Cupola already sends Radarr's key. Move it to the API key field?",
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Move it'));
      await tester.pump();

      expect(
        tester.widget<TextField>(_field('API key')).controller?.text,
        'moved-key',
      );
      expect(
        tester.widget<TextField>(_field('Header name')).controller?.text,
        '',
      );

      await _save(tester, harness);
      final saved = container
          .read(settingsProvider)
          .instanceById(WorldIds.radarr);
      expect(saved?.credential, 'moved-key');
      expect(saved?.access, const NoAccess());

      await harness.unmount(tester);
    });

    testWidgets('a header the transport owns is refused', (tester) async {
      final (harness, container) = await _pumpForm(
        tester,
        Profiles.p3,
        WorldIds.radarr,
      );

      await _choose(tester, 'Custom headers');
      await tester.enterText(_field('Header name'), 'Host');
      await tester.enterText(_field('Header value'), 'elsewhere');
      await _save(tester, harness);

      expect(find.text('Cupola sets this header itself'), findsOneWidget);
      expect(
        container.read(settingsProvider).instanceById(WorldIds.radarr)?.access,
        const NoAccess(),
      );

      await harness.unmount(tester);
    });
  });

  group('an address typed with user:password@', () {
    testWidgets('becomes a proxy password, and the address is cleaned', (
      tester,
    ) async {
      final (harness, container) = await _pumpForm(
        tester,
        Profiles.p3,
        WorldIds.radarr,
      );

      await tester.enterText(
        _field('Server URL'),
        'https://matt:p%40ss@radarr.example.com',
      );
      await _save(tester, harness);

      final saved = container
          .read(settingsProvider)
          .instanceById(WorldIds.radarr);
      expect(saved?.url, 'https://radarr.example.com');
      expect(
        saved?.access,
        const ProxyPassword(username: 'matt', password: 'p@ss'),
      );

      await harness.unmount(tester);
    });

    testWidgets('is the sign-in of a service that signs in with '
        'Authorization itself', (tester) async {
      final (harness, container) = await _pumpForm(
        tester,
        Profiles.p1.withConnection(WorldConnections.nzbget),
        WorldConnections.nzbget.id,
      );

      await tester.enterText(
        _field('Server URL'),
        'http://nzbget:tegbzn6789@tower.home.arpa:6789',
      );
      await _save(tester, harness);

      final saved = container
          .read(settingsProvider)
          .instanceById(WorldConnections.nzbget.id);
      expect(saved?.url, 'http://tower.home.arpa:6789');
      expect(saved?.username, 'nzbget');
      expect(saved?.credential, 'tegbzn6789');
      expect(saved?.access, const NoAccess());

      await harness.unmount(tester);
    });
  });

  group('the connection test of a Cloudflare service token, under P8', () {
    testWidgets('Access let it through', (tester) async {
      final (harness, _) = await _pumpForm(
        tester,
        Profiles.p8,
        WorldIds.radarr,
      );
      expect(_selected(tester, 'Cloudflare Access'), isTrue);

      await _test(tester, harness);

      expect(
        find.text('Access let the token through and Radarr answered.'),
        findsOneWidget,
      );
      await harness.unmount(tester);
    });

    testWidgets('Access refused it', (tester) async {
      final (harness, _) = await _pumpForm(tester, Profiles.p8, WorldIds.seerr);

      await _test(tester, harness);

      expect(
        find.text(
          'Access did not accept the token: add a Service Auth policy for it '
          'on nas.home.arpa:5055.',
        ),
        findsOneWidget,
      );
      await harness.unmount(tester);
    });

    testWidgets('nothing reached Access', (tester) async {
      final (harness, _) = await _pumpForm(
        tester,
        Profiles.p8.withBehaviour(
          WorldIds.radarr,
          ConnectionBehaviour.didNotAnswer,
        ),
        WorldIds.radarr,
      );

      await _test(tester, harness);

      expect(find.text('Nothing reached Access.'), findsOneWidget);
      await harness.unmount(tester);
    });
  });

  testWidgets('after a token passes, the same token is offered to the '
      'connections the same Access team turned away', (tester) async {
    // P8 with Radarr not yet given its token: Radarr, Sonarr and Seerr all
    // last failed at the cupola-home team.
    final profile = Profiles.p8.withConnection(
      Profiles.p8.connection(WorldIds.radarr).withAccess(const NoAccess()),
    );
    final (harness, container) = await _pumpForm(
      tester,
      profile,
      WorldIds.radarr,
      initialAccess: AccessKind.cloudflare,
      // What Home's probe already knows when the remedy is tapped.
      before: (container) async {
        for (final (service, id) in [
          (ServiceKey.radarr, WorldIds.radarr),
          (ServiceKey.sonarr, WorldIds.sonarr),
          (ServiceKey.seerr, WorldIds.seerr),
        ]) {
          await container.read(
            instanceSummaryProvider((service: service, instanceId: id)).future,
          );
        }
      },
    );

    await tester.enterText(_field('Client ID'), WorldTokens.radarr.id);
    await tester.enterText(_field('Client secret'), WorldTokens.radarr.secret);
    await _test(tester, harness);

    expect(
      find.text('Access let the token through and Radarr answered.'),
      findsOneWidget,
    );
    // In the user's own order of connections.
    expect(
      find.text('Use the same token for Seerr and Sonarr?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Use it'));
    await harness.settle(tester);

    final settings = container.read(settingsProvider);
    for (final id in [WorldIds.sonarr, WorldIds.seerr]) {
      expect(settings.instanceById(id)?.access, WorldTokens.radarr.access);
    }
    // Radarr's own form is not saved by the offer.
    expect(settings.instanceById(WorldIds.radarr)?.access, const NoAccess());
    expect(find.text('Saved the token for Seerr and Sonarr'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a token already answering offers itself too: the team is asked '
      'of its address once, without the token', (tester) async {
    // The live case: Radarr was set up with its token and answers, so no
    // failure of its own names the team; Sonarr and Seerr were stopped by it.
    final (harness, _) = await _pumpForm(
      tester,
      Profiles.p8,
      WorldIds.radarr,
      before: (container) async {
        for (final (service, id) in [
          (ServiceKey.radarr, WorldIds.radarr),
          (ServiceKey.sonarr, WorldIds.sonarr),
          (ServiceKey.seerr, WorldIds.seerr),
        ]) {
          await container.read(
            instanceSummaryProvider((service: service, instanceId: id)).future,
          );
        }
      },
    );

    await _test(tester, harness);

    expect(
      find.text('Access let the token through and Radarr answered.'),
      findsOneWidget,
    );
    expect(
      find.text('Use the same token for Seerr and Sonarr?'),
      findsOneWidget,
    );
    await harness.unmount(tester);
  });

  group('a gateway\'s remedy opens the form on the Access row', () {
    AccessKind? accessOf(ServiceKey service, AccessGatewayKind kind) =>
        FailureRemedy.forReason(
          service,
          ServiceFailureReason.accessGateway,
          gateway: AccessGatewayAnswer(
            kind: kind,
            credentialsSent: false,
            gatewayHost: 'team.cloudflareaccess.com',
            serviceHost: 'radarr.example.com',
          ),
        )?.access;

    test('with the choice the gateway wants', () {
      expect(
        accessOf(ServiceKey.radarr, AccessGatewayKind.cloudflareAccess),
        AccessKind.cloudflare,
      );
      expect(
        accessOf(ServiceKey.radarr, AccessGatewayKind.passwordPrompt),
        AccessKind.password,
      );
      expect(
        accessOf(ServiceKey.radarr, AccessGatewayKind.signInPage),
        AccessKind.password,
      );
      // No Password where the service signs in with Authorization.
      expect(
        accessOf(ServiceKey.nginxProxyManager, AccessGatewayKind.signInPage),
        AccessKind.custom,
      );
      expect(
        FailureRemedy.forReason(
          ServiceKey.radarr,
          ServiceFailureReason.unauthorized,
        )?.access,
        isNull,
      );
      expect(
        ServiceRoutes.settingsForConnection(
          ServiceKey.radarr,
          'radarr',
          access: AccessKind.cloudflare,
        ),
        '/settings/service/radarr?i=radarr&access=cloudflare',
      );
    });

    testWidgets('Sonarr\'s library under P8: Add a service token lands on '
        'Cloudflare Access', (tester) async {
      final harness = await ProfileHarness.start(Profiles.p8);
      final container = harness.container();
      Uri? opened;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const Scaffold(body: SeriesScreen(showAppBar: false)),
          ),
          GoRoute(
            path: '/settings/service/:service',
            // The settings route of `router.dart`, as it reads its query.
            builder: (context, state) {
              opened = state.uri;
              return ServiceSettingsScreen(
                service: ServiceKey.values.firstWhere(
                  (s) => s.routeParam == state.pathParameters['service'],
                ),
                instanceId: state.uri.queryParameters['i'],
                initialAccess: AccessKind.byName(
                  state.uri.queryParameters['access'],
                ),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.binding.setSurfaceSize(_surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.darkTheme(),
            routerConfig: router,
          ),
        ),
      );
      await harness.settle(tester);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Add a service token'),
      );
      await harness.settle(tester);

      expect(
        opened.toString(),
        '/settings/service/sonarr?i=sonarr&access=cloudflare',
      );
      expect(_selected(tester, 'Cloudflare Access'), isTrue);
      expect(_field('Client ID'), findsOneWidget);

      await harness.unmount(tester);
    });
  });
}
