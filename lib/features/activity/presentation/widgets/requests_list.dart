import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/tag_chip.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';

/// The Seerr requests list, reached from `/activity/discover`.
///
/// Rebuilt on the shared vocabulary. This was the most off-system surface in the
/// feature: a bare Material `Card`, a hand-rolled 4K badge at a hardcoded
/// `fontSize: 10`, bare `TextStyle`s with no `textTheme` base, a `label: value`
/// info-row pattern found nowhere else in the app, and a raw
/// `CircularProgressIndicator` plus `'Error: $err'` for its states. Every string
/// here still takes a role off `textTheme` — and re-weights through
/// `CupolaTextStyle.weight`, since `copyWith(fontWeight:)` on the bundled
/// variable Inter does not reach the `wght` axis and silently renders Regular.
class RequestsList extends ConsumerWidget {
  const RequestsList({super.key, this.instanceId = ''});

  /// Which Seerr this list belongs to, from the route's `?i=`.
  ///
  /// Empty means the lens, which is what every link that predates a service
  /// having two still carries. A named connection is the /activity case: the
  /// feed merges every configured Seerr, so a request row can come off a server
  /// the lens is not on — and both the list and every write on it have to
  /// follow the row rather than the lens, because a Seerr request id is per
  /// instance.
  final String instanceId;

  /// Drops both providers, never the family entry alone.
  ///
  /// For the lens — an empty id, which is every link that predates a second
  /// Seerr — `requestsForProvider` is a passthrough of `requestsProvider`.
  /// Invalidating only the entry rebuilds it, re-reads the value the plain
  /// provider is still holding, and hands back the identical list: a
  /// pull-to-refresh that fetches nothing. `_RequestCard._run` already drops
  /// both for the same reason.
  void _reload(WidgetRef ref) {
    ref.invalidate(requestsProvider);
    ref.invalidate(requestsForProvider(instanceId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(requestsForProvider(instanceId));

    return RefreshIndicator(
      onRefresh: () async => _reload(ref),
      child: requestsAsync.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: AppSpacing.md),
          children: [AppSkeleton.listRows(count: 5)],
        ),
        error: (err, stack) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [AppErrorState(error: err, onRetry: () => _reload(ref))],
        ),
        data: (requests) {
          if (requests.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                AppEmptyState(
                  icon: Icons.person_add_alt_1_rounded,
                  title: 'No requests yet',
                  message:
                      'Requests made in Seerr, by you or anyone you share it '
                      'with, will appear here.',
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: AppSpacing.md),
            itemCount: requests.length,
            itemBuilder: (context, index) =>
                _RequestCard(request: requests[index], instanceId: instanceId),
          );
        },
      ),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final SeerrRequest request;

  /// The connection this card's request lives on — see [RequestsList].
  final String instanceId;

  const _RequestCard({required this.request, required this.instanceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = request.media?.title ?? 'Unknown';
    final year = request.media?.year;
    final heading = year == null || year.isEmpty ? title : '$title ($year)';
    // Delete and Decline are the irreversible-action exception, walked against
    // the card they sit on rather than painted as the raw byte.
    final destructiveInk = statusToneColor(
      colorScheme,
      StatusTone.error,
      surface: colorScheme.surfaceContainer,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: AppCard.outlined(
        backgroundColor: colorScheme.surfaceContainer,
        borderColor: colorScheme.outlineVariant,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              // Centred, not top-aligned: the delete button keeps its full 48pt
              // touch target, so top-aligning left the title stranded at the top
              // of a 48pt row with a visible hole above the status line.
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    heading,
                    style: theme.textTheme.titleSmall?.weight(FontWeight.w600),
                  ),
                ),
                if (request.is4k) ...[
                  const SizedBox(width: AppSpacing.sm),
                  const TagChip(text: '4K'),
                ],
                IconButton(
                  tooltip: 'Delete request',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: destructiveInk,
                  ),
                  onPressed: () => _delete(context, ref),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusBadge(info: resolveRequestStatus(request)),
                Text(
                  _metadataLine(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            // A pending request is the one row in this app that exists purely to
            // be decided, so the decision is named rather than hidden behind an
            // overflow glyph — the same reasoning that gives the queue detail
            // sheet worded buttons. `Wrap` rather than `Row` so the pair reflows
            // instead of overflowing at an accessibility reading size.
            //
            // Gated on the request's **own** status, never on `displayStatus`:
            // media availability overrides that getter, so a request still
            // waiting for approval reports "Available" as soon as the media
            // exists anywhere, and would lose the only action it needs.
            if (request.status == RequestStatus.pendingApproval) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  FilledButton.icon(
                    onPressed: () => _approve(context, ref),
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
                    label: const Text('Approve'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _decline(context, ref),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: destructiveInk,
                      side: BorderSide(
                        color: destructiveInk.withValues(alpha: 0.5),
                      ),
                    ),
                    label: const Text('Decline'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One dot-separated line, the way every other row in the app states its
  /// metadata — rather than a stack of `label: value` pairs.
  String _metadataLine() {
    final seasons = request.seasons
        ?.map((season) => season.seasonNumber)
        .join(', ');
    final createdAt = DateTime.tryParse(
      request.createdAt,
    )?.toLocal().toString().split(' ')[0];

    return [
      request.type == 'tv' ? 'TV' : 'Movie',
      if (request.type == 'tv' && seasons != null && seasons.isNotEmpty)
        'Seasons $seasons',
      request.profileName ?? request.profileId?.toString() ?? 'Default profile',
      ?createdAt,
    ].join(' · ');
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Approve request?',
      message: request.media?.title,
      icon: Icons.check_circle_outline_rounded,
      confirmLabel: 'Approve',
    );

    if (!result.confirmed || !context.mounted) return;

    await _run(
      context,
      ref,
      action: () => ref
          .read(seerrServiceForProvider(instanceId))
          .approveRequest(request.id),
      successMessage: 'Request approved',
      failureMessage: 'Could not approve the request',
    );
  }

  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Decline request?',
      message: request.media?.title,
      icon: Icons.cancel_outlined,
      destructive: true,
      confirmLabel: 'Decline',
    );

    if (!result.confirmed || !context.mounted) return;

    await _run(
      context,
      ref,
      action: () => ref
          .read(seerrServiceForProvider(instanceId))
          .declineRequest(request.id),
      successMessage: 'Request declined',
      failureMessage: 'Could not decline the request',
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Delete request?',
      message: request.media?.title,
      icon: Icons.delete_outline_rounded,
      destructive: true,
      confirmLabel: 'Delete',
    );

    if (!result.confirmed || !context.mounted) return;

    await _run(
      context,
      ref,
      action: () => ref
          .read(seerrServiceForProvider(instanceId))
          .deleteRequest(request.id),
      successMessage: 'Request deleted',
      failureMessage: 'Could not delete the request',
    );
  }

  /// Runs one request mutation and reports what happened.
  ///
  /// A [SeerrRequestConflict] is not our failure — somebody got there first from
  /// the web UI — so it says so and *still* refreshes, because the stale thing is
  /// the list on screen. The catch-all used to swallow that case into "Seerr may
  /// be unreachable", which is the one explanation guaranteed to be wrong.
  ///
  /// (The earlier version of this method was also silent on failure entirely: the
  /// dialog closed, the list refreshed, and the request was still sitting there
  /// with no explanation.)
  Future<void> _run(
    BuildContext context,
    WidgetRef ref, {
    required Future<void> Function() action,
    required String successMessage,
    required String failureMessage,
  }) async {
    try {
      await action();
      if (context.mounted) SnackBarHelper.success(context, successMessage);
    } on SeerrRequestConflict catch (conflict) {
      if (context.mounted) SnackBarHelper.error(context, '$conflict');
    } catch (_) {
      if (context.mounted) {
        SnackBarHelper.error(
          context,
          '$failureMessage. Seerr may be unreachable.',
        );
      }
      return;
    }
    // The whole family, not this entry alone: the lens's own id collapses onto
    // the plain provider, so dropping one and not the other leaves a stale copy
    // of the same list for the next reader.
    ref.invalidate(requestsProvider);
    ref.invalidate(requestsForProvider);
  }
}
