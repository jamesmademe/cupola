import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/import/domain/manual_import_display.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/manual_import_fix_sheet.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/import/presentation/manual_import_review_rows.dart';
import 'package:cupola/features/import/presentation/manual_import_widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Per-file options for a matched file: quality, languages, or a new match.
Future<void> showManualImportAdjustSheet(
  BuildContext context,
  WidgetRef ref,
  ServiceKey service,
  ManualImportItem item,
) {
  final identity = manualImportIdentityFor(service, item);
  return AppBottomSheet.show<void>(
    context: context,
    // Title is the matched identity — the series (or movie, or artist) plus the
    // positional code. Subtitle is the raw file, nothing else. Folding the
    // episode name and the filename into one subtitle line made the sheet's two
    // jobs — "what did this match" and "which file is this" — indistinguishable.
    title: [
      manualImportGroupTitle(service, item),
      if (identity.code != null) identity.code!,
    ].join(' · '),
    subtitle: item.fileName,
    icon: service.icon,
    accent: service.accent,
    bodyPadding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    builder: (sheetContext) => SettingsGroupCard(
      children: [
        SettingsCard.grouped(
          leading: const Icon(Icons.high_quality_rounded),
          title: 'Quality',
          subtitle: item.qualityLabel,
          accentColor: service.accent,
          semanticHint: 'opens the quality picker',
          onTap: () {
            Navigator.of(sheetContext).pop();
            _showQualityPicker(context, ref, service, item);
          },
        ),
        SettingsCard.grouped(
          leading: const Icon(Icons.translate_rounded),
          title: 'Languages',
          subtitle: item.languageLabel,
          accentColor: service.accent,
          semanticHint: 'opens the language picker',
          onTap: () {
            Navigator.of(sheetContext).pop();
            _showLanguagePicker(context, ref, service, item);
          },
        ),
        SettingsCard.grouped(
          leading: const Icon(Icons.swap_horiz_rounded),
          title: 'Change match',
          subtitle:
              'Assign a different '
              '${service.manualImportSubLabel.toLowerCase()} identity',
          accentColor: service.accent,
          semanticHint: 'opens match assignment',
          onTap: () {
            Navigator.of(sheetContext).pop();
            showManualImportFixSheet(
              context: context,
              service: service,
              item: item,
            );
          },
        ),
      ],
    ),
  );
}

Future<void> _showQualityPicker(
  BuildContext context,
  WidgetRef ref,
  ServiceKey service,
  ManualImportItem item,
) async {
  final options = await ref
      .read(manualImportFlowProvider.notifier)
      .getQualityOptions();
  if (!context.mounted) return;

  await AppBottomSheet.show<void>(
    context: context,
    title: 'Select quality',
    icon: Icons.high_quality_rounded,
    accent: service.accent,
    builder: (sheetContext) {
      if (options.isEmpty) {
        return const AppEmptyState.compact(
          icon: Icons.high_quality_rounded,
          title: 'No quality options available',
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            ImportChoiceRow(
              label: option.name,
              selected: option.id == item.qualityId,
              accent: service.accent,
              onSelected: () async {
                Navigator.of(sheetContext).pop();
                await ref
                    .read(manualImportFlowProvider.notifier)
                    .updateItemMetadata(item, quality: option);
              },
            ),
        ],
      );
    },
  );
}

Future<void> _showLanguagePicker(
  BuildContext context,
  WidgetRef ref,
  ServiceKey service,
  ManualImportItem item,
) async {
  final options = await ref
      .read(manualImportFlowProvider.notifier)
      .getLanguageOptions();
  if (!context.mounted) return;

  final selectedIds = item.languageIds.toSet();

  await AppBottomSheet.show<void>(
    context: context,
    title: 'Select languages',
    icon: Icons.translate_rounded,
    accent: service.accent,
    builder: (sheetContext) {
      if (options.isEmpty) {
        return const AppEmptyState.compact(
          icon: Icons.translate_rounded,
          title: 'No language options available',
        );
      }
      return StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              CheckboxListTile(
                value: selectedIds.contains(option.id),
                activeColor: service.accent,
                checkColor: ServiceTheme.foregroundOn(service.accent),
                title: Text(option.name),
                onChanged: (selected) {
                  setState(() {
                    if (selected == true) {
                      selectedIds.add(option.id);
                    } else {
                      selectedIds.remove(option.id);
                    }
                  });
                },
              ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () async {
                final selected = options
                    .where((option) => selectedIds.contains(option.id))
                    .toList(growable: false);
                Navigator.of(sheetContext).pop();
                await ref
                    .read(manualImportFlowProvider.notifier)
                    .updateItemMetadata(item, languages: selected);
              },
              style: FilledButton.styleFrom(
                backgroundColor: service.accent,
                foregroundColor: ServiceTheme.foregroundOn(service.accent),
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Apply languages'),
            ),
          ],
        ),
      );
    },
  );
}
