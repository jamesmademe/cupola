import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/fault_note.dart';
import 'package:cupola/core/widgets/media_detail_slot.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/presentation/stream_lookup_provider.dart';

/// The "it's watchable, and you're 34 minutes in" slot for an *arr detail page.
///
/// **This is where the pipeline closes.** Radarr answers "do I own it"; a media
/// server is the only thing that knows "is it in the library, and where did *you*
/// stop". Cupola is the only place both facts sit on one screen, and this slot is
/// that sentence.
///
/// **"You", never "anyone", and the difference is load-bearing.** This used to
/// claim the slot knew whether *anyone* had started the title, which neither
/// server will answer: a Plex token is one user and `/library/*` takes no
/// impersonation parameter (decision 16), and Jellyfin's admin key has to name a
/// household member, so its answer is the configured viewer's and nobody else's.
/// Both readings are one perspective. The line the card prints — "34 min in",
/// "Watched" — is therefore about the person the connection speaks for, and the
/// slot must never be widened into a household summary it cannot compute.
///
/// It is a *decoration on the arr's own record*, not a second catalogue and not a
/// search group — see [streamMatchProvider] for why adding Jellyfin and Plex as
/// their own global-search sources would have produced six sections for one film.
///
/// ## What it draws when the title is not found
///
/// Four different nothings, each said as what it is ([StreamAvailability]):
///
///  * **no media server set up** (case a) — nothing: the slot is detail, and a
///    setup prompt on every film page would be a nag;
///  * **the server did not answer**, or answered with a failure (case c) — one
///    quiet line in the failure's tone and words (`Jellyfin did not answer.`),
///    because "we could not ask" is a fact the page owes the reader;
///  * **the server answered, without the title** — `Not on Jellyfin`, in plain
///    ink: the one absence that is a claim, made only after an answer;
///  * **a row that does not verify** (case f) — nothing: no link, no Play, and
///    no claim that the title is missing.
///
/// It used to draw the same nothing for all four, which made a dark server
/// indistinguishable from a library without the title.
///
/// [accent] is the **host** page's, never Jellyfin's or Plex's. The data comes
/// from the media server but the section belongs to the page it renders in —
/// the same rule `ArrMediaExtrasSection` keeps for Seerr data (every accent is
/// the lamp now; the rule keeps the light with one owner).
///
/// [kind] is what the host's record is — [StreamItemKind.movie] on Radarr,
/// [StreamItemKind.series] on Sonarr — and a host that knows it should pass it:
/// TMDB numbers films and shows separately, so without it a Sonarr page could be
/// answered with a *film* that shares the show's TMDB number. [title] and [year]
/// are the host's own, and only settle a server row whose ids cannot be
/// compared; they never start a lookup. See [streamMatchProvider].
List<MediaDetailSlot> streamAvailabilitySlots(
  WidgetRef ref, {
  required Color accent,
  String? tmdbId,
  String? tvdbId,
  String? imdbId,
  StreamItemKind? kind,
  String? title,
  int? year,
}) {
  final availability = ref
      .watch(
        streamAvailabilityProvider((
          tmdbId: tmdbId,
          tvdbId: tvdbId,
          imdbId: imdbId,
          kind: kind,
          title: title,
          year: year,
        )),
      )
      .value;
  // Still asking: nothing yet, as before — a skeleton here would promise a
  // card that may never come.
  if (availability == null) return const <MediaDetailSlot>[];

  switch (availability.state) {
    case StreamAvailabilityState.found:
      return [
        MediaDetailSlot.box(
          label: 'On your server',
          child: _StreamAvailabilityCard(
            match: availability.match!,
            accent: accent,
          ),
        ),
      ];
    case StreamAvailabilityState.failed:
      final service = availability.services.first;
      final reason = availability.failure ?? ServiceFailureReason.unknown;
      final sentence =
          '${describeFailure(service, reason, gateway: availability.gateway).headline}, so Cupola cannot say '
          'whether it has this.';
      return [
        MediaDetailSlot.box(
          label: 'On your server',
          // One quiet line, red only when nothing answered.
          child: failureDidNotAnswer(reason)
              ? FaultNote.unreachable(message: sentence)
              : FaultNote.fault(message: sentence),
        ),
      ];
    case StreamAvailabilityState.notInLibrary:
      return [
        MediaDetailSlot.box(
          label: 'On your server',
          child: _NotInLibraryLine(services: availability.services),
        ),
      ];
    case StreamAvailabilityState.notSetUp:
    case StreamAvailabilityState.notVerified:
      return const <MediaDetailSlot>[];
  }
}

/// `Not on Jellyfin` — said only after Jellyfin answered. Plain secondary
/// ink: an absence from the library is the backlog's kind of fact, not a
/// fault.
class _NotInLibraryLine extends StatelessWidget {
  const _NotInLibraryLine({required this.services});

  final List<ServiceKey> services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = services.map((s) => s.title).join(' or ');
    return Text(
      'Not on $names',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _StreamAvailabilityCard extends StatelessWidget {
  const _StreamAvailabilityCard({required this.match, required this.accent});

  final StreamMatch match;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = match.item;
    final line = _statusLine(item, match.service);

    return AppCard.filled(
      onTap: () => context.push(_itemRoute()),
      pressFeedback: AppCardPressFeedback.scale,
      semanticLabel: 'On ${match.service.title}',
      semanticValue: line,
      semanticHint: 'Open on ${match.service.title}',
      child: Row(
        children: [
          Icon(
            match.service.icon,
            size: 20,
            color: ServiceTheme.onTint(
              accent,
              surface: theme.colorScheme.surfaceContainer,
              tintAlpha: 0,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'On ${match.service.title}',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (item.resumeProgress != null)
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                value: item.resumeProgress,
                strokeWidth: 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            )
          else
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  String _itemRoute() => match.service == ServiceKey.jellyfin
      ? ServiceRoutes.jellyfinItem(match.item.id)
      : ServiceRoutes.plexItem(match.item.id);

  /// The one line the slot exists to say.
  ///
  /// In-progress first, because a resume point is the only state that carries an
  /// action; then watched; then plain availability. Minutes rather than a
  /// percentage for a part-watched item: "34 min in" is where you are, where "28%"
  /// makes the reader do the arithmetic against a runtime they may not know.
  static String _statusLine(StreamItem item, ServiceKey service) {
    final offset = item.resumeOffsetMs;
    if (item.isInProgress && offset != null) {
      final minutes = (offset / 60000).round();
      return minutes < 1 ? 'Just started' : '$minutes min in';
    }
    if (item.isPlayed) return 'Watched';
    final unplayed = item.unplayedChildCount;
    if (unplayed != null && unplayed > 0) {
      return '$unplayed not played yet';
    }
    return 'Ready to watch';
  }
}
