import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Seerr home's first region: the requests waiting on a human.
///
/// Seerr is the exception among the media services. Every other service home
/// leads with what is arriving or what is on disk; this one leads with the
/// decisions, and the Discover rails move below it, because approving is what
/// the phone is opened for. The rails are the reason the *service* exists and
/// the decisions are the reason the *page* is opened, and those are not the same
/// question.
///
/// Renders nothing at all when nothing is waiting — which, on a stack with
/// auto-approvals, is the normal state. An empty "Needs a decision" well would
/// be a permanent apology for a working configuration, and a count of 0 would be
/// a figure nobody has to read.
class SeerrDecisionsSection extends ConsumerWidget {
  const SeerrDecisionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decisions = ref.watch(seerrDecisionsProvider);

    return decisions.when(
      // Nothing while it loads, rather than five skeleton rows. The common
      // outcome of this load is "no section" — see the class comment — so
      // reserving its height and then collapsing would make the catalog jump on
      // every visit to the page, in exchange for a shimmer nobody was waiting
      // on. The rails underneath are loading in the same moment, so the screen
      // is not blank meanwhile.
      loading: () => const SizedBox.shrink(),
      error: (error, _) {
        // Same detection as `AsyncValueWidget`: a service that was never set up
        // is not a service that failed, and the whole page is already empty
        // under it. Saying "Seerr did not answer" there would invent a fault.
        if (error.toString().contains('not configured')) {
          return const SizedBox.shrink();
        }
        return InlineErrorRetry(
          message: sectionFailureMessage(
            ServiceKey.seerr,
            error,
            consequence: 'the requests waiting for approval are unknown',
          ),
          error: error,
          // The section owns no fetch of its own; dropping the list it derives
          // from is what re-runs it.
          onRetry: () => ref.invalidate(requestsProvider),
        );
      },
      data: (decisions) {
        if (decisions.preview.isEmpty) return const SizedBox.shrink();

        final waiting = decisions.total;
        final noun = waiting == 1 ? 'request' : 'requests';
        // Counted over the requests that arrived, so a lost page leaves a
        // floor: `3+ waiting`, "at least 3" to the ear.
        final floor = decisions.isFloor;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Needs a decision',
              // Tabular in `SectionHeader`, which matters here: the count moves
              // under the user's finger as they approve.
              subtitle: '$waiting${floor ? '+' : ''} waiting',
              onTap: () => context.push(ServiceRoutes.seerrRequests),
              // The header silences its own subtree, so the visible count is
              // only spoken if it is folded in here.
              semanticLabel:
                  'Needs a decision, ${floor ? 'at least ' : ''}'
                  '$waiting $noun waiting',
              semanticHint: 'Opens every Seerr request',
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final request in decisions.preview)
              _DecisionRow(request: request),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }
}

/// One waiting request: what it is, who asked, and the two answers.
///
/// Deliberately carries **no status pill**. Pending is the one row the tone rule
/// does not settle, and the answer depends on where it is drawn: in the Activity
/// vocabulary it is amber, because it waits on a human and that screen's job is
/// to say what needs doing. Here the section is already called "Needs a
/// decision" and the row's presence inside it *is* the signal, so a pill would
/// restate the heading in colour and spend a tone on it.
class _DecisionRow extends ConsumerWidget {
  const _DecisionRow({required this.request});

  final SeerrRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final media = request.media;
    final title = media?.title ?? 'Unknown media';
    final year = media?.year;
    final heading = year == null || year.isEmpty ? title : '$title ($year)';
    final requester = request.requestedBy?.displayName;
    final kind = request.type == 'tv' ? 'Series' : 'Movie';
    // '—' and never a fabricated date: `formatRelativeActivityDate` already
    // answers that way for a timestamp Seerr omitted.
    final age = formatRelativeActivityDate(request.createdAt);

    final posterUrl = ImageUtils.buildTmdbPosterUrl(media?.posterPath);
    final heroTag = 'seerr_decision_${request.id}';
    final tmdbId = media?.tmdbId;

    // Spoken as one sentence. On screen this is four fragments plus a '·' that
    // a screen reader reads out as "middle dot".
    final spokenValue = [
      kind,
      if (requester != null) 'requested by $requester',
      age,
    ].join(', ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: AppCard.outlined(
        // Without a TMDB id there is no detail page to open, so the card is a
        // plain container rather than a control that goes nowhere. The two
        // answers below still work: deciding needs the request id, not the id
        // of the title.
        onTap: tmdbId == null
            ? null
            : () => context.push(
                ServiceRoutes.seerrDetail(
                  mediaType: request.type,
                  id: tmdbId,
                  heroTag: heroTag,
                  posterUrl: posterUrl,
                ),
              ),
        semanticLabel: heading,
        semanticValue: spokenValue,
        semanticHint: tmdbId == null ? null : 'Opens the title in Seerr',
        backgroundColor: colorScheme.surfaceContainer,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            ExcludeSemantics(
              child: SizedBox(
                width: 38,
                height: 54,
                child: posterUrl.isEmpty
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(AppSpacing.xs),
                        ),
                        child: Icon(
                          request.type == 'tv'
                              ? Icons.tv_rounded
                              : Icons.movie_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Hero(
                        tag: heroTag,
                        transitionOnUserGestures:
                            MediaPosterCard.flightOnUserGestures,
                        child: ContentCard(imageUrl: posterUrl),
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.rowTitle(
                        theme.brightness,
                      ).copyWith(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [kind, ?requester, age].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Left outside the card's label so each keeps a node of its own,
            // and each names the title: there is one pair of these per row and
            // "Approve" alone would be four identical buttons in the rotor.
            _DecisionButton.decline(request: request, title: title),
            _DecisionButton.approve(request: request, title: title),
          ],
        ),
      ),
    );
  }
}

/// One of the two answers.
///
/// Both dispatch through [ActivityActions], which is the app's single Seerr
/// write path: it owns the confirm dialog, the `SeerrRequestConflict` case —
/// somebody else approved it from the web UI a moment ago — the toast, and the
/// invalidation of the request list this section derives from. A private copy
/// here would be the third and would be the one that drifts.
class _DecisionButton extends ConsumerWidget {
  const _DecisionButton.approve({required this.request, required this.title})
    : _isApprove = true;

  const _DecisionButton.decline({required this.request, required this.title})
    : _isApprove = false;

  final SeerrRequest request;
  final String title;
  final bool _isApprove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    // Approve is the weightier of the two, and monochrome: the primary ink on
    // the room's strong fill — it used to be Seerr's accent on a tint of
    // itself. Decline stays the secondary ink on nothing: it is not
    // destructive enough for a tone (the request stays on record as
    // declined), and red here would read as a fault on a screen whose whole
    // job is that nothing is wrong.
    final foreground = _isApprove
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;

    return IconButton(
      icon: Icon(
        _isApprove ? Icons.check_rounded : Icons.close_rounded,
        size: 20,
      ),
      style: IconButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: _isApprove ? CupolaRoom.of(context).fillStrong : null,
      ),
      // Names which request. `tooltip` is also what `IconButton` publishes as
      // the node's label, so this is the spoken name too.
      tooltip: _isApprove
          ? 'Approve request for $title'
          : 'Decline request for $title',
      onPressed: () => _isApprove
          ? ActivityActions.approveRequest(
              context,
              ref,
              instanceId: _lensConnection,
              requestId: request.id,
              title: title,
            )
          : ActivityActions.declineRequest(
              context,
              ref,
              instanceId: _lensConnection,
              requestId: request.id,
              title: title,
            ),
    );
  }

  /// This page is the lens's own Seerr — it reads [requestsProvider], not the
  /// per-connection family — so the write goes to the lens too. An empty id is
  /// how that is spelled, and it matters: a Seerr request id is per instance,
  /// so id 42 sent to the wrong server approves a different person's request
  /// and reports success.
  static const String _lensConnection = '';
}
