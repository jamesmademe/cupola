/// The requester's last drawing of her requests: what Ready to watch and Your
/// requests draw, until her Seerr answers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/seerr_request_codec.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/requests/data/my_requests_provider.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';

/// How many arrivals the drawing keeps: Ready to watch draws the newest and
/// one more under it, and a margin of one for the day's turn.
const _arrivedKept = 3;

/// How many answered requests (a no of the last seven days) are kept: the
/// Home lists three rows.
const _answeredKept = 3;

/// The most requests on their way a drawing keeps. The Home says how many
/// are on the way (`3 on the way`), and a count read off a list that was
/// cut would state a total it does not know, so a list longer than this is
/// not kept at all rather than cut.
const _onTheWayKept = 100;

/// A time before any request was made, so that every arrival that has a day
/// reads as fresh when the drawing is made: the week is cut again, against
/// the time of the drawing, when it is drawn.
final _beforeAll = DateTime.utc(1970);

/// Her requests as the Home's two modules draw them: every request still on
/// its way, the newest arrivals and the newest answers, in the fields
/// `seerrRequestToJson` keeps.
///
/// What is derived from a window (`ready in the last seven days`, `a no of the
/// last seven days`) is cut again when drawn (`myRequestsOf` at that day), so
/// an arrival the week left behind is not drawn as ready. What runs (the
/// percentage of a download, `Ready around 21:10`) is not kept at all: a
/// drawing reads every request as `stale`, and one that was downloading is on
/// its way.
final myRequestsLastKnown = HomeLastKnownSlot<List<SeerrRequest>>(
  id: 'requests',
  schema: 1,
  services: HomeModule.yourRequests.services.toSet(),
  encode: (requests, _) {
    final read = [
      for (final request in requests)
        myRequestOf(request, now: _beforeAll, stale: true),
    ];
    final onTheWay = [
      for (final mine in read)
        if (mine.stage.onTheWay) mine,
    ];
    if (onTheWay.length > _onTheWayKept) return null;
    List<MyRequest> newest(
      bool Function(MyRequest mine) wanted,
      DateTime? Function(MyRequest mine) when,
      int count,
    ) {
      final found = [
        for (final mine in read)
          if (wanted(mine) && when(mine) != null) mine,
      ]..sort((a, b) => when(b)!.compareTo(when(a)!));
      return found.take(count).toList(growable: false);
    }

    final arrived = newest(
      (mine) => mine.stage == MyRequestStage.readyToWatch,
      (mine) => mine.arrivedAt,
      _arrivedKept,
    );
    final answered = newest(
      (mine) =>
          mine.stage == MyRequestStage.declined ||
          mine.stage == MyRequestStage.didNotGoThrough,
      (mine) => mine.answeredAt,
      _answeredKept,
    );
    return {
      'requests': [
        for (final mine in [...onTheWay, ...arrived, ...answered])
          seerrRequestToJson(mine.request),
      ],
    };
  },
  decode: (data, _) {
    if (data is! Map || data['requests'] is! List) return null;
    final requests = <SeerrRequest>[];
    for (final json in data['requests'] as List) {
      // One record that cannot be read and the count of what is on its way
      // is no longer known: the drawing is not drawn.
      final request = seerrRequestFromJson(json);
      if (request == null) return null;
      requests.add(request);
    }
    return requests;
  },
);

/// Her requests as the Home draws them, and when they are as of.
///
/// [read] is what `myRequestsProvider` reads, or until her list has an answer
/// the last drawing's, read as the last answer left it: every request `stale`
/// (no percentage, no time left, one that was downloading is on its way).
/// [asOf] is null for the live list.
typedef HomeMyRequests = ({MyRequestsRead read, DateTime? asOf});

extension HomeMyRequestsWatch on WidgetRef {
  /// What Ready to watch and Your requests read: her requests live, or the
  /// last drawing of them until the live list comes
  /// (`HomeLastKnownWatch.watchOrLastKnown` over her list, and the same
  /// derivation `myRequestsProvider` makes of it).
  ///
  /// Not `watchOrLastKnown` over `myRequestsProvider` itself: that read is
  /// not an `AsyncValue`, and what is drawn must be cut again against the
  /// time of the drawing from the requests, not from what they were read as
  /// then.
  HomeMyRequests watchMyRequestsOrLastKnown() {
    final known = watchOrLastKnown(requestsProvider, myRequestsLastKnown);
    final asOf = known.asOf;
    final drawn = known.value;
    if (asOf == null || drawn == null) {
      return (read: watch(myRequestsProvider), asOf: null);
    }
    return (
      read: (
        requests: myRequestsDrawn(drawn, now: watch(calendarClockProvider)()),
        error: known.live.error,
        stale: true,
      ),
      asOf: asOf,
    );
  }
}

/// A last drawing's requests at [now]: every one read as `stale`.
MyRequests myRequestsDrawn(List<SeerrRequest> drawn, {required DateTime now}) =>
    myRequestsOf(drawn, now: now, stale: true);

/// The request Ready to watch leads with, for the room's light: the live
/// list's, or until it has one the last drawing's, so the room does not
/// change colour when the answer comes.
final readyLeadProvider = Provider.autoDispose<MyRequest?>((ref) {
  final live = ref.watch(myRequestsProvider).requests;
  if (live != null) return live.ready.firstOrNull;
  final known = ref.watch(homeLastKnownProvider(myRequestsLastKnown));
  if (known == null) return null;
  final drawn = known.value as List<SeerrRequest>;
  final now = ref.watch(calendarClockProvider)();
  return myRequestsDrawn(drawn, now: now).ready.firstOrNull;
});
