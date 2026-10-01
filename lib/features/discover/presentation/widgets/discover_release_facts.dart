import 'package:flutter/material.dart';

import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';

/// The encyclopaedic fact grid for a Seerr title: release dates, studios,
/// networks and crew.
///
/// Headless: the heading comes from the `MediaDetailSlot` that hosts it.
class DiscoverReleaseInfoCard extends StatelessWidget {
  final List<MediaFact> releaseEntries;
  final String? emptyMessage;
  final List<String> studios;
  final List<String> directors;
  final List<String> writers;
  final String networks;

  const DiscoverReleaseInfoCard._({
    required this.releaseEntries,
    this.emptyMessage,
    this.studios = const [],
    this.directors = const [],
    this.writers = const [],
    this.networks = '',
  });

  factory DiscoverReleaseInfoCard.movie({
    required List<MovieRelease> releases,
    required String region,
    List<String> studios = const [],
    List<String> directors = const [],
    List<String> writers = const [],
  }) {
    final theatrical = _releaseByType(releases, 3);
    final digital = _releaseByType(releases, 4);
    final physical = _releaseByType(releases, 5);
    final entries = <MediaFact>[];

    _addDatedFactEntry(entries, 'Theatrical', theatrical?.releaseDate);
    _addDatedFactEntry(entries, 'Digital', digital?.releaseDate);
    _addDatedFactEntry(entries, 'Physical', physical?.releaseDate);

    return DiscoverReleaseInfoCard._(
      releaseEntries: entries,
      emptyMessage: entries.isEmpty
          ? 'Release info is not available in your region ($region).'
          : null,
      studios: studios,
      directors: directors,
      writers: writers,
    );
  }

  factory DiscoverReleaseInfoCard.tv({
    String? firstAirDate,
    String? lastAirDate,
    TvEpisodeSummary? nextEpisodeToAir,
    List<String> studios = const [],
    List<String> directors = const [],
    List<String> writers = const [],
    String networks = '',
  }) {
    final entries = <MediaFact>[];

    _addDatedFactEntry(entries, 'First aired', firstAirDate);
    _addDatedFactEntry(entries, 'Last aired', lastAirDate);
    if (nextEpisodeToAir != null &&
        (nextEpisodeToAir.airDate?.isNotEmpty ?? false)) {
      final parts = <String>[];
      final code = formatArrEpisodeCode(
        nextEpisodeToAir.seasonNumber,
        nextEpisodeToAir.episodeNumber,
      );
      if (code != null) parts.add(code);
      if ((nextEpisodeToAir.name?.isNotEmpty ?? false)) {
        parts.add(nextEpisodeToAir.name!);
      }
      parts.add(formatMediumDate(nextEpisodeToAir.airDate!));

      entries.add(MediaFact('Next episode', parts.join(' · ')));
    }

    return DiscoverReleaseInfoCard._(
      releaseEntries: entries,
      emptyMessage: entries.isEmpty ? 'No release info available.' : null,
      studios: studios,
      directors: directors,
      writers: writers,
      networks: networks,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sectionChildren = <MediaInfoGroup>[
      MediaInfoGroup(
        title: 'Release dates',
        child: emptyMessage != null
            ? Text(
                emptyMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : MediaFactsList(facts: releaseEntries),
      ),
      if (studios.isNotEmpty)
        MediaInfoGroup(
          title: 'Studios',
          child: Text(studios.join(', '), style: theme.textTheme.bodyMedium),
        ),
      if (networks.isNotEmpty)
        MediaInfoGroup(
          title: 'Networks',
          child: Text(networks, style: theme.textTheme.bodyMedium),
        ),
      if (directors.isNotEmpty || writers.isNotEmpty)
        MediaInfoGroup(
          title: 'Crew',
          child: MediaFactsList(
            facts: [
              if (directors.isNotEmpty)
                MediaFact('Director', directors.join(', ')),
              if (writers.isNotEmpty) MediaFact('Writer', writers.join(', ')),
            ],
          ),
        ),
    ];

    return MediaInfoCard(groups: sectionChildren);
  }
}

void _addDatedFactEntry(List<MediaFact> entries, String label, String? value) {
  if (value == null || value.isEmpty) {
    return;
  }

  entries.add(MediaFact(label, formatMediumDate(value)));
}

MovieRelease? _releaseByType(List<MovieRelease> releases, int type) {
  for (final release in releases) {
    if (release.type == type && release.releaseDate.isNotEmpty) {
      return release;
    }
  }

  return null;
}
