/// The parts of one download's page: who it is, where it stands and how fast
/// it goes, the steps of the way, and the facts.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart' show spokenBytesPerSecond;
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/machine_name.dart'
    show machineNameWithBreaks;
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';

/// Whether the page reads at a large size: what sits side by side stacks.
bool downloadStacked(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) > 14 * 1.4;

/// The poster, the title and the line under it: `2021 · out on digital
/// today · Anna asked for it`.
class DownloadHero extends StatelessWidget {
  const DownloadHero({
    super.key,
    required this.title,
    required this.meta,
    required this.posterUrl,
    required this.icon,
    this.wide = false,
  });

  final String title;
  final String meta;
  final String? posterUrl;

  /// The glyph of the service it came from, on the plate when there is no
  /// poster.
  final IconData icon;

  /// A pane or a window wider than a phone: a larger poster.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final width = wide ? 120.0 : 88.0;
    final url = posterUrl;
    final poster = SizedBox(
      width: width,
      height: width * 1.5,
      child: url == null || url.isEmpty
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: room.fillQuiet,
                borderRadius: BorderRadius.circular(AppRadius.poster),
                border: Border.all(color: room.hair),
              ),
              child: Icon(icon, size: 28, color: room.inkSecondary),
            )
          : ExcludeSemantics(child: ContentCard(imageUrl: url)),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: AppType.room.copyWith(color: room.ink)),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(meta, style: AppType.meta.copyWith(color: room.inkSecondary)),
        ],
      ],
    );
    if (downloadStacked(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          poster,
          const SizedBox(height: AppSpacing.md),
          words,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        poster,
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: words),
      ],
    );
  }
}

/// Where the download stands, in one slab: the big percentage and its word
/// in their tone, how fast and until when, the speed since the page was
/// opened, the bar, and the steps of the way.
class DownloadReadout extends StatelessWidget {
  const DownloadReadout({
    super.key,
    required this.stand,
    required this.percent,
    required this.progress,
    required this.pace,
    required this.steps,
    this.trace = const [],
    this.watched,
  });

  final DownloadStand stand;

  /// `62%`, or null when the client gave none.
  final String? percent;

  /// 0 to 1, or null.
  final double? progress;

  /// `4.2 MB/s · 11 min left · ready around 21:10`.
  final String? pace;

  final List<DownloadStep> steps;

  /// The speed, sampled since the page was opened.
  final List<RateSample> trace;

  /// How long the speed has been watched.
  final Duration? watched;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(
      scheme,
      downloadStandTone(stand),
      surface: room.slab,
    );
    // The neutral of a stopped download is the room's secondary ink.
    final word = downloadStandWord(stand);
    final figureText = percent == null
        ? null
        : Text(percent!, style: AppType.figureHero.copyWith(color: room.ink));
    final wordText = Text(
      word,
      style: AppType.label.weight(FontWeight.w600).copyWith(color: tone),
    );
    // At a large reading size the word goes under the figure: beside it,
    // `Downloading` broke inside the word.
    final figure = downloadStacked(context)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [?figureText, wordText],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (figureText != null) ...[
                figureText,
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(child: wordText),
            ],
          );
    final paceText = pace == null
        ? null
        : Text(
            pace!,
            style: AppType.meta.tabular.copyWith(color: room.inkSecondary),
          );
    final spoken = [
      if (percent != null) spokenPercents(percent!),
      word,
      if (pace != null) _spokenPace(pace!),
    ].join(', ');
    final traced = trace.length >= 2 && watched != null;

    Widget traceBox({required double width, required double height}) =>
        ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: width,
                height: height,
                child: CustomPaint(
                  painter: _RateTracePainter(
                    trace,
                    line: tone,
                    track: room.hair,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                rateTraceCaption(watched!),
                style: AppType.caption.copyWith(color: room.inkTertiary),
              ),
            ],
          ),
        );

    return ActivitySlab(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final head = Semantics(
              container: true,
              label: spoken,
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    figure,
                    if (paceText != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      paceText,
                    ],
                  ],
                ),
              ),
            );
            // Beside the figure when there is room for both; under it on a
            // phone, the width of the slab.
            if (!traced) return head;
            if (box.maxWidth >= 480 && !downloadStacked(context)) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: head),
                  const SizedBox(width: AppSpacing.lg),
                  traceBox(width: 160, height: 40),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                head,
                const SizedBox(height: AppSpacing.md),
                traceBox(width: box.maxWidth, height: 36),
              ],
            );
          },
        ),
        if (progress case final progress?) ...[
          const SizedBox(height: AppSpacing.md),
          ExcludeSemantics(
            child: _Bar(value: progress, color: tone),
          ),
        ],
        if (steps.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          DownloadSteps(steps: steps),
        ],
      ],
    );
  }

  /// The pace line for the ear: `4.2 megabytes per second, 11 min left`.
  static String _spokenPace(String pace) => pace
      .split(' · ')
      .map((part) => part.endsWith('/s') ? spokenBytesPerSecond(part) : part)
      .join(', ');
}

/// The 6pt bar of a download's page: how far it got, in its tone.
class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: LinearProgressIndicator(
      value: value.clamp(0, 1).toDouble(),
      minHeight: 6,
      color: color,
      backgroundColor: CupolaRoom.of(context).fillTrack,
    ),
  );
}

/// The speed since the page was opened: a line in the download's tone over
/// a fading wash, its last reading a dot. Time runs left to right; the
/// fastest reading sits near the top.
class _RateTracePainter extends CustomPainter {
  _RateTracePainter(this.trace, {required this.line, required this.track});

  final List<RateSample> trace;
  final Color line;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    if (trace.length < 2) return;
    final start = trace.first.at;
    final span = math.max(1, trace.last.at.difference(start).inMilliseconds);
    final top = trace.map((sample) => sample.bytesPerSecond).reduce(math.max);
    final ceiling = math.max(1, top) * 1.15;
    const inset = 3.0;
    final height = size.height - inset * 2;
    Offset at(RateSample sample) => Offset(
      sample.at.difference(start).inMilliseconds / span * (size.width - inset),
      inset + height * (1 - sample.bytesPerSecond / ceiling),
    );
    final points = [for (final sample in trace) at(sample)];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final wash = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas
      ..drawLine(
        Offset(0, size.height - 0.5),
        Offset(size.width, size.height - 0.5),
        Paint()..color = track,
      )
      ..drawPath(
        wash,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [line.withValues(alpha: 0.18), line.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      )
      ..drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(points.last, 3, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_RateTracePainter oldDelegate) =>
      oldDelegate.trace != trace ||
      oldDelegate.line != line ||
      oldDelegate.track != track;
}

/// The steps of the way, side by side when the four fit, two to a line on a
/// phone, one to a line at a large reading size.
class DownloadSteps extends StatelessWidget {
  const DownloadSteps({super.key, required this.steps});

  final List<DownloadStep> steps;

  /// The narrowest a step reads whole beside the others.
  static const double _least = 116;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = AppSpacing.sm;
      final perLine = downloadStacked(context)
          ? 1
          : (box.maxWidth + gap) / (_least + gap) >= steps.length
          ? steps.length
          : 2;
      final width = (box.maxWidth - gap * (perLine - 1)) / perLine;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final step in steps)
            SizedBox(
              width: width,
              child: _StepTile(step: step),
            ),
        ],
      );
    },
  );
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final DownloadStep step;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    Color tone(StatusTone tone) =>
        statusToneColor(scheme, tone, surface: room.slab);
    final glyph = switch (step.state) {
      DownloadStepState.done => Icon(
        Icons.check_circle_rounded,
        size: 16,
        color: tone(StatusTone.success),
      ),
      DownloadStepState.now => SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          value: 0.7,
          color: tone(StatusTone.info),
          backgroundColor: room.fillTrack,
        ),
      ),
      DownloadStepState.stopped => Icon(
        Icons.pause_circle_rounded,
        size: 16,
        color: room.inkSecondary,
      ),
      DownloadStepState.later => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: room.inkTertiary, width: 1.5),
        ),
      ),
      DownloadStepState.fault => Icon(
        Icons.warning_rounded,
        size: 16,
        color: tone(StatusTone.warning),
      ),
    };
    final spokenState = switch (step.state) {
      DownloadStepState.done => 'done',
      DownloadStepState.now => 'now',
      DownloadStepState.stopped => null,
      DownloadStepState.later => 'to come',
      DownloadStepState.fault => null,
    };
    return Semantics(
      container: true,
      label: [step.name, step.detail, ?spokenState].join(', '),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: room.hair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(width: 18, child: Center(child: glyph)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      step.name,
                      style: AppType.label
                          .weight(FontWeight.w600)
                          .copyWith(color: room.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                step.detail,
                style: AppType.meta.copyWith(
                  color: step.state == DownloadStepState.fault
                      ? tone(StatusTone.warning)
                      : room.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Release, Profile, Folder, Client: one slab, a row each, the label on the
/// left and the value on the right, a machine's strings in the mono face.
/// At a large reading size the value goes under its label.
class DownloadFacts extends StatelessWidget {
  const DownloadFacts({super.key, required this.facts});

  final List<DownloadFact> facts;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final stacked = downloadStacked(context);
    return ActivitySlab(
      children: [
        for (final (index, fact) in facts.indexed)
          DecoratedBox(
            decoration: BoxDecoration(
              border: index == 0
                  ? null
                  : Border(top: BorderSide(color: room.hair)),
            ),
            child: Semantics(
              container: true,
              label: [fact.label, fact.value, ?fact.address].join(', '),
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: _fact(fact, room, stacked: stacked),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fact(DownloadFact fact, CupolaRoom room, {required bool stacked}) {
    final label = Text(
      fact.label,
      style: AppType.body.copyWith(color: room.inkSecondary),
    );
    // A machine's string breaks after its dots, never inside a word.
    final body = AppType.body.copyWith(color: room.ink);
    final mono = AppType.mono.copyWith(color: room.ink);
    final value = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: fact.machine ? machineNameWithBreaks(fact.value) : fact.value,
            style: fact.machine ? mono : body,
          ),
          if (fact.address case final address?) ...[
            TextSpan(text: ' · ', style: body),
            TextSpan(text: machineNameWithBreaks(address), style: mono),
          ],
        ],
      ),
      textAlign: stacked ? TextAlign.start : TextAlign.end,
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          const SizedBox(height: AppSpacing.xxs),
          value,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        label,
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: value),
      ],
    );
  }
}
