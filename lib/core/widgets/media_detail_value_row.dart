import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';

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
/// decides whether a pick equal to the current value is worth a write — it is
/// not: a no-op write to a quality profile can still queue a library-wide
/// upgrade sweep.
Future<MediaDetailValueOption<T>?> showMediaValueSheet<T>(
  BuildContext context, {
  required String title,
  required T? value,
  required List<MediaDetailValueOption<T>> options,
  required String currentLabel,
  Color? accent,
  IconData icon = Icons.tune_rounded,
}) {
  if (options.isEmpty) return Future<MediaDetailValueOption<T>?>.value();

  return AppBottomSheet.show<MediaDetailValueOption<T>>(
    context: context,
    title: title,
    // Not the bare name: the selected row already says it, and two nodes reading
    // 'HD-1080p' is one stop too many for a screen reader.
    subtitle: 'Currently $currentLabel',
    icon: icon,
    accent: accent,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          MediaValueOptionRow(
            label: option.label,
            isSelected: option.value == value,
            accent: accent,
            onTap: () => Navigator.of(
              sheetContext,
            ).pop<MediaDetailValueOption<T>>(option),
          ),
      ],
    ),
  );
}

/// One option in a value picker.
///
/// Through [PressableScale] rather than a `ListTile`: that widget is the sole
/// home of the press-scale, the haptic, the Reduce Motion check *and* the button
/// role plus accessible name, and a ~48pt row floods its own ink splash — a
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
