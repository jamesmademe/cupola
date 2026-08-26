import 'package:flutter/foundation.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

/// What a release search is being run for.
enum ReleaseSearchScope {
  /// Sonarr, `seriesId` + `seasonNumber`. This is also what the "whole series"
  /// action runs — Sonarr's `/release` has no series-wide form, so that button
  /// searches a season like any other.
  season,

  /// Sonarr, a single `episodeId`.
  episode,

  /// Radarr, a single `movieId`.
  movie,

  /// Lidarr, every album of an `artistId`.
  artist,

  /// Lidarr, a single `albumId`.
  album,
}

/// Identifies the thing a release search is for, and — crucially — how targets
/// relate to each other.
///
/// The relationship is what makes deduplication correct. An episode search and
/// its season search are *not* the same target, so plain equality would happily
/// run both, sending two overlapping queries to the same rate-limited indexers.
/// [isCoveredBy] expresses containment instead, so an episode can adopt a
/// running season job rather than duplicating its work.
@immutable
class ReleaseSearchTarget {
  const ReleaseSearchTarget({
    required this.service,
    required this.scope,
    required this.id,
    required this.label,
    this.seasonNumber,
    this.parentId,
    this.instanceId = '',
  });

  /// Sonarr, Radarr or Lidarr. Readarr has no interactive search.
  final ServiceKey service;

  /// Which connection this search belongs to.
  ///
  /// **Part of identity, and that is the whole point.** `movieId 42` on
  /// Radarr · 4K and `movieId 42` on Radarr · HD are two different films, and
  /// without this they were one target: the thirty-minute results cache served
  /// one server's releases for the other's film, and a queued job could be
  /// adopted by a search running somewhere else entirely.
  ///
  /// Empty until [stampedWith] is called. Every target in the app is built by a
  /// screen and handed to `showReleaseSearch`, which stamps it there — one
  /// place, rather than a required argument at twenty construction sites that
  /// would each have to go and ask the same question.
  final String instanceId;

  final ReleaseSearchScope scope;

  /// The id the query is built from: `seriesId` for a season, `episodeId`,
  /// `movieId`, `artistId` or `albumId`.
  final int id;

  /// Shown to the user, already truncated by the caller.
  final String label;

  /// Set for [ReleaseSearchScope.season], and for an episode when its season is
  /// known — without it an episode cannot be recognised as part of a season.
  final int? seasonNumber;

  /// The containing entity: `seriesId` for an episode, `artistId` for an album.
  final int? parentId;

  ReleaseSearchTarget.season({
    required int seriesId,
    required int this.seasonNumber,
    required this.label,
  }) : service = ServiceKey.sonarr,
       scope = ReleaseSearchScope.season,
       id = seriesId,
       parentId = null,
       instanceId = '';

  ReleaseSearchTarget.episode({
    required int episodeId,
    required this.label,
    int? seriesId,
    this.seasonNumber,
  }) : service = ServiceKey.sonarr,
       scope = ReleaseSearchScope.episode,
       id = episodeId,
       parentId = seriesId,
       instanceId = '';

  ReleaseSearchTarget.movie({required int movieId, required this.label})
    : service = ServiceKey.radarr,
      scope = ReleaseSearchScope.movie,
      id = movieId,
      seasonNumber = null,
      parentId = null,
      instanceId = '';

  ReleaseSearchTarget.artist({required int artistId, required this.label})
    : service = ServiceKey.lidarr,
      scope = ReleaseSearchScope.artist,
      id = artistId,
      seasonNumber = null,
      parentId = null,
      instanceId = '';

  ReleaseSearchTarget.album({
    required int albumId,
    required this.label,
    int? artistId,
  }) : service = ServiceKey.lidarr,
       scope = ReleaseSearchScope.album,
       id = albumId,
       seasonNumber = null,
       parentId = artistId,
       instanceId = '';

  /// True when a search for `this` would be answered by a search for [other] —
  /// an episode by its season, an album by its artist.
  ///
  /// Deliberately not symmetric and deliberately not transitive beyond one step:
  /// a season search does *not* cover a different season, and an artist search
  /// covers its albums but nothing above it.
  bool isCoveredBy(ReleaseSearchTarget other) {
    if (other.service != service) return false;
    // Same server, or nothing is covered. Two Sonarr have two unrelated series
    // tables, so `seriesId 7` on one says nothing at all about `seriesId 7` on
    // the other — adopting across connections would hand the user a season's
    // releases from a library that does not contain the episode they asked for.
    if (other.instanceId != instanceId) return false;
    return switch (scope) {
      ReleaseSearchScope.episode =>
        other.scope == ReleaseSearchScope.season &&
            parentId != null &&
            other.id == parentId &&
            seasonNumber != null &&
            other.seasonNumber == seasonNumber,
      ReleaseSearchScope.album =>
        other.scope == ReleaseSearchScope.artist &&
            parentId != null &&
            other.id == parentId,
      _ => false,
    };
  }

  /// True when [other] is the same target, or one this target's results would
  /// cover. Used to decide whether a new search may start at all.
  bool conflictsWith(ReleaseSearchTarget other) =>
      this == other || isCoveredBy(other) || other.isCoveredBy(this);

  /// This target, bound to the connection [instanceId] names.
  ///
  /// Called once, by `showReleaseSearch`, before anything compares this target
  /// against a running job or a cached result — so every target the job manager
  /// ever sees is already stamped, and the empty default never reaches it.
  ReleaseSearchTarget stampedWith(String instanceId) => ReleaseSearchTarget(
    service: service,
    scope: scope,
    id: id,
    label: label,
    seasonNumber: seasonNumber,
    parentId: parentId,
    instanceId: instanceId,
  );

  @override
  bool operator ==(Object other) =>
      other is ReleaseSearchTarget &&
      other.service == service &&
      other.instanceId == instanceId &&
      other.scope == scope &&
      other.id == id &&
      other.seasonNumber == seasonNumber;

  @override
  int get hashCode => Object.hash(service, instanceId, scope, id, seasonNumber);

  @override
  String toString() =>
      'ReleaseSearchTarget(${service.name}'
      '${instanceId.isEmpty ? '' : '/$instanceId'}, ${scope.name}, id: $id'
      '${seasonNumber == null ? '' : ', season: $seasonNumber'})';
}
