import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/search/domain/arr_add_request.dart';
import 'package:cupola/features/search/presentation/arr_add_form_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Opens the add sheet for [request], against the connection that listed the
/// row — never the lens.
///
/// A top-level function per the house convention for sheet helpers. It reads
/// the connection's name here rather than inside the sheet because
/// [AppBottomSheet.show] takes its header as plain strings.
Future<void> showArrAddSheet(
  BuildContext context,
  WidgetRef ref,
  ArrAddRequest request,
) {
  // Through `connectionTitle`, not `displayTitle`: a lone Radarr must not be
  // announced as "Radarr · 7878" because it kept the name a since-removed
  // sibling made it derive.
  final connectionName = ref
      .read(currentSettingsProvider)
      .connectionTitle(request.instanceId, request.service);

  return AppBottomSheet.show<void>(
    context: context,
    title: request.title,
    // The line the whole sheet turns on. There is no server picker because the
    // section the user tapped under already chose one — so this has to say
    // which, or the choice is invisible.
    subtitle: 'Adding to $connectionName',
    icon: request.service.icon,
    accent: request.service.accent,
    builder: (sheetContext) => _ArrAddSheet(request: request),
  );
}

class _ArrAddSheet extends ConsumerWidget {
  final ArrAddRequest request;

  const _ArrAddSheet({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (instanceId: request.instanceId, service: request.service);
    final state = ref.watch(arrAddFormProvider(args));
    final notifier = ref.read(arrAddFormProvider(args).notifier);

    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error != null) ...[
          _SheetError(message: state.error!, detail: state.errorDetail),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (state.profiles.isNotEmpty) ...[
          _FieldLabel('Quality profile'),
          DropdownButtonFormField<int>(
            key: ValueKey('arr_add_profile_${state.profileId}'),
            initialValue: state.profileId,
            items: [
              for (final profile in state.profiles)
                DropdownMenuItem(value: profile.id, child: Text(profile.name)),
            ],
            onChanged: (value) {
              if (value != null) notifier.selectProfile(value);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (state.metadataProfiles.isNotEmpty) ...[
          _FieldLabel('Metadata profile'),
          DropdownButtonFormField<int>(
            key: ValueKey('arr_add_metadata_${state.metadataProfileId}'),
            initialValue: state.metadataProfileId,
            items: [
              for (final profile in state.metadataProfiles)
                DropdownMenuItem(value: profile.id, child: Text(profile.name)),
            ],
            onChanged: (value) {
              if (value != null) notifier.selectMetadataProfile(value);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (state.rootFolders.isNotEmpty) ...[
          _FieldLabel('Root folder'),
          DropdownButtonFormField<String>(
            key: ValueKey('arr_add_root_${state.rootFolder}'),
            initialValue: state.rootFolder,
            items: [
              for (final path in state.rootFolders)
                DropdownMenuItem(value: path, child: Text(path)),
            ],
            onChanged: (value) {
              if (value != null) notifier.selectRootFolder(value);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Monitored'),
          value: state.monitored,
          onChanged: notifier.setMonitored,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Search now'),
          subtitle: const Text('Start looking for a release straight away'),
          value: state.searchOnAdd,
          onChanged: notifier.setSearchOnAdd,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: state.canSubmit
              ? () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  final connectionName = notifier.connectionName;

                  final error = await notifier.submit(request);
                  if (error != null) {
                    // Deliberately left open, with the sentence inside it: a
                    // snackbar under a modal sheet is a message the user never
                    // reads, and the failure is the one moment the form's
                    // choices are worth keeping.
                    return;
                  }
                  navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text('Added to $connectionName')),
                  );
                }
              : null,
          child: state.isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

/// The two-register failure: the sentence, then the diagnostic under it.
class _SheetError extends StatelessWidget {
  final String message;
  final String? detail;

  const _SheetError({required this.message, this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // The presence rule every failure surface follows: the tone is spent on the
    // glyph, walked against the sheet, and the words stay in text ink. The
    // sentence used to be red too, which put the alarm on the words and read
    // under 4.5:1 on paper.
    final alarm = statusToneColor(
      colorScheme,
      StatusTone.error,
      surface: colorScheme.surfaceContainer,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 18, color: alarm),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, style: theme.textTheme.bodyMedium),
              if (detail != null && detail!.isNotEmpty)
                Text(
                  detail!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
