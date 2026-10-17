/// The connection test where TLS is the question: a port that answers in plain
/// http says so and offers nothing to trust; a certificate offered and not
/// trusted stays on the panel to be checked again; and a handshake that broke
/// off before any certificate arrived says that, instead of promising one.
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

/// The https Radarr 4K's form on P1, with [prober] as its certificate probe.
Future<(ProfileHarness, ProviderContainer)> _pumpForm(
  WidgetTester tester, {
  required ConnectionBehaviour behaviour,
  required CertificateProber prober,
}) async {
  final harness = await ProfileHarness.start(Profiles.p1);
  harness.network.behave(WorldIds.radarr4k, behaviour);
  final container = harness.container();
  await tester.binding.setSurfaceSize(const Size(430, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: ServiceSettingsScreen(
          service: ServiceKey.radarr,
          instanceId: WorldIds.radarr4k,
          certificateProber: prober,
          localNetworkProbe: (_, {timeout = Duration.zero}) async =>
              LocalNetworkAccess.unrestricted,
        ),
      ),
    ),
  );
  await harness.settle(tester);
  return (harness, container);
}

/// Taps [finder] and waits for the trust dialog, which opens while the test's
/// spinner still turns, so nothing settles behind it.
Future<void> _toTrustPrompt(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Answers the open dialog with [finder], then lets the retest finish.
Future<void> _answer(
  WidgetTester tester,
  Finder finder,
  ProfileHarness h,
) async {
  await tester.tap(finder);
  await h.settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder, ProfileHarness h) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await h.settle(tester);
}

void main() {
  testWidgets('a port that answers in plain http says so, and asks about no '
      'certificate', (tester) async {
    var probed = 0;
    final (harness, _) = await _pumpForm(
      tester,
      behaviour: ConnectionBehaviour.plainHttpPort,
      prober: (_, {pinnedFingerprint = ''}) async {
        probed++;
        return const UntrustedCertificate(_selfSigned);
      },
    );

    await _tap(tester, find.text('Test connection'), harness);

    // The saved connection's header says it too.
    expect(find.text('No https on this port'), findsNWidgets(2));
    expect(find.textContaining('plain http, not https'), findsOneWidget);
    expect(find.text('Certificate not trusted'), findsNothing);
    expect(find.text('Check the certificate'), findsNothing);
    expect(probed, 0, reason: 'no certificate was sent, so none is probed');
    expect(find.text('Self-signed certificate'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('a certificate not trusted stays on the panel, and trusting it '
      'there tests again', (tester) async {
    final (harness, container) = await _pumpForm(
      tester,
      behaviour: ConnectionBehaviour.untrustedTls,
      prober: (_, {pinnedFingerprint = ''}) async =>
          const UntrustedCertificate(_selfSigned),
    );

    await _toTrustPrompt(tester, find.text('Test connection'));
    expect(find.text('Self-signed certificate'), findsOneWidget);
    await _answer(tester, find.text('Cancel'), harness);

    expect(find.text('Certificate not trusted'), findsNWidgets(2));
    expect(
      find.text(
        'Radarr sent a certificate this device does not trust. If it is '
        'your own, check it and trust it.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('test again'), findsNothing);

    // Trusted now, the server answers through the pin.
    harness.network.behave(WorldIds.radarr4k, ConnectionBehaviour.answers);
    await _toTrustPrompt(tester, find.text('Check the certificate'));
    expect(find.text('Self-signed certificate'), findsOneWidget);
    await _answer(tester, find.text('Trust this certificate'), harness);

    // The panel, and the saved connection's header above the form.
    expect(find.text('Answering'), findsNWidgets(2));
    expect(find.text('Check the certificate'), findsNothing);
    expect(
      container.read(settingsProvider).trustedCertificates.values,
      contains(_fingerprint),
    );

    await harness.unmount(tester);
  });

  testWidgets('a handshake that broke off with nothing behind it is no '
      'secure connection, and asks about no certificate', (tester) async {
    final (harness, _) = await _pumpForm(
      tester,
      behaviour: ConnectionBehaviour.closesHandshake,
      prober: (_, {pinnedFingerprint = ''}) async => null,
    );

    await _tap(tester, find.text('Test connection'), harness);

    // The panel, and the saved connection's header above the form.
    expect(find.text('No secure connection'), findsNWidgets(2));
    expect(
      find.text(
        'The secure connection broke off before a certificate arrived. Check '
        'that this port serves https.',
      ),
      findsOneWidget,
    );
    expect(find.text('Certificate not trusted'), findsNothing);
    expect(find.text('Check the certificate'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('a port that waits out the handshake and answers plain http is '
      'a port without https, not silence', (tester) async {
    // qBittorrent and Bazarr: the TLS hello gets no reply until the
    // deadline, and a plain request gets one at once.
    final (harness, _) = await _pumpForm(
      tester,
      behaviour: ConnectionBehaviour.timesOut,
      prober: (_, {pinnedFingerprint = ''}) async => const PlainHttpPort(),
    );

    await _tap(tester, find.text('Test connection'), harness);

    expect(find.text('No https on this port'), findsOneWidget);
    expect(find.textContaining('plain http, not https'), findsOneWidget);
    expect(find.text('Did not answer'), findsOneWidget, reason: 'the header');

    await harness.unmount(tester);
  });

  testWidgets('a broken-off handshake whose probe finds a certificate offers '
      'it after all', (tester) async {
    final (harness, _) = await _pumpForm(
      tester,
      behaviour: ConnectionBehaviour.closesHandshake,
      prober: (_, {pinnedFingerprint = ''}) async =>
          const UntrustedCertificate(_selfSigned),
    );

    await _toTrustPrompt(tester, find.text('Test connection'));
    expect(find.text('Self-signed certificate'), findsOneWidget);
    await _answer(tester, find.text('Cancel'), harness);

    expect(find.text('Check the certificate'), findsOneWidget);
    expect(
      find.textContaining('sent a certificate this device does not trust'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });
}
