import 'package:flutter/widgets.dart';

import 'package:cupola/features/dockge/presentation/dockge_agent_lens_button.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/qbittorrent_actions_bar.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The action a service's header carries of its own, or null for the default.
///
/// One answer for both places that draw a service header: the phone's band
/// and the desktop window's tab row, so the two cannot drift apart on which
/// service has which instrument.
Widget? serviceBarAction(ServiceKey service) => switch (service) {
  ServiceKey.qbittorrent => const QbittorrentActionsBar(),
  ServiceKey.dockge => const DockgeAgentLensButton(),
  _ => null,
};
