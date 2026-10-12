/// Everyone's requests on Activity: the latest few that move or arrived, who
/// asked, and how the rest stand.
library;

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';

/// How many rows Everyone's requests draws before All requests.
const everyonesRequestsLimit = 3;

/// The latest of [requests] that move or arrived, newest first: what a
/// household member asked for and is coming or came. Waiting ones are in
/// Needs you; a no, a failure and a removal are on the Requests tab.
List<MyRequest> everyonesLatest(
  MyRequests requests, {
  int limit = everyonesRequestsLimit,
}) {
  final shown = [
    for (final mine in requests.all)
      if ((mine.stage.onTheWay && mine.stage != MyRequestStage.waiting) ||
          mine.stage.arrived)
        mine,
  ];
  DateTime? when(MyRequest mine) =>
      mine.stage.arrived ? mine.arrivedAt ?? mine.askedAt : mine.askedAt;
  shown.sort((a, b) {
    final at = when(a);
    final bt = when(b);
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return shown.take(limit).toList(growable: false);
}

/// How the household's requests stand beyond the rows: `1 processing ·
/// 4 declined`, either half alone, empty when neither.
String everyonesSummary(MyRequests requests) {
  var processing = 0;
  var declined = 0;
  for (final mine in requests.all) {
    switch (mine.stage) {
      case MyRequestStage.downloading ||
          MyRequestStage.finishing ||
          MyRequestStage.onItsWay:
        processing++;
      case MyRequestStage.declined:
        declined++;
      default:
        break;
    }
  }
  return [
    if (processing > 0) '$processing processing',
    if (declined > 0) '$declined declined',
  ].join(' · ');
}

/// One request's state and when, as one line: `Ready to watch since 18:40`,
/// `Downloading 62% · ready around 21:10`, `On the server since Sat 12 Sep`,
/// `Declined yesterday`.
///
/// The operator's words: an answer says when it was given, never the
/// requester's `Declined by the server's owner`, since the one reading is
/// the owner.
String everyonesLine(MyRequest mine, DateTime now) {
  switch (mine.stage) {
    case MyRequestStage.declined || MyRequestStage.didNotGoThrough:
      final at = mine.answeredAt;
      return at == null
          ? mine.state
          : '${mine.state} ${dayWords(at, now: now)}';
    case MyRequestStage.removed || MyRequestStage.blocked:
      return mine.state;
    default:
      break;
  }
  final detail = mine.detail(now);
  if (detail.isEmpty || detail == mine.state) return mine.state;
  final lower = '${detail[0].toLowerCase()}${detail.substring(1)}';
  return detail.startsWith('Since ')
      ? '${mine.state} $lower'
      : '${mine.state} · $lower';
}

/// The tone of [stage] on the operator's rows: a request that did not go
/// through is a fault on the stack, theirs to mend, so amber; every other
/// stage keeps the household's tone.
StatusTone everyonesTone(MyRequestStage stage) =>
    stage == MyRequestStage.didNotGoThrough ? StatusTone.warning : stage.tone;
