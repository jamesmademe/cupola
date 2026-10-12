import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/home/presentation/widgets/home_header.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

/// The Home's header: the day, and how many services answered.
void main() {
  StackHealth health({
    int configured = 12,
    int answering = 12,
    int unreachable = 0,
    int checking = 0,
  }) => StackHealth(
    configured: configured,
    answering: answering,
    degraded: 0,
    unreachable: unreachable,
    checking: checking,
    notSetUp: 5,
  );

  test('the day in full, the month on the line under it', () {
    final day = DateTime(2026, 10, 8);
    expect('${weekdayName(day)} ${day.day}', 'Thursday 8');
    expect(monthName(day), 'October');
  });

  test('before anything answered it is checking, and reserves nothing', () {
    expect(
      homeHealthLine(health(answering: 0, checking: 12)),
      'Checking 12 services',
    );
    expect(
      homeHealthLine(health(configured: 1, answering: 0, checking: 1)),
      'Checking 1 service',
    );
  });

  test('then how many answered, the slowest still counted as checking', () {
    expect(homeHealthLine(health()), '12 of 12 answering');
    expect(
      homeHealthLine(health(answering: 11, unreachable: 1)),
      '11 of 12 answering',
    );
    expect(
      homeHealthLine(health(answering: 9, checking: 3)),
      '9 of 12 answering · 3 checking',
    );
  });

  test('nothing asked: no line, only the month', () {
    expect(homeHealthLine(health(configured: 0, answering: 0)), '');
  });

  test('a screen reader hears the services', () {
    expect(spokenHealthLine(health()), '12 of 12 services answering');
    expect(
      spokenHealthLine(health(answering: 9, checking: 3)),
      '9 of 12 services answering, 3 checking',
    );
    expect(
      spokenHealthLine(health(answering: 0, checking: 12)),
      'Checking 12 services',
    );
  });

  testWidgets('the month and the health are one line of words, which wraps '
      'as a sentence at a large reading size', (tester) async {
    // Two texts in a row wrapped the health inside a column of its own beside
    // "October ·" at twice the size.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          calendarClockProvider.overrideWithValue(
            () => DateTime(2026, 10, 9, 14),
          ),
          stackHealthProvider.overrideWith(
            () => _Fixed(health(configured: 10, answering: 10)),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(390, 844),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(body: HomeHeader()),
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().startsWith('October · ') &&
            widget.text.toPlainText().endsWith('10 of 10 answering'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('October. Stack: 10 of 10 services answering'),
      findsOneWidget,
    );
  });
}

class _Fixed extends StackHealthNotifier {
  _Fixed(this.health);

  final StackHealth health;

  @override
  StackHealth build() => health;
}
