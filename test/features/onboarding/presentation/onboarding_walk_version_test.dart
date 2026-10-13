import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_walk.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/connection_access_fields.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';

import '../../../test_helpers/reel_finders.dart';

void main() {
  group('OnboardingWalk outcome', () {
    testWidgets('prints the version a connected server reported', (
      tester,
    ) async {
      await _pumpWalk(
        tester,
        status: ServiceConnectionStatus.connected,
        serverVersion: 'TrueNAS-SCALE-25.04.2',
      );

      expect(find.text('TrueNAS answered.'), findsOneWidget);
      expect(
        find.textContaining('25.04.2'),
        findsOneWidget,
        reason: 'the version read during the test belongs in its outcome',
      );
    });

    testWidgets('an unsupported version qualifies the pass in warning ink', (
      tester,
    ) async {
      await _pumpWalk(
        tester,
        status: ServiceConnectionStatus.connected,
        serverVersion: 'TrueNAS-SCALE-24.10.1',
      );

      // The test passed, so nothing else on the step can tell the user that
      // half the console is about to come up empty. Matched on the reported
      // version rather than on the floor: the step's standing setup note names
      // the floor too, which is the point: it warned before the test, and this
      // line is what the test itself found.
      final line = find.textContaining('24.10.1');
      expect(line, findsOneWidget);
      final text = tester.widget<Text>(line);
      expect(text.data, contains(kTrueNasMinVersion));
      expect(text.style?.color, AppColors.warning);
    });

    testWidgets('says nothing when the server named no version', (
      tester,
    ) async {
      await _pumpWalk(
        tester,
        status: ServiceConnectionStatus.connected,
        serverVersion: null,
      );

      expect(find.textContaining('Running'), findsNothing);
    });
  });

  group('OnboardingWalk primary action', () {
    testWidgets('is a test until the service has answered', (tester) async {
      await _pumpWalk(tester, status: null);

      expect(_primary('Test connection'), findsOneWidget);
      expect(_primary('Go to Home'), findsNothing);
    });

    testWidgets('turns into the way forward the service was given, once it '
        'answers', (tester) async {
      var advanced = 0;
      await _pumpWalk(
        tester,
        status: ServiceConnectionStatus.connected,
        onAdvance: () => advanced++,
      );

      expect(_primary('Go to Home'), findsOneWidget);
      expect(_primary('Test connection'), findsNothing);

      await tester.tap(_primary('Go to Home'));
      await tester.pumpAndSettle();
      expect(advanced, 1);
    });

    testWidgets('says Continue where a second step follows', (tester) async {
      await _pumpWalk(
        tester,
        status: ServiceConnectionStatus.connected,
        service: ServiceKey.seerr,
        advanceLabel: 'Continue',
      );

      expect(_primary('Continue'), findsOneWidget);
      expect(_primary('Go to Home'), findsNothing);
    });

    testWidgets('has Back and nothing to skip', (tester) async {
      await _pumpWalk(tester, status: null);

      expect(find.widgetWithText(TextButton, 'Back'), findsOneWidget);
      expect(find.textContaining('Skip'), findsNothing);
    });
  });
}

Future<void> _pumpWalk(
  WidgetTester tester, {
  required ServiceConnectionStatus? status,
  String? serverVersion,
  ServiceKey service = ServiceKey.truenas,
  String advanceLabel = 'Go to Home',
  VoidCallback? onAdvance,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Scaffold(
        body: OnboardingWalk(
          service: service,
          urlController: TextEditingController(text: 'https://nas.local'),
          apiKeyController: TextEditingController(text: 'key'),
          usernameController: TextEditingController(),
          passwordController: TextEditingController(),
          accessController: ConnectionAccessController(service),
          accessFormKey: GlobalKey<FormState>(),
          onShowAccess: (_) {},
          status: status,
          reason: null,
          failureDetail: null,
          serverVersion: serverVersion,
          verifying: false,
          certificateProbe: null,
          trustedFingerprint: null,
          advanceLabel: advanceLabel,
          onTest: () async {},
          onTrustCertificate: () {},
          onSuggestPort: () {},
          onAdvance: onAdvance ?? () {},
          onBack: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The primary button by its label, whether it is plain text or a rolled line.
Finder _primary(String label) =>
    find.ancestor(of: findLine(label), matching: find.byType(FilledButton));
