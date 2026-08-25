import 'package:cupola/features/settings/domain/service_key.dart';

class GlobalSearchResult {
  final ServiceKey service;
  final int id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final Map<String, String>? imageHeaders;
  final List<String> tags;
  final String route;
  final Object? routeExtra;

  /// Shared-element tag for this result's poster, already stamped into [route]
  /// so the flight has a matching destination on the detail page.
  ///
  /// Stored rather than derived from `service` + `id`: within one service a
  /// movie and a series can carry the same id, so the builder that knows which
  /// kind this is also owns making the tag unique.
  final String heroTag;

  const GlobalSearchResult({
    required this.service,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.imageHeaders,
    required this.tags,
    required this.route,
    required this.heroTag,
    this.routeExtra,
  });

  /// Whether this result has artwork worth flying.
  ///
  /// Bazarr's API carries no poster, so its rows would otherwise fly an empty
  /// grey box into the detail page's fallback glyph — motion with nothing to
  /// follow. Same rule the Recently Added rail applies.
  bool get canFlyPoster => imageUrl.isNotEmpty;
}

class GlobalSearchServiceResults {
  final ServiceKey service;
  final List<GlobalSearchResult> results;
  final Object? error;

  /// Which connection answered, when the user has more than one of this
  /// service. Empty otherwise, and that emptiness is the whole rule: a stack
  /// with one Radarr must not grow a label naming the only Radarr there is.
  ///
  /// On the *section*, not on the rows. Every result under a heading came from
  /// the same server — one leg, one connection — so a chip repeated down forty
  /// rows would say the same thing forty times.
  final String instanceLabel;

  const GlobalSearchServiceResults({
    required this.service,
    required this.results,
    this.error,
    this.instanceLabel = '',
  });

  bool get hasError => error != null;
}
