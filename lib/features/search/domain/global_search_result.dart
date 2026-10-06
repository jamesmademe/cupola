import 'dart:async';

import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/search/domain/arr_add_request.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// What a search hit is, which decides the section it is drawn in.
enum SearchHitKind {
  movie,
  series,
  person,

  /// Anything else a media server finds (an episode, a track): not a title
  /// of the catalogue, so the search by kind leaves it out.
  other,
}

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
  /// Null on two kinds of row, for two different reasons: one the server
  /// already holds (there is nothing to add), and a Seerr or Bazarr row
  /// (neither is a library this app can write into from here — Seerr's own
  /// request flow lives on its detail page). The trailing plus is drawn from
  /// this rather than from the service, so an affordance can never outlive
  /// what is behind it — which is the defect this field exists to close: every
  /// arr row wore a plus that led to a detail page saying "add it in Radarr".
  ///
  /// It carries the CONNECTION, not the lens. Two Radarr answer as two
  /// sections and the user chose one by choosing where to touch.
  final ArrAddRequest? addRequest;

  /// Movie, series, person or neither.
  final SearchHitKind kind;

  /// The title across services, where the row carries the ids to name it:
  /// what folds the same film found by Seerr, Radarr and Jellyfin into one
  /// row. Null for a person, and for a title whose source gave no TMDB or
  /// TVDB id.
  final MediaKey? key;

  /// The year it came out, when the source says.
  final int? year;

  /// TMDB's score, from Seerr's row; null for a title nobody rated.
  final double? score;

  /// Seerr's record of the title (`mediaInfo`): what the server holds of it
  /// and what was asked, in Seerr's words. Only on Seerr's own rows.
  final Map<String, dynamic>? seerrInfo;

  /// A person's best known titles, TMDB's order first.
  final List<String> knownFor;

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
    this.kind = SearchHitKind.other,
    this.key,
    this.year,
    this.score,
    this.seerrInfo,
    this.knownFor = const [],
  });

  /// Whether this result has artwork worth flying.
  ///
  /// Bazarr's API carries no poster, so its rows would otherwise fly an empty
  /// grey box into the detail page's fallback glyph — motion with nothing to
  /// follow. Same rule the Recently Added rail applies.
  bool get canFlyPoster => imageUrl.isNotEmpty;
}

/// One leg of the fan-out: one service, one of its connections.
///
/// The unit of work *and* the key the leg provider family is keyed on, which is
/// what makes a per-lane Retry a one-liner —
/// `ref.invalidate(globalSearchLegProvider(leg))` and nothing wider. A record
/// rather than a class because [ServiceInstance] already carries value
/// equality, so the key compares by what it names: edit a connection's address
/// and the round mints a new family member instead of quietly reusing the old
/// server's answer.
///
/// [name] is what the section calls the connection, resolved once by the
/// provider through `SettingsModel.connectionName`, and empty whenever the
/// service has a single connection: a stack with one Radarr must not grow a
/// chip naming the only Radarr there is. It is part of the key on purpose, so
/// a connection renamed mid-search redraws its heading.
typedef SearchLeg = ({ServiceInstance instance, String name});

/// Where one lane of the fan-out has got to.
///
/// A lane is a whole state machine rather than a `hasError` bool because the
/// design draws four different things in that one slot, and three of them are
/// not the same fault: a lane still in flight is a promise, a lane that ran out
/// of time is a slow server, and a lane whose connection never answered is a
/// box that is off. Collapsing them is what made a Bazarr taking eight seconds
/// render identically to a Bazarr that was unplugged.
enum SearchLaneState {
  /// The request is out and the deadline has not passed.
  searching,

  /// The server answered. [GlobalSearchServiceResults.results] is the answer,
  /// and an empty one means "this library does not have it" — never "the box
  /// is off", which is the distinction the whole per-connection fan-out rests
  /// on.
  answered,

  /// The lane's own deadline passed with nothing on the wire.
  timedOut,

  /// Nothing answered at the socket at all.
  unreachable,

  /// The server answered and the answer was a refusal: a rejected key, an API
  /// that is not at this address, a certificate nothing trusts.
  failed,
}

extension SearchLaneStateVocabulary on SearchLaneState {
  /// The tone this lane paints in, from the closed [StatusTone] vocabulary.
  /// Resolve it with `statusToneColor`; never reach for a palette constant.
  ///
  /// The two arms that are easy to get wrong, and are the point of the sheet:
  ///
  /// * **timed out is AMBER, not red.** A slow server is a fault — something to
  ///   look at — but the address, the key and the route are all fine, and red
  ///   would send the user auditing settings that are already correct.
  /// * **red is UNREACHABLE and nothing else.** It is the one state where there
  ///   is no server on the other end to be slow, so it is the one state worth
  ///   the loudest ink in the app.
  StatusTone get tone => switch (this) {
    SearchLaneState.searching => StatusTone.info,
    SearchLaneState.answered => StatusTone.neutral,
    SearchLaneState.timedOut || SearchLaneState.failed => StatusTone.warning,
    SearchLaneState.unreachable => StatusTone.error,
  };

  /// Whether this lane owes the user a Retry.
  ///
  /// Only a lane that stopped. Retrying a lane still in flight would cancel the
  /// request the user is waiting for and start it again a keystroke behind.
  bool get canRetry => switch (this) {
    SearchLaneState.searching || SearchLaneState.answered => false,
    _ => true,
  };
}

/// One lane of the global search: one connection, its state, and whatever it
/// managed to say.
class GlobalSearchServiceResults {
  /// The connection this lane asked — and the key its Retry invalidates.
  final SearchLeg leg;

  final List<GlobalSearchResult> results;

  final SearchLaneState state;

  /// Why the lane stopped, when the classifier could attribute it. Null on
  /// every lane that did not stop, and on the handful of failures that carry
  /// nothing to attribute them with.
  final ServiceFailureReason? reason;

  /// What answered in the lane's server's place, when [reason] is a
  /// gateway's: its word names it.
  final AccessGatewayAnswer? gateway;

  const GlobalSearchServiceResults({
    required this.leg,
    this.results = const [],
    this.state = SearchLaneState.answered,
    this.reason,
    this.gateway,
  });

  /// A lane that stopped, with its tone resolved from the failure rather than
  /// guessed at the widget.
  ///
  /// The whole mapping lives here so no screen re-derives it. Two arms are
  /// arguments rather than lookups:
  ///
  /// * `timeout` becomes [SearchLaneState.timedOut] and therefore amber. The
  ///   settings sheet's `describeConnection` paints the same reason red, and
  ///   that is a different question: there the timeout is the verdict on the
  ///   connection itself, here it is one query against a server that answers
  ///   the rest of the app fine.
  /// * `localNetworkBlocked` is a *fault*, not [SearchLaneState.unreachable],
  ///   even though nothing left the device. Nothing is wrong with the address,
  ///   the server or the key — the OS has simply not been told Cupola may talk
  ///   to this network — and red here sends the user auditing settings that are
  ///   already correct. Same argument `describeConnection` makes.
  factory GlobalSearchServiceResults.fault(SearchLeg leg, Object? error) {
    // The lane's own deadline is the one bare timeout whose meaning is known:
    // the search itself ran long on a server the rest of the app reaches. The
    // shared classifier reads a bare deadline as "did not answer", because in
    // general it cannot tell; here the lane can, so it says timed out.
    final reason = error is TimeoutException
        ? ServiceFailureReason.timeout
        : classifyConnectionFailure(error);
    return GlobalSearchServiceResults(
      leg: leg,
      state: switch (reason) {
        ServiceFailureReason.timeout => SearchLaneState.timedOut,
        ServiceFailureReason.unreachable => SearchLaneState.unreachable,
        _ => SearchLaneState.failed,
      },
      reason: reason,
      gateway: accessGatewayOf(error),
    );
  }

  ServiceKey get service => leg.instance.service;

  /// Which connection answered, when the user has more than one of this
  /// service. Empty otherwise, and that emptiness is the whole rule: a stack
  /// with one Radarr must not grow a label naming the only Radarr there is.
  ///
  /// On the *section*, not on the rows. Every result under a heading came from
  /// the same server — one leg, one connection — so a chip repeated down forty
  /// rows would say the same thing forty times.
  ///
  /// Read off the leg rather than stored: it used to be a field the provider
  /// filled in on the success path and again on the failure path, which is two
  /// chances to spell one fact differently. A connection the user never named
  /// reads `Radarr 2`, by the app's one rule, and never its id.
  String get instanceLabel => leg.name;

  /// How a sentence names this lane: `Radarr`, `Radarr · 4K` once there are
  /// two of them, or `Radarr 2` for one the user never named, whose name
  /// already says the service.
  String get laneTitle => serviceWithConnection(service, instanceLabel);

  /// What [gate] lets this lane be called on screen: [laneTitle] wherever the
  /// service may be named, and `Requests` for the requester's Seerr, whose
  /// name she never reads.
  String titleFor(RoleGate gate) =>
      gate.namesService(service) ? laneTitle : Lexicon.requestsLane;

  /// Whether the lane stopped short of an answer. Not "is red" — three of the
  /// four stopped states are amber.
  bool get hasFault => state.canRetry;

  /// The sentence the lane's fault card prints, in place of rows: what is
  /// missing, and why, in one shape for every way a lane stops.
  ///
  /// It says nothing about Retry. Whether there is one is the cause's call
  /// (`failureRetryHelps`), and where there is, the button itself names the
  /// server it asks again (`Retry Radarr`), so the sentence is left to say
  /// what happened.
  String get faultSentence => switch (state) {
    // The lane's own deadline, on a server the rest of the app reaches: the
    // search ran long, which is not the server going quiet.
    SearchLaneState.timedOut => 'No $laneTitle results: the search timed out.',
    _ => 'No $laneTitle results: $_failureClause.',
  };

  /// The connection whose form holds the fix for this lane's failure, for its
  /// remedy: the lane's own.
  String get instanceId => leg.instance.id;

  /// What went wrong, as the clause after the colon: the classification's
  /// headline in sentence form, never a state label, whose capital would land
  /// in the middle of the sentence ("No Radarr results, Behind Cloudflare
  /// Access."). Its first word keeps its capital only when it is a name: the
  /// lane's own, or the gateway's (`Cloudflare Access answered instead of
  /// Radarr`); `A sign-in page`, `The request` and the like go lower case.
  String get _failureClause {
    final headline = failureHeadline(
      state == SearchLaneState.unreachable
          ? ServiceFailureReason.unreachable
          : reason ?? ServiceFailureReason.unknown,
      subject: laneTitle,
      credential: refusedCredentialOf(service),
      gateway: gateway,
    );
    final named =
        headline.startsWith(laneTitle) || headline.startsWith('Cloudflare');
    return named
        ? headline
        : '${headline[0].toLowerCase()}${headline.substring(1)}';
  }
}
