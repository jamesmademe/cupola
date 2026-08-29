import 'package:cupola/features/search/domain/arr_add_request.dart';
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

  /// Whether the server that listed this row already holds the title.
  ///
  /// A separate fact from anything in [tags], which are words on a chip: this
  /// is what the row's trailing affordance reads to decide between "already
  /// here" and "add it". It used to sniff the tags for the substring
  /// `available`, which tied a semantic decision to a label's wording — and to
  /// a field the lookup endpoints never populate.
  final bool inLibrary;

  /// What it would take to add this row to the server that listed it, or null
  /// when there is nothing honest to offer.
  ///
  /// Null on three kinds of row, for three different reasons: one the server
  /// already holds (there is nothing to add), a Seerr or Bazarr row (neither
  /// is a library this app can write into from here — Seerr's own request flow
  /// lives on its detail page), and a Lidarr artist the lookup returned with no
  /// MusicBrainz id (Lidarr keys an artist on that id, so an add without it
  /// would be refused). The trailing plus is drawn from this rather than from
  /// the service, so an affordance can never outlive what is behind it — which
  /// is the defect this field exists to close: every arr row wore a plus that
  /// led to a detail page saying "add it in Radarr".
  ///
  /// It carries the CONNECTION, not the lens. Two Radarr answer as two
  /// sections and the user chose one by choosing where to touch.
  final ArrAddRequest? addRequest;

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
    this.inLibrary = false,
    this.addRequest,
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
