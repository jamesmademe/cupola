import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/lifecycle/refresh_on_return.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/requests/data/my_requests_provider.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/requests/presentation/my_request_actions.dart';
import 'package:cupola/features/requests/presentation/widgets/requester_request_row.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/core/widgets/screen_title.dart';

/// The requester's third tab: every request she made, where each stands and
/// when.
///
/// `2 ready to watch · 2 on the way` under the title; then each request that
/// waits for an answer, on a card with its steps and Cancel request, the one
/// thing she may do; then the rest, what moves first: downloading, on its
/// way, ready to watch with Watch, the answers, and what has long been on
/// the server. Read from her own session, which Seerr limits to her own
/// requests.
///
/// When the server does not answer, one line with its time and Retry, and
/// the list stays as it last was, in full ink, without a figure that no
/// longer moves.
class RequestsScreen extends ConsumerWidget {
  const RequestsScreen({super.key});

  /// How old the list may be before coming back to the tab reads it again:
  /// Seerr's download status is at most a minute old.
  static const _staleAfter = Duration(minutes: 1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );
    ref.listen<int>(
      navigationRefreshProvider(NavigationSection.requests),
      (_, _) => invalidateSeerrRequestsOf(ref.container, ''),
    );
    final configured = ref.watch(
      currentSettingsProvider.select(
        (s) => s.isServiceConfigured(ServiceKey.seerr),
      ),
    );

    return RefreshOnReturn(
      id: 'requests',
      maxAge: _staleAfter,
      onStale: () => ref.triggerNavigationRefresh(NavigationSection.requests),
      child: AmbientScaffold(
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                invalidateSeerrRequestsOf(ref.container, '');
                try {
                  await ref.read(requestsProvider.future);
                } catch (_) {}
              },
              // One column in the reading well on a tablet and in a window,
              // as her Home.
              child: LayoutBuilder(
                builder: (context, box) {
                  final inset = AppBreakpoints.wellInset(box.maxWidth);
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      inset,
                      0,
                      inset,
                      bottomPadding,
                    ),
                    children: [
                      if (configured)
                        const _RequestsBody()
                      else ...[
                        const _Header(requests: null),
                        const _NothingAsked(),
                      ],
                    ],
                  );
                },
              ),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: StatusBarScrim(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestsBody extends ConsumerWidget {
  const _RequestsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(myRequestsProvider);
    final mine = read.requests;
    final error = read.error;
    final now = ref.watch(calendarClockProvider)();
    final gate = ref.watch(roleGateProvider(''));

    final failure = error == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: BriefFailureLine.line(
              error: error,
              service: ServiceKey.seerr,
              onRetry: () => invalidateSeerrRequestsOf(ref.container, ''),
            ),
          );

    if (mine == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(requests: null),
          ?failure,
          if (error == null)
            Semantics(
              container: true,
              excludeSemantics: true,
              label: 'Loading your requests',
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: AppSkeleton.listRows(count: 4, rowHeight: 78),
              ),
            ),
        ],
      );
    }

    if (mine.all.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(requests: mine),
          ?failure,
          const _NothingAsked(),
        ],
      );
    }

    final rest = mine.rest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(requests: mine),
        ?failure,
        for (final waiting in mine.waiting)
          Padding(
            key: ValueKey('waiting-${waiting.request.id}'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: RequesterWaitingCard(
              mine: waiting,
              now: now,
              onTap: () => openMyRequest(context, waiting),
              cancel: RoleGatedAction.builder(
                verdict: gate.cancelAction(own: true, waitingForApproval: true),
                onTap: () => cancelMyRequest(context, ref, waiting),
                builder: (context, onPressed, annotate) => OutlinedButton(
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.standard,
                    minimumSize: const Size(0, 44),
                  ),
                  child: annotate(
                    Text(
                      Lexicon.cancelRequest,
                      semanticsLabel:
                          '${Lexicon.cancelRequest} for ${waiting.title}',
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (rest.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: _Slab(
              children: [
                for (final (index, row) in rest.indexed)
                  RequesterRequestRow.page(
                    key: ValueKey(row.request.id),
                    mine: row,
                    now: now,
                    divided: index > 0,
                    onTap: () => openMyRequest(context, row),
                    onWatch: switch (row.watchAt) {
                      final at? => () => watchMyRequest(context, at),
                      null => null,
                    },
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// The page's title, and how many are ready and how many are coming.
class _Header extends StatelessWidget {
  const _Header({required this.requests});

  final MyRequests? requests;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final ready = requests?.ready.length ?? 0;
    final coming = requests?.onTheWay.length ?? 0;
    final counts = [
      if (ready > 0)
        (StatusTone.success, '$ready ${Lexicon.readyToWatch.toLowerCase()}'),
      if (coming > 0)
        (StatusTone.info, coming == 1 ? '1 on its way' : '$coming on the way'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        MediaQuery.paddingOf(context).top + AppSpacing.sm,
        AppSpacing.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenTitle('Requests'),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Align(
              alignment: Alignment.centerLeft,
              child: counts.isEmpty
                  ? const SizedBox.shrink()
                  : Semantics(
                      label: counts.map((count) => count.$2).join(', '),
                      excludeSemantics: true,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xxs,
                        children: [
                          for (final (index, (tone, words))
                              in counts.indexed) ...[
                            if (index > 0)
                              Text(
                                '·',
                                style: AppType.body.copyWith(
                                  color: room.inkTertiary,
                                ),
                              ),
                            _Count(tone: tone, words: words),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.tone, required this.words});

  final StatusTone tone;
  final String words;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final color = statusToneColor(
      Theme.of(context).colorScheme,
      tone,
      surface: room.ground,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            words,
            style: AppType.body.weight(FontWeight.w600).copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// The slab her other requests sit on.
class _Slab extends StatelessWidget {
  const _Slab({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: room.slab,
        borderRadius: BorderRadius.circular(AppRadius.slab),
        border: Border.all(color: room.hair),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Her list while it is empty: the promise of what will be here, and
/// Discover.
class _NothingAsked extends StatelessWidget {
  const _NothingAsked();

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.lg,
        0,
      ),
      child: Column(
        children: [
          Text(
            Lexicon.yourRequestsAppearHere,
            textAlign: TextAlign.center,
            style: AppType.body.copyWith(color: room.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: () => context.go(ServiceRoutes.discover),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.standard,
              minimumSize: const Size(0, 44),
            ),
            icon: const Icon(Icons.explore_outlined, size: 18),
            label: const Text('Discover'),
          ),
        ],
      ),
    );
  }
}
