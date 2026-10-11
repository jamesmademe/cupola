import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/settings/data/stream_player_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_choice_row.dart';
import 'package:cupola/features/stream/data/stream_app_launcher.dart';
import 'package:cupola/features/stream/domain/stream_players.dart';

/// Whether this device plays a Jellyfin title in an app of the viewer's
/// choosing: a phone, where those apps exist. Elsewhere the browser, as before.
bool playsOnPhone() =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

/// Plays [itemId] on [server], in the app the viewer chooses.
///
/// Only Jellyfin on a phone has a choice. Anything else opens [webUrl] in the
/// browser with no sheet, as it always did. On Jellyfin the order is:
///
///  1. the app the viewer remembered, while it is still installed, straight
///     away; one uninstalled since is forgotten, and the sheet shows;
///  2. the browser alone, when no app is installed: opened, no sheet;
///  3. otherwise the sheet, one row per installed player with the browser last,
///     and a box to remember the choice.
///
/// Nothing is preferred by default. [title] is what the sheet names the item.
Future<void> playWith(
  BuildContext context,
  WidgetRef ref, {
  required ServiceInstance server,
  required String itemId,
  required String title,
  Uri? webUrl,
}) async {
  if (server.service != ServiceKey.jellyfin || !playsOnPhone()) {
    await _open(context, ref, StreamPlayer.web, webUrl);
    return;
  }

  final serverId = await _jellyfinServerId(ref, server.id);
  final userId = server.viewerId.trim();
  final links = <StreamPlayer, Uri>{};
  for (final player in StreamPlayer.values) {
    if (!player.platforms.contains(defaultTargetPlatform)) continue;
    final link = player.link(
      itemId: itemId,
      serverId: serverId,
      userId: userId,
      webUrl: webUrl,
    );
    if (link != null) links[player] = link;
  }
  final installed = await _installed(ref, links);
  if (!context.mounted || installed.isEmpty) return;

  final remembered = ref.read(streamPlayerChoiceProvider);
  if (remembered != null) {
    if (installed.contains(remembered)) {
      await _open(context, ref, remembered, links[remembered]);
      return;
    }
    // Uninstalled since it was chosen: forgotten, and the viewer is asked.
    ref.read(streamPlayerChoiceProvider.notifier).set(null);
  }

  if (installed.length == 1 && installed.single == StreamPlayer.web) {
    await _open(context, ref, StreamPlayer.web, links[StreamPlayer.web]);
    return;
  }

  if (!context.mounted) return;
  final choice = await AppBottomSheet.show<(StreamPlayer, bool)>(
    context: context,
    title: 'Play with',
    subtitle: title,
    showClose: true,
    builder: (_) => _PlayWithSheet(players: installed),
  );
  if (choice == null || !context.mounted) return;
  final (player, remember) = choice;
  if (remember) ref.read(streamPlayerChoiceProvider.notifier).set(player);
  await _open(context, ref, player, links[player]);
}

/// Opens [link] in [player]'s app. A failure says so once.
Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  StreamPlayer player,
  Uri? link,
) async {
  final opened =
      link != null && await ref.read(streamAppLauncherProvider).open(link);
  if (!opened && context.mounted) {
    SnackBarHelper.error(context, 'Could not open ${player.label}');
  }
}

/// The players among [links] that can be opened: the browser always, an app
/// when the platform says one claims its scheme. In the order of
/// [StreamPlayer.values], the browser last.
Future<List<StreamPlayer>> _installed(
  WidgetRef ref,
  Map<StreamPlayer, Uri> links,
) async {
  final launcher = ref.read(streamAppLauncherProvider);
  final installed = <StreamPlayer>[];
  for (final player in StreamPlayer.values) {
    final link = links[player];
    if (link == null) continue;
    if (player == StreamPlayer.web || await launcher.canOpen(link)) {
      installed.add(player);
    }
  }
  return [
    ...installed.where((player) => player != StreamPlayer.web),
    if (installed.contains(StreamPlayer.web)) StreamPlayer.web,
  ];
}

/// The server's own id, or null when it is not known: Swiftfin is then not
/// offered.
Future<String?> _jellyfinServerId(WidgetRef ref, String instanceId) async {
  try {
    return await ref.read(jellyfinServerIdProvider(instanceId).future);
  } catch (_) {
    return null;
  }
}

/// The choice of the player, one row each, the browser last. Tapping one
/// chooses it; the box says whether to remember it.
class _PlayWithSheet extends StatefulWidget {
  const _PlayWithSheet({required this.players});

  final List<StreamPlayer> players;

  @override
  State<_PlayWithSheet> createState() => _PlayWithSheetState();
}

class _PlayWithSheetState extends State<_PlayWithSheet> {
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Nothing is chosen until the viewer taps: no row carries a check.
        for (final player in widget.players)
          SettingsChoiceRow(
            label: player.label,
            description: player.line,
            selected: false,
            onSelected: () => Navigator.of(context).pop((player, _remember)),
          ),
        const SizedBox(height: AppSpacing.sm),
        CheckboxListTile(
          value: _remember,
          onChanged: (value) => setState(() => _remember = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          title: const Text('Remember my choice'),
          // The secondary ink, as every subtitle.
          subtitle: Text(
            'Change it in Settings, on your Jellyfin connection.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The Settings choice of the app a Jellyfin title plays in: `Ask every time`,
/// or one of the players installed here, the browser last. Chosen in a sheet,
/// saved at once.
Future<void> chooseStreamPlayer(BuildContext context, WidgetRef ref) async {
  final launcher = ref.read(streamAppLauncherProvider);
  final installed = <StreamPlayer>[];
  for (final player in StreamPlayer.values) {
    final probe = player.probe;
    if (probe != null && await launcher.canOpen(probe)) installed.add(player);
  }
  // The browser last, as in the sheet that plays a title.
  installed.add(StreamPlayer.web);
  if (!context.mounted) return;
  await AppBottomSheet.show<void>(
    context: context,
    title: 'Play with',
    subtitle: 'Jellyfin titles',
    showClose: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(streamPlayerChoiceProvider);
        void choose(StreamPlayer? player) {
          ref.read(streamPlayerChoiceProvider.notifier).set(player);
          Navigator.of(sheetContext).pop();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsChoiceRow(
              label: 'Ask every time',
              selected: current == null,
              onSelected: () => choose(null),
            ),
            for (final player in installed)
              SettingsChoiceRow(
                label: player.label,
                description: player.line,
                selected: current == player,
                onSelected: () => choose(player),
              ),
          ],
        );
      },
    ),
  );
}
