import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';

/// Every key of the window, in one sheet: `⌘/`, and the deck's footer, which
/// names it.
///
/// The keys are accelerators; each has its control somewhere in the window.
/// This is where they are learnt all at once, in the order a person reaches
/// for them, from [ShellShortcuts.legend], the same source the bindings and
/// every tooltip read. The requester's sheet leaves out what reaches the
/// stack, which her window has none of.
Future<void> showShortcutsSheet(
  BuildContext context, {
  required bool requester,
}) => showDialog<void>(
  context: context,
  builder: (context) => ShortcutsSheet(requester: requester),
);

class ShortcutsSheet extends StatelessWidget {
  const ShortcutsSheet({super.key, required this.requester});

  final bool requester;

  /// Wide enough for the longest line beside its keys, and no wider.
  static const double width = 440;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dim = CupolaThemeColors.of(context).dimText;
    final rows = [
      for (final entry in ShellShortcuts.legend)
        if (!requester || !entry.operatorOnly) entry,
    ];
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: width),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Keyboard shortcuts',
                        style: AppType.section.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final row in rows)
                MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: AppSpacing.md,
                      top: 5,
                      bottom: 5,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.does,
                            style: AppType.row.copyWith(
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.06,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          child: Text(
                            row.keys,
                            style: AppTheme.chrome(
                              context,
                              size: 12,
                              color: dim,
                            ).mono,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
