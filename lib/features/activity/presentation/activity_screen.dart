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

  /// Which connection this screen belongs to, from the route's `?i=`.
  ///
  /// Honoured by the **requests** branch only, and that is the whole of it:
  /// /activity merges every configured Seerr, so a request row can belong to a
  /// server the lens is not on, and it opens this screen. Resolved through the
  /// lens, that row would open somebody else's request list — and every write
  /// on it would land on the wrong server. Null means the lens, which is what
  /// every link that predates a service having two still carries.
  ///
  /// The \*arr branches take no connection: their tabs read through the lens
  /// end to end, so this route deliberately does not hand them one to ignore.
  final String? instanceId;

  const ActivityScreen({super.key, required this.serviceType, this.instanceId});

  Color get _accent => switch (serviceType) {
    ServiceType.movies => ServiceKey.radarr.accent,
    ServiceType.series => ServiceKey.sonarr.accent,
    ServiceType.music => ServiceKey.lidarr.accent,
    ServiceType.discover => ServiceKey.seerr.accent,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Which connection this screen is read through, named only when there is
    // more than one it could be. For the \*arr tabs that is the lens; for the
    // requests list it is the connection the link named, falling back to the
    // lens — the title has to agree with the list under it, and after the
    // Seerr fan-out those two are no longer the same fact.
    final multiple = ref.watch(
      hasMultipleInstancesProvider(serviceType.service),
    );
    final id = instanceId;
    final named = id == null || id.isEmpty
        ? null
        // Selects the resolved instance rather than the list it came out of,
        // for the reason `activeInstanceProvider` documents: a fresh `List`
        // never equals its predecessor, a `ServiceInstance` does.
        : ref.watch(
            currentSettingsProvider.select(
              (s) => s
                  .configuredInstancesOf(serviceType.service)
                  .where((candidate) => candidate.id == id)
                  .firstOrNull,
            ),
          );
    final connection = multiple
        ? (named ?? ref.watch(activeInstanceProvider(serviceType.service)))
        : null;
    final name = connection == null
        ? null
        : ref.watch(connectionNameProvider(connection.id));
    final suffix = name == null ? '' : ' · $name';

    if (!serviceType.supportsArrActivity) {
      return AmbientScaffold(
        accent: _accent,
        appBar: GlassAppBar(title: Text('Requests$suffix')),
        // The id the TITLE resolved to, not the one the link carried. A link
        // naming a connection that has since been removed resolves `named` to
        // null and falls the title back to the lens; handing the dead id to the
        // list as well would put "not configured" under a header naming a
        // server that is up. The two have to be the same fact or neither can be
        // trusted.
        body: RequestsList(instanceId: named == null ? '' : named.id),
      );
    }

    return DefaultTabController(
      length: 2,
      child: AmbientScaffold(
        accent: _accent,
        appBar: GlassAppBar(
          title: Text('${serviceType.displayTitle} Activity$suffix'),
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
