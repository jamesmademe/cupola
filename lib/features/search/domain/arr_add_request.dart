import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Everything an "add this" needs: the lookup row, and the connection that
/// listed it.
///
/// The connection is baked in rather than chosen, and that is the whole shape
/// of this feature. The global search fans out one section per connection, so
/// by the time a finger lands on a row the server is already decided — the user
/// picked it by choosing which section to touch. The add sheet therefore has no
/// server picker (Seerr's does, because Seerr's servers are a registry of its
/// own that no part of the row knows about); it only has to *say* which one it
/// is about.
///
/// Sealed so the submit path is an exhaustive switch: an arr added later
/// without an add of its own is a compile error rather than a plus that opens
/// a sheet which cannot post anything.
sealed class ArrAddRequest {
  /// The connection that listed the row — never the lens.
  final String instanceId;

  const ArrAddRequest({required this.instanceId});

  ServiceKey get service;

  /// What the user is adding, for the sheet's header and the failure sentence.
  String get title;
}

class RadarrAddRequest extends ArrAddRequest {
  final RadarrMovie movie;

  const RadarrAddRequest({required super.instanceId, required this.movie});

  @override
  ServiceKey get service => ServiceKey.radarr;

  @override
  String get title => movie.title;
}

class SonarrAddRequest extends ArrAddRequest {
  final SonarrSeries series;

  const SonarrAddRequest({required super.instanceId, required this.series});

  @override
  ServiceKey get service => ServiceKey.sonarr;

  @override
  String get title => series.title;
}
