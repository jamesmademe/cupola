import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One module of the Home, in the slab every module shares.
///
/// Every module is in one of five states, and four of them are drawn here, so
/// no module invents its own way of loading, failing or asking for a service:
///
///  * **loading** ([HomeModuleFrame.loading]): the module's name over the
///    shape of its rows, never a spinner in the middle of the Home;
///  * **ready** (the default constructor): the name, the line under it, the
///    way on, and the rows;
///  * **nothing to say**: no frame at all. The module returns nothing and the
///    next one moves up: a Home has no empty boxes;
///  * **its sources did not answer** ([HomeModuleFrame.silent]): the module
///    keeps its place and says which service and why, in the classified
///    words, with Retry, under its last known rows when it has them;
///  * **its service is not set up** ([HomeModuleFrame.needsService]): a dashed
///    outline that names the service and stays a target. Only a module the person
///    switched on in Edit Home gets it; a module that is on by default and
///    lacks its service is not drawn, and Set up next names the service once.
class HomeModuleFrame extends StatelessWidget {
  /// A module with something to say.
  const HomeModuleFrame({
    super.key,
    required this.title,
    required Widget this.child,
    this.subtitle,
    this.action,
    this.semanticLabel,
  }) : _state = _FrameState.ready,
       coverage = null,
       onRetry = null,
       service = null,
       onSetUp = null,
       setUpLine = null,
       headline = null;

  /// A module whose sources have not answered yet: its name and the shape of
  /// its rows. [skeleton] is the shape when the module's rows are not two list
  /// rows.
  const HomeModuleFrame.loading({
    super.key,
    required this.title,
    Widget? skeleton,
  }) : child = skeleton,
       _state = _FrameState.loading,
       subtitle = null,
       action = null,
       semanticLabel = null,
       coverage = null,
       onRetry = null,
       service = null,
       onSetUp = null,
       setUpLine = null,
       headline = null;

  /// A module whose every source failed: the fault in the words of its cause,
  /// and Retry. [child] is what was last known (the Home's last drawing at a
  /// cold start, `HomeLastKnownWatch`), drawn above the fault at full ink:
  /// nothing is dimmed for being unreachable, the line under it says what it
  /// is (the brand book's fourth rule).
  const HomeModuleFrame.silent({
    super.key,
    required this.title,
    required SourceCoverage this.coverage,
    required VoidCallback this.onRetry,
    this.child,
  }) : _state = _FrameState.silent,
       subtitle = null,
       action = null,
       semanticLabel = null,
       service = null,
       onSetUp = null,
       setUpLine = null,
       headline = null;

  /// A module the person switched on whose service is not set up: [headline]
  /// (`Set up TrueNAS to see your storage`), what it would show, and the way
  /// there.
  const HomeModuleFrame.needsService({
    super.key,
    required this.title,
    required ServiceKey this.service,
    required String this.headline,
    required String this.setUpLine,
    required VoidCallback this.onSetUp,
  }) : _state = _FrameState.needsService,
       child = null,
       subtitle = null,
       action = null,
       semanticLabel = null,
       coverage = null,
       onRetry = null;

  final _FrameState _state;

  /// The module's name, its heading.
  final String title;

  /// The line under the name: `4 moving · 40.4 MB/s`, `2 wait for you`.
  final String? subtitle;

  /// The way on, at the end of the heading: `Calendar`, `See all`.
  final HomeModuleAction? action;

  /// The rows; for [HomeModuleFrame.silent], what was last known.
  final Widget? child;

  /// What the heading says to a screen reader, when the name and the line
  /// under it are not the whole sentence.
  final String? semanticLabel;

  final SourceCoverage? coverage;
  final VoidCallback? onRetry;
  final ServiceKey? service;
  final String? headline;
  final String? setUpLine;
  final VoidCallback? onSetUp;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final Widget body = switch (_state) {
      _FrameState.ready => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_heading(context), child!],
      ),
      _FrameState.loading => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(context),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            container: true,
            excludeSemantics: true,
            label: 'Loading ${title.toLowerCase()}',
            child: child ?? AppSkeleton.listRows(count: 2, rowHeight: 56),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
      _FrameState.silent => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(context),
          ?child,
          const SizedBox(height: AppSpacing.xs),
          _fault(),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
      _FrameState.needsService => const SizedBox.shrink(),
    };

    if (_state == _FrameState.needsService) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          0,
        ),
        child: _setUp(context, room),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: room.slab,
            borderRadius: BorderRadius.circular(AppRadius.slab),
            border: Border.all(color: room.hair),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.slabY,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context) {
    final room = CupolaRoom.of(context);
    final action = this.action;
    return Semantics(
      header: true,
      label: semanticLabel ?? joinSpokenParts([title, ?subtitle]),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppType.section.copyWith(color: room.ink),
                  ),
                ),
                if (action != null) _ActionLink(action: action),
              ],
            ),
            if (subtitle case final line?)
              Text(
                line,
                style: AppType.meta.copyWith(color: room.inkSecondary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fault() {
    final coverage = this.coverage!;
    final message = coverageFailureSentence(coverage);
    // Red only when a source did not answer; amber when every one of them
    // answered with a fault. The words and the remedy are the band's.
    return coverage.anyDidNotAnswer
        ? FaultBand.section(message: message, onRetry: onRetry!)
        : FaultBand.partial(message: message, onRetry: onRetry!);
  }

  /// Not set up: a dashed outline instead of the slab, since there is
  /// nothing in it yet; the service's mark, what setting it up would show,
  /// and `Set up TrueNAS`, the whole outline one target.
  Widget _setUp(BuildContext context, CupolaRoom room) {
    final service = this.service!;
    final setUp = Lexicon.setUp(service.title);
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final mark = Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: room.fillStrong,
        borderRadius: AppRadius.borderRadiusSm,
        border: Border.all(color: room.hair),
      ),
      child: Icon(service.icon, size: 18, color: room.inkSecondary),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(headline!, style: AppType.row.copyWith(color: room.ink)),
        const SizedBox(height: 2),
        Text(setUpLine!, style: AppType.meta.copyWith(color: room.inkTertiary)),
      ],
    );
    final button = Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: room.fillStrong,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: room.edge),
      ),
      child: Text(
        setUp,
        style: AppType.label.weight(FontWeight.w600).copyWith(color: room.ink),
      ),
    );
    return PressableScale(
      onTap: onSetUp,
      semanticLabel: '$setUp, $setUpLine',
      semanticHint: 'opens the ${service.title} setup',
      excludeChildSemantics: true,
      child: CustomPaint(
        painter: _DashedOutline(color: room.edge, radius: AppRadius.slab),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        mark,
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: words),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    button,
                  ],
                )
              : Row(
                  children: [
                    mark,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: words),
                    const SizedBox(width: AppSpacing.sm),
                    button,
                  ],
                ),
        ),
      ),
    );
  }
}

/// A rounded outline drawn in dashes: a place on the Home kept for something
/// not set up yet.
class _DashedOutline extends CustomPainter {
  const _DashedOutline({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash + _gap) {
        canvas.drawPath(metric.extractPath(at, at + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) =>
      old.color != color || old.radius != radius;
}

/// The way on from a module's heading.
@immutable
class HomeModuleAction {
  const HomeModuleAction(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}

enum _FrameState { loading, ready, silent, needsService }

/// `Calendar`, `See all in Activity`: the heading's link, quiet and 44pt tall.
class _ActionLink extends StatelessWidget {
  const _ActionLink({required this.action});

  final HomeModuleAction action;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: AppRadius.borderRadiusSm,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            child: Center(
              child: Text(
                action.label,
                maxLines: 1,
                style: AppType.meta
                    .weight(FontWeight.w600)
                    .copyWith(color: room.inkSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
