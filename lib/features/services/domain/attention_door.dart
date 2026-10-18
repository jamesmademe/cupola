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
List<T> foldAttention<T, K>(
  List<T> items, {
  required K Function(T item) kindOf,
  required T Function(K kind, List<T> members) merge,
}) {
  final byKind = <K, List<T>>{};
  for (final item in items) {
    byKind.putIfAbsent(kindOf(item), () => []).add(item);
  }
  final emitted = <K>{};
  final folded = <T>[];
  for (final item in items) {
    final kind = kindOf(item);
    final members = byKind[kind]!;
    if (members.length == 1) {
      folded.add(item);
    } else if (emitted.add(kind)) {
      folded.add(merge(kind, members));
    }
  }
  return List.unmodifiable(folded);
}
