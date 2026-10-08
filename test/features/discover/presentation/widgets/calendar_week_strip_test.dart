import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_week_strip.dart';

/// The week strip at a large reading size: seven days cannot reflow, so the
/// names, the dates and the disc grow together to the single-line ceiling.
void main() {
  final now = DateTime(2026, 10, 8, 12);
  final window = CalendarWindow.from(now);
  final days = calendarWeekDays(calendarWeeks(window).first);

  Future<void> pump(WidgetTester tester, double textScale) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 370,
                child: CalendarWeekStrip(
                  days: days,
                  now: now,
                  window: window,
                  dots: const {},
                  selected: DateTime(2026, 10, 8),
                  onSelect: (_) {},
                  countOf: (_) => 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('at 200% a day\'s name and date stop at the single-line '
      'ceiling together', (tester) async {
    await pump(tester, 2);

    double scaleOf(String text) => tester
        .renderObject<RenderParagraph>(find.text(text))
        .textScaler
        .scale(1);
    expect(scaleOf('Wed'), TextScaleMetrics.singleLineChromeMaxScaleFactor);
    expect(scaleOf('7'), TextScaleMetrics.singleLineChromeMaxScaleFactor);
  });

  testWidgets('the disc grows with the date, to the single-line ceiling', (
    tester,
  ) async {
    await pump(tester, 1);
    final base = tester.getSize(_disc('8')).width;

    await pump(tester, 2);
    final grown = tester.getSize(_disc('8')).width;

    expect(
      grown,
      moreOrLessEquals(
        base * TextScaleMetrics.singleLineChromeMaxScaleFactor,
        epsilon: 0.5,
      ),
    );
  });
}

/// The disc a date sits in.
Finder _disc(String date) =>
    find.ancestor(of: find.text(date), matching: find.byType(Container)).first;
