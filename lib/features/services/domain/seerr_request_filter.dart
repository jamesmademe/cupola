import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/services/domain/request_ordering.dart';

/// The buckets the All Requests screen filters by.
///
/// Grouped by **request lifecycle**, not by the exact pill text, and that
/// distinction is the whole reason this lives here instead of in a build method.
/// [SeerrRequest.displayStatus] lets media availability override the request's
/// own status, so an approved request whose media is still downloading reports
/// `processing` and one that finished reports `available` — neither reports
/// `approved`. Matching the chip label literally would therefore leave
/// "Approved" almost always empty while the requests it should list sit under
/// labels of their own.
///
/// So [approved] means "got past approval", which is what a user picking that
/// chip is asking for.
///
/// [pending] reads the request's own status and nothing else
/// ([isAwaitingApproval]), the same test every "N waiting" count makes. It
/// used to read `displayStatus`, which is the trap seen from this side: a
/// request still waiting for approval, for a series some of which is already
/// on disk, reads "Partially available" and fell out of Pending into Approved,
/// while a request already approved, for a title whose media Seerr still
/// marks pending, was listed under Pending though nobody had to decide it.
/// Neither agreed with the count the header showed.
enum SeerrRequestFilter {
  all('All'),
  // The label only: the filter keys on Seerr's own request status, never on
  // the display status the media's availability overrides.
  pending('Waiting for approval'),
  approved('Approved'),
  declined('Declined');

  const SeerrRequestFilter(this.label);

  /// The chip text, and the word used in the empty state.
  final String label;

  /// Whether [request] belongs in this bucket.
  ///
  /// A request waiting for approval belongs in [pending] and no other bucket,
  /// whatever its media says: the buckets do not overlap.
  bool matches(SeerrRequest request) {
    if (this == SeerrRequestFilter.all) return true;
    final waiting = isAwaitingApproval(request);
    if (this == SeerrRequestFilter.pending) return waiting;
    if (waiting) return false;

    final kind = _lifecycleKind(request);
    return switch (this) {
      SeerrRequestFilter.all || SeerrRequestFilter.pending => false,
      SeerrRequestFilter.approved =>
        kind == SeerrRequestDisplayKind.approved ||
            kind == SeerrRequestDisplayKind.processing ||
            kind == SeerrRequestDisplayKind.available ||
            kind == SeerrRequestDisplayKind.partiallyAvailable ||
            kind == SeerrRequestDisplayKind.completed,
      // `failed`, `blocklisted` and `deleted` belong here rather than in
      // their own bucket: each means the request will not deliver, which is
      // what someone looking for declined requests wants to see. `unknown` is
      // deliberately in no bucket but `all`, so an unparsed status never hides
      // behind a wrong one.
      SeerrRequestFilter.declined =>
        kind == SeerrRequestDisplayKind.declined ||
            kind == SeerrRequestDisplayKind.failed ||
            kind == SeerrRequestDisplayKind.blocklisted ||
            kind == SeerrRequestDisplayKind.deleted,
    };
  }

  /// Where a request no longer waiting is in its life: its display status,
  /// except where that only says the **media** is pending. The media can be
  /// pending under another request while this one was already decided, and
  /// then the request's own status is the answer.
  static SeerrRequestDisplayKind _lifecycleKind(SeerrRequest request) {
    final kind = request.displayStatus.kind;
    if (kind != SeerrRequestDisplayKind.pending) return kind;
    return switch (request.status) {
      RequestStatus.approved => SeerrRequestDisplayKind.approved,
      RequestStatus.completed => SeerrRequestDisplayKind.completed,
      RequestStatus.declined => SeerrRequestDisplayKind.declined,
      RequestStatus.failed => SeerrRequestDisplayKind.failed,
      RequestStatus.pendingApproval => SeerrRequestDisplayKind.pending,
      RequestStatus.unknown => SeerrRequestDisplayKind.unknown,
    };
  }

  /// The requests in [requests] that belong to this bucket, order preserved.
  List<SeerrRequest> apply(List<SeerrRequest> requests) {
    if (this == SeerrRequestFilter.all) return requests;
    return requests.where(matches).toList(growable: false);
  }

  /// The empty-state copy for this bucket.
  String get emptyLabel => switch (this) {
    SeerrRequestFilter.all => 'No requests found',
    SeerrRequestFilter.pending => 'No requests waiting for approval',
    _ => 'No ${label.toLowerCase()} requests',
  };
}
