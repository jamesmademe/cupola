import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/shell/presentation/activity_badge.dart';

ActivityBadge? _of({
  int faults = 0,
  bool faultsFloor = false,
  int requests = 0,
  bool requestsFloor = false,
  int searches = 0,
}) => activityBadgeOf(
  faults: faults,
  faultsFloor: faultsFloor,
  requests: requests,
  requestsFloor: requestsFloor,
  searches: searches,
);

void main() {
  test('nothing waiting: no number', () {
    expect(_of(), isNull);
  });

  test('a fault is amber and counts the faults alone, and the ear hears '
      'both', () {
    final badge = _of(faults: 18, requests: 2)!;
    expect(badge.tone, StatusTone.warning);
    expect(badge.count, 18);
    expect(badge.spoken, '18 need you, 2 requests wait for you');
  });

  test('one fault needs you', () {
    expect(_of(faults: 1)!.spoken, '1 needs you');
  });

  test('without faults: blue, requests and finished searches together', () {
    final badge = _of(requests: 2, searches: 1)!;
    expect(badge.tone, StatusTone.info);
    expect(badge.count, 3);
    expect(
      badge.spoken,
      '2 requests wait for you, 1 finished search to look at',
    );
  });

  test('a floor is heard and printed as one', () {
    final badge = _of(faults: 5, faultsFloor: true)!;
    expect(badge.floor, isTrue);
    expect(badge.spoken, 'at least 5 need you');
    expect(
      _of(requests: 1, requestsFloor: true)!.spoken,
      'at least 1 request waits for you',
    );
  });
}
