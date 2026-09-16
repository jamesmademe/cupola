import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';

/// Decision 46: **the compact frame is not a narrow one.**
///
/// The flow used to decide between its two arrangements on width alone
/// (`>= AppBreakpoints.desktopCompact`, i.e. 1100), which made the four drawn
/// compact onboarding frames unreachable: at 720x450 a desktop window kept the
/// phone's stacked layout. The gate is the window's *shape* now, so the test is
/// about shape — a portrait window twice as wide as the compact one still
/// stacks, and a landscape window half its width does not.
void main() {
  Future<bool> sideBySideAt(
    WidgetTester tester,
    Size size, {
    required TargetPlatform platform,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    late bool answer;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(
          builder: (context) {
            answer = onboardingSideBySide(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // Cleared inside the body rather than in `tearDown`: the harness checks
    // that no foundation debug variable survives the test, and that check runs
    // before tear-down callbacks do.
    debugDefaultTargetPlatformOverride = null;
    return answer;
  }

  group('onboardingSideBySide', () {
    testWidgets('a landscape desktop window gets the two-column arrangement '
        'whatever its width', (tester) async {
      // The three drawn desktop frames, and the one that used to fail: 720x450
      // is 1.6:1, the same shape as 1440x900.
      expect(
        await sideBySideAt(
          tester,
          const Size(1440, 900),
          platform: TargetPlatform.macOS,
        ),
        isTrue,
      );
      expect(
        await sideBySideAt(
          tester,
          const Size(720, 450),
          platform: TargetPlatform.macOS,
        ),
        isTrue,
      );
    });

    testWidgets('a portrait window stacks however wide it is', (tester) async {
      // The phone, which is the only portrait frame the flow draws…
      expect(
        await sideBySideAt(
          tester,
          const Size(390, 844),
          platform: TargetPlatform.macOS,
        ),
        isFalse,
      );
      // …and a desktop window dragged taller than it is wide, which the old
      // width gate would have handed two columns and nowhere to put them.
      expect(
        await sideBySideAt(
          tester,
          const Size(900, 1200),
          platform: TargetPlatform.macOS,
        ),
        isFalse,
      );
    });

    testWidgets('a touch build never gets it, however landscape', (
      tester,
    ) async {
      // Platform first: a tablet in landscape has no window to put a second
      // column beside, and this is the test that keeps window chrome off it.
      expect(
        await sideBySideAt(
          tester,
          const Size(1440, 900),
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });
  });
}
