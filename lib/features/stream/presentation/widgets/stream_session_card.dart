import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';

/// One live playback, as three stacked lines.
///
/// **Why this is a card and not a horizontal path row.** The first design drew a
/// session as one line tracing what → how → where → rate, with connectors, on the
/// theory that a connection should be traceable end to end. That layout cannot
/// ship: `TextScaleMetrics.singleLineChromeMaxScaleFactor` is 1.3 precisely
/// because "a strip of pills with connectors between them… cannot reflow", and
/// worse, any `Flexible` distribution ellipsises the longest child first — which
/// here is the transcode *reason*, the one string the surface exists to show. The
/// layout would have eaten its own focal point. `TorrentTile`, the app's other
/// live-transfer row, reached the same conclusion and stacks.
///
/// So the path survives as **vertical reading order** instead:
///
///  1. what is playing,
///  2. how it is being delivered, and why — in the delivery's own tone: green
///     while the file is going out untouched, amber once the box is
///     re-encoding,
///  3. who is watching it, on what, and how far in.
///
/// The rate keeps its own row-end slot rather than a column, so it can update in
/// place (tabular figures) without a shared column grid to keep aligned.
///
/// **The description is one node; the controls are not inside it.** The whole
/// card used to sit under `Semantics(excludeSemantics: true)`, which is right for
/// the four text lines — read top to bottom they are a comma list with no
/// structure — and catastrophic for the buttons it also swallowed: the stop
/// control was on screen, focusable by a pointer, and completely absent from the
/// screen reader's traversal. So the exclusion now wraps the *readout* only, and
/// every action stays its own reachable node with its own name.
class StreamSessionCard extends StatelessWidget {
  const StreamSessionCard({
    super.key,
    required this.session,
    required this.accent,
    this.onStop,
    this.onTogglePause,
    this.onMessage,
  });

  final StreamSession session;
  final Color accent;

  /// Stopping is optional because it is not always permitted: Plex gates
  /// termination behind Plex Pass. A null handler renders no control at all
  /// rather than a button that fails on tap.
  final VoidCallback? onStop;

  /// Pause, or resume when [StreamSession.isPaused].
  ///
  /// **Jellyfin only, and that asymmetry is the API's.** `/Sessions/{id}/Playing/Pause`
  /// and `/Unpause` are Jellyfin remote-control commands; Plex's player endpoints
  /// address the *client* by its own machine identifier over a connection the
  /// server does not proxy, so the board cannot reach them. Plex therefore keeps
  /// stop alone, and the control is absent rather than present-and-failing.
  final VoidCallback? onTogglePause;

  /// Send a line of text to the player. Jellyfin only, for the same reason as
  /// [onTogglePause].
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reason = session.transcodeReasonLabel;
    final rate = formatStreamBitrate(session.bitrate);
    final progressLabel = _progressLabel(session.progress);

    // The tone is the *session's* own, resolved in the domain layer, and walked
    // for contrast against the card's own fill rather than against the page: an
    // `AppCard.filled` paints `surfaceContainer`, and only the caller knows the
    // tone is landing on an elevated surface.
    final costColor = statusToneColor(
      colorScheme,
      session.deliveryTone,
      surface: colorScheme.surfaceContainer,
    );

    return AppCard.filled(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: session.title,
            value: streamSessionValue(
              userName: session.userName,
              title: session.title,
              subtitle: session.subtitle,
              playMethodLabel: session.playMethod.label,
              transcodeReason: reason,
              deviceLabel: session.deviceLabel,
              progressLabel: progressLabel,
              bitrateLabel: rate,
              bitrateIsNominal: session.bitrateIsNominal,
              isPaused: session.isPaused,
            ),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TitleRow(session: session),
                const SizedBox(height: AppSpacing.sm),
                _CostRow(
                  session: session,
                  reason: reason,
                  color: costColor,
                  rate: rate,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${session.userName} · ${session.deviceLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (session.progress != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _ProgressBar(progress: session.progress!, accent: accent),
                ],
              ],
            ),
          ),
          if (onTogglePause != null || onMessage != null || onStop != null)
            _SessionActions(
              isPaused: session.isPaused,
              onTogglePause: onTogglePause,
              onMessage: onMessage,
              onStop: onStop,
            ),
        ],
      ),
    );
  }

  static String? _progressLabel(double? progress) {
    if (progress == null) return null;
    return '${(progress * 100).round()}% in';
  }
}

/// The controls for one live playback.
///
/// A trailing row at the card's foot rather than a glyph tucked beside the
/// title: three of them do not fit a phone's title line beside a two-line title,
/// and pinning them there is what forced the old single stop button down to
/// `VisualDensity.compact` — a 40pt target on a surface whose whole job is to
/// interrupt someone. Each one keeps `IconButton`'s full 48×48 and carries a
/// tooltip, which is also its spoken name.
class _SessionActions extends StatelessWidget {
  const _SessionActions({
    required this.isPaused,
    required this.onTogglePause,
    required this.onMessage,
    required this.onStop,
  });

  final bool isPaused;
  final VoidCallback? onTogglePause;
  final VoidCallback? onMessage;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (onTogglePause != null)
          IconButton(
            onPressed: onTogglePause,
            icon: Icon(
              isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 20,
            ),
            color: color,
            // Named for what the tap does, not for the state it is in: "Pause"
            // on an already-paused session is the one label that cannot be read
            // two ways.
            tooltip: isPaused ? 'Resume this playback' : 'Pause this playback',
          ),
        if (onMessage != null)
          IconButton(
            onPressed: onMessage,
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
            color: color,
            tooltip: 'Send a message to this player',
          ),
        if (onStop != null)
          IconButton(
            onPressed: onStop,
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            color: color,
            tooltip: 'Stop this playback',
          ),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.session});

  final StreamSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = session.subtitle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (session.isPaused)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs, top: 2),
            child: Icon(
              Icons.pause_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall!.weight(FontWeight.w700),
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// How the bytes are being delivered, and what it costs.
///
/// A `Wrap` rather than a `Row`, so the reason can take a second line instead of
/// eliding — see the class doc on [StreamSessionCard]. The rate sits in the same
/// wrap so it follows the reason down rather than pinning a column.
class _CostRow extends StatelessWidget {
  const _CostRow({
    required this.session,
    required this.reason,
    required this.color,
    required this.rate,
  });

  final StreamSession session;
  final String? reason;
  final Color color;
  final String? rate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              session.needsAttention
                  ? Icons.memory_rounded
                  : Icons.bolt_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              session.playMethod.label,
              style: theme.textTheme.labelMedium!
                  .weight(FontWeight.w600)
                  .copyWith(color: color),
            ),
          ],
        ),
        if (reason != null)
          Text(
            reason!,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        if (rate != null)
          Text(
            // "~" carries the same hedge the spoken form says as "about". Neither
            // server reports measured throughput, so an unqualified figure would
            // assert egress the API never gave us.
            session.bitrateIsNominal ? '~$rate' : rate!,
            style: theme.textTheme.labelMedium!.tabular.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 3,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation(accent),
      ),
    );
  }
}

/// Bits per second as a short human figure.
///
/// Decimal megabits, because that is the unit every media server, router and ISP
/// states a stream in — bytes here would be correct and unreadable. Returns null
/// for a null or non-positive input so callers can omit the slot rather than
/// printing "0 Mbps" for a session whose rate the server simply did not report.
String? formatStreamBitrate(int? bitsPerSecond) {
  if (bitsPerSecond == null || bitsPerSecond <= 0) return null;
  final mbps = bitsPerSecond / 1000000;
  if (mbps >= 10) return '${mbps.round()} Mbps';
  if (mbps >= 1) return '${mbps.toStringAsFixed(1)} Mbps';
  return '${(bitsPerSecond / 1000).round()} kbps';
}
