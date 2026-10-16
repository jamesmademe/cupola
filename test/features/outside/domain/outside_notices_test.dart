import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What Cupola says in a notification, and what keeps it from saying a thing
/// twice.
void main() {
  // Friday 16 October 2026, 14:02.
  final now = DateTime(2026, 10, 16, 14, 2);
  const both = {OutsideNoticeKind.needsYou, OutsideNoticeKind.readyToWatch};

  OutsideNotice fault(String id) => OutsideNotice(
    kind: OutsideNoticeKind.needsYou,
    id: id,
    body: '$id is stuck',
  );

  OutsideHeard run(
    OutsideSaid said,
    List<OutsideNotice>? faults, {
    DateTime? at,
    bool speak = true,
    Set<OutsideNoticeKind> enabled = both,
  }) => outsideNoticesOf(
    current: {OutsideNoticeKind.needsYou: faults},
    said: said,
    enabled: enabled,
    now: at ?? now,
    speak: speak,
  );

  test('the first read records what is there and says nothing', () {
    final first = run(const OutsideSaid(), [fault('Charge'), fault('Spring')]);
    expect(first.say, isEmpty);
    expect(first.said.baselined, contains(OutsideNoticeKind.needsYou));
    expect(first.said.seen.keys, ['needsYou:Charge', 'needsYou:Spring']);
  });

  test('what came since is said, once', () {
    final first = run(const OutsideSaid(), [fault('Charge')]);
    final second = run(first.said, [fault('Charge'), fault('Spring')]);
    expect(second.say, [fault('Spring')]);
    final third = run(second.said, [fault('Charge'), fault('Spring')]);
    expect(third.say, isEmpty);
  });

  test('the app on screen records what it shows and says nothing', () {
    final first = run(const OutsideSaid(), const []);
    final looked = run(first.said, [fault('Charge')], speak: false);
    expect(looked.say, isEmpty);
    final after = run(looked.said, [fault('Charge')]);
    expect(after.say, isEmpty, reason: 'the person saw it on the Home');
  });

  test(
    'a fault that clears and comes back within the day is not news twice',
    () {
      var said = run(const OutsideSaid(), const []).said;
      said = run(said, [fault('Charge')]).said;
      said = run(said, const [], at: now.add(const Duration(hours: 3))).said;
      final back = run(said, [
        fault('Charge'),
      ], at: now.add(const Duration(hours: 6)));
      expect(back.say, isEmpty);
      // Gone for more than a day: it is forgotten, and its return is news.
      final cleared = run(
        back.said,
        const [],
        at: now.add(const Duration(hours: 32)),
      ).said;
      final again = run(cleared, [
        fault('Charge'),
      ], at: now.add(const Duration(hours: 33)));
      expect(again.say, [fault('Charge')]);
    },
  );

  test('a read that did not answer forgets nothing and says nothing', () {
    var said = run(const OutsideSaid(), [fault('Charge')]).said;
    said = run(said, null, at: now.add(const Duration(days: 3))).said;
    expect(said.seen.keys, ['needsYou:Charge']);
    final answered = run(said, [
      fault('Charge'),
    ], at: now.add(const Duration(days: 3, minutes: 15)));
    expect(answered.say, isEmpty);
  });

  test(
    'switched off, a kind forgets; switched on again, it starts quietly',
    () {
      var said = run(const OutsideSaid(), [fault('Charge')]).said;
      said = run(said, [
        fault('Charge'),
        fault('Spring'),
      ], enabled: const {}).said;
      expect(said.seen, isEmpty);
      expect(said.baselined, isEmpty);
      final on = run(said, [fault('Charge'), fault('Spring'), fault('Sintel')]);
      expect(on.say, isEmpty, reason: 'no dozen old faults at once');
    },
  );

  test('what is remembered survives the file', () {
    final said = run(const OutsideSaid(), [fault('Charge')]).said;
    expect(OutsideSaid.fromJson(said.toJson()), said);
    expect(OutsideSaid.fromJson({'version': 99}), const OutsideSaid());
    expect(OutsideSaid.fromJson('garbage'), const OutsideSaid());
  });

  group('the words', () {
    DashboardDecision decision(DecisionKind kind, String title) =>
        DashboardDecision(
          kind: kind,
          id: '${kind.name}-$title',
          service: ServiceKey.radarr,
          title: title,
          detail: 'detail',
          occurredAt: null,
          route: '/activity',
        );

    test('Needs you says its faults in its own line, and no request', () {
      final notices = needsYouNotices([
        decision(DecisionKind.stalledDownload, 'Charge'),
        decision(DecisionKind.failedImport, 'Spring'),
        decision(DecisionKind.pendingRequest, 'Sintel'),
      ], now: now);
      expect(notices.map((notice) => notice.body), [
        'Charge is stuck',
        'Could not import Spring',
      ]);
      expect(notices.first.title, 'Needs you');
      expect(notices.first.route, '/activity');
    });

    test('Ready to watch says the title that arrived', () {
      final ready = SeerrRequest.fromJson({
        'id': 4,
        'status': 2,
        'type': 'movie',
        'createdAt': now.subtract(const Duration(days: 2)).toIso8601String(),
        'media': {
          'id': 4,
          'tmdbId': 104,
          'mediaType': 'movie',
          'status': 5,
          'title': 'Spring',
          'mediaAddedAt': now
              .subtract(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
        },
      }, numbering: SeerrNumbering.seerr);
      final waiting = SeerrRequest.fromJson({
        'id': 5,
        'status': 1,
        'type': 'movie',
        'createdAt': now.subtract(const Duration(hours: 2)).toIso8601String(),
        'media': {
          'id': 5,
          'tmdbId': 105,
          'mediaType': 'movie',
          'title': 'Caligari',
        },
      }, numbering: SeerrNumbering.seerr);
      final notices = readyToWatchNotices(
        myRequestsOf([ready, waiting], now: now),
        idOf: (mine) => 'seerr-${mine.request.id}',
      );
      expect(notices, hasLength(1));
      expect(notices.single.title, 'Ready to watch');
      expect(notices.single.body, 'Spring');
      expect(notices.single.key, 'readyToWatch:seerr-4');
    });
  });
}
