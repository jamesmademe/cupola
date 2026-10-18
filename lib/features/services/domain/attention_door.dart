/// Where a row of a service's Overview that needs attention leads, and the
/// two pure helpers every Overview folds its faults with.
///
/// A row says what is wrong; its door is the place the app fixes it. The door
/// is data, not a callback, so the fold that builds the row can be tested
/// without a router or a widget, and the one place that opens a door
/// (`openAttentionDoor`, `lib/core/widgets/service_overview.dart`) is the one
/// place that decides how.
///
/// The rule for choosing one is the same everywhere: the most specific place
/// the app has today. The thing itself (a download's page, an indexer's, a
/// stack's) where it has a page; else the tab of the service that lists it;
/// else no door at all. Never a door to a place that does not show the thing.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/services/domain/service_tab.dart';

/// The place an attention row leads. See the library doc.
@immutable
sealed class AttentionDoor {
  const AttentionDoor();

  /// A tab of the service the Overview belongs to: the list that shows what
  /// the row is about. Switches branch, as the tab bar does.
  const factory AttentionDoor.tab(ServiceTab tab) = AttentionTab;

  /// One download's own page (`/activity/download`): [instanceId] the
  /// connection the page reads it from, [key] the client's id for the
  /// transfer.
  const factory AttentionDoor.download({
    required String instanceId,
    required String key,
  }) = AttentionDownload;

  /// A page pushed on the service, by its [location], spoken as [hint]
  /// (`opens Nyaa, with its tests and history`).
  const factory AttentionDoor.page({
    required String location,
    required String hint,
  }) = AttentionPage;
}

/// [AttentionDoor.tab].
final class AttentionTab extends AttentionDoor {
  const AttentionTab(this.tab);

  final ServiceTab tab;

  @override
  bool operator ==(Object other) => other is AttentionTab && other.tab == tab;

  @override
  int get hashCode => Object.hash(AttentionTab, tab);

  @override
  String toString() => 'AttentionDoor.tab(${tab.segment})';
}

/// [AttentionDoor.download].
final class AttentionDownload extends AttentionDoor {
  const AttentionDownload({required this.instanceId, required this.key});

  final String instanceId;
  final String key;

  @override
  bool operator ==(Object other) =>
      other is AttentionDownload &&
      other.instanceId == instanceId &&
      other.key == key;

  @override
  int get hashCode => Object.hash(AttentionDownload, instanceId, key);

  @override
  String toString() => 'AttentionDoor.download($instanceId, $key)';
}

/// [AttentionDoor.page].
final class AttentionPage extends AttentionDoor {
  const AttentionPage({required this.location, required this.hint});

  final String location;
  final String hint;

  @override
  bool operator ==(Object other) =>
      other is AttentionPage && other.location == location;

  @override
  int get hashCode => Object.hash(AttentionPage, location);

  @override
  String toString() => 'AttentionDoor.page($location)';
}

/// How many names a folded row spells out before it counts the rest.
///
/// Three, because the row is one line of evidence and not a list: the list is
/// what the row's door opens.
const int attentionNamesLimit = 3;

/// `Nyaa, 1337x, Bitsearch and 2 more`: the names a folded row stands for.
///
/// Empty names are skipped rather than printed as blanks, and a name that
/// repeats is said once: two torrents of one title are one thing to look for.
String attentionNames(
  Iterable<String> names, {
  int limit = attentionNamesLimit,
}) {
  final seen = <String>{};
  final distinct = [
    for (final name in names)
      if (name.trim().isNotEmpty && seen.add(name.trim())) name.trim(),
  ];
  if (distinct.length <= limit) return distinct.join(', ');
  final hidden = distinct.length - limit;
  return '${distinct.take(limit).join(', ')} and $hidden more';
}

/// A folded row's count as it is printed (`3`, or the floor `3+` when the
/// read it was counted in stopped short of the whole list).
String attentionCount(int count, {bool floor = false}) =>
    floor ? Lexicon.floor(count) : '$count';

/// [attentionCount] as the ear should hear it: a floor is `at least 3`.
String attentionCountSpoken(int count, {bool floor = false}) =>
    Lexicon.spokenFigure(attentionCount(count, floor: floor));

/// Folds the members of every kind that has more than one into one row, in
/// place: a kind with a single member keeps its own row, and a folded row
/// takes the position of the first member it stands for.
///
/// [merge] builds the folded row from the kind and its members, so each
/// service keeps its own words and its own door. Kinds are compared by
/// equality, so a service passes its enum.
///
/// [identityOf] names the thing a member is about, where two members can be
/// about the same one: the records of a season pack are one download, and one
/// download is one fault however many records say so. Members of a kind that
/// share an identity count once (the first stands for them), so a kind
/// whose members are all one thing keeps its own row.
List<T> foldAttention<T, K>(
  List<T> items, {
  required K Function(T item) kindOf,
  required T Function(K kind, List<T> members) merge,
  Object Function(T item)? identityOf,
}) {
  final byKind = <K, List<T>>{};
  final seen = <K, Set<Object>>{};
  for (final item in items) {
    final kind = kindOf(item);
    final identity = identityOf;
    if (identity != null &&
        !seen.putIfAbsent(kind, () => {}).add(identity(item))) {
      continue;
    }
    byKind.putIfAbsent(kind, () => []).add(item);
  }
  final emitted = <K>{};
  final folded = <T>[];
  for (final item in items) {
    final kind = kindOf(item);
    if (!emitted.add(kind)) continue;
    final members = byKind[kind]!;
    folded.add(members.length == 1 ? members.single : merge(kind, members));
  }
  return List.unmodifiable(folded);
}

/// A folded row's headline and its sentence, which differ only where the
/// count is a floor (`3+` is read `at least 3`).
typedef AttentionWords = ({String headline, String spoken});

/// `3 downloads stuck`, `3+ downloads stuck`: several downloads of a service
/// that are not moving.
AttentionWords stuckDownloadsWords(int count, {bool floor = false}) => (
  headline:
      '${attentionCount(count, floor: floor)} downloads ${StateWord.stuck.inline}',
  spoken:
      '${attentionCountSpoken(count, floor: floor)} downloads ${StateWord.stuck.inline}',
);

/// `3 imports failed`, `3+ imports failed`: several downloads an \*arr
/// grabbed and could not move into the library.
AttentionWords failedImportsWords(int count, {bool floor = false}) => (
  headline:
      '${attentionCount(count, floor: floor)} imports ${StateWord.failed.inline}',
  spoken:
      '${attentionCountSpoken(count, floor: floor)} imports ${StateWord.failed.inline}',
);

/// The key the page of the download an \*arr's queue [record] is names it by
/// (`downloadPageKey` of the row the queue builds from it): the client's id
/// for the transfer when the record carries one, else the record's own id.
/// Null when the record names neither, which is a download with no page.
String? arrQueueRecordDownloadKey(Map<String, dynamic> record) {
  final downloadId = stringOrNull(record['downloadId'])?.trim();
  if (downloadId != null && downloadId.isNotEmpty) return downloadId;
  final id = intOrNull(record['id']);
  return id == null || id <= 0 ? null : '$id';
}

/// The door of the download an \*arr's queue [record] is, on the connection
/// [instanceId] read it from; null when the record has no page to open.
AttentionDoor? arrQueueRecordDoor(
  Map<String, dynamic> record, {
  required String instanceId,
}) {
  final key = arrQueueRecordDownloadKey(record);
  return key == null
      ? null
      : AttentionDoor.download(instanceId: instanceId, key: key);
}
