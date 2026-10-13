/// A connection's form with its two addresses: the one at home and the
/// optional one away, each with its own Access; `http://` across the internet
/// refused in both; the test asking both and saying what each answered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _home = 'Address at home';
const _away = 'Address away · optional';

/// Radarr's form on P3, pushed over a launcher so a save can pop.
Future<(ProfileHarness, ProviderContainer)> _pumpForm(
  WidgetTester tester, {
  ConfigProfile? profile,
  void Function(ProfileHarness harness)? network,
}) async {
  final harness = await ProfileHarness.start(profile ?? Profiles.p3);
  network?.call(harness);
  final container = harness.container();
  await tester.binding.setSurfaceSize(const Size(430, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
                  service: ServiceKey.radarr,
                  instanceId: WorldIds.radarr,
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

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(_field(label), text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder, ProfileHarness h) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await h.settle(tester);
}

ServiceInstance? _saved(ProviderContainer container) =>
    container.read(settingsProvider).instanceById(WorldIds.radarr);

const _refusedHome =
    "Cupola doesn't send your key over plain http across the internet. "
    'Use its https address.';
const _refusedAway =
    "Cupola doesn't send your key over plain http across the internet. "
    'Use its https address, or leave this empty.';

void main() {
  group('the two addresses', () {
    testWidgets('at home, then away and optional, each with its Access', (
      tester,
    ) async {
      final (harness, _) = await _pumpForm(tester);

      expect(_field(_home), findsOneWidget);
      expect(_field(_away), findsOneWidget);
      expect(
        find.text(
          "Used when the home address doesn't answer. Leave it empty to "
          'reach Radarr only at home.',
        ),
        findsOneWidget,
      );
      // At home, folded while nothing stands in front of the address.
      expect(find.bySemanticsLabel('Change access at home'), findsOneWidget);
      expect(find.bySemanticsLabel('Cloudflare Access'), findsNothing);
      // Away, no Access until there is an address to put it in front of.
      expect(find.bySemanticsLabel('Change access away'), findsNothing);
      expect(find.text('The same key at both addresses.'), findsNothing);

      await _type(tester, _away, 'https://radarr.example.net');
      expect(find.bySemanticsLabel('Change access away'), findsOneWidget);
      expect(
        find.textContaining('The same key at both addresses.'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(_field(_home)).dy,
        lessThan(tester.getTopLeft(_field(_away)).dy),
      );

      await harness.unmount(tester);
    });

    testWidgets('the address away saves with its own Access, and the one at '
        'home keeps none', (tester) async {
      final (harness, container) = await _pumpForm(tester);

      await _type(tester, _away, 'https://radarr.example.net');
      await _tap(tester, find.bySemanticsLabel('Change access away'), harness);
      await _tap(tester, find.bySemanticsLabel('Cloudflare Access'), harness);
      await _type(tester, 'Client ID', 'abc.access');
      await _type(tester, 'Client secret', 'shh');
      await _tap(tester, find.text('Save'), harness);

      final saved = _saved(container)!;
      expect(saved.access, const NoAccess());
      expect(
        saved.away,
        const ConnectionAddress(
          url: 'https://radarr.example.net',
          access: CloudflareServiceToken(
            clientId: 'abc.access',
            clientSecret: 'shh',
          ),
        ),
      );

      await harness.unmount(tester);
    });

    testWidgets('emptied, the address away is forgotten', (tester) async {
      final (harness, container) = await _pumpForm(
        tester,
        profile: Profiles.p3.withConnection(
          ProfileConnection(
            WorldConnections.radarr.instance.copyWith(
              away: const ConnectionAddress(url: 'https://radarr.example.net'),
            ),
          ),
        ),
      );
      expect(
        tester.widget<TextField>(_field(_away)).controller!.text,
        'https://radarr.example.net',
      );

      await _type(tester, _away, '');
      await _tap(tester, find.text('Save'), harness);

      expect(_saved(container)!.away, isNull);

      await harness.unmount(tester);
    });

    testWidgets('the address away cannot be the one at home', (tester) async {
      final (harness, container) = await _pumpForm(tester);
      final home = _saved(container)!.url;

      await _type(tester, _away, home);
      await _tap(tester, find.text('Save'), harness);

      expect(
        find.text(
          'This is the address at home. Use the one you reach from outside, '
          'or leave this empty.',
        ),
        findsOneWidget,
      );
      expect(_saved(container)!.away, isNull);

      await harness.unmount(tester);
    });
  });

  group('http across the internet', () {
    testWidgets('is refused at home: nothing saved, Save leads to the field, '
        'and Use https is the fix', (tester) async {
      final (harness, container) = await _pumpForm(tester);
      final before = _saved(container)!.url;

      await _type(tester, _home, 'http://radarr.example.com');
      expect(find.text(_refusedHome), findsOneWidget);
      expect(find.text('Use https'), findsOneWidget);

      await _tap(tester, find.text('Save'), harness);
      expect(_saved(container)!.url, before);
      expect(find.text('Use https'), findsOneWidget, reason: 'still here');
      expect(
        tester.widget<TextField>(_field(_home)).focusNode!.hasFocus,
        isTrue,
        reason: 'Save moves to the refused field',
      );

      await _tap(tester, find.text('Use https'), harness);
      expect(
        tester.widget<TextField>(_field(_home)).controller!.text,
        'https://radarr.example.com',
      );
      expect(find.text(_refusedHome), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('is refused away, where it can also be left empty', (
      tester,
    ) async {
      final (harness, container) = await _pumpForm(tester);

      await _type(tester, _away, 'http://radarr.example.com');
      expect(find.text(_refusedAway), findsOneWidget);
      await _tap(tester, find.text('Save'), harness);
      expect(_saved(container)!.away, isNull);

      await harness.unmount(tester);
    });

    testWidgets('a tailnet address is not refused: WireGuard carries it', (
      tester,
    ) async {
      final (harness, container) = await _pumpForm(tester);

      await _type(tester, _away, 'http://100.101.102.103:7878');
      expect(find.text(_refusedAway), findsNothing);
      expect(find.text('Use https'), findsNothing);
      await _tap(tester, find.text('Save'), harness);
      expect(_saved(container)!.away?.url, 'http://100.101.102.103:7878');

      await harness.unmount(tester);
    });

    testWidgets('on the local network nothing is said', (tester) async {
      final (harness, _) = await _pumpForm(tester);

      await _type(tester, _home, 'http://192.168.1.20:7878');
      expect(find.text(_refusedHome), findsNothing);
      expect(find.text('Use https'), findsNothing);

      await harness.unmount(tester);
    });
  });

  group('the test asks both addresses', () {
    testWidgets('both answer: one panel for each, saying where', (
      tester,
    ) async {
      final (harness, _) = await _pumpForm(
        tester,
        network: (h) => h.network.serveAlsoAt(
          WorldIds.radarr,
          'https://radarr.example.net',
        ),
      );

      await _type(tester, _away, 'https://radarr.example.net');
      await _tap(tester, find.text('Test connection'), harness);

      expect(find.text('Answering'), findsNWidgets(2));
      expect(find.text('At home · nas.home.arpa:7878'), findsOneWidget);
      expect(find.text('Away · radarr.example.net'), findsOneWidget);
      expect(find.text('Not checked from here'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('the address away silent from home is blue, not a fault (Q2)', (
      tester,
    ) async {
      final (harness, _) = await _pumpForm(tester);

      await _type(tester, _away, 'https://silent.example.net');
      await _tap(tester, find.text('Test connection'), harness);

      expect(find.text('Answering'), findsOneWidget);
      expect(find.text('Not checked from here'), findsOneWidget);
      expect(
        find.text("Cupola tries it when the home address doesn't answer."),
        findsOneWidget,
      );
      expect(find.text('Away · silent.example.net'), findsOneWidget);
      expect(find.text('Unreachable'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('neither answers: one red panel naming both', (tester) async {
      final (harness, _) = await _pumpForm(
        tester,
        profile: Profiles.p3.withBehaviour(
          WorldIds.radarr,
          ConnectionBehaviour.didNotAnswer,
        ),
      );

      await _type(tester, _away, 'https://silent.example.net');
      await _tap(tester, find.text('Test connection'), harness);

      expect(
        find.text('Radarr did not answer at home or away.'),
        findsOneWidget,
      );
      expect(find.text('At home · nas.home.arpa:7878'), findsOneWidget);
      expect(find.text('Away · silent.example.net'), findsOneWidget);
      expect(find.text('Not checked from here'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('one address alone keeps the one panel, with no address line', (
      tester,
    ) async {
      final (harness, _) = await _pumpForm(tester);

      await _tap(tester, find.text('Test connection'), harness);

      expect(find.text('Radarr answered as expected.'), findsOneWidget);
      expect(find.textContaining('At home ·'), findsNothing);

      await harness.unmount(tester);
    });
  });
}
