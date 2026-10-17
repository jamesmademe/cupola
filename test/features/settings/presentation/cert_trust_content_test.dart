import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_content.dart';

final _cert = ServerCertificate(
  fingerprint:
      'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab1',
  subject: 'CN=nas.local',
  issuer: 'CN=nas.local',
  validFrom: DateTime(2026, 10, 13, 20, 41, 18),
  validTo: DateTime(2027, 10, 13, 20, 41, 18),
);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme(),
  home: Scaffold(body: child),
);

void main() {
  group('displayOrigin', () {
    test('drops the https:// prefix, since every origin carries one', () {
      expect(displayOrigin('https://nas.local:8443'), 'nas.local:8443');
    });

    test('drops the default port nobody typed', () {
      expect(displayOrigin('https://nas.local:443'), 'nas.local');
    });
  });

  group('CertTrustContent', () {
    testWidgets('first trust reads as a normal prompt, not an escalation', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CertTrustContent(
            origin: 'https://nas.local:8443',
            probe: (certificate: _cert, rotated: false),
          ),
        ),
      );

      // Was 'Untrusted certificate'. The card names what the *server* did
      // rather than what this device concluded: a self-signed certificate is
      // the normal condition on a home install, and it is the phrase the user
      // recognises from having generated one.
      expect(find.text('Self-signed certificate'), findsOneWidget);
      expect(find.text('This certificate has changed'), findsNothing);
      expect(find.textContaining('nas.local:8443'), findsOneWidget);
      expect(find.text('Subject'), findsOneWidget);
      expect(find.text('SHA-256'), findsOneWidget);
      // Dates as a person reads them, not as `DateTime.toString` prints them.
      expect(find.text('Oct 13, 2026'), findsOneWidget);
      expect(find.text('Oct 13, 2027'), findsOneWidget);
      expect(find.textContaining('20:41:18'), findsNothing);
      // Nothing to compare against on a first trust.
      expect(find.text('Previously trusted'), findsNothing);
    });

    testWidgets('a certificate other than the invite\'s says so in amber, '
        'beside the invite\'s', (tester) async {
      const invited =
          '99ee88dd77cc99ee88dd77cc99ee88dd77cc99ee88dd77cc99ee88dd77cc99e';

      await tester.pumpWidget(
        _host(
          CertTrustContent(
            origin: 'https://nas.local:8443',
            probe: (certificate: _cert, rotated: false),
            invitedFingerprint: invited,
          ),
        ),
      );

      final line = tester.widget<Text>(
        find.text("This isn't the certificate in the invite"),
      );
      final scheme = AppTheme.darkTheme().colorScheme;
      expect(
        line.style?.color,
        statusToneColor(
          scheme,
          StatusTone.warning,
          surface:
              AppTheme.darkTheme().dialogTheme.backgroundColor ??
              scheme.surfaceContainerHigh,
        ),
      );
      expect(find.text('In the invite'), findsOneWidget);
      expect(find.textContaining('99:EE:88:DD'), findsOneWidget);
      expect(find.text('Self-signed certificate'), findsOneWidget);
    });

    testWidgets('the invite\'s own certificate says nothing of the invite', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CertTrustContent(
            origin: 'https://nas.local:8443',
            probe: (certificate: _cert, rotated: false),
            invitedFingerprint: _cert.fingerprint,
          ),
        ),
      );

      expect(
        find.text("This isn't the certificate in the invite"),
        findsNothing,
      );
      expect(find.text('In the invite'), findsNothing);
    });

    testWidgets('a rotated certificate escalates the headline and shows both '
        'fingerprints', (tester) async {
      const previous =
          '11aa22bb33cc11aa22bb33cc11aa22bb33cc11aa22bb33cc11aa22bb33cc11a';

      await tester.pumpWidget(
        _host(
          CertTrustContent(
            origin: 'https://nas.local:8443',
            probe: (certificate: _cert, rotated: true),
            previousFingerprint: previous,
          ),
        ),
      );

      expect(find.text('This certificate has changed'), findsOneWidget);
      expect(find.text('Untrusted certificate'), findsNothing);
      expect(find.text('Previously trusted'), findsOneWidget);
      // Both fingerprints render, uppercased and colon-grouped: the
      // previously-trusted one and the one presented now must both be
      // visible for the user to actually compare them.
      expect(find.textContaining('11:AA:22:BB'), findsOneWidget);
      expect(find.textContaining('AB:12:CD:34'), findsOneWidget);
    });

    // ── The escalation belongs to the rotation, and to nothing else ───────
    //
    // The shield was painted `scheme.error` in both states, so a routine first
    // trust looked exactly as dangerous as a changed fingerprint, and when
    // both look alarming, the one that matters stops standing out.
    testWidgets('the shield is neutral on a first trust and red on a change', (
      tester,
    ) async {
      final scheme = AppTheme.darkTheme().colorScheme;

      await tester.pumpWidget(
        _host(
          CertTrustContent(
            origin: 'https://nas.local:8443',
            probe: (certificate: _cert, rotated: false),
          ),
        ),
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.gpp_maybe_outlined)).color,
        scheme.onSurfaceVariant,
      );

      await tester.pumpWidget(
        _host(
          CertTrustContent(
            origin: 'https://nas.local:8443',
            probe: (certificate: _cert, rotated: true),
          ),
        ),
      );
      // Red, walked against the dialog it is drawn in rather than raw.
      expect(
        tester.widget<Icon>(find.byIcon(Icons.gpp_bad_outlined)).color,
        statusToneColor(
          scheme,
          StatusTone.error,
          surface: AppTheme.darkTheme().dialogTheme.backgroundColor,
        ),
      );
    });

    // ── ADR-6, said out loud ──────────────────────────────────────────────
    //
    // Trust is keyed by TLS origin, never by service, so the decision covers
    // services this walk has not reached yet. The onboarding card said so and
    // this content did not, which left the Settings dialog describing a
    // narrower promise than the walk for the same decision. Unconditional on
    // purpose: the shared clause below only lists what already shares the
    // origin *today*, so on a first service it said nothing at all.
    testWidgets('the body names host-pinning whether or not anything shares '
        'the origin', (tester) async {
      for (final shared in [
        <ServiceKey>[],
        [ServiceKey.sonarr],
      ]) {
        for (final rotated in [false, true]) {
          await tester.pumpWidget(
            _host(
              CertTrustContent(
                origin: 'https://nas.local:8443',
                probe: (certificate: _cert, rotated: rotated),
                sharedWith: shared,
              ),
            ),
          );
          expect(
            find.textContaining('pinned to the host'),
            findsOneWidget,
            reason: 'rotated: $rotated, shared with: $shared',
          );
        }
      }
    });

    testWidgets('names every other service the trust decision covers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CertTrustContent(
            origin: 'https://nas.local:8443',
            probe: (certificate: _cert, rotated: false),
            sharedWith: [ServiceKey.sonarr, ServiceKey.prowlarr],
          ),
        ),
      );

      expect(find.textContaining('Sonarr'), findsWidgets);
      expect(find.textContaining('Prowlarr'), findsWidgets);
    });

    testWidgets('says nothing about sharing when nothing else uses it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CertTrustContent(
            origin: 'https://nas.local:8443',
            probe: (certificate: _cert, rotated: false),
          ),
        ),
      );

      expect(find.text('Also used by'), findsNothing);
    });
  });
}
