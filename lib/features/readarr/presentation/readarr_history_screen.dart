import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/readarr/presentation/widgets/readarr_tiles.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Full Readarr history tab. The dashboard's compact "today" provider is
/// intentionally not reused: a tab named History must not silently cap itself
/// to today's three rows.
class ReadarrHistoryScreen extends ConsumerStatefulWidget {
  const ReadarrHistoryScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  ConsumerState<ReadarrHistoryScreen> createState() =>
      _ReadarrHistoryScreenState();
}

class _ReadarrHistoryScreenState extends ConsumerState<ReadarrHistoryScreen> {
  Future<List<ReadarrHistoryItem>>? _future;

  @override
  void initState() {
    super.initState();
    if (ref
        .read(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.readarr)) {
      _future = _load();
    }
  }

  Future<List<ReadarrHistoryItem>> _load() async {
    final records = await ref
        .read(readarrServiceProvider)
        .getHistory(page: 1, pageSize: 100);
    return records
        .whereType<Map>()
        .map(
          (record) =>
              ReadarrHistoryItem.fromJson(Map<String, dynamic>.from(record)),
        )
        .toList(growable: false);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _refresh() async {
    _reload();
    final future = _future!;
    try {
      await future;
    } catch (_) {
      // FutureBuilder owns the error state; RefreshIndicator only needs the
      // same request to settle before it releases its progress affordance.
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.readarr);
    if (!configured) {
      return NotConfiguredPlaceholder.forService(ServiceKey.readarr);
    }

    final future = _future ??= _load();
    return AmbientScaffold(
      accent: ServiceKey.readarr.accent,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ReadarrHistoryItem>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: widget.topPadding),
                children: [AppSkeleton.listRows(count: 6)],
              );
            }
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: widget.topPadding),
                children: [
                  AppErrorState(
                    error: snapshot.error!,
                    onRetry: _reload,
                    serviceName: ServiceKey.readarr.title,
                    service: ServiceKey.readarr,
                  ),
                ],
              );
            }
            final items = snapshot.data ?? const <ReadarrHistoryItem>[];
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: widget.topPadding),
                children: const [
                  AppEmptyState(
                    icon: Icons.history_rounded,
                    title: 'No history yet',
                    message: 'Readarr activity will appear here.',
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                0,
                widget.topPadding + AppSpacing.md,
                0,
                FloatingNavBarMetrics.getScrollViewBottomPadding(context),
              ),
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) =>
                  ReadarrHistoryTile(item: items[index]),
            );
          },
        ),
      ),
    );
  }
}
