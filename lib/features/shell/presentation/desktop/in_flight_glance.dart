import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

/// What is in flight, at the foot of the window's sidebar.
///
/// It replaces the inspector that stood open with the queue in it: a column a
/// third of the window wide that, most of the time, said `Nothing downloading
/// right now`. The downloads are still one glance away, in two lines, and the
/// inspector is left for what it is good at: the thing you chose.
///
/// One bar per transfer, as many as the width holds ([maxBars]), the stuck ones
/// amber; how many move and how fast above them, how many are stuck under them. A
/// press opens Activity, where the rest is. Nothing here exists only here: it
/// is the Home's Downloads, folded.
class InFlightGlance extends ConsumerWidget {
  const InFlightGlance({super.key, required this.onOpen});

  /// Opens Activity.
  final VoidCallback onOpen;

  /// The most bars the sidebar's width holds and still reads as bars.
  static const int maxBars = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watchWhileLive(context, sidebarInFlightPollProvider);
    final read = ref.watch(servicesInFlightProvider);
    final glance = switch (read) {
      AsyncData(:final value) => inFlightGlanceOf(value),
      AsyncError() => const InFlightGlanceData.unread(),
      _ => const InFlightGlanceData.reading(),
    };
    return InFlightGlanceTile(glance: glance, onOpen: onOpen);
  }
}

/// What the glance draws, worked out apart from the drawing so it can be
/// tested without a window.
@immutable
class InFlightGlanceData {
  const InFlightGlanceData({
    required this.title,
    this.rate,
    this.bars = const [],
    this.more = 0,
    this.stuck = 0,
    this.note,
  });

  const InFlightGlanceData.reading() : this(title: 'Reading downloads…');

  const InFlightGlanceData.unread()
    : this(title: 'Downloads could not be read');

  /// `4 moving`, `Nothing moving` beside a stuck one, `Nothing in flight`.
  final String title;

  /// The summed rate, as the queue reads it: `40.4 MB/s`.
  final String? rate;

  /// One per transfer drawn: how far it is, and whether it is stuck.
  final List<({double? progress, bool stuck})> bars;

  /// Transfers past [InFlightGlance.maxBars], said as `+3`.
  final int more;

  /// How many are stuck, said under the bars in amber.
  final int stuck;

  /// A quiet line under the title when nothing is moving: `2 queued`.
  final String? note;

  /// The one sentence a screen reader hears.
  String get spoken {
    final parts = [
      title,
      if (rate != null) 'at ${spokenBytesPerSecond(rate!)}',
      if (stuck > 0) '$stuck stuck',
      ?note,
    ];
    return '${parts.join(', ')}. Open Activity';
  }
}

/// The glance of [inFlight]: the moving ones as the queue orders them, then
/// the stuck ones, as the Home's Downloads draws them.
InFlightGlanceData inFlightGlanceOf(ServicesInFlight inFlight) {
  final stuckItems = [
    for (final item in inFlight.faults)
      if (isDownloadFault(item.fault)) item,
  ];
  final moving = inFlight.movingCount;
  final total = moving + stuckItems.length;
  if (total == 0) {
    final queued = inFlight.queued.length;
    return InFlightGlanceData(
      title: 'Nothing in flight',
      note: queued > 0 ? '$queued queued' : null,
    );
  }
  final drawn = [
    for (final item in inFlight.preview)
      (progress: item.progress, stuck: false),
    for (final item in stuckItems) (progress: item.progress, stuck: true),
  ].take(InFlightGlance.maxBars).toList(growable: false);
  final rate = inFlight.rateBytesPerSecond;
  return InFlightGlanceData(
    // The readout's own words (`4 moving · 1 stuck`): a stuck transfer is in
    // flight, but it is not moving, and the title says what moves.
    title: moving > 0 ? '$moving moving' : 'Nothing moving',
    rate: moving > 0 && rate != null ? formatBytesPerSecond(rate) : null,
    bars: drawn,
    more: total - drawn.length,
    stuck: stuckItems.length,
  );
}

/// The glance as drawn, from its data: what [InFlightGlance] puts in the
/// sidebar, and what the catalog renders without a queue behind it.
class InFlightGlanceTile extends StatefulWidget {
  const InFlightGlanceTile({
    super.key,
    required this.glance,
    required this.onOpen,
  });

  final InFlightGlanceData glance;
  final VoidCallback onOpen;

  @override
  State<InFlightGlanceTile> createState() => _GlanceTileState();
}

class _GlanceTileState extends State<InFlightGlanceTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final room = CupolaRoom.of(context);
    final dim = CupolaThemeColors.of(context).dimText;
    final glance = widget.glance;
    final amber = statusToneColor(colorScheme, StatusTone.warning);
    final blue = statusToneColor(colorScheme, StatusTone.info);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

    final under = [
      if (glance.stuck > 0)
        Text(
          '${glance.stuck} stuck',
          style: AppType.meta.copyWith(color: amber).weight(FontWeight.w600),
          textScaler: scaler,
        ),
      if (glance.note case final note?)
        Text(
          note,
          style: AppType.meta.copyWith(color: dim),
          textScaler: scaler,
        ),
    ];

    return Semantics(
      button: true,
      container: true,
      label: glance.spoken,
      onTap: widget.onOpen,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            key: const ValueKey('in-flight-glance'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen,
            child: AnimatedContainer(
              duration: AppAnimation.durationXs,
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.row,
                AppSpacing.sm,
                AppSpacing.row,
                AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: _hovered
                    ? room.fillQuiet
                    : room.fillQuiet.withValues(alpha: room.fillQuiet.a / 2),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          glance.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: scaler,
                          style: AppType.row
                              .copyWith(color: colorScheme.onSurface)
                              .weight(FontWeight.w600),
                        ),
                      ),
                      if (glance.rate case final rate?)
                        Text(
                          rate,
                          textScaler: scaler,
                          style: AppTheme.chrome(
                            context,
                            size: 12,
                            color: dim,
                          ).tabular,
                        ),
                    ],
                  ),
                  if (glance.bars.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        for (final (index, bar) in glance.bars.indexed) ...[
                          if (index > 0) const SizedBox(width: 4),
                          Expanded(
                            child: _Bar(
                              progress: bar.progress,
                              color: bar.stuck ? amber : blue,
                              track: colorScheme.onSurface.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                        ],
                        if (glance.more > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '+${glance.more}',
                            textScaler: scaler,
                            style: AppTheme.chrome(
                              context,
                              size: 11,
                              color: dim,
                            ).tabular,
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (under.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        for (final (index, line) in under.indexed) ...[
                          if (index > 0)
                            Text(
                              dotSeparator.trim(),
                              style: AppType.meta.copyWith(color: dim),
                              textScaler: scaler,
                            ),
                          line,
                        ],
                      ],
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
}

/// One transfer: a 4pt track, filled as far as it is; empty when its client
/// did not say, which is not zero but draws like it.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double? progress;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (progress ?? 0).clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
