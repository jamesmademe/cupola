/// Ready to watch: the requester's Featured.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/featured_pager.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/requests/data/my_requests_provider.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/requests/presentation/my_request_actions.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// The newest thing she asked for that arrived in the last seven days, with
/// the way to watch it: Seerr's link to it in the player, and Details. The
/// room takes the title's light (`featuredRoomLightProvider`). A second
/// arrival is one line under it; with none, the module is not there and
/// Your requests leads.
///
/// Never a failure of its own: the Home's one line says the server did not
/// answer.
class HomeReadyToWatchModule extends ConsumerWidget {
  const HomeReadyToWatchModule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(myRequestsProvider);
    final mine = read.requests;
    Widget placed(Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.slabY,
        AppSpacing.lg,
        0,
      ),
      child: child,
    );
    if (mine == null) {
      return read.error != null
          ? const SizedBox.shrink()
          : placed(const FeaturedSkeleton());
    }
    final ready = mine.ready;
    if (ready.isEmpty) return const SizedBox.shrink();

    final now = ref.watch(calendarClockProvider)();
    final lead = ready.first;
    final art = lead.art;
    final player = ref.watch(roleGateProvider('')).server?.mediaServer;
    final watchAt = lead.watchAt;
    void details() => openMyRequest(context, lead);
    final eyebrow = switch (lead.arrivedAt) {
      final at? =>
        '${Lexicon.readyToWatch} · since ${sinceWords(at, now: now)}',
      null => Lexicon.readyToWatch,
    };
    final line = lead.askedLine(now);
    final page = FeaturedPage(
      eyebrow: eyebrow,
      eyebrowTone: StatusTone.success,
      title: lead.title,
      line: line,
      art: art,
      label: joinSpokenParts([
        lead.title,
        spokenFromDotted(eyebrow),
        spokenFromDotted(line),
      ]),
      onOpen: details,
      light: ref.watch(featuredLightProvider(art.url)),
      lead: watchAt == null
          ? FeaturedAction('Details', details)
          : FeaturedAction(
              SeerrMediaServer.watchLabel(player),
              () => watchMyRequest(context, watchAt),
              icon: Icons.play_arrow_rounded,
            ),
      second: watchAt == null ? null : FeaturedAction('Details', details),
    );
    final also = ready.length > 1 ? ready[1] : null;
    return placed(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FeaturedPager(
            pages: [page],
            label: HomeModule.readyToWatch.label,
            onArtDrawn: ref.read(featuredViewProvider.notifier).drawn,
            live: watchPageActivity(context, ref).isLive,
            advances: false,
          ),
          if (also != null) ...[
            const SizedBox(height: AppSpacing.md),
            _AlsoReady(
              mine: also,
              now: now,
              onTap: () => openMyRequest(context, also),
            ),
          ],
        ],
      ),
    );
  }
}

/// The second arrival: `Also ready · Tears of Steel`, since when, the way to
/// its page.
class _AlsoReady extends StatelessWidget {
  const _AlsoReady({
    required this.mine,
    required this.now,
    required this.onTap,
  });

  final MyRequest mine;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final since = switch (mine.arrivedAt) {
      final at? => '${Lexicon.onTheServer} since ${sinceWords(at, now: now)}',
      null => Lexicon.onTheServer,
    };
    final heading = 'Also ready · ${mine.title}';
    return Semantics(
      container: true,
      button: true,
      label: joinSpokenParts(['Also ready', mine.title, since]),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: room.slab,
        borderRadius: AppRadius.borderRadiusMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusMd,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.borderRadiusMd,
              border: Border.all(color: room.edge),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 42,
                  child: HomeRowArt(
                    posterUrl: ImageUtils.buildTmdbPosterUrl(
                      mine.request.media?.posterPath,
                      size: 'w185',
                    ),
                    icon: Icons.movie_outlined,
                  ),
                ),
                const SizedBox(width: AppSpacing.row),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.row.copyWith(color: room.ink),
                      ),
                      Text(
                        since,
                        style: AppType.meta.copyWith(color: room.inkSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: room.inkSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
