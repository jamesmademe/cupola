import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class DockgeTerminalScreen extends ConsumerStatefulWidget {
  const DockgeTerminalScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  });

  final bool showAppBar;
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
      accent: AppColors.dockge,
      appBar: widget.showAppBar
          ? const GlassAppBar(title: Text('Terminal'))
          : null,
      body: SafeArea(
        top: widget.showAppBar,
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
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: stacks
                  .map(
                    (stack) => ChoiceChip(
                      label: Text(stack.name),
                      selected: selected == stack.name,
                      onSelected: (_) => onSelected(stack.name),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
    loading: () => const ListRowsShimmer(count: 3),
    error: (_, _) => InlineErrorRetry(
      message: 'Failed to load stacks',
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
          '$stackName · combined log',
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
            error: (_, _) => InlineErrorRetry(
              message: 'Terminal stream disconnected',
              onRetry: () =>
                  ref.invalidate(dockgeTerminalTextProvider(stackName)),
            ),
          ),
        ),
      ],
    );
  }
}
