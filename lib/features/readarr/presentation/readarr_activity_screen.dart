import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

enum ReadarrActivityMode { queue, wanted }

/// Readarr's queue and wanted tabs share the same raw *arr contract as the
/// other activity clients but do not have a ServiceType (the Activity screen
/// intentionally covers only the three actively maintained arr products).
class ReadarrActivityScreen extends ConsumerStatefulWidget {
  const ReadarrActivityScreen({
    super.key,
    required this.mode,
    this.topPadding = 0,
  });

  final ReadarrActivityMode mode;
  final double topPadding;

  @override
  ConsumerState<ReadarrActivityScreen> createState() =>
      _ReadarrActivityScreenState();
}

class _ReadarrActivityScreenState extends ConsumerState<ReadarrActivityScreen> {
  Future<List<dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    if (ref
        .read(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.readarr)) {
      _future = _load();
    }
  }

  Future<List<dynamic>> _load() {
    final service = ref.read(readarrServiceProvider);
    return widget.mode == ReadarrActivityMode.queue
        ? service.getQueue()
        : service.getAllMissing();
  }

  void _reload() => setState(() => _future = _load());

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
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<dynamic>>(
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
                  ),
                ],
              );
            }
            final items = snapshot.data ?? const <dynamic>[];
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: widget.topPadding),
                children: [
                  AppEmptyState(
                    icon: widget.mode == ReadarrActivityMode.queue
                        ? Icons.download_done_rounded
                        : Icons.manage_search_rounded,
                    title: widget.mode == ReadarrActivityMode.queue
                        ? 'Queue is empty'
                        : 'Nothing missing',
                    message: 'Readarr returned no records for this view.',
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
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) => _ReadarrRecordTile(
                item: Map<String, dynamic>.from(items[index] as Map),
                mode: widget.mode,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReadarrRecordTile extends StatelessWidget {
  const _ReadarrRecordTile({required this.item, required this.mode});

  final Map<String, dynamic> item;
  final ReadarrActivityMode mode;

  @override
  Widget build(BuildContext context) {
    final status = mode == ReadarrActivityMode.queue
        ? resolveQueueDisplayStatus(item)
        : resolveWantedStatus(item, isCutoff: false);
    final theme = Theme.of(context);
    final author = mapOrNull(item['author']);
    final book = mapOrNull(item['book']);
    final title =
        stringOrNull(book?['title'] ?? item['title'] ?? item['sourceTitle']) ??
        stringOrNull(author?['authorName']) ??
        'Readarr record';
    final subtitle = [
      stringOrNull(author?['authorName'] ?? item['authorName']),
      stringOrNull(item['releaseTitle'] ?? item['quality']?['name']),
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppCard.outlined(
        padding: const EdgeInsets.all(12),
        semanticLabel: '$title, ${status.label}',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.weight(FontWeight.w600),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  StatusBadge(info: status),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
