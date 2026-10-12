import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/sample_age.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/beside_or_below.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// One row of a download client's queue: name, percentage, progress bar and a
/// counting-down secondary line.
///
/// **One plate, four clients.** The SABnzbd and NZBGet dashboards each carried a
/// line-for-line copy of this, differing only in field names and accent colour:
/// and the copies had already started to drift (one of them showed an ETA the
/// other did not). qBittorrent then wrote a *third*, `TorrentTile`, which is the
/// precise thing this widget exists to prevent: it had its own radius, its own
/// padding, its own 34pt leading tile, its own state chip painted from raw
/// palette constants, and no semantics container at all. All of them render
/// through this now, so a fix to the row's density, radius or screen-reader
/// behaviour lands on every client at once.
///
/// Per the design's own list, only three things may differ between clients: the
/// **label chip** ([statusLabel]), the **metrics** ([metrics]) and the **menu
/// items** ([actions]). Everything else (geometry, type, tone resolution,
/// selection, semantics) belongs to the plate. That is why the chip takes a
/// tone rather than a colour and the metrics take a flag rather than a colour:
/// a caller that could pass a `Color` is a caller that can reintroduce the
/// palette literal the migration removed.
///
/// Deliberately given no knowledge of any client: it takes the rendered values
/// and an [accent]. That is what keeps one tile serving four APIs whose queue
/// records share no field names at all.
class DownloadQueueTile extends StatelessWidget {
  const DownloadQueueTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.percentage,
    required this.accent,
    this.actions,
    this.statusLabel,
    this.statusTone = StatusTone.neutral,
    this.metrics = const [],
    this.selected = false,
    this.sampleAge,
    this.onTap,
    this.onLongPress,
  });

  final String title;

  /// The counting-down line: status, category/ETA and remaining size.
  final String subtitle;

  /// 0..1, for the bar, or **null** for a job with no meaningful bar to draw.
  ///
  /// Nullable because "no progress" and "zero progress" are different facts and
  /// the row must not draw the second when it means the first: a queued, errored
  /// or checking torrent has not started, and a 0% bar under it reads as a
  /// transfer that is stuck rather than one that has not begun.
  final double? progress;

  /// The same value as a whole number, for the label. Taken separately because
  /// SABnzbd reports it directly while NZBGet derives it from sizes, and
  /// re-deriving one from the other would round twice. Null means the server
  /// did not report enough information to compute a percentage.
  final int? percentage;

  final Color accent;

  /// The row's overflow menu, when the client supports per-job commands.
  final Widget? actions;

  /// The state chip's text: "Downloading", "Seeding", "Paused".
  ///
  /// Text plus a [statusTone], never a built widget: the chip's geometry and its
  /// contrast walk belong to the plate, and the three copies this replaced each
  /// painted their own from raw `AppColors` constants, which is how a "Seeding"
  /// chip ended up at 2.07:1 on the light theme.
  final String? statusLabel;

  /// Which of the five tones [statusLabel] carries. Resolved through
  /// `statusToneColor`, so the amber-is-a-fault / red-is-unreachable rule is
  /// applied here rather than re-argued per client.
  final StatusTone statusTone;

  /// The bottom figure row: transfer rates, ratios, whatever the client
  /// measures. Empty on the Usenet pair, which says everything it has in
  /// [subtitle].
  final List<DownloadQueueMetric> metrics;

  /// How old this row's figures are, when the poll has stopped coming back.
  ///
  /// `null` is the normal case: the figures are current and the row prints its
  /// counting-down line as usual.
  ///
  /// When it is set, the row **trades its time-left for the age of the sample**,
  /// and that trade is the whole point. A progress bar that is not advancing
  /// must not look like one that is: left alone, a stalled poll leaves a row
  /// claiming "12 min left, 1.2 GB remaining" in the service accent, counting
  /// down nothing, and the user reads a healthy transfer where there is a dead
  /// connection. So the ETA (the one figure that is definitely false) is
  /// replaced by the one fact that is definitely true, and the bar drains to a
  /// neutral so it stops reading as live.
  ///
  /// The bar itself stays, at its last position. It is still what the service
  /// last said, and dropping it would throw away the readout the operator came
  /// for. See `FaultBand.stale`, which carries the same condition for the page.
  ///
  /// The four client queue pages pass it while they show their last read under
  /// a fault band, measured from when that read came back (`ReadClock`).
  final Duration? sampleAge;

  /// Whether this row is part of a multi-select.
  ///
  /// 8% accent fill and a 40% accent border, which is what the artboards draw
  /// and what qBittorrent's private copy already did, brought up to the plate
  /// so the next client to grow bulk actions inherits it.
  final bool selected;

  final VoidCallback? onTap;

  /// Long-press starts selection (decision 28). It is deliberately *not* the row
  /// menu: the menu is the trailing control in [actions], at its own 44pt
  /// target, because a menu reachable only by long-press is a menu a pointer
  /// user and a switch user cannot reach at all.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.bodyMedium!.weight(FontWeight.w600);
    final titleEm = MediaQuery.textScalerOf(
      context,
    ).scale(titleStyle.fontSize ?? 14);
    final colorScheme = theme.colorScheme;
    // The ground everything on this row is measured against. The plate paints
    // `surface` when idle and an 8% accent tint when selected; the tint is thin
    // enough that walking against the base surface is right for both, and
    // re-walking every tone on selection would make the row change colour when
    // it changes state.
    final ink = ServiceTheme.onTint(
      accent,
      surface: colorScheme.surface,
      tintAlpha: 0,
    );
    final interactive = onTap != null || onLongPress != null;

    return Semantics(
      container: true,
      // The row read as four unrelated fragments: a filename, "63%", a
      // counting-down line, and a menu button with no subject, because nothing
      // here declared a container. One label, in the order a person would say
      // it, and the percentage spoken as a percentage rather than as a bare
      // numeral glued to the name.
      label: _spokenLabel,
      // Announced as a state rather than baked into the label, so a screen
      // reader says "selected" in its own voice and stops saying it when the
      // selection clears.
      selected: interactive ? selected : null,
      button: interactive,
      // The row's own gestures live on the *container* node, not on the InkWell
      // under it (which is excluded below). One row is one thing a screen reader
      // can act on: leaving the actions on the ink would have published a second,
      // unlabelled node inside the labelled one, and a two-finger swipe would
      // have had to find the inner one to open a torrent.
      onTap: onTap,
      onLongPress: onLongPress,
      // `explicitChildNodes`, not `ExcludeSemantics`: the actions menu is the
      // only control on the row and it has to stay on the screen reader's path.
      explicitChildNodes: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        child: Material(
          color: selected
              ? accent.withValues(alpha: 0.08)
              : colorScheme.surface,
          // `shape` carries the radius *and* the border together. Passing
          // `borderRadius` beside a `shape` trips a Material assertion and
          // blanks the whole list: the P0 qBittorrent's private copy shipped
          // once and then carried a comment about forever.
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusMd,
            side: BorderSide(
              color: selected
                  ? accent.withValues(alpha: 0.4)
                  : colorScheme.outlineVariant,
            ),
          ),
          // The ink is added only when there is something to press. An InkWell
          // around a row with no gestures is a control that highlights and does
          // nothing, and because the container above sets
          // `explicitChildNodes`, it also publishes an empty, unlabelled
          // semantics node inside the labelled one, which is a stop on the
          // screen reader's path that says nothing when it gets there.
          child: _MaybeInk(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ExcludeSemantics(
                          // The title keeps ten of its own em beside the chip
                          // and the figure, or they go under it at the
                          // trailing edge: a long state label, or any label
                          // at a large text size, used to leave the name six
                          // letters and the chip "Downloa…".
                          child: BesideOrBelow(
                            gap: AppSpacing.sm,
                            minLead: 10 * titleEm,
                            lead: Text(
                              title,
                              style: titleStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (statusLabel != null) ...[
                                  // Flexible: under the title, a label longer
                                  // than the whole line ellipsises rather than
                                  // pushing the figure out.
                                  Flexible(
                                    child: _StatusChip(
                                      label: statusLabel!,
                                      tone: statusTone,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                ],
                                Text(
                                  percentage == null
                                      ? '—'
                                      : formatPercent(percentage!),
                                  style: theme.textTheme.labelMedium!
                                      .weight(FontWeight.w600)
                                      .tabular
                                      // One plate, four clients: the percentage
                                      // is the primary ink: the client's
                                      // accent is the lamp, which `onTint`
                                      // resolves to the room's ink.
                                      .copyWith(color: ink),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      ?actions,
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    ExcludeSemantics(
                      child: ClipRRect(
                        borderRadius: AppRadius.borderRadiusXs,
                        child: LinearProgressIndicator(
                          value: progress!.clamp(0, 1),
                          minHeight: 4,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          // A transfer in flight is the blue tone: in progress,
                          // The brand book's bar: never the client's colour. A stale bar
                          // keeps its position and loses the tone: the blue is
                          // what makes a bar read as moving.
                          valueColor: AlwaysStoppedAnimation(
                            sampleAge == null
                                ? statusToneColor(
                                    colorScheme,
                                    StatusTone.info,
                                    surface:
                                        colorScheme.surfaceContainerHighest,
                                  )
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  ExcludeSemantics(
                    child: Text(
                      _subtitleLine,
                      // Carries the ETA and the remaining size, both counting
                      // down, so the figures are tabular and do not jitter as
                      // they tick.
                      style: theme.textTheme.bodySmall!.tabular.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (metrics.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    ExcludeSemantics(
                      child: Row(
                        children: [
                          for (var i = 0; i < metrics.length; i++) ...[
                            if (i > 0) const SizedBox(width: AppSpacing.md),
                            Flexible(
                              child: _Metric(
                                metric: metrics[i],
                                color: metrics[i].accented
                                    ? ink
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What the second line actually prints: the counting-down figures, or the
  /// age that replaces them once they have stopped counting.
  String get _subtitleLine {
    final age = sampleAge;
    return age == null ? subtitle : 'as of ${formatDurationAge(age)}';
  }

  /// The row as one sentence, in the order a person would say it.
  ///
  /// The state comes before the percentage because "paused, 63 percent" and
  /// "63 percent, paused" answer different questions, and the first word is the
  /// one a screen-reader user hears before they decide to keep listening. The
  /// metrics are appended because they are the only figures not already in the
  /// subtitle, and dropping them would make the spoken row poorer than the drawn
  /// one: the failure mode the whole plate exists to stop repeating per client.
  String get _spokenLabel => [
    title,
    ?statusLabel,
    percentage == null ? 'progress unavailable' : spokenPercent(percentage!),
    _subtitleLine,
    for (final metric in metrics) metric.spoken ?? metric.label,
  ].join(', ');
}

/// [InkWell] when the row is pressable, and nothing at all when it is not.
///
/// The splash only; both gestures are declared once on the plate's own semantics
/// container, so this is excluded from the tree it would otherwise duplicate.
class _MaybeInk extends StatelessWidget {
  const _MaybeInk({
    required this.onTap,
    required this.onLongPress,
    required this.child,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (onTap == null && onLongPress == null) return child;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: AppRadius.borderRadiusMd,
      excludeFromSemantics: true,
      child: child,
    );
  }
}

/// One figure on the row's bottom line: a dot and a value.
///
/// A flag rather than a colour, deliberately. The two things a metric can be are
/// "this client's own accent" and "everything else", and both resolve inside the
/// plate against the composited surface; so there is no way for a caller to
/// hand in a palette literal, which is exactly how the three private copies got
/// their contrast wrong.
@immutable
class DownloadQueueMetric {
  const DownloadQueueMetric({
    required this.label,
    this.accented = false,
    this.spoken,
  });

  /// The drawn value, e.g. `↓ 4.2 MB/s`.
  final String label;

  /// Whether the dot and the value take the client's accent.
  final bool accented;

  /// What a screen reader says instead, when [label] leans on a glyph.
  ///
  /// `↓ 4.2 MB/s` is read as "4.2 MB/s" by some engines and as the name of the
  /// arrow character by others; neither is "downloading at 4.2 megabytes per
  /// second". A row whose meaning is carried by an arrow has to spell it.
  final String? spoken;

  @override
  bool operator ==(Object other) =>
      other is DownloadQueueMetric &&
      other.label == label &&
      other.accented == accented &&
      other.spoken == spoken;

  @override
  int get hashCode => Object.hash(label, accented, spoken);
}

class _Metric extends StatelessWidget {
  const _Metric({required this.metric, required this.color});

  final DownloadQueueMetric metric;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.tabular.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// The state chip: one geometry, one contrast walk, five tones.
///
/// Both halves go through `statusToneColor`, which is what the private copies
/// did not do: they tinted with a raw `AppColors` constant and inked with the
/// same one, so on paper the fill and the label were two shades of the same
/// invisible.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = statusToneColor(colorScheme, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusXs,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall!
            .weight(FontWeight.w600)
            // Walked against the chip's own composited tint, not against the
            // surface: the label sits on 12% of its own tone, which is part of
            // the contrast calculation.
            .copyWith(
              color: ServiceTheme.onTint(
                color,
                surface: colorScheme.surface,
                tintAlpha: 0.12,
              ),
            ),
      ),
    );
  }
}

/// The three commands a Usenet download client offers on a single job.
enum DownloadQueueCommand { pause, resume, delete }

/// The per-job overflow menu shared by the Usenet dashboards.
///
/// [paused] chooses which half of the toggle is offered, exactly as the two
/// private copies did; the difference being that there is now one of them.
class DownloadQueueActionsMenu extends StatelessWidget {
  const DownloadQueueActionsMenu({
    super.key,
    required this.paused,
    required this.onCommand,
    required this.subject,
  });

  final bool paused;
  final ValueChanged<DownloadQueueCommand> onCommand;

  /// The job's name, for the button's tooltip and spoken label: every row's
  /// ⋯ saying "Job actions" left a screen reader with a list of identical
  /// buttons.
  final String subject;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<DownloadQueueCommand>(
      icon: const Icon(Icons.more_vert_rounded, size: 18),
      tooltip: 'Actions for $subject',
      onSelected: onCommand,
      itemBuilder: (context) => [
        if (paused)
          const PopupMenuItem(
            value: DownloadQueueCommand.resume,
            child: Text('Resume'),
          )
        else
          const PopupMenuItem(
            value: DownloadQueueCommand.pause,
            child: Text('Pause'),
          ),
        const PopupMenuItem(
          value: DownloadQueueCommand.delete,
          child: Text('Delete job'),
        ),
      ],
    );
  }
}
