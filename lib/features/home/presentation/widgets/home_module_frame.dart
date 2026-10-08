import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
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
///    words, with Retry;
///  * **its service is not set up** ([HomeModuleFrame.needsService]): a dimmed
///    slab that names the service and stays a target. Only a module the person
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
       setUpLine = null;

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
       setUpLine = null;

  /// A module whose every source failed: the fault in the words of its cause,
  /// and Retry. [child] is what was last known, drawn dimmed above the fault
  /// where the module has it.
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
       setUpLine = null;

  /// A module the person switched on whose service is not set up: `Set up
  /// TrueNAS to see your storage`, what it would show, and the way there.
  const HomeModuleFrame.needsService({
    super.key,
    required this.title,
    required ServiceKey this.service,
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
          if (child case final known?) Opacity(opacity: 0.5, child: known),
          const SizedBox(height: AppSpacing.xs),
          _fault(),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
      _FrameState.needsService => _setUp(context, room),
    };

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

  Widget _setUp(BuildContext context, CupolaRoom room) {
    final service = this.service!;
    final setUp = 'Set up ${service.title}';
    return PressableScale(
      onTap: onSetUp,
      semanticLabel: '$setUp, $setUpLine',
      semanticHint: 'opens the ${service.title} setup',
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$setUp to see ${title.toLowerCase()}',
                      style: AppType.row.copyWith(color: room.inkSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      setUpLine!,
                      style: AppType.meta.copyWith(color: room.inkTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                setUp,
                style: AppType.label
                    .weight(FontWeight.w600)
                    .copyWith(color: room.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
