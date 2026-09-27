import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/capability_banner.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/section_header.dart';

/// The floor a finger can reach: iOS's 44pt. Android's 48dp is the theme's own
/// padded floor and lands above it.
const double _floor = 44;

/// Measures what a finger can hit, not what the eye sees.
///
/// Every control here once declared 44 and measured 40, because
/// `VisualDensity.compact` takes 8 off `minimumSize` *and* off the padded tap
/// target — a size nobody reads back once it is written. So the assertion is
/// the rendered box of the button itself, which is where the padding lives.
void _expectReachable(WidgetTester tester, Finder button) {
  expect(button, findsOneWidget);
  final size = tester.getSize(button);
  expect(
    size.width,
    greaterThanOrEqualTo(_floor),
    reason: 'tap target is ${size.width} wide',
  );
  expect(
    size.height,
    greaterThanOrEqualTo(_floor),
    reason: 'tap target is ${size.height} tall',
  );
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Column(children: [child])),
    ),
  );
}

Finder _textButton(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextButton));

void main() {
  testWidgets(
    'InlineErrorRetry: Retry is reachable',
    (tester) async {
      await _pump(
        tester,
        InlineErrorRetry(message: 'Could not load the queue.', onRetry: () {}),
      );

      _expectReachable(tester, _textButton('Retry'));
    },
    variant: TargetPlatformVariant.mobile(),
  );

  testWidgets(
    'CapabilityBanner: the fix verb is reachable',
    (tester) async {
      await _pump(
        tester,
        CapabilityBanner(
          message: 'This key can read. Start and stop need write scope.',
          onFix: () {},
        ),
      );

      _expectReachable(tester, _textButton('Update the key'));
    },
    variant: TargetPlatformVariant.mobile(),
  );

  testWidgets(
    'FaultBand: both recovery verbs are reachable',
    (tester) async {
      await _pump(
        tester,
        FaultBand.section(
          message: 'Calendar did not answer.',
          onRetry: () {},
          onOpenSettings: () {},
        ),
      );

      _expectReachable(tester, _textButton('Retry'));
      _expectReachable(tester, _textButton('Settings'));
    },
    variant: TargetPlatformVariant.mobile(),
  );

  testWidgets(
    'AppBottomSheet: the close button is reachable',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBottomSheet(
              title: 'Releases',
              showClose: true,
              child: SizedBox(height: 40),
            ),
          ),
        ),
      );

      _expectReachable(
        tester,
        find.ancestor(
          of: find.byIcon(Icons.close_rounded),
          matching: find.byType(IconButton),
        ),
      );
    },
    variant: TargetPlatformVariant.mobile(),
  );

  // The whole row is the button, and a one-line title made it 36pt tall.
  testWidgets(
    'SectionHeader: a tappable header is reachable',
    (tester) async {
      await _pump(tester, SectionHeader(title: 'Popular movies', onTap: () {}));

      _expectReachable(tester, find.byType(InkWell));
    },
    variant: TargetPlatformVariant.mobile(),
  );
}
