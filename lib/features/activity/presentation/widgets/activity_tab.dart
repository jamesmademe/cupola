import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_tab_helpers.dart';
import 'package:cupola/features/activity/presentation/widgets/segment_selector.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class ActivityTab extends ConsumerStatefulWidget {
  final ServiceType serviceType;

  const ActivityTab({super.key, required this.serviceType})
    : assert(
        serviceType != ServiceType.discover,
        'ActivityTab does not support ServiceType.discover.',
      );

  @override
  ConsumerState<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends ConsumerState<ActivityTab>
    with ActivityTabHelpers {
  @override
  ServiceKey get failureService => widget.serviceType.service;

  @override
  void readAgain() => _refresh();

  ActivitySegment _selectedSegment = ActivitySegment.queue;
  Key _refreshKey = UniqueKey();

  /// The in-flight request, held in state.
  ///
  /// This used to be created inside `build` — `service.getQueue()` as an
  /// argument — so every rebuild started a fresh request and the
  /// `FutureBuilder` fell back to its waiting state. Switching tabs animated the
  /// `TabBarView`, which rebuilt, which re-fetched, which flashed the spinner
  /// back over content that was already on screen.
  ///
  /// Null until there is a service to ask; see [_configured].
  Future<List<dynamic>>? _items;

  /// Whether the connection [_load] reads is set up.
  ///
  /// Asked before the first read rather than after it. The service provider
  /// throws for a connection that is not set up, and it used to be read in
  /// `initState`, so `/activity/movies` on a stack with no Radarr was not a
  /// page that said so but a build that failed. The lens, because that is the
  /// connection `resolvedArrServiceProvider` hands back.
  bool _configured() => ref.watch(
    activeInstanceProvider(
      widget.serviceType.service,
    ).select((instance) => instance?.isConfigured ?? false),
  );

  Future<List<dynamic>> _load() {
    final service = ref.read(resolvedArrServiceProvider(widget.serviceType));
    return switch (_selectedSegment) {
      ActivitySegment.queue => service.getQueue(),
      ActivitySegment.history => service.getAllHistory(),
      ActivitySegment.blocklist => service.getBlocklist(),
    };
  }

  void _refresh({ActivitySegment? nextSegment}) {
    setState(() {
      if (nextSegment != null) {
        _selectedSegment = nextSegment;
      }
      _refreshKey = UniqueKey();
      _items = _load();
    });
  }

  Widget _buildContentSliver(Future<List<dynamic>> items) {
    return switch (_selectedSegment) {
      ActivitySegment.queue => buildAsyncContentSliver(
        items,
        (item) => QueueItemTile(
          item: item as Map<String, dynamic>,
          serviceType: widget.serviceType,
        ),
      ),
      ActivitySegment.history => buildAsyncContentSliver(
        items,
        (item) => HistoryItemTile(
          item: item as Map<String, dynamic>,
          serviceType: widget.serviceType,
        ),
      ),
      ActivitySegment.blocklist => buildAsyncContentSliver(
        items,
        (item) => BlocklistItemTile(
          item: item as Map<String, dynamic>,
          serviceType: widget.serviceType,
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_configured()) {
      _items = null;
      return NotConfiguredPlaceholder.forService(widget.serviceType.service);
    }
    final items = _items ??= _load();

    return buildRefreshableSegmentedView<ActivitySegment>(
      refreshKey: _refreshKey,
      onRefreshRequested: () => _refresh(),
      segments: ActivitySegment.values,
      selected: _selectedSegment,
      onSegmentChanged: (segment) => _refresh(nextSegment: segment),
      labelBuilder: (segment) => segment.label,
      contentSliver: _buildContentSliver(items),
    );
  }
}
