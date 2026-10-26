/// A Plex token that is a shared account's is case d, not a fault.
///
/// A Plex token is a person's. A shared account's reads the libraries it was
/// given and is refused `/status/sessions` with a 401, the status a wrong
/// token gets everywhere. Now playing used to report that 401 as a refused
/// credential, and the Streaming list as a server that did not answer, in
/// red. Plex now has a capability probe, and what it learns is said in blue:
/// only the owner of the server sees what is playing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/plex/presentation/plex_capability.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/plex/presentation/plex_tab_screens.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_now_playing_section.dart';

import '../../test_helpers/profiles/profiles.dart';

/// P1 with its Plex set up on the owner's token.
final _ownerPlex = Profiles.p1.withConnection(WorldConnections.plex);

Future<CapabilityGrant> _probe(ConfigProfile profile) async {
  final harness = await ProfileHarness.start(profile);
  return harness
      .container(retry: (_, _) => null)
      .read(connectionCapabilityProvider(WorldIds.plex).future);
}

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget child,
) async {
  final harness = await ProfileHarness.start(profile);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: child),
    ),
  );
  await harness.settle(tester);
  return harness;
}

/// Plex's Now playing, as the Overview hosts it: the lens's sessions, read by
/// the host.
final Widget _nowPlaying = Scaffold(
  body: SingleChildScrollView(
    child: Consumer(
      builder: (context, ref, _) => StreamNowPlayingSection(
        service: ServiceKey.plex,
        sessions: ref.watch(plexSessionsProvider),
      ),
    ),
  ),
);

final _ownerOnly = find.text(plexOwnerOnlyMessage());

/// No refusal and no "did not answer" anywhere on screen.
void _expectNoFault() {
  expect(find.textContaining('refused'), findsNothing);
  expect(find.textContaining('did not answer'), findsNothing);
  expect(find.byType(ServiceOfflineState), findsNothing);
  expect(find.byType(AppErrorState), findsNothing);
}

/// The note's glyph is the information tone, walked for the scaffold.
void _expectBlue(WidgetTester tester) {
  final note = find.byType(PlexOwnerOnlyNote);
  final icon = tester.widget<Icon>(
    find.descendant(of: note, matching: find.byType(Icon)),
  );
  final colorScheme = Theme.of(tester.element(note)).colorScheme;
  expect(
    icon.color,
    statusToneColor(colorScheme, StatusTone.info, surface: colorScheme.surface),
  );
}

void main() {
  group('the probe', () {
    test('P6: a shared account\'s token reads the server, not who is '
        'watching', () async {
      final grant = await _probe(Profiles.p6);

      expect(grant, const CapabilityGrant.partial({}));
      expect(plexIsSharedAccount(grant), isTrue);
      // Where the token is replaced, the connection says whose it is.
      expect(
        credentialScopeQualifier(ServiceKey.plex, grant),
        'shared account',
      );
    });

    test('the owner\'s token may do everything', () async {
      final grant = await _probe(_ownerPlex);

      expect(grant, const CapabilityGrant.readWrite());
      expect(plexIsSharedAccount(grant), isFalse);
      expect(credentialScopeQualifier(ServiceKey.plex, grant), isNull);
    });

    test('a token Plex refuses everywhere is not a shared account', () async {
      final grant = await _probe(
        Profiles.p1.withConnection(
          WorldConnections.plex.withBehaviour(ConnectionBehaviour.refusesKey),
        ),
      );

      expect(grant, const CapabilityGrant.unanswered());
      expect(plexIsSharedAccount(grant), isFalse);
    });

    test('a Plex that did not answer is not a shared account', () async {
      final grant = await _probe(
        Profiles.p1.withConnection(
          WorldConnections.plex.withBehaviour(ConnectionBehaviour.didNotAnswer),
        ),
      );

      expect(grant, const CapabilityGrant.unanswered());
    });
  });

  group('P6, a shared account\'s Plex', () {
    testWidgets('Now playing says only the owner sees what is playing, in '
        'blue', (tester) async {
      final harness = await _pump(tester, Profiles.p6, _nowPlaying);

      expect(_ownerOnly, findsOneWidget);
      _expectBlue(tester);
      _expectNoFault();
      await harness.unmount(tester);
    });

    testWidgets('Plex\'s Activity tab is not offline', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p6,
        const PlexActivitiesScreen(),
      );

      expect(_ownerOnly, findsOneWidget);
      _expectNoFault();
      await harness.unmount(tester);
    });
  });

  testWidgets('a token Plex refuses everywhere still reads as refused in '
      'Now playing', (tester) async {
    final harness = await _pump(
      tester,
      Profiles.p1.withConnection(
        WorldConnections.plex.withBehaviour(ConnectionBehaviour.refusesKey),
      ),
      _nowPlaying,
    );

    expect(_ownerOnly, findsNothing);
    expect(find.textContaining('refused'), findsWidgets);
    await harness.unmount(tester);
  });
}
