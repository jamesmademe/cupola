import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/title_light.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_band.dart';

final _now = DateTime(2026, 9, 29, 20, 53);

/// [title], [inDays] days after today.
CalendarEvent _event(String title, int inDays) => CalendarEvent(
  identity: title,
  kind: CalendarKind.movie,
  day: DateTime(2026, 9, 29 + inDays),
  title: title,
  sources: const ['Radarr'],
  state: const CalendarState.notYet(),
);

Future<void> _pump(
  WidgetTester tester,
  double width,
  List<CalendarEvent> events,
) async {
  tester.view
    ..physicalSize = Size(width, 600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [titleLightProvider.overrideWith((ref, url) async => null)],
      child: MaterialApp(
        home: Scaffold(
          body: CalendarBand(
            events: events,
            window: CalendarWindow.from(_now),
            now: _now,
            onTap: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a desktop window\'s band is seven days from today, each with '
      'what comes out on it', (tester) async {
    await _pump(tester, 1200, [_event('Sprite Fright', 0)]);

    expect(find.text('Today\u00A0· 29'), findsOneWidget);
    expect(find.text('Mon 5'), findsOneWidget);
    // A day of one thing names it.
    expect(find.text('Sprite Fright'), findsWidgets);
  });

  testWidgets('a day with more than its cell holds ends on +N', (tester) async {
    await _pump(tester, 1200, [
      for (var i = 0; i < 6; i++) _event('Title $i', 3),
    ]);

    expect(find.textContaining(RegExp(r'^\+\d$')), findsOneWidget);
  });

  testWidgets('narrower, the week is dots: no day cells', (tester) async {
    await _pump(tester, 860, [_event('Sprite Fright', 0)]);

    expect(find.text('Today\u00A0· 29'), findsNothing);
  });

  testWidgets('the band stays one link and one sentence', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, 1200, [_event('Sprite Fright', 0)]);

    expect(find.bySemanticsLabel(RegExp('^Today\u00A0· 29')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Calendar: ')), findsOneWidget);
    handle.dispose();
  });
}
