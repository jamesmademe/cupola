/// What Save waits for. A save that moved the connection (an address, the one
/// away, a gateway's access) still tests it and offers the certificate it
/// finds; one that left them as they were closes at once, with no test of the
/// connection to wait out, which with the server down was ten seconds and more.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _fingerprint =
    'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12';

const UntrustedCertificateProbe _selfSigned = (
  certificate: ServerCertificate(
    fingerprint: _fingerprint,
    subject: 'CN=nas.home.arpa',
    issuer: 'CN=nas.home.arpa',
  ),
  rotated: false,
);

/// Radarr 4K's form on P1, whose server offers a certificate nobody trusts,
/// pushed over a launcher so a save can pop. The list holds the addresses its
/// certificate probe was asked about.
Future<(ProfileHarness, ProviderContainer, List<String>)> _pumpForm(
  WidgetTester tester,
) async {
  final harness = await ProfileHarness.start(Profiles.p1);
  harness.network.behave(WorldIds.radarr4k, ConnectionBehaviour.untrustedTls);
  final container = harness.container();
  final probed = <String>[];
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
                  instanceId: WorldIds.radarr4k,
                  certificateProber: (url, {pinnedFingerprint = ''}) async {
                    probed.add(url);
                    return const UntrustedCertificate(_selfSigned);
                  },
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
  return (harness, container, probed);
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(_field(label), text);
  await tester.pump();
}

/// Taps Save and lets the page do what it does next: with a certificate to
/// offer the dialog opens while the test's spinner still turns, so nothing
/// settles behind it.
Future<void> _save(WidgetTester tester) async {
  final save = find.text('Save');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('a name changed alone closes at once, and asks no certificate', (
    tester,
  ) async {
    final (harness, container, probed) = await _pumpForm(tester);

    await _type(tester, 'Name', 'UHD');
    await _save(tester);

    expect(probed, isEmpty, reason: 'the address did not move');
    expect(find.text('Self-signed certificate'), findsNothing);
    expect(find.byType(ServiceSettingsScreen), findsNothing);
    expect(
      container.read(settingsProvider).instanceById(WorldIds.radarr4k)?.label,
      'UHD',
    );

    await harness.unmount(tester);
  });

  testWidgets('a key changed alone closes at once as well', (tester) async {
    final (harness, container, probed) = await _pumpForm(tester);

    await _type(tester, 'API key', 'a-new-key');
    await _save(tester);

    expect(probed, isEmpty);
    expect(find.text('Self-signed certificate'), findsNothing);
    expect(find.byType(ServiceSettingsScreen), findsNothing);
    expect(
      container
          .read(settingsProvider)
          .instanceById(WorldIds.radarr4k)
          ?.credential,
      'a-new-key',
    );

    await harness.unmount(tester);
  });

  testWidgets('a new address at home still offers the certificate it finds', (
    tester,
  ) async {
    final (harness, _, probed) = await _pumpForm(tester);

    await _type(tester, 'Address at home', 'https://nas.home.arpa:7880');
    await _save(tester);

    expect(probed, isNotEmpty);
    expect(find.text('Self-signed certificate'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await harness.settle(tester);
    expect(find.byType(ServiceSettingsScreen), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('an address away added still offers it too', (tester) async {
    final (harness, _, probed) = await _pumpForm(tester);

    await _type(
      tester,
      'Address away\u00A0· optional',
      'https://r.example.net',
    );
    await _save(tester);

    expect(probed, isNotEmpty);
    expect(find.text('Self-signed certificate'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await harness.settle(tester);

    await harness.unmount(tester);
  });
}
