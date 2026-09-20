import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/features/onboarding/presentation/onboarding_screen.dart';
import 'package:cupola/features/services/presentation/dashboard_screen.dart';
import 'package:cupola/main.dart' as app;

/// Native smoke gate for macOS, iOS Simulator and Android Emulator.
///
/// This deliberately verifies the real bootstrap path rather than mounting a
/// hand-built ProviderScope. It is not the feature E2E suite: that suite must
/// still exercise the seeded service lab and every service tab. Its job is to
/// catch platform/plugin/bootstrap regressions before those suites waste time.
/// Pumps until the tree is quiet, with a ceiling rather than a fixed sleep.
///
/// `pump(Duration(seconds: 5))` advances one frame and then waits: it does not
/// wait for the bootstrap's async work, so it was both slower than it needed
/// to be on a fast machine and too short on a cold simulator.
/// `pumpAndSettle` can itself time out on a screen with a looping animation,
/// which is why the timeout is caught and the assertions are left to say
/// whether the app actually arrived.
Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
  } on FlutterError {
    // A persistent animation; the tree is as settled as it is going to get.
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const captureScreenshot = bool.fromEnvironment('CUPOLA_NATIVE_SCREENSHOT');

  testWidgets('Cupola boots through onboarding to the dashboard', (
    tester,
  ) async {
    app.main();
    await _settle(tester);

    expect(find.byType(app.CupolaApp), findsOneWidget);

    // **The assertion has to be that it reached the dashboard, not that it
    // reached one of the two screens it could already have been on.** An
    // `onboarding || dashboard` check is satisfied by the state a clean
    // simulator starts in, so a Skip button that had been renamed — or a
    // routing change that trapped the app in onboarding — left this gate
    // green. There is exactly one acceptable end state and it is named below.
    final onboarding = find.byType(OnboardingScreen);
    if (tester.any(onboarding)) {
      final skip = find.text('Skip for now');
      expect(
        skip,
        findsWidgets,
        reason:
            'onboarding must offer a way past it that needs no service and no '
            'network permission; if the copy moved, this test moves with it',
      );
      await tester.tap(skip.first);
      await _settle(tester);
    }

    expect(
      find.byType(DashboardScreen),
      findsOneWidget,
      reason: 'the native bootstrap must land on the dashboard',
    );
    expect(
      find.byType(OnboardingScreen),
      findsNothing,
      reason: 'onboarding must not survive the skip',
    );

    // Keep the evidence artifact for the visual-E2E ledger. The screenshot
    // is intentionally named by target-independent state, so the same test
    // can be compared across macOS, iOS and Android.
    // Some headless Android renderers expose no Flutter screenshot surface and
    // leave `takeScreenshot` pending forever. The boot assertion remains a
    // valid native smoke gate there; visual evidence can be captured with the
    // platform screenshot tool, or this branch can be opted into explicitly
    // on a renderer that supports the integration-test screenshot protocol.
    if (captureScreenshot) {
      await binding.convertFlutterSurfaceToImage();
      await binding.takeScreenshot('cupola-native-boot');
    }
  });
}
