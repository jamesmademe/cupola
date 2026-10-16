import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// A setting that is on or off: its glyph in a well, what it is, what it
/// does, and the switch. The row of Hints, Background search and
/// Notifications, inside a `SettingsGroupCard`.
///
/// One node to a screen reader: the words and the switch's state are said
/// as one sentence (`Needs you, When a download is stuck…, switch, off`), and
/// a double tap flips it, so the row is one stop and not three.
///
/// [onChanged] null draws the switch where it stands and lets it not move:
/// the setting depends on another one, and [description] says which.
/// [busy] puts a spinner where the switch is while something outside the app
/// answers for it (the OS asking for a permission).
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.note,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// A line under the description about what stands outside the setting:
  /// the system's permission. Its tone, when it has one, is the line's
  /// colour (a permission blocked is amber: something to switch back on,
  /// not something that failed).
  final ({String text, StatusTone? tone})? note;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ExcludeSemantics(
                child: Icon(icon, size: 18, color: colors.primary),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  Text(description, style: quiet),
                  if (note case (:final text, :final tone))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        text,
                        style: tone == null
                            ? quiet
                            : quiet?.copyWith(
                                // Walked against the settings card the row
                                // sits on: the raw yellow is about 1.5:1 on
                                // paper.
                                color: statusToneColor(
                                  colors,
                                  tone,
                                  surface: colors.surfaceContainer,
                                ),
                              ),
                      ),
                    ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
