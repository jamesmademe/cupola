import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/string_utils.dart';
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
}
