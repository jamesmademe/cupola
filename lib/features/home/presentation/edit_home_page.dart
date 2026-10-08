import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/domain/home_layout.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';

/// Edit Home: the person's own Home, reordered and hidden.
///
/// Nothing is added here: the Home starts from the default for its person,
/// and this page moves and switches off what the registry gives it. Needs you
/// stands first and cannot be switched off; Set up next stands last. A module
/// moves by its handle: held and dragged, or tapped, which lifts it and offers
/// the two arrows, the way a thumb and a screen reader can both use. With a
/// screen reader each row also carries Move up and Move down.
///
/// The same page at `/home/edit` and `/settings/home`; its way back is where
/// it was opened from.
class EditHomePage extends ConsumerStatefulWidget {
  const EditHomePage({super.key});

  @override
  ConsumerState<EditHomePage> createState() => _EditHomePageState();
}

class _EditHomePageState extends ConsumerState<EditHomePage> {
  /// The module whose handle was tapped: its arrows show.
  HomeModule? _lifted;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final layout = ref.watch(homeLayoutProvider);
    final notifier = ref.read(homeLayoutProvider.notifier);
    final first = [
      for (final module in layout.rows)
        if (module.placement == HomePlacement.first) module,
    ];
    final last = [
      for (final module in layout.rows)
        if (module.placement == HomePlacement.last) module,
    ];

    return AmbientScaffold(
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              MediaQuery.paddingOf(context).top + AppSpacing.sm,
              AppSpacing.gutter,
              FloatingNavBarMetrics.getScrollViewBottomPadding(context),
            ),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: MediaBackPlate(),
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(
                header: true,
                child: Text(
                  'Edit Home',
                  style: AppType.room.copyWith(color: room.ink),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _intro(layout.audience),
                style: AppType.body.copyWith(color: room.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.scaleXl),
              if (first.isNotEmpty) ...[
                _Group(
                  label: 'Always on Home',
                  children: [
                    for (final module in first) _LockedRow(module: module),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _Group(
                label: 'Modules, in order',
                children: [
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) => Material(
                      color: room.raised,
                      borderRadius: BorderRadius.circular(AppRadius.group),
                      elevation: 6,
                      child: child,
                    ),
                    onReorderStart: (_) => setState(() => _lifted = null),
                    onReorder: notifier.reorder,
                    children: [
                      for (final (index, module) in layout.order.indexed)
                        _ModuleRow(
                          key: ValueKey(module),
                          module: module,
                          index: index,
                          count: layout.order.length,
                          on: layout.isOn(module),
                          lifted: _lifted == module,
                          onLift: () => setState(
                            () => _lifted = _lifted == module ? null : module,
                          ),
                          onMove: (by) => notifier.move(module, by),
                          onSwitch: (on) => notifier.setOn(module, on: on),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Hold a handle and drag, or tap it and use the arrows. '
                'With ${_screenReader()}: Move up, Move down.',
                style: AppType.caption.copyWith(color: room.inkSecondary),
              ),
              if (last.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _Group(
                  label: 'At the foot of Home',
                  children: [
                    for (final module in last)
                      _FootRow(
                        module: module,
                        on: layout.isOn(module),
                        onSwitch: (on) => notifier.setOn(module, on: on),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.scaleXl),
              _ResetButton(
                onPressed: layout.isDefault
                    ? null
                    : () {
                        setState(() => _lifted = null);
                        notifier.reset();
                      },
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                _otherPerson(layout.audience),
                style: AppType.meta.copyWith(color: room.inkSecondary),
              ),
            ],
          ),
          const Positioned(top: 0, left: 0, right: 0, child: StatusBarScrim()),
        ],
      ),
    );
  }
}

String _intro(Audience audience) => switch (audience) {
  Audience.operator =>
    'Your Home starts from the default for the person who runs the server. '
        'Reorder and hide; nothing else is added.',
  Audience.requester =>
    'Your Home starts from the default for someone who asks for movies and '
        'series. Reorder and hide; nothing else is added.',
};

/// What the other person's Home starts from, from the registry, so it never
/// names a module the app does not have.
String _otherPerson(Audience audience) {
  final other = audience == Audience.operator
      ? Audience.requester
      : Audience.operator;
  final names = joinWithAnd([
    for (final module in HomeModule.of(other))
      if (module.placement != HomePlacement.last) module.label,
  ]);
  return switch (other) {
    Audience.requester =>
      'A requester’s Home starts from their requests instead: $names. '
          'Each person arranges their own.',
    Audience.operator =>
      'The Home of the person who runs the server starts from what needs '
          'them instead: $names. Each person arranges their own.',
  };
}

String _screenReader() => switch (defaultTargetPlatform) {
  TargetPlatform.iOS || TargetPlatform.macOS => 'VoiceOver',
  TargetPlatform.android => 'TalkBack',
  _ => 'a screen reader',
};

/// A slab of rows, named for a screen reader.
class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Semantics(
      container: true,
      label: label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.group),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: room.slab,
            borderRadius: BorderRadius.circular(AppRadius.group),
            border: Border.all(color: room.hair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A module's name and its line, as every row prints them.
class _Words extends StatelessWidget {
  const _Words({required this.module, this.dimmed = false});

  final HomeModule module;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return AnimatedOpacity(
      opacity: dimmed ? 0.5 : 1,
      duration: const Duration(milliseconds: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(module.label, style: AppType.row.copyWith(color: room.ink)),
          const SizedBox(height: 2),
          Text(
            module.line,
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
        ],
      ),
    );
  }
}

/// Needs you: a lock where the handle would be, and no switch.
class _LockedRow extends StatelessWidget {
  const _LockedRow({required this.module});

  final HomeModule module;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Semantics(
      container: true,
      label: '${module.label}, always first',
      value: module.line,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 20,
                  color: room.inkTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _Words(module: module)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One module in the order: its handle, its words, then the switch, or the
/// two arrows while it is lifted.
class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    super.key,
    required this.module,
    required this.index,
    required this.count,
    required this.on,
    required this.lifted,
    required this.onLift,
    required this.onMove,
    required this.onSwitch,
  });

  final HomeModule module;
  final int index;
  final int count;
  final bool on;
  final bool lifted;
  final VoidCallback onLift;
  final ValueChanged<int> onMove;
  final ValueChanged<bool> onSwitch;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final canUp = index > 0;
    final canDown = index < count - 1;
    // On the row's two stops, the handle and the switch, so a screen reader
    // offers them wherever it lands on the row.
    final moves = <CustomSemanticsAction, VoidCallback>{
      if (canUp)
        const CustomSemanticsAction(label: 'Move up'): () => onMove(-1),
      if (canDown)
        const CustomSemanticsAction(label: 'Move down'): () => onMove(1),
    };
    return Semantics(
      container: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: lifted ? room.fillQuiet : null,
          border: index > 0 ? Border(top: BorderSide(color: room.hair)) : null,
        ),
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            ReorderableDelayedDragStartListener(
              index: index,
              child: Semantics(
                button: true,
                toggled: lifted,
                label: lifted
                    ? 'Put ${module.label} down'
                    : 'Move ${module.label}',
                customSemanticsActions: moves,
                excludeSemantics: true,
                child: InkWell(
                  onTap: onLift,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 22,
                      color: room.inkSecondary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: ExcludeSemantics(
                child: _Words(module: module, dimmed: !on),
              ),
            ),
            if (lifted) ...[
              _Arrow(
                icon: Icons.arrow_upward_rounded,
                label: 'Move ${module.label} up',
                onTap: canUp ? () => onMove(-1) : null,
              ),
              const SizedBox(width: 2),
              _Arrow(
                icon: Icons.arrow_downward_rounded,
                label: 'Move ${module.label} down',
                onTap: canDown ? () => onMove(1) : null,
              ),
            ] else
              Semantics(
                label: module.label,
                value: module.line,
                customSemanticsActions: moves,
                child: Switch(value: on, onChanged: onSwitch),
              ),
          ],
        ),
      ),
    );
  }
}

/// Set up next: no handle, it stands last; a switch.
class _FootRow extends StatelessWidget {
  const _FootRow({
    required this.module,
    required this.on,
    required this.onSwitch,
  });

  final HomeModule module;
  final bool on;
  final ValueChanged<bool> onSwitch;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Icons.vertical_align_bottom_rounded,
                size: 20,
                color: room.inkTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ExcludeSemantics(
                child: _Words(module: module, dimmed: !on),
              ),
            ),
            Semantics(
              label: module.label,
              value: module.line,
              child: Switch(value: on, onChanged: onSwitch),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two arrows of a lifted row: 44pt, dimmed at its end of the
/// order.
class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: room.fillControl,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: room.edge),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: onTap == null ? room.inkDisabled : room.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Reset to default: dimmed while the layout already is the default.
class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.restart_alt_rounded, size: 20),
        label: const Text('Reset to default'),
      ),
    );
  }
}
