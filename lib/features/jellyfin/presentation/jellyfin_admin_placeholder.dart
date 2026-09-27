import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A Jellyfin tab whose read only an administrator may make, reached with a
/// credential that is not one.
///
/// **Not an error.** A household member's token is a legitimate way to connect
/// — it plays, browses and controls its own sessions — and the server refusing
/// `/Devices`, `/ScheduledTasks` or `/Library/VirtualFolders` to it is policy
/// working as configured. So this speaks in [NotConfiguredPlaceholder]'s calm
/// voice, not [AppErrorState]'s: what this credential is, what the tab needs,
/// and one door to the connection form where an administrator's key goes.
class JellyfinAdminPlaceholder extends StatelessWidget {
  const JellyfinAdminPlaceholder({
    super.key,
    required this.what,
    required this.connectionId,
    this.topPadding = 0,
  });

  /// What the tab lists, as the tail of a sentence: `devices`,
  /// `scheduled tasks`, `libraries`.
  final String what;

  /// The connection whose form the action opens.
  final String connectionId;

  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: AppEmptyStatePage(
        emptyState: AppEmptyState(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Needs a Jellyfin administrator',
          message:
              'This Jellyfin account can play and browse. Only an '
              'administrator can list $what; use an API key or an '
              'administrator\'s sign-in to see them here.',
          action: FilledButton.icon(
            onPressed: () => context.go(
              ServiceRoutes.settingsForConnection(
                ServiceKey.jellyfin,
                connectionId,
              ),
            ),
            icon: const Icon(Icons.key_outlined, size: 18),
            label: const Text('Update the key'),
          ),
        ),
      ),
    );
  }
}

/// The line under Now playing on a non-administrator connection: its list is
/// only this account's playback, which is true and worth saying once so an
/// empty list is not read as an idle server.
class JellyfinOwnPlaybackNote extends StatelessWidget {
  const JellyfinOwnPlaybackNote({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: AppEmptyState.inline(
      icon: Icons.person_outline_rounded,
      title: 'Showing only this account\'s playback',
      message: 'Other people\'s sessions need an administrator to see.',
    ),
  );
}
