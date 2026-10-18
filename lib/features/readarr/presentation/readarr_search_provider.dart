import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';

/// The word typed into the Authors search field.
final readarrSearchQueryProvider = StateProvider<String>((ref) => '');

/// The library's authors whose name carries what was typed, or null for an
/// empty query (nothing was asked).
///
/// Readarr's search is the library's own, on purpose. Lidarr's field asks its
/// server to look an artist up, and Readarr's lookup answers from a metadata
/// host that no longer exists (the project is archived upstream), so a field
/// that did the same would search nothing. What can be found is what Readarr
/// holds, and the whole library is already in hand: one request, read once.
///
/// It reads the library through [readarrAuthorsProvider], so a Readarr that
/// does not answer reaches the search as the failure it is and never as "no
/// results"; and it carries `noProviderRetry` as the provider it derives from
/// does.
final readarrSearchResultsProvider = FutureProvider<List<ReadarrAuthor>?>((
  ref,
) async {
  final query = ref.watch(readarrSearchQueryProvider);
  if (query.trim().isEmpty) return null;
  final authors = await ref.watch(readarrAuthorsProvider.future);
  return readarrAuthorsMatching(authors, query);
}, retry: noProviderRetry);

/// The [authors] whose name holds every word of [query], in any order and
/// whatever the case, by name.
///
/// Words, not the phrase: a search for `Verne, Jules` finds `Jules Verne`,
/// as people type a name either way round.
List<ReadarrAuthor> readarrAuthorsMatching(
  List<ReadarrAuthor> authors,
  String query,
) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'[\s,]+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return const [];

  final found = [
    for (final author in authors)
      if (words.every(author.authorName.toLowerCase().contains)) author,
  ];
  return found..sort(
    (a, b) => a.authorName.toLowerCase().compareTo(b.authorName.toLowerCase()),
  );
}
