import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';

/// One choice offered by [showMediaValueSheet].
@immutable
class MediaDetailValueOption<T> {
  /// What is written when this option is picked.
  final T value;

  /// What the user reads. The server's own name for the thing, never a
  /// re-worded one: a quality profile called `Ultra-HD` is called that in
  /// Radarr's own UI and renaming it here breaks the only join the user has.
  final String label;

  const MediaDetailValueOption({required this.value, required this.label});
}

/// Opens the sheet that edits one field of a detail page where it is read.
///
/// One field per sheet, deliberately: a sheet carrying four selects is an Edit
/// form with a drag handle, and the app has none.
///
/// Returns the picked option, or null if the sheet was dismissed. The caller
/// decides whether a pick equal to the current value is worth a write. It is
/// not: a no-op write to a quality profile can still queue a library-wide
/// upgrade sweep.
///
/// Past [mediaValueSearchFrom] options the sheet opens on a search field
/// ([searchHint]), which narrows the rows as the user types
/// ([mediaValueMatches]): a season of twenty-four episodes is not scrolled
/// for E17.
Future<MediaDetailValueOption<T>?> showMediaValueSheet<T>(
  BuildContext context, {
  required String title,
  required T? value,
  required List<MediaDetailValueOption<T>> options,
  required String currentLabel,
  Color? accent,
  IconData icon = Icons.tune_rounded,
  String searchHint = 'Search',
}) {
  if (options.isEmpty) return Future<MediaDetailValueOption<T>?>.value();
  final searchable = options.length > mediaValueSearchFrom;

  return AppBottomSheet.show<MediaDetailValueOption<T>>(
    context: context,
    title: title,
    // Not the bare name: the selected row already says it, and two nodes reading
    // 'HD-1080p' is one stop too many for a screen reader.
    subtitle: 'Currently $currentLabel',
    icon: icon,
    accent: accent,
    // The search field keeps its own gutter, as it does on every screen.
    bodyPadding: searchable
        ? const EdgeInsets.only(bottom: AppSpacing.lg)
        : null,
    builder: (sheetContext) {
      Widget row(MediaDetailValueOption<T> option) => MediaValueOptionRow(
        label: option.label,
        isSelected: option.value == value,
        accent: accent,
        onTap: () =>
            Navigator.of(sheetContext).pop<MediaDetailValueOption<T>>(option),
      );
      if (searchable) {
        return MediaValueSearchList<T>(
          options: options,
          hint: searchHint,
          row: row,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [for (final option in options) row(option)],
      );
    },
  );
}

/// How many options a value sheet lists before it offers a search: twelve
/// rows fit a phone's sheet, and a few more are still read at a glance.
const mediaValueSearchFrom = 12;

/// Whether [label] answers [query], ignoring case. A number is a whole
/// number: `4` finds `E4` and `Track 4`, never `E14` or `E40`.
bool mediaValueMatches(String label, String query) {
  final words = query.trim().toLowerCase();
  if (words.isEmpty) return true;
  final pattern = [
    if (RegExp(r'^\d').hasMatch(words)) r'(?<!\d)',
    RegExp.escape(words),
    if (RegExp(r'\d$').hasMatch(words)) r'(?!\d)',
  ].join();
  return RegExp(pattern).hasMatch(label.toLowerCase());
}

/// A long value sheet's body: the search field over the options, and the
/// options that answer it ([mediaValueMatches]), or that none does.
class MediaValueSearchList<T> extends StatefulWidget {
  const MediaValueSearchList({
    super.key,
    required this.options,
    required this.hint,
    required this.row,
  });

  final List<MediaDetailValueOption<T>> options;

  /// What the field asks for: `Episode number or title`.
  final String hint;

  /// The row an option is drawn as ([MediaValueOptionRow]).
  final Widget Function(MediaDetailValueOption<T> option) row;

  @override
  State<MediaValueSearchList<T>> createState() =>
      _MediaValueSearchListState<T>();
}

class _MediaValueSearchListState<T> extends State<MediaValueSearchList<T>> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final option in widget.options)
        if (mediaValueMatches(option.label, _query)) option,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SearchBarHeader(
          hintText: widget.hint,
          debounceDuration: Duration.zero,
          onQueryChanged: (query) => setState(() => _query = query),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in shown) widget.row(option),
              if (shown.isEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: MediaValueOptionRow.rowHeight,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'Nothing matches "$_query"',
                      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                        color: CupolaThemeColors.of(context).dimText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Radarr/Sonarr/Lidarr quality profiles as picker options.
///
/// The arr clients all hand these back as untyped `{'id': int, 'name': String}`
/// maps, so the cast lives in exactly one place instead of at every call site.
/// Entries missing either key are dropped rather than rendered as a blank row
/// with an id behind it.
List<MediaDetailValueOption<int>> qualityProfileOptions(
  List<Map<String, dynamic>> qualityProfiles,
) {
  return [
    for (final profile in qualityProfiles)
      if (profile['id'] is int && profile['name'] is String)
        MediaDetailValueOption<int>(
          value: profile['id'] as int,
          label: profile['name'] as String,
        ),
  ];
}

/// One option in a value picker.
///
/// Through [PressableScale] rather than a `ListTile`: that widget is the sole
/// home of the press-scale, the haptic, the Reduce Motion check *and* the button
/// role plus accessible name, and a ~48pt row floods its own ink splash: a
/// flooded ripple reads as selection rather than as a touch, which is precisely
/// the wrong signal on a row where one sibling genuinely *is* selected.
class MediaValueOptionRow extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? accent;
  final VoidCallback onTap;

  const MediaValueOptionRow({
    super.key,
    required this.label,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  /// Tall enough for a thumb on a phone and for a pointer on a window; the same
  /// height the app's other action rows use.
  static const double rowHeight = HeaderActionRow.buttonHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = accent ?? colorScheme.primary;
    final selectedInk = ServiceTheme.onTint(
      accentColor,
      surface: colorScheme.surfaceContainer,
      tintAlpha: 0,
    );

    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      semanticValue: isSelected ? 'Selected' : null,
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: rowHeight),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: ActionStateGlyph.glyphSize,
              color: isSelected ? selectedInk : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: isSelected
                    ? theme.textTheme.bodyLarge!
                          .weight(FontWeight.w600)
                          .copyWith(color: selectedInk)
                    : theme.textTheme.bodyLarge!.weight(FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
