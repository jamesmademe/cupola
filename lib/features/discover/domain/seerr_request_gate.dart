import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';

/// Why the detail page's Request does or does not act.
enum SeerrRequestState {
  /// Seerr would take a request for it now.
  open,

  /// Everything Seerr can hold of it is on disk.
  available,

  /// Asked for, and waiting on somebody's approval.
  waitingForApproval,

  /// Asked for and on its way: approved, or already in the arr.
  onItsWay,

  /// The last request for it failed, and Seerr will not take another until
  /// that one is dealt with.
  failed,

  /// The operator put it on Seerr's blocklist, and Seerr takes no request for
  /// it. A choice someone made, not a fault: nothing to fix from here.
  blocklisted,
}

/// What Request can do for one title, read from Seerr's own record of it.
typedef SeerrRequestGate = ({
  SeerrRequestState state,

  /// For a series that is [SeerrRequestState.open] while some of it is held
  /// or asked for already: the seasons a request would add, in order. Empty
  /// otherwise, including for a series nothing of which is held yet.
  List<int> missingSeasons,
});

/// Whether Seerr would take a request for this title, and if not, why.
///
/// It reads what Seerr's own request endpoint reads, and **nothing else**. The
/// page used to disable Request for any title Seerr held a row for, which
/// caught three kinds of title that can be requested: a series with some
/// seasons on disk and others not, a title whose files were deleted, and any
/// title on a stack whose Radarr is known only through Seerr.
///
/// Only the standard request: the sheet sends no 4K request, so `status4k`
/// and the 4K requests are not this gate's to read.
///
/// The codes are decoded with [numbering], the server's own
/// ([SeerrMediaAvailability.fromCode]), as the badge decodes them, so the
/// badge and the button cannot disagree about the same title. A deleted
/// title is requestable again; a blocklisted one is not. While the numbering
/// is unknown a 6 is neither, and Request stays open: Seerr itself refuses a
/// barred title.
///
/// A request's own status is read, never the `displayStatus` that lets the
/// media's availability stand in for it — the trap every Seerr list in this
/// app has to step around.
SeerrRequestGate seerrRequestGate(
  Map<String, dynamic>? mediaInfo, {
  required bool isMovie,
  List<TvSeason> seasons = const [],
  SeerrNumbering? numbering,
}) {
  SeerrMediaAvailability? decode(Object? code) => code == null
      ? null
      : SeerrMediaAvailability.fromCode(code, numbering: numbering);

  final media = decode(intOrNull(mediaInfo?['status']));
  final requests = _activeRequests(mediaInfo);

  // Seerr refuses any request for a barred title, by season or whole.
  if (media == SeerrMediaAvailability.blocklisted) {
    return _gate(SeerrRequestState.blocklisted);
  }

  if (isMovie) {
    if (media == SeerrMediaAvailability.available ||
        media == SeerrMediaAvailability.partiallyAvailable) {
      return _gate(SeerrRequestState.available);
    }
    // An active request is what Seerr refuses a second movie request over.
    final active = requests.firstOrNull;
    if (active != null) return _gate(_stateOf(active.status));
    return switch (media) {
      SeerrMediaAvailability.pending => _gate(
        SeerrRequestState.waitingForApproval,
      ),
      SeerrMediaAvailability.processing => _gate(SeerrRequestState.onItsWay),
      _ => _gate(SeerrRequestState.open),
    };
  }

  // A series: Seerr requests by season, and drops from a request every season
  // that is already asked for or that it has any record of on disk.
  final requestable = [
    for (final season in seasons)
      if (season.seasonNumber > 0 && season.episodeCount > 0)
        season.seasonNumber,
  ];
  if (requestable.isEmpty) {
    // No season list to count against: the title's own code is all there is.
    return switch (media) {
      null ||
      SeerrMediaAvailability.unknown ||
      SeerrMediaAvailability.deleted => _gate(SeerrRequestState.open),
      SeerrMediaAvailability.available ||
      SeerrMediaAvailability.partiallyAvailable => _gate(
        SeerrRequestState.available,
      ),
      SeerrMediaAvailability.pending => _gate(
        SeerrRequestState.waitingForApproval,
      ),
      SeerrMediaAvailability.processing => _gate(SeerrRequestState.onItsWay),
      SeerrMediaAvailability.blocklisted => _gate(
        SeerrRequestState.blocklisted,
      ),
    };
  }

  final asked = <int, int>{
    for (final request in requests)
      for (final season in request.seasons) season: request.status,
  };
  final held = <int, SeerrMediaAvailability>{};
  final rawSeasons = mediaInfo?['seasons'];
  if (rawSeasons is List) {
    for (final raw in rawSeasons) {
      final entry = mapOrNull(raw);
      final number = intOrNull(entry?['seasonNumber']);
      final status = decode(intOrNull(entry?['status']));
      if (number == null || status == null || _isUnheld(status)) continue;
      held[number] = status;
    }
  }

  final missing = [
    for (final season in requestable)
      if (!asked.containsKey(season) && !held.containsKey(season)) season,
  ];
  if (missing.isNotEmpty) {
    final partly = missing.length < requestable.length;
    return (
      state: SeerrRequestState.open,
      missingSeasons: partly ? missing : const <int>[],
    );
  }

  if (requestable.every(
    (season) => held[season] == SeerrMediaAvailability.available,
  )) {
    return _gate(SeerrRequestState.available);
  }
  if (asked.values.contains(_requestPending)) {
    return _gate(SeerrRequestState.waitingForApproval);
  }
  final unheld = requestable.where((season) => !held.containsKey(season));
  if (unheld.isNotEmpty &&
      unheld.every((season) => asked[season] == _requestFailed)) {
    return _gate(SeerrRequestState.failed);
  }
  return _gate(SeerrRequestState.onItsWay);
}

SeerrRequestGate _gate(SeerrRequestState state) =>
    (state: state, missingSeasons: const <int>[]);

// Request codes, Seerr's `MediaRequestStatus`.
const _requestPending = 1;
const _requestDeclined = 3;
const _requestFailed = 4;
const _requestCompleted = 5;

/// A season Seerr counts as not held: never seen, or deleted.
bool _isUnheld(SeerrMediaAvailability status) =>
    status == SeerrMediaAvailability.unknown ||
    status == SeerrMediaAvailability.deleted;

/// An active request's own status, as the gate says it. Approved, and any
/// code this app does not know, is on its way.
SeerrRequestState _stateOf(int requestStatus) => switch (requestStatus) {
  _requestPending => SeerrRequestState.waitingForApproval,
  _requestFailed => SeerrRequestState.failed,
  _ => SeerrRequestState.onItsWay,
};

/// The standard requests Seerr still counts against a new one: every request
/// that was neither declined nor completed.
List<({int status, List<int> seasons})> _activeRequests(
  Map<String, dynamic>? mediaInfo,
) {
  final raw = mediaInfo?['requests'];
  if (raw is! List) return const [];

  final active = <({int status, List<int> seasons})>[];
  for (final item in raw) {
    final request = mapOrNull(item);
    if (request == null || boolOrFalse(request['is4k'])) continue;
    final status = intOrNull(request['status']);
    if (status == null ||
        status == _requestDeclined ||
        status == _requestCompleted) {
      continue;
    }
    final seasons = <int>[];
    final rawSeasons = request['seasons'];
    if (rawSeasons is List) {
      for (final season in rawSeasons) {
        final number = intOrNull(mapOrNull(season)?['seasonNumber']);
        if (number != null) seasons.add(number);
      }
    }
    active.add((status: status, seasons: seasons));
  }
  return active;
}
