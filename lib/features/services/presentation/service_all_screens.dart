import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_decisions_section.dart';
import 'package:cupola/features/services/domain/seerr_request_filter.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class ServiceAllRequestsScreen extends ConsumerStatefulWidget {
  /// Whether to draw this screen's own app bar.
  ///
  /// False inside Seerr's tab shell, where `ServiceHomeScreen` draws the
  /// service band and `ServiceTabScaffold` the tab bar above it: a third bar of
  /// its own would put two titles and two back chevrons in one corner.
  final bool showAppBar;

  /// Room those two glass bands take above this page, since they float over it
  /// rather than pushing it down.
  final double topPadding;

  const ServiceAllRequestsScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  });

  @override
  ConsumerState<ServiceAllRequestsScreen> createState() =>
      _ServiceAllRequestsScreenState();
}

class _ServiceAllRequestsScreenState
    extends ConsumerState<ServiceAllRequestsScreen> {
  // Screen-local rather than a provider: the chosen bucket is not worth
  // restoring when the user comes back to this screen.
  SeerrRequestFilter _filter = SeerrRequestFilter.all;

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(servicesRequestsProvider);

    return Scaffold(
      appBar: widget.showAppBar
          ? _ServiceListAppBar(
              title: 'All requests',
              backRoute: ServiceRoutes.seerr,
              accent: ServiceKey.seerr.accent,
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(servicesRequestsProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // The host's bands float over this list rather than pushing it down,
          // so the first filter chip has to clear them itself — otherwise it
          // starts its life frosted under the tab bar.
          //
          // The top inset is part of that room and has to be added here. There
          // is no `SafeArea` on this page and, hosted, no app bar for the
          // `Scaffold` to strip the padding for: the band above consumes the
          // inset and is drawn an inset lower than `kToolbarHeight` suggests,
          // so a list clearing the bare chrome height starts under it on every
          // notched phone. Only when hosted — standalone this page draws its
          // own app bar, which owns the inset.
          padding: EdgeInsets.only(
            top:
                widget.topPadding +
                (widget.topPadding > 0 ? MediaQuery.paddingOf(context).top : 0),
            bottom:
                AppSpacing.lg +
                FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            _FilterChipRow(
              selected: _filter,
              onSelected: (filter) => setState(() => _filter = filter),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: AsyncValueWidget<List<SeerrRequest>>(
                value: requests,
                serviceName: 'Seerr requests',
                onRetry: () => ref.invalidate(requestsProvider),
                data: (items) {
                  final visible = _filter.apply(items);
                  if (visible.isEmpty) {
                    return _EmptyListState(label: _filter.emptyLabel);
                  }

                  return Column(
                    children: [
                      for (final request in visible)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _RequestListRow(request: request),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceListAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final String backRoute;
  final Color accent;

  const _ServiceListAppBar({
    required this.title,
    required this.backRoute,
    required this.accent,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.chevron_left_rounded),
        onPressed: () => RouteUtils.popOrGo(context, backRoute),
        tooltip: 'Back',
      ),
      title: Text(title),
      titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _FilterChipRow extends StatelessWidget {
  final SeerrRequestFilter selected;
  final ValueChanged<SeerrRequestFilter> onSelected;

  const _FilterChipRow({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const filters = SeerrRequestFilter.values;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = filter == selected;
          // FilterChip supplies the button role and the selected state to
          // assistive technology, so no explicit Semantics is needed here.
          return FilterChip(
            label: Text(filter.label),
            selected: isSelected,
            showCheckmark: false,
            onSelected: (_) => onSelected(filter),
            // The brand book's chip: selected is the ink fill with the on-ink label, the
            // rest the quiet fill with an edge and the primary ink — the
            // theme's chip, the same on every page.
            labelStyle: Theme.of(context).textTheme.labelMedium
                ?.weight(FontWeight.w600)
                .copyWith(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                ),
            shape: const StadiumBorder(),
          );
        },
      ),
    );
  }
}

class _RequestListRow extends ConsumerWidget {
  final SeerrRequest request;

  const _RequestListRow({required this.request});

  /// The delete button's painted plate.
  static const double _deletePlate = 28;

  /// The widest the status pill may be: the cap a figure beside a row's title
  /// takes on the Overviews.
  static const double _pillMaxWidth = 132;

  /// The delete button's hit box: 44 anywhere a finger can reach the row, the
  /// plate itself on a desktop build, which a pointer drives. The switch is
  /// [AppBreakpoints.isDesktopPlatform], not a width, because a narrow desktop
  /// window is still driven by a pointer.
  static double get _deleteTarget =>
      AppBreakpoints.isDesktopPlatform ? _deletePlate : 44;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final media = request.media;
    final title = media?.title ?? 'Unknown media';
    // The lens's Seerr, which this list reads: who asked only where the
    // connection sees everyone's requests, never to the requester.
    final gate = ref.watch(roleGateProvider(''));
    final requester = gate.showsRequesterNames
        ? request.requestedBy?.displayName ?? 'Unknown'
        : null;
    final mediaType = request.type == 'tv' ? 'Series' : 'Movie';
    // The request's own state, the media's only past approval: the same
    // reading the Pending chip and the counts make.
    final displayStatus = request.lifecycleStatus;
    final heroTag = 'services_all_request_${request.id}';

    return AppCard.outlined(
      onTap: () => _openRequest(context, request, heroTag: heroTag),
      // The body is seven fragments on screen — including a bare '·' that reads
      // as "middle dot" — so it is composed into one label here. The delete
      // button is left out of the exclusion so it keeps a node of its own.
      semanticLabel: title,
      semanticValue: seerrRequestRowValue(
        mediaTypeLabel: mediaType,
        requester: requester,
        statusLabel: displayStatus.label,
        dateLabel: _formatRequestDate(request.createdAt),
      ),
      backgroundColor: colorScheme.surfaceContainer,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rowBody(
            context,
            ref,
            title: title,
            requester: requester,
            gate: gate,
          ),
          // A waiting request is answered where it is listed, with the
          // dashboard's own pair, on a line of its own so the title keeps its
          // width on a phone. "N waiting" links here, and this was the one
          // list of them without the answer. Gated on the request's own
          // status, never on displayStatus.
          if (request.status == RequestStatus.pendingApproval)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SeerrDecisionButton.decline(request: request, title: title),
                SeerrDecisionButton.approve(request: request, title: title),
              ],
            ),
        ],
      ),
    );
  }

  Widget _rowBody(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String? requester,
    required RoleGate gate,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final media = request.media;
    final mediaType = request.type == 'tv' ? 'Series' : 'Movie';
    // The request's own state, the media's only past approval: the same
    // reading the Pending chip and the counts make.
    final displayStatus = request.lifecycleStatus;
    final statusTone = resolveRequestStatus(request).tone;
    final posterUrl = ImageUtils.buildTmdbPosterUrl(media?.posterPath);
    final heroTag = 'services_all_request_${request.id}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            width: 38,
            height: 54,
            child: posterUrl.isEmpty
                ? Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusXs2,
                      ),
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
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.weight(FontWeight.w600),
                ),
                const SizedBox(height: 4),
                // One line, cut short at the end rather than pushed past the
                // card: at 375pt beside a wide pill the requester, the dot and
                // the kind overflowed the row by 68px. The row's sentence is
                // its own label and value, so nothing spoken is cut.
                Row(
                  children: [
                    if (requester != null) ...[
                      _RequesterAvatar(name: requester),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(
                        requester == null
                            ? mediaType
                            : '$requester · $mediaType',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _formatRequestDate(request.createdAt),
                  style: Theme.of(context).textTheme.labelSmall?.tabular
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ExcludeSemantics(
              // Capped, so a long word at a large reading size wraps inside
              // the pill instead of starving the title of its width.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _pillMaxWidth),
                child: _SmallPill(
                  label: displayStatus.label,
                  tone: statusTone,
                  // The row's own card, which is what the pill's wash sits on.
                  surface: colorScheme.surfaceContainer,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _deleteButton(context, ref, title, gate: gate),
          ],
        ),
      ],
    );
  }

  /// Delete for the key and for an account that manages requests; for any
  /// other account, Cancel on its own request while it still waits, and
  /// nothing on the rest (the requester), or dimmed with the reason (an
  /// operator's account).
  Widget _deleteButton(
    BuildContext context,
    WidgetRef ref,
    String title, {
    required RoleGate gate,
  }) {
    final own =
        request.requestedBy?.id != null &&
        request.requestedBy?.id == ref.watch(seerrAccountUserIdProvider(''));
    final verdict = gate.cancelAction(
      own: own,
      waitingForApproval: request.status == RequestStatus.pendingApproval,
    );
    final cancels =
        !(gate.grant?.mayCancelRequest(own: false, waitingForApproval: false) ??
            true);
    if (!verdict.isDrawn) {
      return SizedBox.square(dimension: _deleteTarget);
    }
    final colorScheme = Theme.of(context).colorScheme;
    // The plate stays the 28pt square the row was drawn with; what grows is
    // the square around it. `Center` loosens the constraints so
    // `MaterialTapTargetSize.padded` can spread the hit box out to fill it —
    // a tight 28 square capped it at 28.
    return SizedBox.square(
      dimension: _deleteTarget,
      child: Center(
        child: RoleGatedAction.builder(
          verdict: verdict,
          onTap: () => _deleteRequest(context, ref, title, cancels: cancels),
          builder: (context, onPressed, annotate) => IconButton.filledTonal(
            icon: annotate(
              Icon(
                cancels ? Icons.undo_rounded : Icons.delete_outline_rounded,
                size: 14,
              ),
            ),
            // Neutral: the instrument-face plate chips sit on, and
            // the secondary ink. Red means unreachable and nothing
            // else; the confirmation says what the tap deletes.
            color: colorScheme.onSurfaceVariant,
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHighest,
              padding: EdgeInsets.zero,
              // `minimumSize` as well as `fixedSize`: `fixedSize` is
              // clamped into the resolved minimum, and IconButton's M3
              // default minimum is 48.
              minimumSize: const Size.square(_deletePlate),
              fixedSize: const Size.square(_deletePlate),
              visualDensity: VisualDensity.standard,
              tapTargetSize: AppBreakpoints.isDesktopPlatform
                  ? MaterialTapTargetSize.shrinkWrap
                  : MaterialTapTargetSize.padded,
            ),
            onPressed: onPressed,
            // Names which request: there is one of these per row.
            tooltip: cancels
                ? '${Lexicon.cancelRequest} for $title'
                : 'Delete request for $title',
          ),
        ),
      ),
    );
  }

  Future<void> _deleteRequest(
    BuildContext context,
    WidgetRef ref,
    String title, {
    required bool cancels,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: cancels ? '${Lexicon.cancelRequest}?' : 'Delete request?',
      message: cancels
          ? title
          : 'This removes the request for $title from Seerr.',
      confirmLabel: cancels ? Lexicon.cancelRequest : 'Delete request',
      cancelLabel: cancels ? 'Keep it' : 'Cancel',
    );
    if (!result.confirmed || !context.mounted) return;

    try {
      await ref.read(seerrServiceProvider).deleteRequest(request.id);
      ref.invalidate(servicesRequestsProvider);
      if (!context.mounted) return;
      // The row simply vanishes otherwise, which reads as a glitch rather than a
      // result. SnackBar carries liveRegion, so this is also the announcement.
      SnackBarHelper.success(
        context,
        cancels
            ? 'Cancelled the request for $title'
            : 'Deleted the request for $title',
      );
    } catch (error) {
      if (!context.mounted) return;
      if (seerrRefusalOf(error) == SeerrRefusal.noLongerCancellable) {
        // Approved meanwhile: the list is stale.
        ref.invalidate(servicesRequestsProvider);
        SnackBarHelper.info(context, Lexicon.noLongerCancellable);
        return;
      }
      SnackBarHelper.error(
        context,
        cancels
            ? "Could not cancel the request. ${Lexicon.nothingChanged}"
            : "Could not delete the request.",
        detail: ref.read(roleGateProvider('')).faultVoice == FaultVoice.brief
            ? null
            : error,
      );
    }
  }

  void _openRequest(
    BuildContext context,
    SeerrRequest request, {
    required String heroTag,
  }) {
    final media = request.media;
    final id = media?.tmdbId ?? media?.id;
    if (id == null || id <= 0) return;
    final mediaType = request.type == 'tv' ? 'tv' : 'movie';
    final posterUrl = ImageUtils.buildTmdbPosterUrl(media?.posterPath);
    context.push(
      ServiceRoutes.seerrDetail(
        mediaType: mediaType,
        id: id,
        heroTag: heroTag,
        posterUrl: posterUrl,
      ),
    );
  }
}

class _RequesterAvatar extends StatelessWidget {
  final String name;

  const _RequesterAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: ServiceKey.seerr.accent.withValues(alpha: 0.14),
        border: Border.all(
          color: ServiceKey.seerr.accent.withValues(alpha: 0.27),
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: Theme.of(context).textTheme.labelSmall
            ?.weight(FontWeight.w600)
            .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  final String label;
  final StatusTone tone;

  /// The ground under the pill's wash, which the label is walked against.
  final Color surface;

  const _SmallPill({
    required this.label,
    required this.tone,
    required this.surface,
  });

  static const double _tintAlpha = 0.14;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The wash keeps the tone's raw byte; the label is walked against that
    // wash over the card, so it clears 4.5:1 in both themes. The label used to
    // be the raw tone too, which put it under the floor on its own tint.
    final color = statusToneColor(
      colorScheme,
      tone,
      surface: surface,
      tintAlpha: _tintAlpha,
    );
    return Container(
      decoration: BoxDecoration(
        color: statusToneFill(colorScheme, tone).withValues(alpha: _tintAlpha),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        // Sentence case: this pill repeats once per request row, so it is a
        // dense label, not a kicker. The eyebrow is the one uppercase voice and
        // earns it by being the single kicker over a region; a pill that
        // shouted on every row was a second uppercase voice beside it.
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.weight(FontWeight.w600).copyWith(color: color),
      ),
    );
  }
}

class _EmptyListState extends StatelessWidget {
  final String label;

  const _EmptyListState({required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

String _formatRequestDate(String value) {
  if (value.trim().isEmpty) return 'Unknown date';
  return formatIsoDate(value);
}
