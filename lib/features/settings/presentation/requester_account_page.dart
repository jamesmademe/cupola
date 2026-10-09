import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/seerr_account_fields.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';

/// `/settings/account`: the requester's account on one Seerr.
///
/// The operator meets the same account inside the connection's form, among
/// its address, its key and its gateway. She runs none of that, so her page
/// holds only what is hers (the spec of the requester, § 7.3): who she is
/// signed in as, signing out and back in, and removing the server from this
/// device. The account block is the form's own ([SeerrAccountFields]), so the
/// two ways in cannot drift.
class RequesterAccountPage extends ConsumerWidget {
  const RequesterAccountPage({super.key, this.instanceId = ''});

  /// The connection, when she asks more than one Seerr; empty, the first.
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(
      currentSettingsProvider.select((settings) {
        final accounts = [
          for (final instance in settings.instancesOf(ServiceKey.seerr))
            if (instance.account != null) instance,
        ];
        return accounts
                .where((instance) => instance.id == instanceId)
                .firstOrNull ??
            accounts.firstOrNull;
      }),
    );

    return AmbientScaffold(
      // No accent: a settings pane has no artwork, so its room is lit by the
      // neutral lamp, the fallback of `AmbientBackground`.
      appBar: const GlassAppBar(title: Text('Account')),
      body: SettingsMasterDetail(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            if (connection != null) ...[
              // The card every settings group wears, so her account reads as
              // part of the same page as the rows under it.
              SettingsGroupCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: SeerrAccountFields(
                      key: ValueKey(connection.id),
                      connection: () =>
                          ref
                              .read(currentSettingsProvider)
                              .instanceById(connection.id) ??
                          connection,
                      // Every way in turned off, an address that is not
                      // Seerr, an address that is not encrypted: each is
                      // fixed in the connection's own form, the operator's,
                      // which is where a server she runs herself is set up.
                      onUseApiKey: () => _openForm(context, connection),
                      onCheckAddress: () => _openForm(context, connection),
                      onUseHttps: () => _openForm(context, connection),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              SettingsGroupCard(
                children: [
                  SettingsCard.grouped(
                    leading: const Icon(Icons.link_off_rounded),
                    title: 'Remove this server',
                    subtitle: 'From this device only',
                    semanticHint: 'asks before removing',
                    onTap: () => _remove(context, ref, connection),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openForm(BuildContext context, ServiceInstance connection) =>
      context.push(
        ServiceRoutes.settingsForConnection(ServiceKey.seerr, connection.id),
      );

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ServiceInstance connection,
  ) async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.link_off_rounded,
      title: 'Remove this server?',
      message:
          'Cupola signs you out and forgets its address. Your requests stay '
          'on the server.',
      confirmLabel: 'Remove this server',
    );
    if (!result.confirmed || !context.mounted) return;
    await ref.read(seerrAccountsProvider).remove(connection.id);
    if (!context.mounted) return;
    SnackBarHelper.info(context, 'Server removed');
    await Navigator.of(context).maybePop();
  }
}
