import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/search/domain/arr_add_request.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
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
/// [named] is the "two Radarr" flag and not a label: a stack with one Radarr
/// must not grow a chip naming the only Radarr there is.
typedef SearchLeg = ({ServiceInstance instance, bool named});

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

  /// Whether the lane's word is preceded by a coloured pip.
  ///
  /// An answered lane prints its count and nothing else: a pip beside every
  /// heading is a pip that marks nothing.
  bool get showsPip => this != SearchLaneState.answered;

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

  const GlobalSearchServiceResults({
    required this.leg,
    this.results = const [],
    this.state = SearchLaneState.answered,
    this.reason,
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
    final reason = classifyConnectionFailure(error);
    return GlobalSearchServiceResults(
      leg: leg,
      state: switch (reason) {
        ServiceFailureReason.timeout => SearchLaneState.timedOut,
        ServiceFailureReason.unreachable => SearchLaneState.unreachable,
        _ => SearchLaneState.failed,
      },
      reason: reason,
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
  /// Derived rather than stored: it used to be a field the provider filled in
  /// on the success path and again on the failure path, which is two chances to
  /// spell one fact differently.
  String get instanceLabel {
    if (!leg.named) return '';
    final label = leg.instance.label;
    return label.isEmpty ? leg.instance.id : label;
  }

  /// How a sentence names this lane: `Radarr`, or `Radarr · 4K` once there are
  /// two of them.
  String get laneTitle => instanceLabel.isEmpty
      ? service.title
      : '${service.title} · $instanceLabel';

  /// Whether the lane stopped short of an answer. Not "is red" — three of the
  /// four stopped states are amber.
  bool get hasFault => state.canRetry;

  /// The word beside the pip: what this lane is doing, or what went wrong.
  String get stateWord => switch (state) {
    SearchLaneState.searching => 'Searching…',
    SearchLaneState.answered =>
      '${results.length} result${results.length == 1 ? '' : 's'}',
    SearchLaneState.timedOut => 'Did not answer in time',
    SearchLaneState.unreachable => 'Unreachable',
    SearchLaneState.failed => _failureWord,
  };

  /// The sentence the lane's fault card prints, in place of rows.
  ///
  /// It says what is missing *and* that Retry is per lane, because the whole
  /// promise of the screen is that one dead server does not hold the other six:
  /// a Retry the user reads as "start the search again" is a Retry they will
  /// not press while the rest of the page is still useful.
  String get faultSentence => switch (state) {
    SearchLaneState.timedOut =>
      'No $laneTitle results, the query timed out. Retry is per lane.',
    SearchLaneState.unreachable =>
      'No $laneTitle results, that connection did not answer at all. '
          'Retry is per lane.',
    _ =>
      'No $laneTitle results, $_failureWord. '
          'Retry is per lane.',
  };

  /// The words this app already uses for each refusal, so the search screen and
  /// the settings rows cannot describe one failure two different ways.
  String get _failureWord => switch (reason) {
    ServiceFailureReason.unauthorized =>
      service.usesApiKey ? 'API key rejected' : 'Sign-in rejected',
    ServiceFailureReason.notFound => 'API not at this address',
    ServiceFailureReason.redirected => 'Redirected elsewhere',
    ServiceFailureReason.tls => 'Certificate not trusted',
    ServiceFailureReason.localNetworkBlocked => 'Local network blocked',
    ServiceFailureReason.serverError => 'Answered with an error',
    // Reached, failed, and nothing in the exception says why. Deliberately not
    // "unreachable": claiming the box is off on the strength of an error nobody
    // could read is the same lie one tone louder.
    _ => 'Search failed',
  };
}

/// "7 connections asked · 5 answered · 1 still searching · 1 timed out".
///
/// A fold over the lane states and nothing else, so the line beside the heading
/// can never disagree with the sections under it — which is the whole reason it
/// is a function over the lanes rather than a counter the page keeps.
///
/// Zero counts are left out: "0 timed out" is a word about nothing. *Answered*
/// always prints, because it is the number the line exists to report and
/// "0 answered" is the entire story while a stack is down.
///
/// Null for no lanes at all — there is nothing to census before a query, and a
/// readout saying "0 connections asked" would state a fact about the query
/// rather than about the stack.
String? searchLaneCensus(List<GlobalSearchServiceResults> lanes) {
  if (lanes.isEmpty) return null;
  var answered = 0;
  var searching = 0;
  var timedOut = 0;
  var unreachable = 0;
  var failed = 0;
  for (final lane in lanes) {
    switch (lane.state) {
      case SearchLaneState.answered:
        answered++;
      case SearchLaneState.searching:
        searching++;
      case SearchLaneState.timedOut:
        timedOut++;
      case SearchLaneState.unreachable:
        unreachable++;
      case SearchLaneState.failed:
        failed++;
    }
  }
  return [
    '${lanes.length} connection${lanes.length == 1 ? '' : 's'} asked',
    '$answered answered',
    if (searching > 0) '$searching still searching',
    if (timedOut > 0) '$timedOut timed out',
    if (unreachable > 0) '$unreachable unreachable',
    if (failed > 0) '$failed failed',
  ].join(' · ');
}
