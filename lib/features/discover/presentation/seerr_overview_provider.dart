/// What the Seerr Overview reads, and the pure functions that shape it.
///
/// Seerr is the exception among the media services: its home leads with the
/// **decisions**, then the work already under way, and the discover rails move
/// down — approving is what the phone opens Seerr for, and the rails are the
/// reason the service exists rather than the reason the page is opened.
///
/// Everything here is derived from the one request list the KPI rail already
/// loads, so the page costs one `/request` fetch plus the trending rail. Every
/// windowing rule is a top-level pure function taking an explicit `now`, so the
/// boundaries are unit-testable without a clock or a container.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart'
    show formatRelativeDateTime;
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// Rows the Processing section draws before its header count is the only place
/// the rest are reported.
const int seerrProcessingPreviewLimit = 5;

/// Posters on the Trending rail.
const int seerrTrendingRailLimit = 10;

/// One row of the Seerr Overview: the title, who and when, and the tone.
@immutable
class SeerrOverviewRow {
  const SeerrOverviewRow({
    required this.request,
    required this.headline,
    required this.detail,
    required this.tone,
  });

  /// The record the row stands for, so a caller can act on it by id without
  /// re-deriving anything.
  final SeerrRequest request;

  /// `Severance — Season 2`.
  final String headline;

  /// `nadia · 4 h ago · TV · 4K`, as far as the record carried them.
  final String detail;

  /// How the row reads.
  ///
  /// A pending request is [StatusTone.warning] in the **Activity** vocabulary,
  /// where it is a thing waiting on a human and the point of the page is to
  /// find it. On a service home it is [StatusTone.neutral]: a queue of
  /// approvals is the normal resting state of a Seerr with no auto-approve
  /// rule, and painting it amber would say something broke.
  final StatusTone tone;

  /// The row as one sentence, with the layout's `·` turned back into commas.
  String get spoken => joinSpokenParts([headline, spokenFromDotted(detail)]);
}

/// A section's preview rows and the count they were cut from.
///
/// [total] is counted **before** [rows] is limited, so a header built from it
/// tells the truth when there is more waiting than the section has room for.
/// [isFloor] when the request list it was counted over is not all of Seerr's
/// ([holdsEveryRequest]): the header then reads `3+`, never `3`.
typedef SeerrOverviewSection = ({
  List<SeerrOverviewRow> rows,
  int total,
  bool isFloor,
});

/// `Severance, Season 2`, `Dune: Part Three`, `The Bear, 3 seasons`.
///
/// A TV request is a request for *seasons*, not for a show: two people asking
/// for two different seasons of the same series are two rows that would
/// otherwise be indistinguishable.
String seerrRequestHeadline(SeerrRequest request) {
  final title = request.media?.title?.trim();
  final name = (title == null || title.isEmpty) ? 'Untitled request' : title;

  final seasons = request.seasons;
  if (request.type != 'tv' || seasons == null || seasons.isEmpty) return name;
  if (seasons.length == 1) {
    return '$name, Season ${seasons.single.seasonNumber}';
  }
  return '$name, ${seasons.length} seasons';
}

/// `nadia · 4 h ago · TV · 4K`.
///
/// The quality clause is the request's own profile name, or the bare `4K` flag
/// when Seerr named no profile. Nothing is printed when it carried neither:
/// a default of `1080p` would be a figure nobody sent.
///
/// Who asked only with [namesWho], and the profile only with [showsProfile]:
/// the gate of the Seerr the request came off says each (who may see
/// everyone's requests, who may choose where one goes). Without the profile
/// the bare `4K` stands in.
String seerrRequestDetail(
  SeerrRequest request, {
  required DateTime now,
  bool namesWho = true,
  bool showsProfile = true,
}) {
  final created = DateTime.tryParse(request.createdAt);
  return joinDisplayParts([
    if (namesWho) request.requestedBy?.displayName,
    created == null ? null : formatRelativeDateTime(created, now: now),
    request.type == 'tv' ? 'TV' : 'Movie',
    (showsProfile ? request.profileName : null) ?? (request.is4k ? '4K' : null),
  ]);
}

/// What the gate of the lens's Seerr lets a request row say.
typedef SeerrRowVoice = ({bool namesWho, bool showsProfile});

/// [SeerrRowVoice] for the lens's Seerr, from its gate.
SeerrRowVoice seerrRowVoice(Ref ref) {
  final gate = ref.watch(roleGateOfProvider(''));
  return (
    namesWho: gate.showsRequesterNames,
    showsProfile: gate.operatorAction(SeerrAbility.chooseDestination).isDrawn,
  );
}

SeerrOverviewRow _row(
  SeerrRequest request, {
  required DateTime now,
  required StatusTone tone,
  required SeerrRowVoice voice,
}) => SeerrOverviewRow(
  request: request,
  headline: seerrRequestHeadline(request),
  detail: seerrRequestDetail(
    request,
    now: now,
    namesWho: voice.namesWho,
    showsProfile: voice.showsProfile,
  ),
  tone: tone,
);

const SeerrRowVoice _operatorVoice = (namesWho: true, showsProfile: true);

/// The requests waiting on a human, shaped into rows.
///
/// The filtering itself belongs to [seerrDecisionsProvider], which reads the
/// request's OWN status and never `displayStatus` — the one trap on this
/// service. This function only dresses what that provider already chose.
List<SeerrOverviewRow> seerrDecisionRows(
  List<SeerrRequest> requests, {
  required DateTime now,
  SeerrRowVoice voice = _operatorVoice,
}) => List.unmodifiable([
  for (final request in requests)
    _row(request, now: now, tone: StatusTone.neutral, voice: voice),
]);

/// The requests Seerr has already accepted and is still working on.
///
/// **This** one reads `displayStatus`, and that is correct here: the question
/// is where the media is, not what the request needs from a person. The trap is
/// in the other direction — a decisions list keyed off `displayStatus` silently
/// drops the approvals for titles the library already holds.
///
/// [StatusTone.info]: work in flight is informational, not a fault and not
/// backlog.
SeerrOverviewSection seerrProcessingSection(
  List<SeerrRequest> requests, {
  required DateTime now,
  int limit = seerrProcessingPreviewLimit,
  SeerrRowVoice voice = _operatorVoice,
}) {
  final working = <SeerrRequest>[];
  for (final request in requests) {
    switch (request.displayStatus.kind) {
      case SeerrRequestDisplayKind.approved:
      case SeerrRequestDisplayKind.processing:
        working.add(request);
      case SeerrRequestDisplayKind.pending:
      case SeerrRequestDisplayKind.available:
      case SeerrRequestDisplayKind.partiallyAvailable:
      case SeerrRequestDisplayKind.completed:
      case SeerrRequestDisplayKind.declined:
      case SeerrRequestDisplayKind.failed:
      case SeerrRequestDisplayKind.blocklisted:
      case SeerrRequestDisplayKind.deleted:
      case SeerrRequestDisplayKind.unknown:
        break;
    }
  }

  // Newest first, and an unparseable `createdAt` sorts last within the group
  // rather than to the epoch — the same rule `sortRequestsPendingFirst` keeps,
  // and for the same reason: an undated row planted at the bottom of a "newest
  // first" list reads as genuinely old.
  working.sort((a, b) {
    final createdA = DateTime.tryParse(a.createdAt);
    final createdB = DateTime.tryParse(b.createdAt);
    if (createdA == null && createdB == null) return 0;
    if (createdA == null) return 1;
    if (createdB == null) return -1;
    return createdB.compareTo(createdA);
  });

  return (
    rows: List.unmodifiable([
      for (final request in working.take(limit))
        _row(request, now: now, tone: StatusTone.info, voice: voice),
    ]),
    total: working.length,
    isFloor: !holdsEveryRequest(requests),
  );
}

// ─── Providers ──────────────────────────────────────────────────────────────

/// The Overview's first region: what is waiting on a person.
///
/// `noProviderRetry`, because the provider it derives from carries it: without
/// it the derivation quietly reintroduces the ten backed-off re-runs the source
/// refused, which cannot reach a server that has already settled on a failure
/// and only hold the section in its loading state for the best part of a
/// minute.
final seerrOverviewDecisionsProvider =
    FutureProvider.autoDispose<SeerrOverviewSection>((ref) async {
      final voice = seerrRowVoice(ref);
      final decisions = await ref.watch(seerrDecisionsProvider.future);
      return (
        rows: seerrDecisionRows(
          decisions.preview,
          now: DateTime.now(),
          voice: voice,
        ),
        total: decisions.total,
        isFloor: decisions.isFloor,
      );
    }, retry: noProviderRetry);

/// The Overview's second region: what Seerr is already doing about the rest.
final seerrOverviewProcessingProvider =
    FutureProvider.autoDispose<SeerrOverviewSection>((ref) async {
      final voice = seerrRowVoice(ref);
      final requests = await ref.watch(requestsProvider.future);
      return seerrProcessingSection(
        requests,
        now: DateTime.now(),
        voice: voice,
      );
    }, retry: noProviderRetry);

/// The trending rail, cut to the rail's budget.
///
/// Seerr's `/discover/trending` proxies TMDB's weekly trending list, which is
/// what lets the section call itself "this week" without inventing a window the
/// client never asked for.
///
/// `noProviderRetry` like the rail it cuts: a Seerr that did not answer fails
/// the source now, and a derived provider under the default policy would
/// retry what its source had already given up on.
final seerrOverviewTrendingProvider =
    FutureProvider.autoDispose<List<MediaPreview>>((ref) async {
      final trending = await ref.watch(discoverTrendingProvider.future);
      return List.unmodifiable(trending.take(seerrTrendingRailLimit));
    }, retry: noProviderRetry);
