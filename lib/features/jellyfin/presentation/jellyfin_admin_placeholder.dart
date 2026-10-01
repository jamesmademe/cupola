import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What a Jellyfin read only an administrator may make says, reached with a
/// household member's token: the placeholder's title, and the Overview's
/// Libraries region on its own.
const jellyfinNeedsAdministratorTitle = 'Needs a Jellyfin administrator';

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
          title: jellyfinNeedsAdministratorTitle,
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
///
/// Activity reads every connection and says it once per connection whose
/// token is a non-administrator's, naming that one when there are two.
class JellyfinOwnPlaybackNote extends StatelessWidget {
  const JellyfinOwnPlaybackNote({
    super.key,
    this.server,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  });

  /// The connection's name when the household has two Jellyfin servers
  /// (`Jellyfin Cabin`); null where there is no other to tell it from.
  final String? server;

  /// Around the note. Activity's list pads its rows itself.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: AppEmptyState.inline(
      icon: Icons.person_outline_rounded,
      title: 'Showing only this account\'s playback',
      message: server == null
          ? 'Other people\'s sessions need an administrator to see.'
          : 'Other people\'s sessions on $server need an administrator to '
                'see.',
    ),
  );
}
