import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class DockgeTerminalScreen extends ConsumerStatefulWidget {
  const DockgeTerminalScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  ConsumerState<DockgeTerminalScreen> createState() =>
      _DockgeTerminalScreenState();
}

class _DockgeTerminalScreenState extends ConsumerState<DockgeTerminalScreen> {
  String? selectedStack;

  @override
  Widget build(BuildContext context) {
    final configured = ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.dockge);
    return AmbientScaffold(
      accent: ServiceKey.dockge.accent,
      // The inset is consumed here with or without an app bar: with one the
      // `Scaffold` has already taken it off the body, and without one (the tab
      // shell) the band above consumes it and the tab bar sits an inset lower
      // than `topPadding` says.
      body: SafeArea(
        child: configured
            ? _body(context)
            : NotConfiguredPlaceholder.forService(ServiceKey.dockge),
      ),
    );
  }

  Widget _body(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: EdgeInsets.only(
      bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
    ),
    children: [
      if (widget.topPadding > 0) SizedBox(height: widget.topPadding),
      const SectionHeader(
        title: 'Choose a stack',
        subtitle:
            'Dockge exposes the combined action log, not an interactive shell',
        showChevron: false,
      ),
      _StackPicker(
        stacksAsync: ref.watch(dockgeStackListProvider),
        selected: selectedStack,
        onSelected: (name) => setState(() => selectedStack = name),
      ),
      if (selectedStack != null) ...[
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: DockgeTerminalPane(stackName: selectedStack!),
        ),
      ],
    ],
  );
}

class _StackPicker extends ConsumerWidget {
  const _StackPicker({
    required this.stacksAsync,
    required this.selected,
    required this.onSelected,
  });
  final AsyncValue<List<DockgeStack>> stacksAsync;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) => stacksAsync.when(
    data: (stacks) => stacks.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text('No stacks reported by this Dockge instance.'),
          )
        // `SelectionPills`, not a `Wrap` of `ChoiceChip`: the shared control
        // is where the press animation, the haptic, the Reduce Motion check
        // and, the part that matters here, the button role live together. A
        // bare chip row has no semantics node at all, so a screen reader got
        // no role, no accessible name and no selected state for the one
        // control that chooses which stack the terminal is showing.
        : SelectionPills<String?>(
            values: stacks.map((stack) => stack.name).toList(growable: false),
            selected: selected,
            labelBuilder: (name) => name ?? '',
            onSelected: (name) => onSelected(name!),
          ),
    loading: () => const ListRowsShimmer(count: 3),
    error: (error, _) => InlineErrorRetry(
      message: sectionFailureMessage(
        ServiceKey.dockge,
        error,
        consequence: 'the stacks are not shown',
      ),
      error: error,
      service: ServiceKey.dockge,
      onRetry: () => ref.invalidate(dockgeStackListProvider),
    ),
  );
}

class DockgeTerminalPane extends ConsumerWidget {
  const DockgeTerminalPane({super.key, required this.stackName});
  final String stackName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final output = ref.watch(dockgeTerminalTextProvider(stackName));
    final colorScheme = Theme.of(context).colorScheme;
    final terminalHeight = (MediaQuery.sizeOf(context).height * 0.36).clamp(
      220.0,
      360.0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$stackName\u00A0· combined log',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          height: terminalHeight,
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: AppRadius.borderRadiusMd,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: output.when(
            data: (text) => text.isEmpty
                ? Center(
                    child: Text(
                      'Waiting for output…',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(
                      text,
                      style: Theme.of(context).textTheme.bodySmall!.mono
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => InlineErrorRetry(
              message: sectionFailureMessage(
                ServiceKey.dockge,
                error,
                consequence: 'the terminal stopped',
              ),
              error: error,
              service: ServiceKey.dockge,
              onRetry: () =>
                  ref.invalidate(dockgeTerminalTextProvider(stackName)),
            ),
          ),
        ),
      ],
    );
  }
}
