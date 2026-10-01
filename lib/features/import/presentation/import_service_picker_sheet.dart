import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/import/presentation/manual_import_widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

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
            settings,
            service,
            settings.configuredInstancesOf(service),
          ),
      ],
    );
  }

  List<Widget> _rowsFor(
    BuildContext context,
    SettingsModel settings,
    ServiceKey service,
    List<ServiceInstance> instances,
  ) {
    // No configured connection: the row stays, because hiding it hides the
    // fact. It is dimmed but tappable, says "Not set up", and its tap is the
    // fix: that service's own setup. It used to open the wizard against no
    // connection, which could only fail and offer a Retry that asked nobody.
    if (instances.isEmpty) {
      return [_notSetUpRow(context, service: service)];
    }
    if (instances.length < 2) {
      return [
        _row(
          context,
          service: service,
          subtitle: service.manualImportSubtitle,
          instanceId: instances.first.id,
        ),
      ];
    }

    return [
      for (final instance in instances)
        _row(
          context,
          service: service,
          // The glyph is the service, the label is the connection — the same
          // division every multi-connection surface in the app uses. Named by
          // the app's one rule, so a connection the user never named reads
          // `Radarr 2` rather than a blank line under a second "Radarr".
          subtitle: settings.connectionName(instance.id) ?? service.title,
          instanceId: instance.id,
        ),
    ];
  }

  Widget _row(
    BuildContext context, {
    required ServiceKey service,
    required String subtitle,
    required String instanceId,
  }) {
    return SettingsCard.grouped(
      leading: Icon(service.icon),
      title: service.title,
      subtitle: subtitle,
      accentColor: service.accent,
      semanticHint: 'starts a ${service.title} manual import',
      onTap: () {
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.push(
          manualImportLocation(
            manualImportBrowsePath,
            service,
            instanceId: instanceId,
          ),
        );
      },
    );
  }

  /// A service with nothing set up yet: the cross-service rule, in a row.
  ///
  /// The foreground drains to the one dim the app uses for "precondition
  /// unmet"; the row keeps its full height, its button role and a hint that
  /// names the service. The tap goes straight to that service's setup rather
  /// than raising the toast a `CrossServiceAction` would: this sheet sits over
  /// the page the toast would land on, so the fix has to be the tap itself.
  Widget _notSetUpRow(BuildContext context, {required ServiceKey service}) {
    return Opacity(
      opacity: GatedAffordance.dimmedOpacity,
      child: SettingsCard.grouped(
        leading: Icon(service.icon),
        title: service.title,
        subtitle: StateWord.notSetUp.label,
        accentColor: service.accent,
        semanticHint: 'requires ${service.title}, opens its setup',
        onTap: () {
          final router = GoRouter.of(context);
          Navigator.of(context).pop();
          router.go(ServiceRoutes.setUp(service));
        },
      ),
    );
  }
}
