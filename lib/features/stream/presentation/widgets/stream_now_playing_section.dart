import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_message_prompt.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_card.dart';

/// Who is watching, right now — the one thing only a media server knows.
///
/// **A section rather than a screen, and that is the point of the file.** Every
/// other domain in Cupola answers questions about objects (is this film owned,
/// grabbed, subtitled, on disk); Jellyfin and Plex are the only source of
/// subject-and-time state — who is watching, where they stopped, what is next
/// for them. That belongs at the top of the service's Overview, above whatever
/// readouts the board grows, and it is built here so the Overview composes it
/// instead of rewriting three controls whose rules took a live server to learn.
///
/// **The caller passes the sessions and therefore owns the configuration
/// check.** A media server that is not set up has no sessions to be idle about,
/// and a `FutureProvider` that throws "not configured" is a *failed* provider
/// that retries on a backoff no waiting changes. So the host reads
/// `jellyfinSessionsProvider` / `plexSessionsProvider` only once
/// `isServiceConfigured` says there is something to read.
///
/// **What this deliberately does not have: a total.** An earlier design opened
/// on an aggregate "egress" figure, on the theory that streams are the mirror of
/// the download rate. That figure does not exist. Jellyfin reports a bitrate only
/// while transcoding — a direct play carries none, so the only number available
/// is the source file's own — and Plex's `Session.bandwidth` is a reservation
/// made by its streaming brain. Summing those adds two different units together
/// and presents the result as the box's outbound traffic, which would be
/// fabricated. Per-session figures live on the cards, where
/// `StreamSession.bitrateIsNominal` can say what they actually are.
///
/// **Idle is the majority state and is built first.** Nobody watching is not an
/// empty state and not a failure — it is a quiet room, and on a home server it is
/// the normal condition. It gets one line.
class StreamNowPlayingSection extends ConsumerWidget {
  const StreamNowPlayingSection({
    super.key,
    required this.service,
    required this.sessions,
  });

  final ServiceKey service;
  final AsyncValue<List<StreamSession>> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SectionHeader(title: 'Now playing', showChevron: false),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: AsyncValueWidget<List<StreamSession>>(
            value: sessions,
            serviceName: service.title,
            onRetry: () {
              if (service == ServiceKey.jellyfin) {
                ref.invalidate(jellyfinSessionsProvider);
              } else {
                ref.invalidate(plexSessionsProvider);
              }
            },
            isEmpty: (list) => list.isEmpty,
            emptyBuilder: const _IdleRoom(),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < list.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == list.length - 1 ? 0 : AppSpacing.md,
                    ),
                    child: StaggeredEntrance(
                      index: i,
                      child: StreamSessionCard(
                        session: list[i],
                        accent: service.accent,
                        onStop: _stopHandler(context, ref, list[i]),
                        onTogglePause: _pauseHandler(context, ref, list[i]),
                        onMessage: _messageHandler(context, ref, list[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The stop control, or null when stopping is not available.
  ///
  /// Plex gates termination behind Plex Pass, and answers a server without it
  /// with a 401 that has nothing to do with the token. Reading the flag first
  /// means the control is simply absent rather than present-and-misleading — and
  /// a user who taps it never gets sent off to re-paste a credential that was
  /// fine. A session with no server-side id cannot be terminated at all, which is
  /// a real Plex shape, not a defensive guard.
  ///
  /// **Through [PlexServerCapabilities.canTerminateSessions], not through
  /// `myPlexSubscription` again.** This re-derived the gate as
  /// `myPlexSubscription != true`, which is the opposite of what that getter
  /// decided for two whole populations: a server that does not send the
  /// attribute at all (it is absent on several builds) lost the button, and so
  /// did every session drawn before `plexCapabilitiesProvider` had resolved —
  /// the control appeared a beat later, which on a live list reads as a glitch.
  /// The getter's own comment says it treats silence as available so a missing
  /// attribute hides the button on nobody's server by mistake; a widget is not
  /// the place to disagree with it.
  VoidCallback? _stopHandler(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) {
    if (session.id.isEmpty) return null;

    if (service == ServiceKey.plex) {
      final capabilities = ref.watch(plexCapabilitiesProvider).value;
      // Null while the sheet is still loading, and `canTerminateSessions` is
      // true by default, so an unanswered probe keeps the control rather than
      // flickering one in.
      if (capabilities != null && !capabilities.canTerminateSessions) {
        return null;
      }
    }

    return () => _confirmStop(context, ref, session);
  }

  /// Pause / resume, and only on Jellyfin.
  ///
  /// `/Sessions/{id}/Playing/Pause` is a Jellyfin remote-control command relayed
  /// over the WebSocket the server already holds to that client. Plex has no
  /// equivalent this app can reach: its player routes address the client
  /// directly on the LAN, so the board keeps **stop alone** there rather than
  /// drawing two controls that would fail. Absent, not dimmed — a dimmed control
  /// promises a way to enable it, and there is none.
  VoidCallback? _pauseHandler(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) {
    if (service != ServiceKey.jellyfin || session.id.isEmpty) return null;
    return () => _togglePause(context, ref, session);
  }

  /// Send a line of text to the player. Jellyfin only, same reason as
  /// [_pauseHandler].
  VoidCallback? _messageHandler(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) {
    if (service != ServiceKey.jellyfin || session.id.isEmpty) return null;
    return () => _sendMessage(context, ref, session);
  }

  /// Pausing asks nobody: it is the one control here that is instantly
  /// reversible by the person it happens to, and a confirm on it would be
  /// ceremony. Stopping and messaging both ask, because neither is.
  Future<void> _togglePause(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) async {
    final client = ref.read(jellyfinClientProvider);
    try {
      if (session.isPaused) {
        await client.unpauseSession(session.id);
      } else {
        await client.pauseSession(session.id);
      }
      // Re-read rather than flipping `isPaused` here: the 204 means the command
      // was dispatched to the client, not that the client acted on it.
      ref.invalidate(jellyfinSessionsProvider);
    } catch (error) {
      if (!context.mounted) return;
      final failed = session.isPaused
          ? 'Could not resume playback'
          : 'Could not pause playback';
      SnackBarHelper.error(
        context,
        '$failed. ${writeFailureReason(ServiceKey.jellyfin, error)}',
      );
    }
  }

  Future<void> _sendMessage(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) async {
    final text = await showStreamMessagePrompt(
      context: context,
      userName: session.userName,
      playerLabel: session.deviceLabel,
    );
    if (text == null || !context.mounted) return;

    try {
      await ref
          .read(jellyfinClientProvider)
          .sendMessage(session.id, text: text);
      if (!context.mounted) return;
      // "Sent", never "delivered": the server relays it and the client decides
      // whether it has anywhere to draw it. Claiming delivery would be the same
      // overstatement the stop dialog's note exists to avoid.
      SnackBarHelper.success(context, 'Message sent to ${session.userName}');
    } catch (error) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        'Could not send the message. '
        '${writeFailureReason(ServiceKey.jellyfin, error)}',
      );
    }
  }

  Future<void> _confirmStop(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Stop playback?',
      // Both servers only *dispatch* a stop, and the viewer can simply press
      // play again, so the sentence says that rather than anything about
      // undoing. Overstating it would make an ordinary courtesy feel like a
      // purge.
      message:
          '${streamStopSessionPrompt(userName: session.userName, title: session.title)} '
          'They can start it again straight away.',
      icon: Icons.stop_circle_outlined,
      confirmLabel: 'Stop playback',
    );
    if (!result.confirmed || !context.mounted) return;

    try {
      final client = service == ServiceKey.jellyfin
          ? ref.read(jellyfinServerProvider)
          : ref.read(plexServerProvider);
      await client.stopSession(session.id);
      // Both servers only *dispatch* a stop — Jellyfin's 204 means "sent to the
      // client", which may ignore it. So the board re-reads rather than removing
      // the row optimistically and claiming something it cannot know.
      if (service == ServiceKey.jellyfin) {
        ref.invalidate(jellyfinSessionsProvider);
      } else {
        ref.invalidate(plexSessionsProvider);
      }
    } catch (error) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        'Could not stop playback. ${writeFailureReason(service, error)}',
      );
    }
  }
}

/// Nobody watching.
///
/// Not `AppEmptyState` with a "nothing here" glyph and not an error: the server
/// answered, and an idle media server is the normal daily condition rather than a
/// state the user needs to fix. One quiet line, in the same register the
/// `/services` outage notice uses for a fault that is normal for the product.
///
/// **A dashed rule, and that is the whole shape of it.** A well — a filled box
/// with a centred glyph and a sentence — is how this surface reads when
/// something is missing, and nothing is missing here. The dash says the region
/// exists and is empty by nature, the way an outline on a plan says "this space
/// is reserved" rather than "this space failed".
class _IdleRoom extends StatelessWidget {
  const _IdleRoom();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.nights_stay_outlined, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              streamIdleMessage,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // The dash carries no information, so it is hidden from the screen
          // reader: `streamIdleMessage` already says the room is quiet, and a
          // second node announcing a line would only lengthen the sentence.
          Expanded(
            child: ExcludeSemantics(
              child: CustomPaint(
                // A height rather than a `SizedBox.shrink`: a `CustomPaint`
                // with no child takes its size from the parent, and inside a
                // `Row` that is an unbounded cross axis.
                size: const Size.fromHeight(1),
                painter: _DashedRulePainter(
                  // Dimmer than the text it trails, because it is scenery: at
                  // the text's own weight it reads as a divider between two
                  // regions, and there is only one region here.
                  color: color.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The hairline that trails the idle sentence.
///
/// Local to this file on purpose. There is no dashed primitive in
/// `lib/core/widgets/`, and one line on one screen does not earn a shared
/// widget — the moment a second surface wants dashes, this is what moves.
class _DashedRulePainter extends CustomPainter {
  const _DashedRulePainter({required this.color});

  final Color color;

  /// Dash and gap, in logical pixels. Even-length dashes on an even gap read as
  /// a deliberate rule; anything finer disappears on a low-density display.
  static const double _dash = 4;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += _dash + _gap) {
      final end = (x + _dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRulePainter oldDelegate) =>
      oldDelegate.color != color;
}
