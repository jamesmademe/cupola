import 'package:flutter/material.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/machine_name.dart';

/// The File section of a detail page: the file on disk, the folder, or the
/// hint for a title with nothing on disk yet.
///
/// Headless: the heading comes from the `MediaDetailSlot` that hosts it, so
/// every heading on a detail page is built by the spine and cannot lose its
/// accent, its `Semantics(header: true)` or its place in the region order.
class FileInfoSection extends StatelessWidget {
  /// The item's folder on the server.
  final String? path;

  /// [FileInfoSection.file] only: the file inside [path], in full.
  final String? fileName;

  /// [FileInfoSection.file] only: the release the file came from, when the
  /// service renamed it on import.
  final String? releasedAs;

  /// Optional page accent for the storage glyph: the service's accent, which is
  /// the lamp, walked to the room's ink against the well.
  final Color? accent;

  final _FileInfoShape _shape;

  /// What the folder is called wherever it is drawn: the folder row's title,
  /// the folder line's spoken label in [FileInfoSection.file], and the slot
  /// label of a page whose section shows only the folder.
  static const folderLabel = 'Library path';

  /// The folder alone, titled *Library path*: what a page shows when the
  /// service names no single file (a series keeps one per episode).
  const FileInfoSection({super.key, this.path, this.accent})
    : fileName = null,
      releasedAs = null,
      _shape = _FileInfoShape.folder;

  /// The file on disk, named in full (a [MachineName] in full: wrapping,
  /// selectable, with a copy button), then *Released as* and the release it
  /// came from when the service renamed it, then the folder.
  ///
  /// The file is the service's own record of it (Radarr's
  /// `movieFile.relativePath`), never the last part of the folder: that named
  /// the folder as though it were the file.
  const FileInfoSection.file({
    super.key,
    required String this.fileName,
    this.releasedAs,
    this.path,
    this.accent,
  }) : _shape = _FileInfoShape.file;

  /// The same row, for a title the service tracks with nothing on disk yet.
  ///
  /// Deliberately this row and **not** an `AppEmptyState`: a centred well with a
  /// circled glyph cost far more height than the fact deserves, on a page whose
  /// hero already says `No file` and whose consequence sentence already says the
  /// state — and it made the region jump when a file finally arrived. One
  /// footprint in both states is the whole point.
  ///
  /// The copy is a suggestion, and it names the route the promoted button does
  /// not: on this rung the primary directly above already reads "Automatic search",
  /// so repeating it would spend the region on nothing.
  const FileInfoSection.missing({super.key, this.accent})
    : path = null,
      fileName = null,
      releasedAs = null,
      _shape = _FileInfoShape.missing;

  /// The page accent walked against the well the glyph sits in
  /// (`surfaceContainerHighest`), so an amber page does not paint a sub-2:1
  /// glyph in daylight.
  Color _glyphColor(ColorScheme colorScheme) {
    final tone = accent;
    if (tone == null) return colorScheme.onSurfaceVariant;
    return ServiceTheme.onTint(
      tone,
      surface: colorScheme.surfaceContainerHighest,
      tintAlpha: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    switch (_shape) {
      case _FileInfoShape.missing:
        return _InfoRow(
          title: 'Import a file you already have',
          subtitle: 'Manual import is in the actions menu.',
          icon: Icons.drive_folder_upload_rounded,
          iconColor: _glyphColor(colorScheme),
          colorScheme: colorScheme,
          theme: theme,
          // The actionable half must survive a reading size, and this line is
          // the only place the alternative route is named.
          subtitleMaxLines: 2,
        );
      case _FileInfoShape.file:
        return _FileRow(
          fileName: fileName!,
          releasedAs: releasedAs,
          folder: path,
          iconColor: _glyphColor(colorScheme),
          colorScheme: colorScheme,
          theme: theme,
        );
      case _FileInfoShape.folder:
        final folder = path;
        if (folder == null) return const SizedBox.shrink();
        return _InfoRow(
          title: folderLabel,
          subtitle: folder,
          icon: Icons.storage_rounded,
          iconColor: _glyphColor(colorScheme),
          colorScheme: colorScheme,
          theme: theme,
        );
    }
  }
}

enum _FileInfoShape { folder, file, missing }

BoxDecoration _plate(ColorScheme colorScheme) => BoxDecoration(
  color: colorScheme.surfaceContainer,
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: colorScheme.outlineVariant),
);

const _platePadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.md,
  vertical: 11,
);

Widget _well(ColorScheme colorScheme, IconData icon, Color iconColor) =>
    Container(
      width: 38,
      height: 54,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXs2),
      ),
      child: Icon(icon, size: 18, color: iconColor),
    );

/// The file, then the release it came from, then the folder.
///
/// Three nodes rather than the folder row's one: each name is read whole after
/// its label and carries its own copy action, and the folder reads *Library
/// path* first, as it does on the pages that show only the folder.
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.fileName,
    required this.releasedAs,
    required this.folder,
    required this.iconColor,
    required this.colorScheme,
    required this.theme,
  });

  final String fileName;
  final String? releasedAs;
  final String? folder;
  final Color iconColor;
  final ColorScheme colorScheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final folder = this.folder;
    final releasedAs = this.releasedAs;
    return Container(
      padding: _platePadding,
      decoration: _plate(colorScheme),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _well(colorScheme, Icons.storage_rounded, iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MachineName.fileInFull(fileName),
                if (releasedAs != null)
                  MachineName.releaseInFull(releasedAs, caption: 'Released as'),
                if (folder != null)
                  Semantics(
                    container: true,
                    label: FileInfoSection.folderLabel,
                    value: folder,
                    child: ExcludeSemantics(
                      child: Text(
                        folder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final ColorScheme colorScheme;
  final ThemeData theme;
  final int subtitleMaxLines;

  const _InfoRow({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.colorScheme,
    required this.theme,
    this.subtitle,
    this.subtitleMaxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: _platePadding,
      decoration: _plate(colorScheme),
      child: Row(
        children: [
          _well(colorScheme, icon, iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            // One node, so a screen reader hears a whole thought instead of a
            // title and then a path as two unrelated fragments.
            child: Semantics(
              container: true,
              label: <String>[title, ?subtitle].join(', '),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall!
                          .weight(FontWeight.w600)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: subtitleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
