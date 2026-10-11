/// An \*arr's failing health checks in the app's words, and the same check
/// failing on several \*arrs as one fault.
///
/// A check is known by its `source`, the name of the class that raised it
/// (`IndexerRssCheck`), which is the same in every language the \*arr speaks;
/// its message is not. The \*arr's own message stays behind Why?.
library;

import 'package:cupola/features/services/domain/dashboard_decision.dart';

/// What a failing check means: the headline Needs you sets large, and what
/// it stops the \*arrs doing.
typedef ArrHealthWords = ({String headline, String explanation});

/// `Radarr`, `Radarr and Sonarr`, `Radarr, Sonarr and Lidarr`.
String namesSaid(List<String> names) => switch (names.length) {
  0 => '',
  1 => names.single,
  _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
};

/// [check] in the app's words, or null for a check the app has no words
/// for: its own message stands. The words name no \*arr: the line under them
/// does, once for all the \*arrs the check fails on.
ArrHealthWords? arrHealthWords(String check) => switch (check) {
  'IndexerRssCheck' => (
    headline: 'No indexer is watching for new releases',
    explanation:
        "New releases aren't grabbed on their own until an indexer has RSS "
        'sync on.',
  ),
  'IndexerSearchCheck' => (
    headline: 'No indexer can be searched',
    explanation:
        'Searches find nothing until an indexer has automatic search on.',
  ),
  'IndexerStatusCheck' || 'IndexerLongTermStatusCheck' => (
    headline: 'No indexer is answering',
    explanation: "New releases can't be found while every indexer fails.",
  ),
  'DownloadClientCheck' => (
    headline: "The download client isn't answering",
    explanation: "Nothing grabbed can start downloading until it answers.",
  ),
  'DownloadClientStatusCheck' => (
    headline: 'No download client is answering',
    explanation:
        "Nothing grabbed can start downloading while every client "
        'fails.',
  ),
  'RootFolderCheck' => (
    headline: 'A library folder is missing',
    explanation: "A folder your library is kept in can't be reached.",
  ),
  'MountCheck' => (
    headline: 'A library folder is read-only',
    explanation: "New files can't be put into it.",
  ),
  'ImportMechanismCheck' => (
    headline: "Finished downloads aren't imported",
    explanation: "They aren't moved into your library on their own.",
  ),
  'RemotePathMappingCheck' => (
    headline: "Finished downloads can't be found",
    explanation:
        'The download client and the library see the downloads folder in '
        'different places.',
  ),
  'SystemTimeCheck' => (
    headline: "The server's clock is wrong",
    explanation: 'Searches and schedules go wrong until it is set.',
  ),
  'UpdateCheck' => (
    headline: "An update can't be installed",
    explanation: "Its program folder can't be written to.",
  ),
  _ => null,
};

/// What folds two failing checks into one fault: the check, for one the app
/// has words for (each \*arr says it in its own name); the check and its
/// message otherwise, so only the same sentence folds.
Object arrHealthGroupKey(String check, String message) =>
    arrHealthWords(check) == null || check.isEmpty ? (check, message) : check;

/// [decisions], each a failing check on one connection, with the same check
/// on several \*arrs folded into one fault: `No indexer is watching for new
/// releases` · `Radarr, Sonarr and Lidarr`. Every member's own message stays
/// behind Why?, once each, a paragraph apart.
List<DashboardDecision> foldArrHealth(List<DashboardDecision> decisions) {
  final buckets = <Object, List<DashboardDecision>>{};
  for (final decision in decisions) {
    buckets
        .putIfAbsent(
          arrHealthGroupKey(decision.subject ?? '', decision.reason ?? ''),
          () => [],
        )
        .add(decision);
  }
  return [
    for (final members in buckets.values)
      if (members.length == 1) members.single else _foldOf(members),
  ];
}

DashboardDecision _foldOf(List<DashboardDecision> members) {
  final first = members.first;
  // A check is a fault only with a message (`_healthDecisions`).
  final reasons = <String>{for (final member in members) ?member.reason};
  return DashboardDecision(
    kind: first.kind,
    id: 'health-group-${first.subject}-${first.reason.hashCode}',
    service: first.service,
    title: first.title,
    detail: namesSaid([for (final member in members) member.detail]),
    // A blank line between them: each is a sentence of its own \*arr.
    reason: reasons.isEmpty ? null : reasons.join('\n\n'),
    subject: first.subject,
    // An \*arr does not date a check.
    occurredAt: null,
    route: first.route,
    instanceId: first.instanceId,
    connectionName: first.connectionName,
    actionInstanceId: first.actionInstanceId,
    members: members,
  );
}
