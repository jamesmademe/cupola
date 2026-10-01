/// Home's Renew asks what the NPM account may change.
///
/// An expiring certificate is a decision on Home, and its control is Renew.
/// The Certificates tab already dims its own Renew for an account that can
/// only view certificates, but Home drew the same control live for that
/// account, so the one place that collects faults across services offered a
/// write the account cannot make. Home now reads the same grant.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_capability.dart';
import 'package:cupola/features/services/presentation/dashboard_screen.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _tall = Size(430, 6000);
const _npm = 'npm';

/// One Let's Encrypt certificate ten days from lapsing, on the NPM at [_npm].
void _scriptExpiringCertificate(ProfileNetwork network) => network.on(
  _npm,
  'GET',
  '/api/nginx/certificates',
  (r) => NetworkReply.json([
    {
      'id': 7,
      'provider': 'letsencrypt',
      'nice_name': 'jellyfin.example.com',
      'domain_names': ['jellyfin.example.com'],
      'expires_on': network.now
          .add(const Duration(days: 10))
          .toUtc()
          .toIso8601String(),
    },
  ]),
);

Future<ProfileHarness> _pumpHome(
  WidgetTester tester,
  ConfigProfile profile,
) async {
  final harness = await ProfileHarness.start(profile);
  _scriptExpiringCertificate(harness.network);
  await tester.binding.setSurfaceSize(_tall);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: const DashboardScreen(),
      ),
    ),
  );
  await harness.settle(tester);
  return harness;
}

Finder get _renew => find.descendant(
  of: find.byType(DashboardDecisionsSection),
  matching: find.text('Renew'),
);

/// Whether [label] sits under the gate's dim.
bool _dimmed(WidgetTester tester, Finder label) => tester
    .widgetList<Opacity>(
      find.ancestor(of: label, matching: find.byType(Opacity)),
    )
    .any((o) => o.opacity == GatedAffordance.dimmedOpacity);

void main() {
  testWidgets('a view-only NPM account: Renew is dimmed, hinted, and answers '
      'with the account it needs', (tester) async {
    final handle = tester.ensureSemantics();
    final harness = await _pumpHome(
      tester,
      Profiles.p3.withConnection(
        WorldConnections.npm.withBehaviour(ConnectionBehaviour.readOnly),
      ),
    );

    expect(_renew, findsOneWidget);
    expect(_dimmed(tester, _renew), isTrue);
    // Still a button a screen reader stops on, never a disabled one.
    expect(
      tester.getSemantics(
        find.ancestor(of: _renew, matching: find.byType(TextButton)),
      ),
      containsSemantics(
        label: 'Renew',
        hint: npmCapabilityHint,
        isButton: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    // The probe is what told it: NPM's own answer about this account.
    expect(
      harness.network.requestsTo(_npm).where((r) => r.path == '/api/users/me'),
      isNotEmpty,
    );

    await tester.tap(_renew);
    await tester.pump();
    expect(
      find.text(npmBlockedMessage(NpmResource.certificates)),
      findsOneWidget,
    );
    expect(find.text('Change account'), findsOneWidget);

    handle.dispose();
    await harness.unmount(tester);
  });

  testWidgets('an admin NPM account: Renew is live', (tester) async {
    final handle = tester.ensureSemantics();
    final harness = await _pumpHome(
      tester,
      Profiles.p3.withConnection(WorldConnections.npm),
    );

    expect(_renew, findsOneWidget);
    expect(_dimmed(tester, _renew), isFalse);
    expect(
      tester
          .getSemantics(
            find.ancestor(of: _renew, matching: find.byType(TextButton)),
          )
          .hint,
      isEmpty,
    );

    handle.dispose();
    await harness.unmount(tester);
  });
}
