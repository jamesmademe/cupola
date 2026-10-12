import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_walk.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/connection_access_fields.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';

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
}

Future<void> _pumpWalk(
  WidgetTester tester, {
  required ServiceConnectionStatus status,
  required String? serverVersion,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Scaffold(
        body: OnboardingWalk(
          service: ServiceKey.truenas,
          urlController: TextEditingController(text: 'https://nas.local'),
          apiKeyController: TextEditingController(text: 'key'),
          usernameController: TextEditingController(),
          passwordController: TextEditingController(),
          accessController: ConnectionAccessController(ServiceKey.truenas),
          accessFormKey: GlobalKey<FormState>(),
          onShowAccess: (_) {},
          status: status,
          reason: null,
          failureDetail: null,
          serverVersion: serverVersion,
          verifying: false,
          certificateProbe: null,
          trustedFingerprint: null,
          next: null,
          onTest: () async {},
          onTrustCertificate: () {},
          onSuggestPort: () {},
          onSkip: () {},
          onAdvance: () {},
          onBack: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
