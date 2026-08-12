import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';

/// Opens the quality profile picker.
///
/// A top-level function rather than a static, per the house convention for sheet
/// helpers — and it exists as a function at all so the detail actions overflow
/// can open the picker directly. There the sheet row *is* the tap target, so
/// there is no button to host it.
///
/// Returns after [onProfileSelected] has been awaited, and only calls it when
/// the chosen profile actually differs from [currentProfileId] — a no-op write
/// to a quality profile can queue a library-wide upgrade sweep.
///
/// [accent] lights the sheet and the selected row. Pass the page's service
/// accent; without it the picker would put `colorScheme.primary` indigo on a
/// Sonarr violet page, which is a second accent on one screen.
Future<void> showMediaProfileSelector(
  BuildContext context, {
  required String currentProfileName,
  required int? currentProfileId,
  required List<Map<String, dynamic>> qualityProfiles,
  required Future<void> Function(int profileId) onProfileSelected,
  Color? accent,
  bool enableHaptics = true,
}) async {
  if (qualityProfiles.isEmpty) return;

  if (enableHaptics) {
    HapticFeedback.selectionClick();
  }

  final selectedId = await AppBottomSheet.show<int>(
    context: context,
    title: 'Quality profile',
    // Not the bare name: the selected row already says it, and two nodes reading
    // "HD-1080p" is one stop too many for a screen reader.
    subtitle: 'Currently $currentProfileName',
    icon: Icons.tune_rounded,
    accent: accent,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final profile in qualityProfiles)
          _ProfileRow(
            name: profile['name'] as String,
            isSelected: (profile['id'] as int) == currentProfileId,
            accent: accent,
            onTap: () =>
                Navigator.of(sheetContext).pop<int>(profile['id'] as int),
          ),
      ],
    ),
  );

  if (selectedId != null && selectedId != currentProfileId) {
    await onProfileSelected(selectedId);
  }
}

/// One profile row in the picker.
///
/// Through [PressableScale] rather than a `ListTile`: that widget is the sole
/// home of the press-scale, the haptic, the Reduce Motion check *and* the button
/// role plus accessible name, and a ~48pt row floods its own ink splash — a
/// flooded ripple reads as selection rather than as a touch, which is precisely
/// the wrong signal on a row where one sibling genuinely *is* selected.
class _ProfileRow extends StatelessWidget {
  final String name;
  final bool isSelected;
  final Color? accent;
  final VoidCallback onTap;

  const _ProfileRow({
    required this.name,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

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
      semanticLabel: name,
      semanticValue: isSelected ? 'Selected' : null,
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: HeaderActionRow.buttonHeight,
        ),
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
                name,
                style: isSelected
                    ? theme.textTheme.bodyLarge!
                          .weight(FontWeight.w700)
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
