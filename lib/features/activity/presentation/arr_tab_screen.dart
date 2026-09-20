import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_tab_helpers.dart';
import 'package:cupola/features/activity/presentation/widgets/segment_selector.dart';
import 'package:cupola/features/activity/presentation/widgets/sonarr_wanted_hierarchy.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

enum ArrTabMode { queue, wanted, history }

/// A tab-sized view over the shared *arr activity contract.
///
/// The per-service Activity page remains a useful aggregate view, but it has
/// its own three-way selector. A service bar needs one stable destination per
/// label, so this screen keeps the selected tab as the only content and leaves
/// the wanted/cutoff distinction as the one meaningful second axis.
///
/// **What it draws is the same as `WantedTab`/`ActivityTab`, deliberately.**
/// The two surfaces disagreeing is the defect, not the duplication: a Sonarr
/// Wanted list is a flat wall of episode rows until it is grouped by series
/// and season, and a Radarr cutoff row without its quality-profile name does
/// not say what cutoff it is failing. Both behaviours live in widgets those
/// pages already share — [SonarrWantedHierarchy] and `WantedItemTile`'s
/// `qualityProfileName` — so this screen calls them rather than growing a
/// second, shallower rendering of the same records.
class ArrTabScreen extends ConsumerStatefulWidget {
  const ArrTabScreen({
    super.key,
    required this.serviceType,
    required this.mode,
    this.topPadding = 0,
  });

  final ServiceType serviceType;
  final ArrTabMode mode;
  final double topPadding;

  @override
  ConsumerState<ArrTabScreen> createState() => _ArrTabScreenState();
}

class _ArrTabScreenState extends ConsumerState<ArrTabScreen> {
  WantedSegment _wantedSegment = WantedSegment.missing;
  Future<List<dynamic>>? _future;

  /// Radarr's quality profiles, resolved once per load.
  ///
  /// Only the cutoff view needs them, and only Radarr: Sonarr's rows carry
  /// their cutoff through the hierarchy instead.
  Future<Map<int, String>>? _movieQualityProfiles;

  ServiceKey get _service => switch (widget.serviceType) {
    ServiceType.movies => ServiceKey.radarr,
    ServiceType.series => ServiceKey.sonarr,
    ServiceType.music => ServiceKey.lidarr,
    ServiceType.discover => throw UnsupportedError(
      'Seerr does not expose an arr activity tab',
    ),
  };

  bool get _isCutoff => _wantedSegment == WantedSegment.cutoffUnmet;

  @override
  void initState() {
    super.initState();
    if (ref.read(currentSettingsProvider).isServiceConfigured(_service)) {
      _future = _load();
    }
  }

  Future<List<dynamic>> _load() {
    final service = ref.read(resolvedArrServiceProvider(widget.serviceType));
    return switch (widget.mode) {
      ArrTabMode.queue => service.getQueue(),
      ArrTabMode.history => service.getAllHistory(),
      ArrTabMode.wanted => switch (_wantedSegment) {
        WantedSegment.missing => service.getAllMissing(),
        WantedSegment.cutoffUnmet => service.getAllCutoff(),
      },
    };
  }

  void _reload() => setState(() {
    _movieQualityProfiles = null;
    _future = _load();
  });

  void _selectWanted(WantedSegment segment) {
    if (_wantedSegment == segment) return;
    setState(() {
      _wantedSegment = segment;
      _movieQualityProfiles = null;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(_service);
    if (!configured) {
      return NotConfiguredPlaceholder.forService(_service);
    }

    // The request is held in state, so moving the instance lens would
    // otherwise leave the previous server's rows on screen under the new
    // connection's label.
    ref.listen(activeInstanceProvider(_service), (previous, next) {
      if (previous?.id == next?.id) return;
      _reload();
    });

    final future = _future ??= _load();
    return AmbientScaffold(
      accent: _service.accent,
      body: RefreshIndicator(
        // Awaited: `_reload` is synchronous, so returning straight from it
        // snapped the spinner away before the new request had left the device.
        onRefresh: () async {
          _reload();
          await _future;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(0, widget.topPadding, 0, 96),
          children: [
            if (widget.mode == ArrTabMode.wanted)
              SelectionPills<WantedSegment>(
                values: WantedSegment.values,
                selected: _wantedSegment,
                labelBuilder: (segment) => segment.label,
                onSelected: _selectWanted,
              ),
            FutureBuilder<List<dynamic>>(
              future: future,
              builder: (context, snapshot) => _content(context, snapshot),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AsyncSnapshot<List<dynamic>> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return AppSkeleton.listRows(count: 6);
    }
    if (snapshot.hasError) {
      return AppErrorState(error: snapshot.error!, onRetry: _reload);
    }

    final items = snapshot.data ?? const <dynamic>[];
    if (items.isEmpty) {
      final label = switch (widget.mode) {
        ArrTabMode.queue => 'Queue is empty',
        ArrTabMode.history => 'No history yet',
        ArrTabMode.wanted =>
          _isCutoff ? 'Everything meets its cutoff' : 'Nothing missing',
      };
      return AppEmptyState(
        icon: switch (widget.mode) {
          ArrTabMode.queue => Icons.download_done_rounded,
          ArrTabMode.history => Icons.history_rounded,
          ArrTabMode.wanted => Icons.manage_search_rounded,
        },
        title: label,
        message: 'The service returned no records for this view.',
      );
    }

    final service = ref.read(resolvedArrServiceProvider(widget.serviceType));

    // Sonarr's Wanted list is episodes, and a flat wall of them is unreadable
    // — which series, which season, how many. The grouped rendering is the
    // same one `/activity` uses.
    if (widget.mode == ArrTabMode.wanted &&
        widget.serviceType == ServiceType.series) {
      return SonarrWantedHierarchy(
        items: items,
        service: service as SonarrService,
        isCutoff: _isCutoff,
      );
    }

    // A Radarr cutoff row has to name the profile whose cutoff it is failing,
    // or "cutoff unmet" is a claim with no referent.
    if (widget.mode == ArrTabMode.wanted &&
        widget.serviceType == ServiceType.movies &&
        _isCutoff) {
      _movieQualityProfiles ??= _loadMovieQualityProfiles(
        service as RadarrService,
      );
      return FutureBuilder<Map<int, String>>(
        future: _movieQualityProfiles,
        builder: (context, profileSnapshot) => _rows(
          context,
          items,
          service,
          qualityProfiles: profileSnapshot.data ?? const <int, String>{},
        ),
      );
    }

    return _rows(context, items, service);
  }

  Widget _rows(
    BuildContext context,
    List<dynamic> items,
    ArrActivityMixin service, {
    Map<int, String> qualityProfiles = const {},
  }) {
    return Column(
      children: [
        for (final item in items)
          _row(context, item, service, qualityProfiles: qualityProfiles),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    dynamic value,
    ArrActivityMixin service, {
    required Map<int, String> qualityProfiles,
  }) {
    final item = value is Map<String, dynamic>
        ? value
        : Map<String, dynamic>.from(value as Map);
    return switch (widget.mode) {
      ArrTabMode.queue => QueueItemTile(
        item: item,
        serviceType: widget.serviceType,
      ),
      ArrTabMode.history => HistoryItemTile(
        item: item,
        serviceType: widget.serviceType,
      ),
      ArrTabMode.wanted => _wantedRow(
        context,
        item,
        service,
        qualityProfiles: qualityProfiles,
      ),
    };
  }

  Widget _wantedRow(
    BuildContext context,
    Map<String, dynamic> item,
    ArrActivityMixin service, {
    required Map<int, String> qualityProfiles,
  }) {
    final canSearch = extractWantedItemId(widget.serviceType, item) != null;
    final profileId = intOrNull(item['qualityProfileId']);
    return WantedItemTile(
      item: item,
      serviceType: widget.serviceType,
      isCutoff: _isCutoff,
      qualityProfileName: profileId == null ? null : qualityProfiles[profileId],
      onAutoSearch: canSearch
          ? () =>
                runWantedAutoSearch(context, service, widget.serviceType, item)
          : null,
      onInteractiveSearch: canSearch
          ? () => showWantedInteractiveSearch(
              context,
              ref,
              widget.serviceType,
              item,
            )
          : null,
    );
  }

  Future<Map<int, String>> _loadMovieQualityProfiles(
    RadarrService service,
  ) async {
    final profiles = await service.getQualityProfiles();
    final mapped = <int, String>{};
    for (final profile in profiles) {
      final id = intOrNull(profile['id']);
      final name = stringOrNull(profile['name']);
      if (id != null && name != null) mapped[id] = name;
    }
    return mapped;
  }
}
