import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/import/presentation/manual_import_widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Station 1 — Locate: walk the server's filesystem to the folder that holds
/// the files, then hand it to Review for the scan.
class ManualImportLocateScreen extends ConsumerStatefulWidget {
  final ServiceKey service;
  final int? targetId;

  /// The connection the route named (`?i=`), or null when it named none.
  ///
  /// Station 1 is where the binding is made: every later station reads it back
  /// off the flow state. Null falls through to the lens, which is how every link
  /// written before the parameter existed still works.
  final String? instanceId;

  /// Pre-seeded folder, e.g. a failed download's output path from Activity.
  final String? initialPath;

  const ManualImportLocateScreen({
    super.key,
    required this.service,
    this.targetId,
    this.instanceId,
    this.initialPath,
  });

  @override
  ConsumerState<ManualImportLocateScreen> createState() =>
      _ManualImportLocateScreenState();
}

class _ManualImportLocateScreenState
    extends ConsumerState<ManualImportLocateScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_start);
  }

  @override
  void didUpdateWidget(covariant ManualImportLocateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.targetId != widget.targetId ||
        oldWidget.instanceId != widget.instanceId ||
        oldWidget.initialPath != widget.initialPath) {
      Future.microtask(() => _start(force: true));
    }
  }

  void _start({bool force = false}) {
    ref
        .read(manualImportFlowProvider.notifier)
        .start(
          widget.service,
          instanceId: widget.instanceId,
          targetId: widget.targetId,
          force: force,
          initialPath: widget.initialPath,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualImportFlowProvider);
    final selectedFolder = state.selectedFolder;

    return ManualImportFrame(
      service: widget.service,
      // One title on all three stations; the station bar says which one this
      // is. Three Title Case titles used to do that job badly — the page name
      // changed under a flow that had not changed, and the browser back button
      // read as three unrelated destinations.
      title: manualImportTitle,
      subtitle: '${widget.service.title} · choose a folder to scan',
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Before the commitment, not during it: the server parses and probes
          // every file it finds, and the only moment that warning can change a
          // decision is while the user is still choosing the folder.
          const ImportFooterNote(
            text:
                'Scanning parses and probes every file on the server, '
                'large folders take minutes.',
          ),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.lg),
            child: Row(
              children: [
                ImportSecondaryButton(
                  label: 'Cancel',
                  onPressed: () => context.pop(),
                ),
                Expanded(
                  child: ImportPrimaryButton(
                    service: widget.service,
                    icon: Icons.radar_rounded,
                    label: selectedFolder == null
                        ? 'Choose a folder'
                        : 'Scan "${manualImportPathName(selectedFolder)}"',
                    onPressed: selectedFolder == null
                        ? null
                        : () => context.push(
                            manualImportLocation(
                              manualImportReviewPath,
                              widget.service,
                              targetId: widget.targetId,
                              // The binding travels with the link: Review is a
                              // separate route, and without this it would
                              // re-resolve the connection through the lens.
                              instanceId: state.instanceId,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      child: _LocateBody(
        service: widget.service,
        state: state,
        onRetry: () => _start(force: true),
      ),
    );
  }
}

class _LocateBody extends ConsumerWidget {
  final ServiceKey service;
  final ManualImportFlowState state;
  final VoidCallback onRetry;

  const _LocateBody({
    required this.service,
    required this.state,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.error != null && state.rootFolders.isEmpty) {
      // The message here is the service's own error text, which quotes the
      // address it could not reach: long enough to wrap, so the page has to be
      // able to scroll.
      return AppEmptyStatePage(
        emptyState: AppEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Manual import unavailable',
          message: state.error,
          accentColor: service.accent,
          action: FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ),
      );
    }

    final lastFolder = ref.watch(
      manualImportLastFolderProvider((service, state.instanceId)),
    );
    final showLastFolder =
        lastFolder != null && lastFolder.path != state.selectedFolder;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ImportStationBar(service: service, activeIndex: 0),
        if (state.rootFolders.isNotEmpty)
          _RootFolderRail(service: service, state: state),
        if (showLastFolder)
          _LastFolderShortcut(service: service, folder: lastFolder),
        _PathField(service: service),
        ImportBreadcrumb(
          service: service,
          path: state.currentPath,
          onSegmentTap: (path) =>
              ref.read(manualImportFlowProvider.notifier).selectFolder(path),
        ),
        if (state.isLoadingBrowse && state.fileSystem == null)
          const _DirectorySkeleton()
        else
          _DirectoryCard(service: service, state: state),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

/// The service's root folders as one horizontal rail of jump points.
class _RootFolderRail extends ConsumerWidget {
  final ServiceKey service;
  final ManualImportFlowState state;

  const _RootFolderRail({required this.service, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          for (final folder in state.rootFolders) ...[
            _RootFolderChip(
              service: service,
              folder: folder,
              selected: _isWithin(state.currentPath, folder.path),
              onTap: () => ref
                  .read(manualImportFlowProvider.notifier)
                  .selectFolder(folder.path),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  bool _isWithin(String? currentPath, String rootPath) {
    if (currentPath == null) return false;
    return currentPath == rootPath || currentPath.startsWith(rootPath);
  }
}

class _RootFolderChip extends StatelessWidget {
  final ServiceKey service;
  final ManualImportRootFolder folder;
  final bool selected;
  final VoidCallback onTap;

  const _RootFolderChip({
    required this.service,
    required this.folder,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = service.accent;
    final freeSpace = folder.freeSpace;
    final subtitle = !folder.accessible
        ? 'Unreachable'
        : freeSpace == null
        ? null
        : '${formatImportBytes(freeSpace)} free';
    final labelColor = selected
        ? ServiceTheme.onTint(
            accent,
            surface: colorScheme.surface,
            tintAlpha: 0.14,
          )
        : colorScheme.onSurface;

    return PressableScale(
      onTap: onTap,
      semanticLabel: 'Root folder ${folder.displayName}',
      semanticValue: [?subtitle, if (selected) 'selected'].join(', '),
      excludeChildSemantics: true,
      child: AnimatedContainer(
        duration: AppAnimation.durationSm,
        curve: AppAnimation.emphasizedCurve,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : colorScheme.surfaceContainer,
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.28)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              folder.accessible
                  ? Icons.folder_rounded
                  : Icons.folder_off_rounded,
              size: 18,
              color: folder.accessible ? accent : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.displayName,
                  style: theme.textTheme.labelMedium!
                      .weight(FontWeight.w600)
                      .copyWith(color: labelColor),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    // Reports free space, which moves as the import runs.
                    style: theme.textTheme.labelSmall!.tabular.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One-tap return to the folder this service last scanned — the rescue scene
/// almost always comes back to the same completed-downloads folder.
class _LastFolderShortcut extends ConsumerWidget {
  final ServiceKey service;
  final ManualImportLastFolder folder;

  const _LastFolderShortcut({required this.service, required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final path = folder.path;
    // "Last scanned" alone cannot say whether it is still the right folder —
    // this morning's rescue and last month's are the same card. The stamp is
    // only written from the version that records it, so a shortcut saved before
    // that says nothing rather than guessing.
    final eyebrow = folder.scannedAt == null
        ? 'Last scanned'
        : 'Last scanned · ${formatRelativeDateTime(folder.scannedAt!)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: AppCard.filled(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        onTap: () =>
            ref.read(manualImportFlowProvider.notifier).selectFolder(path),
        semanticLabel: 'Return to last scanned folder',
        semanticValue: folder.scannedAt == null
            ? path
            : '$path, scanned ${formatRelativeDateTime(folder.scannedAt!)}',
        semanticHint: 'selects the folder',
        excludeChildSemantics: true,
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: service.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    // Carries a relative figure that ticks over.
                    style: theme.textTheme.labelSmall!.tabular.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium!.weight(FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Type the path instead of walking to it.
///
/// A completed-downloads folder is five or six taps down a tree the user
/// already knows the address of, and on a server with a deep mount the walk is
/// the slowest part of the rescue — every level is a round trip the service
/// answers by stat-ing a volume that may be spun down. Submitting jumps
/// straight there; a path that does not exist comes back as the service's own
/// error, which is the honest answer.
class _PathField extends ConsumerStatefulWidget {
  final ServiceKey service;

  const _PathField({required this.service});

  @override
  ConsumerState<_PathField> createState() => _PathFieldState();
}

class _PathFieldState extends ConsumerState<_PathField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final path = _controller.text.trim();
    if (path.isEmpty) return;
    ref.read(manualImportFlowProvider.notifier).selectFolder(path);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Semantics(
        container: true,
        label: 'Folder path',
        hint: 'Type a folder path and press Return to navigate',
        child: TextField(
          controller: _controller,
          onSubmitted: (_) => _submit(),
          textInputAction: TextInputAction.go,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            isDense: true,
            // The visible label is also the field's accessible name. A hint
            // alone was not exposed by the macOS Flutter bridge while the
            // field was empty, leaving VoiceOver with an unnamed control.
            labelText: 'Folder path',
            hintText: 'Type a path…',
            prefixIcon: Icon(
              Icons.folder_open_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            suffixIcon: Semantics(
              button: true,
              label: 'Go to this folder',
              hint: 'Open the folder path',
              onTap: _submit,
              child: ExcludeSemantics(
                child: IconButton(
                  tooltip: 'Go to this folder',
                  onPressed: _submit,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                ),
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: AppRadius.borderRadiusMd,
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectorySkeleton extends StatelessWidget {
  const _DirectorySkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          for (var index = 0; index < 5; index++) ...[
            ShimmerPlaceholder.card(height: 56),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _DirectoryCard extends ConsumerWidget {
  final ServiceKey service;
  final ManualImportFlowState state;

  const _DirectoryCard({required this.service, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directories = state.fileSystem?.directories ?? const [];

    if (directories.isEmpty) {
      return AppEmptyState.compact(
        icon: Icons.folder_off_rounded,
        title: 'No subfolders here',
        message: 'You can still scan this folder as the import source.',
        accentColor: service.accent,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: AppCard.surfaceOutlined(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: AppRadius.borderRadiusMd,
          child: Column(
            children: [
              for (var index = 0; index < directories.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                _DirectoryRow(
                  service: service,
                  entry: directories[index],
                  selected: directories[index].path == state.selectedFolder,
                  onTap: () => ref
                      .read(manualImportFlowProvider.notifier)
                      .selectFolder(directories[index].path),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectoryRow extends StatelessWidget {
  final ServiceKey service;
  final ManualImportFileSystemEntry entry;
  final bool selected;
  final VoidCallback onTap;

  const _DirectoryRow({
    required this.service,
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = service.accent;
    // The only per-folder figure the service actually answers. The canvas also
    // draws "5 files · 46.1 GB", and there is no endpoint behind either: the
    // \*arr filesystem call lists one level and does not recurse, and this
    // client asks it with `includeFiles: false` on purpose because the call
    // already outlives its timeout on a spun-down volume.
    //
    // Absent rather than an em dash when the service omits the field: it omits
    // it for every row or for none, so the dash would be a column of dashes
    // saying the same nothing on each line.
    final modified = entry.lastModified == null
        ? null
        : formatRelativeActivityDate(entry.lastModified);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      selected: selected,
      label: entry.name,
      value: modified == null ? null : 'modified $modified',
      hint: 'opens the folder',
      onTap: onTap,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.08) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: serviceThemeFor(service).softContainer,
                      borderRadius: AppRadius.borderRadiusSm,
                    ),
                    child: Icon(Icons.folder_rounded, size: 18, color: accent),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall!.weight(
                            selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        Text(
                          entry.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (modified != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    // Its own column rather than a third fact appended to the
                    // path line: the path elides, and an elided line would eat
                    // exactly the figure that was added.
                    Text(
                      modified,
                      style: theme.textTheme.labelSmall!.tabular.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (selected) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Icon(Icons.check_rounded, size: 18, color: accent),
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
