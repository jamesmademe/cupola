import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/tag_chip.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Seerr requests list, reached from `/activity/discover`.
///
/// Rebuilt on the shared vocabulary. This was the most off-system surface in the
/// feature: a bare Material `Card`, a hand-rolled 4K badge at a hardcoded
/// `fontSize: 10`, bare `TextStyle`s with no `textTheme` base, a `label: value`
/// info-row pattern found nowhere else in the app, and a raw
/// `CircularProgressIndicator` plus `'Error: $err'` for its states. Every string
/// here still takes a role off `textTheme` — and re-weights through
/// `CupolaTextStyle.weight`, since `copyWith(fontWeight:)` on a bundled
/// variable face does not reach the `wght` axis and silently keeps the role's
/// weight.
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

  /// Whether the Seerr this list reads is set up: the lens for an empty id,
  /// that connection otherwise.
  bool _configured(WidgetRef ref) => instanceId.isEmpty
      ? ref.watch(
          activeInstanceProvider(
            ServiceKey.seerr,
          ).select((instance) => instance?.isConfigured ?? false),
        )
      : ref.watch(
          currentSettingsProvider.select(
            (s) => s
                .configuredInstancesOf(ServiceKey.seerr)
                .any((instance) => instance.id == instanceId),
          ),
        );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Before the list is asked for. With no Seerr the read can only throw,
    // and its error state offered a Retry that could ask nobody.
    if (!_configured(ref)) {
      return NotConfiguredPlaceholder.forService(ServiceKey.seerr);
    }
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
          children: [
            AppErrorState(
              error: err,
              service: ServiceKey.seerr,
              instanceId: instanceId,
              onRetry: () => _reload(ref),
            ),
          ],
        ),
        data: (requests) {
          if (requests.isEmpty) {
            final namesSeerr = ref
                .watch(roleGateProvider(instanceId))
                .namesService(ServiceKey.seerr);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                AppEmptyState(
                  icon: Icons.person_add_alt_1_rounded,
                  title: 'No requests yet',
                  message: namesSeerr
                      ? 'Requests made in Seerr, by you or anyone you share it '
                            'with, will appear here.'
                      : Lexicon.yourRequestsAppearHere,
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
    // The gate of the Seerr this card came off: the decision is the
    // operator's, and taking a request back is everybody's only for their
    // own that still waits.
    final gate = ref.watch(roleGateProvider(instanceId));
    final decide = gate.operatorAction(SeerrAbility.approve);
    final waiting = request.status == RequestStatus.pendingApproval;
    final own =
        request.requestedBy?.id != null &&
        request.requestedBy?.id == _accountUserId(ref);
    final remove = gate.cancelAction(own: own, waitingForApproval: waiting);
    // A key, or an account that manages requests, deletes any request; any
    // other account only takes back its own, which it calls cancelling.
    final cancels =
        !(gate.grant?.mayCancelRequest(own: false, waitingForApproval: false) ??
            true);
    // The profile is a destination's, and only the one who may choose it
    // reads it.
    final showsProfile = gate
        .operatorAction(SeerrAbility.chooseDestination)
        .isDrawn;

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
                // Neutral, like Decline below: red means unreachable and
                // nothing else, and each confirmation says what happens.
                RoleGatedAction.builder(
                  verdict: remove,
                  onTap: () => _delete(context, ref, cancels: cancels),
                  builder: (context, onPressed, annotate) => IconButton(
                    tooltip: cancels ? Lexicon.cancelRequest : 'Delete request',
                    icon: annotate(
                      Icon(
                        cancels
                            ? Icons.undo_rounded
                            : Icons.delete_outline_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onPressed: onPressed,
                  ),
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
                  _metadataLine(showsProfile: showsProfile),
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
            //
            // The requester's app has no decision to make here; an account
            // of the operator's that may not approve keeps the pair, dimmed.
            if (waiting && decide.isDrawn) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  RoleGatedAction.builder(
                    verdict: decide,
                    onTap: () => _approve(context, ref),
                    builder: (context, onPressed, annotate) =>
                        FilledButton.icon(
                          onPressed: onPressed,
                          // Busy at once, in the glyph's place, while the
                          // approval reads where it goes and is sent.
                          icon: SeerrApprovalGlyph(
                            instanceId: instanceId,
                            requestId: request.id,
                            size: 18,
                            idle: Opacity(
                              opacity: decide.acts
                                  ? 1
                                  : GatedAffordance.dimmedOpacity,
                              child: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 18,
                              ),
                            ),
                          ),
                          label: annotate(const Text('Approve')),
                        ),
                  ),
                  RoleGatedAction.builder(
                    verdict: decide,
                    onTap: () => _decline(context, ref),
                    builder: (context, onPressed, annotate) =>
                        OutlinedButton.icon(
                          onPressed: onPressed,
                          icon: Opacity(
                            opacity: decide.acts
                                ? 1
                                : GatedAffordance.dimmedOpacity,
                            child: const Icon(Icons.cancel_outlined, size: 18),
                          ),
                          label: annotate(const Text('Decline')),
                        ),
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
  String _metadataLine({required bool showsProfile}) {
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
      if (showsProfile)
        request.profileName ??
            request.profileId?.toString() ??
            'Default profile',
      ?createdAt,
    ].join(' · ');
  }

  /// Through the app's one approve path, whose confirmation names the server
  /// the request goes to. This card used to keep a copy of its own that said
  /// only the title.
  Future<void> _approve(BuildContext context, WidgetRef ref) =>
      ActivityActions.approveRequest(
        context,
        ref,
        instanceId: instanceId,
        requestId: request.id,
        title: request.media?.title ?? 'This request',
        request: request,
      );

  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Decline request?',
      message: request.media?.title,
      icon: Icons.cancel_outlined,
      confirmLabel: 'Decline request',
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

  /// The account [instanceId] signs in with, by its Seerr user id; null for
  /// the key.
  int? _accountUserId(WidgetRef ref) {
    final id = instanceId.isEmpty
        ? ref.watch(activeInstanceProvider(ServiceKey.seerr))?.id
        : instanceId;
    if (id == null) return null;
    return ref.watch(
      currentSettingsProvider.select(
        (s) => s.instanceById(id)?.account?.userId,
      ),
    );
  }

  /// Deletes the request, or, for an account that only takes back its own
  /// ([cancels]), cancels it: the same call, which Seerr answers with a 401
  /// once the request no longer waits.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref, {
    required bool cancels,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: cancels ? '${Lexicon.cancelRequest}?' : 'Delete request?',
      message: request.media?.title,
      icon: cancels ? Icons.undo_rounded : Icons.delete_outline_rounded,
      confirmLabel: cancels ? Lexicon.cancelRequest : 'Delete request',
      cancelLabel: cancels ? 'Keep it' : 'Cancel',
    );

    if (!result.confirmed || !context.mounted) return;

    await _run(
      context,
      ref,
      action: () => ref
          .read(seerrServiceForProvider(instanceId))
          .deleteRequest(request.id),
      successMessage: cancels ? 'Request cancelled' : 'Request deleted',
      failureMessage: cancels
          ? "Couldn't cancel the request"
          : 'Could not delete the request',
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
    } catch (error) {
      if (!context.mounted) return;
      // A request of one's own that was approved meanwhile: Seerr's own
      // reason, and the list is stale, so it is read again below.
      if (seerrRefusalOf(error) == SeerrRefusal.noLongerCancellable) {
        SnackBarHelper.info(context, Lexicon.noLongerCancellable);
      } else if (ref.read(roleGateProvider(instanceId)).faultVoice ==
          FaultVoice.brief) {
        // The requester reads what did not happen, and no service.
        SnackBarHelper.error(
          context,
          '$failureMessage. ${Lexicon.nothingChanged}',
          cause: error,
        );
        return;
      } else {
        // Why, in the classified words: "Seerr did not answer" only when
        // nothing did; a refusal says it answered and that nothing changed.
        SnackBarHelper.error(
          context,
          '$failureMessage. ${writeFailureReason(ServiceKey.seerr, error)}',
          cause: error,
        );
        return;
      }
    }
    // The whole family, not this entry alone: the lens's own id collapses onto
    // the plain provider, so dropping one and not the other leaves a stale copy
    // of the same list for the next reader.
    ref.invalidate(requestsProvider);
    ref.invalidate(requestsForProvider);
  }
}
