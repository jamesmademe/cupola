import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

extension ManualImportServiceCopy on ServiceKey {
  String get manualImportSubLabel {
    return switch (this) {
      ServiceKey.radarr => 'Movies',
      ServiceKey.sonarr => 'Series',
      ServiceKey.lidarr => 'Music',
      _ => 'Requests',
    };
  }

  String get manualImportSubtitle {
    return switch (this) {
      ServiceKey.radarr => 'Manual import movies',
      ServiceKey.sonarr => 'Manual import series',
      ServiceKey.lidarr => 'Manual import music',
      _ => 'Manual import requests',
    };
  }

  String get manualImportSearchHint {
    return switch (this) {
      ServiceKey.radarr => 'Search movie',
      ServiceKey.sonarr => 'Search series',
      ServiceKey.lidarr => 'Search artist',
      _ => 'Search',
    };
  }
}

/// The shared scaffold for the three import stations: ambient room tinted by
/// the owning service, glass app bar with a two-line title, and an optional
/// pinned bottom bar for the station's primary action.
class ManualImportFrame extends StatelessWidget {
  final ServiceKey service;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? bottomBar;
  final List<Widget>? actions;

  const ManualImportFrame({
    super.key,
    required this.service,
    required this.title,
    required this.subtitle,
    required this.child,
    this.bottomBar,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AmbientScaffold(
      accent: service.accent,
      appBar: GlassAppBar(
        leading: Semantics(
          button: true,
          label: MaterialLocalizations.of(context).backButtonTooltip,
          hint: 'Return to the previous screen',
          onTap: () => context.pop(),
          child: ExcludeSemantics(
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => context.pop(),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium!.weight(FontWeight.w600),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Track passes a submitted-file count through this slot; the
              // other two stations pass digitless copy, which tabular figures
              // leave untouched.
              style: theme.textTheme.labelSmall!.tabular.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: child),
            ?bottomBar,
          ],
        ),
      ),
    );
  }
}

/// The one title all three stations carry.
///
/// Sentence case, and the same string on Locate, Review and Track: the flow has
/// one name, and the station bar underneath says which part of it you are in.
/// Three separate Title Case titles made a single task read as three
/// destinations — in the app bar, and in a browser's back list.
const manualImportTitle = 'Manual import';

/// The names of the three import stations, in order.
///
/// Station 3 is **Track**, not Import: the button beside it already says
/// "Import N files", so a station called Import would name the same act twice
/// and leave the page where the files are already moving without a name of its
/// own.
const manualImportStations = ['Locate', 'Review', 'Track'];

/// A compact "where am I" strip for a multi-step flow.
///
/// One pill per station: the active one takes the service accent as a soft
/// tint (the same selected-affordance vocabulary as the nav pill), finished
/// ones get a small check, upcoming ones recede. Spoken as a single node —
/// "Step 2 of 3: Review" — because three pills and two connectors are one fact.
class ImportStationBar extends StatelessWidget {
  final ServiceKey service;
  final List<String> stations;
  final int activeIndex;

  const ImportStationBar({
    super.key,
    required this.service,
    required this.activeIndex,
    this.stations = manualImportStations,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = service.accent;
    final activeLabelColor = ServiceTheme.onTint(
      accent,
      surface: colorScheme.surface,
      tintAlpha: 0.14,
    );

    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          'Step ${activeIndex + 1} of ${stations.length}: '
          '${stations[activeIndex]}',
      // Compact chrome that must stay one line, so it follows the reading size
      // only to 1.3× — the same clamp DESIGN.md pins on the floating nav bar,
      // and for the same reason: three pills and two connectors cannot reflow.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: TextScaleMetrics.singleLineChromeMaxScaleFactor,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Row(
            children: [
              for (var index = 0; index < stations.length; index++) ...[
                if (index > 0)
                  // Fixed, not Expanded: a flexible connector competes with the
                  // pills for the same flex space, which squeezed "Locate" down
                  // to "Lo…" at the default reading size.
                  Container(
                    width: AppSpacing.lg,
                    height: 2,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: index <= activeIndex
                          ? accent.withValues(alpha: 0.45)
                          : colorScheme.outlineVariant,
                      borderRadius: AppRadius.borderRadiusFull,
                    ),
                  ),
                Flexible(
                  // Loose: the pill takes its natural width and only gives way
                  // when the row genuinely runs out of room.
                  fit: FlexFit.loose,
                  child: AnimatedContainer(
                    duration: AppAnimation.durationSm,
                    curve: AppAnimation.emphasizedCurve,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs + 2,
                    ),
                    decoration: BoxDecoration(
                      color: index == activeIndex
                          ? accent.withValues(alpha: 0.14)
                          : Colors.transparent,
                      borderRadius: AppRadius.borderRadiusPill,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // A check once the station is behind you, its number
                        // until then. Without the number the bar said where you
                        // were but not how far in — three equal words, and no
                        // way to tell "Review" the second of three from
                        // "Review" the last thing left to do.
                        if (index < activeIndex) ...[
                          Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: ServiceTheme.onTint(
                              accent,
                              surface: colorScheme.surface,
                              tintAlpha: 0.14,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ] else ...[
                          Text(
                            '${index + 1}',
                            style: theme.textTheme.labelMedium!
                                .weight(FontWeight.w600)
                                .tabular
                                .copyWith(
                                  color: index == activeIndex
                                      ? activeLabelColor
                                      : colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        // Ellipsises past the clamp rather than clipping.
                        Flexible(
                          child: Text(
                            stations[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium!
                                .weight(
                                  index == activeIndex
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                )
                                .copyWith(
                                  color: index == activeIndex
                                      ? activeLabelColor
                                      : colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The current folder path as tappable segments.
class ImportBreadcrumb extends StatelessWidget {
  final ServiceKey service;
  final String? path;
  final ValueChanged<String>? onSegmentTap;
  final List<String>? segments;

  const ImportBreadcrumb({
    super.key,
    required this.service,
    this.path,
    this.onSegmentTap,
    this.segments,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pathSegments = segments ?? _segmentsFor(path ?? '');
    final isRoot = path == '/' || pathSegments.isEmpty;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Root folder',
            onPressed: onSegmentTap == null ? null : () => onSegmentTap!('/'),
            icon: Icon(
              Icons.home_rounded,
              size: 18,
              color: isRoot
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          for (var index = 0; index < pathSegments.length; index++) ...[
            ExcludeSemantics(
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            TextButton(
              onPressed: onSegmentTap == null || path == null
                  ? null
                  : () => onSegmentTap!(_pathForSegment(path!, index)),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                foregroundColor: index == pathSegments.length - 1
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
                textStyle: theme.textTheme.labelMedium!.weight(
                  index == pathSegments.length - 1
                      ? FontWeight.w600
                      : FontWeight.w500,
                ),
              ),
              child: Text(pathSegments[index]),
            ),
          ],
        ],
      ),
    );
  }
}

/// The station's single primary action, pinned above the home indicator.
class ImportPrimaryButton extends StatelessWidget {
  final ServiceKey service;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const ImportPrimaryButton({
    super.key,
    required this.service,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: FilledButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          disabledBackgroundColor: colorScheme.surfaceContainerHighest,
          disabledForegroundColor: colorScheme.onSurfaceVariant,
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
  }
}

/// The station's way out, beside the primary action.
///
/// Outlined and neutral on purpose: the accent belongs to the one control that
/// commits, and a second filled button next to it would make leaving look like
/// a decision of the same weight. The app-bar chevron does the same job, but it
/// is at the far end of a page whose only other control is pinned to the
/// bottom — on a phone that is the whole screen away from the thumb.
class ImportSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const ImportSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        side: BorderSide(color: colorScheme.outlineVariant),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// A dim line above a station's primary action.
///
/// For the sentence that would change the decision the button is about to make
/// — never for a status, which belongs on the row it describes.
class ImportFooterNote extends StatelessWidget {
  final String text;
  final IconData icon;

  const ImportFooterNote({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelSmall!.tabular.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the import button is about to spend, in words, above the button.
///
/// `3 of 5 selected · 1 re-import · 1 needs an identity · 39.9 GB`. The button
/// itself can only carry the count; this line carries the shape of the scan —
/// how much of it is ticked, how much of it is a replacement rather than a new
/// file, how much of it is still waiting for an identity, and how many bytes
/// are about to move on the user's own disk.
///
/// The denominator is the files this service could take: ready, unmatched, and
/// the ones it already holds. The unimportable remainder of a real downloads
/// folder — artwork, playlists, NFOs, dozens of them — is deliberately outside
/// it, because a line reading "3 of 61 selected" describes a problem the user
/// does not have.
///
/// Every segment is dropped when its figure is zero rather than printed as a
/// zero: "0 re-imports" is a fact about nothing.
String manualImportSelectionSummary({
  required int selected,
  required int selectable,
  required int reimports,
  required int needingIdentity,
  required int selectedBytes,
}) {
  return [
    '$selected of $selectable selected',
    if (reimports > 0) reimports == 1 ? '1 re-import' : '$reimports re-imports',
    if (needingIdentity > 0)
      needingIdentity == 1
          ? '1 needs an identity'
          : '$needingIdentity need an identity',
    // The sentinel, not a zero: a selection whose sizes the service did not
    // report is not a zero-byte import.
    if (selected > 0) formatImportBytes(selectedBytes),
  ].join(' · ');
}

/// What the import confirmation says before [count] files are handed over.
///
/// Pure so the sentence can be asserted without a dialog. It names how the
/// service will take the files ([mode]), how many of them replace a file the
/// library already has ([reimports]), and that the service cannot take it
/// back — Sonarr and Radarr have no undo for an import, and a Move has already
/// relocated the source by the time anything could be undone.
String manualImportConfirmMessage({
  required ServiceKey service,
  required ManualImportMode mode,
  required int count,
  required int reimports,
}) {
  final them = count == 1 ? 'It is' : 'They are';
  return [
    switch (mode) {
      ManualImportMode.move => '$them moved into the library folder.',
      ManualImportMode.copy =>
        '$them copied into the library; the '
            '${count == 1 ? 'original stays' : 'originals stay'} where '
            '${count == 1 ? 'it is' : 'they are'}.',
      ManualImportMode.auto =>
        '${service.title} decides whether to move or copy '
            '${count == 1 ? 'it' : 'each one'}.',
    },
    if (reimports == 1 && count == 1)
      'It replaces the file already in the library.'
    else if (reimports == 1)
      '1 of them replaces the file already in the library.'
    else if (reimports > 1)
      '$reimports of them replace the files already in the library.',
    '${service.title} cannot undo an import.',
  ].join(' ');
}

/// Asks before the selection is spent; true when the user confirmed.
///
/// The button used to be the whole guard: one tap moved (or, for a ticked
/// re-import, overwrote) files that no one can put back. Neutral styling,
/// because the tone rule keeps red for "unreachable" in a status, and the
/// sentence carries the weight.
Future<bool> confirmManualImport(
  BuildContext context, {
  required ServiceKey service,
  required ManualImportMode mode,
  required int count,
  required int reimports,
}) async {
  final files = count == 1 ? '1 file' : '$count files';
  final result = await showAppConfirmDialog(
    context: context,
    icon: Icons.move_to_inbox_rounded,
    title: 'Import $files into ${service.title}?',
    message: manualImportConfirmMessage(
      service: service,
      mode: mode,
      count: count,
      reimports: reimports,
    ),
    confirmLabel: 'Import $files',
  );
  return result.confirmed;
}

/// Review's pinned bottom bar: the import-mode menu plus the primary action.
class ManualImportReviewFooter extends ConsumerWidget {
  final ServiceKey service;
  final int? targetId;

  /// Ticked files the current filter is keeping off screen.
  ///
  /// The button spends the whole selection, and the scan preselects every ready
  /// file — so narrowing to one series and clearing it leaves a button that
  /// imports precisely what the user is not looking at. The count stays whole
  /// (that is what will be sent); the line above it says how much of it is out
  /// of sight.
  final int offScreenSelectedCount;

  const ManualImportReviewFooter({
    super.key,
    required this.service,
    this.targetId,
    this.offScreenSelectedCount = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(manualImportFlowProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final count = state.selectedItems.length;
    final label = count == 0
        ? 'Nothing selected to import'
        : count == 1
        ? 'Import 1 file'
        : 'Import $count files';

    final offScreen = offScreenSelectedCount.clamp(0, count);
    final String? scopeNote = offScreen == 0
        ? null
        : offScreen == count
        ? (count == 1
              ? 'The selected file is not in view'
              : 'None of these $count files are in view')
        : '$offScreen of them are not in view';

    final summary = manualImportSelectionSummary(
      selected: count,
      selectable: state.importableCount,
      reimports: state.selectedReimportItems.length,
      needingIdentity: state.attentionItems.length,
      selectedBytes: state.selectedBytes,
    );

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Above the button, and spoken as one node: the button can only carry
          // a count, and the count alone never said what was left unticked.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              0,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall!.tabular.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (scopeNote != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                0,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_off_rounded,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      scopeNote,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall!.tabular.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              _ImportModeMenu(service: service),
              Expanded(
                child: ImportPrimaryButton(
                  service: service,
                  icon: Icons.check_circle_outline_rounded,
                  label: label,
                  loading: state.isSubmitting,
                  onPressed: !state.canImportSelected
                      ? null
                      : () async {
                          final notifier = ref.read(
                            manualImportFlowProvider.notifier,
                          );
                          // Only a batch that is actually going to be sent
                          // asks: with everything already handed over, the
                          // button is a way back to Track, not a submission.
                          final pending = state.selectedItems
                              .where(
                                (item) =>
                                    !state.blockedPaths.contains(item.path),
                              )
                              .toList(growable: false);
                          if (pending.isNotEmpty) {
                            final confirmed = await confirmManualImport(
                              context,
                              service: service,
                              mode: state.importMode,
                              count: pending.length,
                              reimports: pending
                                  .where((item) => item.isAlreadyImported)
                                  .length,
                            );
                            if (!confirmed || !context.mounted) return;
                          }
                          final command = await notifier.confirmImport();
                          if (command == null || !context.mounted) return;
                          // Await the pop: coming back from Track re-reads the
                          // folder, so the list reflects what the service actually
                          // did with the files instead of the state we left behind.
                          await context.push(
                            manualImportLocation(
                              manualImportProgressPath,
                              service,
                              targetId: targetId,
                              // Track polls the command on the server that is
                              // running it; the link has to say which one.
                              instanceId: state.instanceId,
                            ),
                          );
                          if (!context.mounted) return;
                          await notifier.refreshAfterImport();
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Auto / Move / Copy — how the service should take the files.
class _ImportModeMenu extends ConsumerWidget {
  final ServiceKey service;

  const _ImportModeMenu({required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(manualImportFlowProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MenuAnchor(
      builder: (context, controller, _) {
        return Semantics(
          button: true,
          label: 'Import mode',
          value: state.importMode.label,
          child: OutlinedButton.icon(
            onPressed: controller.isOpen ? controller.close : controller.open,
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.onSurface,
              side: BorderSide(color: colorScheme.outlineVariant),
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            ),
            icon: Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            iconAlignment: IconAlignment.end,
            label: Text(state.importMode.label),
          ),
        );
      },
      menuChildren: [
        for (final mode in ManualImportMode.values)
          MenuItemButton(
            onPressed: () =>
                ref.read(manualImportFlowProvider.notifier).setImportMode(mode),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mode.label, style: theme.textTheme.labelLarge),
                Text(
                  mode.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A file size for the manual-import surfaces, or `Unknown size` when the
/// service reported none.
///
/// Only the sentinel is local: the ladder is the shared [formatBytes] one, the
/// same the qBittorrent list and Interactive Search read from. This was a sixth
/// private ladder with its own precision rule (`unit <= 1 ? 0 : 1`), so the same
/// file read `5.0 GB` here and `5.00 GB` two screens away.
String formatImportBytes(int size) {
  if (size <= 0) return 'Unknown size';
  return formatBytes(size);
}

List<String> _segmentsFor(String path) {
  return path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
}

String _pathForSegment(String path, int segmentIndex) {
  final prefix = path.startsWith('/') ? '/' : '';
  final segments = _segmentsFor(path).take(segmentIndex + 1).join('/');
  return '$prefix$segments';
}
