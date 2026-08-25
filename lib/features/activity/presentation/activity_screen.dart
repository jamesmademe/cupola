import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_tab.dart';
import 'package:cupola/features/activity/presentation/widgets/requests_list.dart';
import 'package:cupola/features/activity/presentation/widgets/wanted_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// Per-service activity screen (reached from a service's library screen).
class ActivityScreen extends ConsumerWidget {
  final ServiceType serviceType;

  const ActivityScreen({super.key, required this.serviceType});

  Color get _accent => switch (serviceType) {
    ServiceType.movies => ServiceKey.radarr.accent,
    ServiceType.series => ServiceKey.sonarr.accent,
    ServiceType.music => ServiceKey.lidarr.accent,
    ServiceType.discover => ServiceKey.seerr.accent,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Which connection this queue is read through, named only when there is
    // more than one it could be. The queue itself needs no change — it already
    // comes from lens-aware providers — but a queue that does not say whose it
    // is invites acting on the wrong server's row.
    final lens = ref.watch(hasMultipleInstancesProvider(serviceType.service))
        ? ref.watch(activeInstanceProvider(serviceType.service))
        : null;
    final lensSuffix = lens == null
        ? ''
        : ' · ${lens.label.isEmpty ? lens.id : lens.label}';

    if (!serviceType.supportsArrActivity) {
      return AmbientScaffold(
        accent: _accent,
        appBar: GlassAppBar(title: Text('Requests$lensSuffix')),
        body: const RequestsList(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: AmbientScaffold(
        accent: _accent,
        appBar: GlassAppBar(
          title: Text('${serviceType.displayTitle} Activity$lensSuffix'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Activity'),
              Tab(text: 'Wanted'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ActivityTab(serviceType: serviceType),
            WantedTab(serviceType: serviceType),
          ],
        ),
      ),
    );
  }
}
