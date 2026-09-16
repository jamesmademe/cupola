import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/import/presentation/manual_import_widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

Future<void> showImportServicePickerSheet(BuildContext context) {
  return AppBottomSheet.show<void>(
    context: context,
    title: manualImportTitle,
    subtitle: 'Pick the connection that should take the files',
    icon: Icons.drive_folder_upload_outlined,
    builder: (context) => const _ImportServicePickerSheet(),
  );
}

/// The Activity app bar's way into the wizard.
///
/// It picks a **connection**, not a service. With two Radarrs, a sheet that
/// offers "Radarr" has to resolve that through the lens — and the lens is the
/// one thing the wizard must not be bound by, because the files it moves go
/// into whichever library it was pointed at. The second connection is drawn as
/// its own row rather than behind a second step: two rows are cheaper than two
/// taps, and the row's own label is what makes the choice legible at all.
class _ImportServicePickerSheet extends ConsumerWidget {
  const _ImportServicePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The whole model rather than a `select`: this list is rebuilt from it, a
    // fresh `List` never compares equal to its predecessor, so a select would
    // buy a rebuild edge and no settling. A sheet that lives for one decision
    // can afford what a hot path cannot.
    final settings = ref.watch(currentSettingsProvider);

    return SettingsGroupCard(
      children: [
        for (final service in const [
          ServiceKey.radarr,
          ServiceKey.sonarr,
          ServiceKey.lidarr,
        ])
          ..._rowsFor(
            context,
            service,
            settings.configuredInstancesOf(service),
          ),
      ],
    );
  }

  List<Widget> _rowsFor(
    BuildContext context,
    ServiceKey service,
    List<ServiceInstance> instances,
  ) {
    // No configured connection: the row stays, dimmed by its own destination —
    // the wizard opens and says the service is not set up, which is the fact
    // the user came here to find out. Hiding the row hides the fact.
    if (instances.length < 2) {
      return [
        _row(
          context,
          service: service,
          subtitle: service.manualImportSubtitle,
          instanceId: instances.isEmpty ? null : instances.first.id,
        ),
      ];
    }

    return [
      for (final instance in instances)
        _row(
          context,
          service: service,
          // The glyph is the service, the label is the connection — the same
          // division every multi-connection surface in the app uses.
          subtitle: instance.label,
          instanceId: instance.id,
        ),
    ];
  }

  Widget _row(
    BuildContext context, {
    required ServiceKey service,
    required String subtitle,
    required String? instanceId,
  }) {
    return SettingsCard.grouped(
      leading: Icon(service.icon),
      title: service.title,
      subtitle: subtitle,
      accentColor: service.accent,
      semanticHint: 'starts a ${service.title} manual import',
      onTap: () {
        Navigator.of(context).pop();
        context.push(
          manualImportLocation(
            manualImportBrowsePath,
            service,
            instanceId: instanceId,
          ),
        );
      },
    );
  }
}
