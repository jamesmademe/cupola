import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/shell/domain/portal_hints.dart';
import 'package:cupola/features/shell/presentation/portal_coach_mark.dart';
import 'package:cupola/features/shell/presentation/service_portal.dart';

/// Counts the bounces instead of animating the bar.
class _CountingController extends ServicePortalController {
  _CountingController({required super.vsync});

  int bounces = 0;

  @override
  Future<void> playDemoBounce() async => bounces++;
}

/// Pumps the coach mark hidden, then earns it the way the app does — enough
/// manual journeys — and runs the arrival part of the way in.
///
/// Returns the pill's vertical slide, in its own heights, part of the way
/// through the arrival.
Future<({_CountingController controller, double slide})> _arrive(
  WidgetTester tester, {
  required bool reduceMotion,
  bool screenReader = false,
}) async {
  final controller = _CountingController(vsync: tester);
  addTearDown(controller.dispose);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            disableAnimations: reduceMotion,
            accessibleNavigation: screenReader,
          ),
          child: Scaffold(
            body: Stack(children: [PortalCoachMark(controller: controller)]),
          ),
        ),
      ),
    ),
  );
  expect(container.read(portalHintsProvider).coachVisible, isFalse);

  final hints = container.read(portalHintsProvider.notifier);
  for (var i = 0; i < PortalHintsState.coachJourneyThreshold; i++) {
    hints.noteManualJourney();
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));

  final slide = tester
      .widget<FractionalTranslation>(
        find.descendant(
          of: find.byType(AnimatedSlide),
          matching: find.byType(FractionalTranslation),
        ),
      )
      .translation
      .dy;
  await tester.pumpAndSettle();
  return (controller: controller, slide: slide);
}

void main() {
  testWidgets('the words arrive with one bounce of the bar', (tester) async {
    final result = await _arrive(tester, reduceMotion: false);

    expect(find.text('Swipe up to open the Portal'), findsOneWidget);
    expect(result.controller.bounces, 1);
    // And the pill rises into place.
    expect(result.slide, greaterThan(0));
  });

  testWidgets('under Reduce Motion nothing lifts: no bounce, no slide', (
    tester,
  ) async {
    final result = await _arrive(tester, reduceMotion: true);

    expect(find.text('Swipe up to open the Portal'), findsOneWidget);
    expect(result.controller.bounces, 0);
    expect(result.slide, 0);
  });

  testWidgets('with a screen reader the words arrive without the bounce', (
    tester,
  ) async {
    final result = await _arrive(
      tester,
      reduceMotion: false,
      screenReader: true,
    );

    expect(find.text('Swipe up to open the Portal'), findsOneWidget);
    expect(result.controller.bounces, 0);
  });
}
