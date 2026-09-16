import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_breakpoints.dart';

/// The three drawn frames, by the numbers the canvas uses.
const _full = Size(1440, 900); // 1.60:1
const _compact = Size(720, 450); // 1.60:1
const _phone = Size(390, 844); // 0.46:1

Future<void> _pumpAt(WidgetTester tester, Size size, ValueChanged<bool> out) {
  return tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: Builder(
        builder: (context) {
          out(AppBreakpoints.isLandscapeFrame(context));
          return const SizedBox.shrink();
        },
      ),
    ),
  );
}

void main() {
  group('AppBreakpoints.isLandscapeFrame', () {
    // Decision 46, and the reason the threshold moved here from the onboarding
    // feature: **the compact frame is not a narrow one.** The flow used to gate
    // its two-column arrangement on `desktopCompact` (1100), which is why the
    // four drawn compact frames were code the app could never reach — at 720 it
    // kept the phone's stacked layout in a window shaped nothing like a phone.
    testWidgets('720x450 answers the same as 1440x900', (tester) async {
      late bool full;
      late bool compact;
      await _pumpAt(tester, _full, (v) => full = v);
      await _pumpAt(tester, _compact, (v) => compact = v);

      expect(full, isTrue);
      expect(compact, isTrue, reason: '720x450 is 1.6:1, exactly as 1440 is');
    });

    // The phone is the only portrait frame in the flow, and the only one that
    // stacks and scrolls.
    testWidgets('the phone is the one frame that stacks', (tester) async {
      late bool phone;
      await _pumpAt(tester, _phone, (v) => phone = v);

      expect(phone, isFalse);
    });

    // 1.2 rather than a bare `width > height`: a window dragged to nearly
    // square has no room for a second column whatever its orientation says.
    testWidgets('a nearly square window stacks despite being landscape', (
      tester,
    ) async {
      late bool square;
      await _pumpAt(tester, const Size(1000, 900), (v) => square = v);

      expect(square, isFalse);
    });

    // A degenerate size is what a test harness's first frame and a window
    // mid-restore both hand out. Dividing by it would throw or answer infinity;
    // "stack it" is the safe answer to a shape that is not known yet.
    testWidgets('a zero height stacks rather than dividing by it', (
      tester,
    ) async {
      late bool degenerate;
      await _pumpAt(tester, Size.zero, (v) => degenerate = v);

      expect(degenerate, isFalse);
    });

    test('the threshold sits between the drawn frames, not on one', () {
      expect(AppBreakpoints.landscapeAspect, greaterThan(_phone.aspectRatio));
      expect(AppBreakpoints.landscapeAspect, lessThan(_compact.aspectRatio));
    });
  });
}
