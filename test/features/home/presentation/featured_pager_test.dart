import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/presentation/widgets/featured_pager.dart';

/// Featured's pager: it moves on by itself, and stops whenever a person is
/// in the middle of something.
void main() {
  late List<int> shown;
  late List<String> acted;

  Future<void> pump(
    WidgetTester tester, {
    int count = 3,
    bool screenReader = false,
    bool reduceMotion = false,
    bool live = true,
  }) async {
    shown = [];
    acted = [];
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            accessibleNavigation: screenReader,
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: FeaturedPager(
              live: live,
              onShown: shown.add,
              pages: [
                for (var i = 0; i < count; i++)
                  FeaturedPage(
                    title: 'Title $i',
                    line: 'Line $i',
                    art: (url: 'https://art.test/$i.jpg', headers: null),
                    label: 'Title $i, line $i',
                    onOpen: () => acted.add('open $i'),
                    lead: FeaturedAction(
                      'Resume',
                      () => acted.add('lead $i'),
                      icon: Icons.play_arrow_rounded,
                    ),
                    second: FeaturedAction(
                      'Details',
                      () => acted.add('second $i'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const dwell = Duration(milliseconds: 6001);

  testWidgets('moves on every six seconds, round to the first', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 5900));
    expect(shown, isEmpty);
    await tester.pump(const Duration(milliseconds: 200));
    expect(shown, [1]);
    await tester.pump(dwell);
    await tester.pump(dwell);
    expect(shown, [1, 2, 0]);
  });

  testWidgets('a finger down holds the slide, and it stays 1.2 s after', (
    tester,
  ) async {
    await pump(tester);
    final finger = await tester.startGesture(
      tester.getCenter(find.text('Line 0').hitTestable()),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(shown, isEmpty);
    await finger.up();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(shown, isEmpty);
    // The hold ends at 1.2 s, and the slide's six seconds start again.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 5900));
    expect(shown, isEmpty);
    await tester.pump(const Duration(milliseconds: 200));
    expect(shown, [1]);
  });

  testWidgets('a touch in the first half of a change acts on the slide '
      'that was leaving, and brings it back', (tester) async {
    await pump(tester);
    await tester.pump(dwell);
    expect(shown, [1]);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Resume').hitTestable());
    expect(acted, ['lead 0']);
    expect(shown, [1, 0]);
  });

  testWidgets('past the half of a change, a touch acts on the new slide', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump(dwell);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Details').hitTestable());
    expect(acted, ['second 1']);
    expect(shown, [1]);
  });

  testWidgets('the artwork opens the slide in front', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Title 0, line 0'));
    expect(acted, ['open 0']);
    semantics.dispose();
  });

  testWidgets('the pause control stops it and then reads Play', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Pause featured, 1 of 3'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 20));
    expect(shown, isEmpty);
    await tester.tap(find.bySemanticsLabel('Play featured, 1 of 3'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(dwell);
    expect(shown, [1]);
    semantics.dispose();
  });

  testWidgets('with a screen reader nothing moves on, and each dot is a '
      'button', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, screenReader: true);
    await tester.pump(const Duration(seconds: 20));
    expect(shown, isEmpty);
    expect(find.bySemanticsLabel('Play featured, 1 of 3'), findsOne);
    await tester.tap(find.bySemanticsLabel('Show slide 2 of 3'));
    await tester.pump(const Duration(seconds: 1));
    expect(shown, [1]);
    expect(find.bySemanticsLabel('Play featured, 2 of 3'), findsOne);
    semantics.dispose();
  });

  testWidgets('with Reduce Motion nothing moves on until asked', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, reduceMotion: true);
    await tester.pump(const Duration(seconds: 20));
    expect(shown, isEmpty);
    expect(find.bySemanticsLabel('Show slide 3 of 3'), findsOne);
    semantics.dispose();
  });

  testWidgets('one slide: no control, and it stays', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, count: 1);
    await tester.pump(const Duration(seconds: 20));
    expect(shown, isEmpty);
    expect(find.bySemanticsLabel(RegExp('featured, 1 of 1')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Show slide')), findsNothing);
    semantics.dispose();
  });

  testWidgets('a page that is not on screen does not move', (tester) async {
    await pump(tester, live: false);
    await tester.pump(const Duration(seconds: 20));
    expect(shown, isEmpty);
  });

  testWidgets('a swipe moves to the next slide and back', (tester) async {
    await pump(tester);
    await tester.drag(find.text('Line 0').hitTestable(), const Offset(-120, 0));
    // A frame to start the crossfade, then past it.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(shown, [1]);
    await tester.drag(find.text('Line 1').hitTestable(), const Offset(120, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(shown, [1, 0]);
  });
}
