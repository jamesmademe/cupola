import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The releases each arr will not take again, from the foot of History:
/// what Try another download left behind, and what was refused by hand.
///
/// Every arr's list in one, newest first, until each service's room carries
/// its own.
class ActivityBlocklistPage extends ConsumerWidget {
  const ActivityBlocklistPage({super.key});

  static const _title = 'Blocklist';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(globalBlocklistItemsProvider);
    final feed = read.value;
    final Widget body;
    if (feed == null) {
      body = read.hasError
          ? ListView(
              children: [
                const PageTitle(_title),
                AppErrorState(
                  error: read.error!,
                  service: ServiceKey.radarr,
                  onRetry: () => ref.invalidate(globalBlocklistItemsProvider),
                ),
              ],
            )
          : ListView(
              children: [
                const PageTitle(_title),
                AppSkeleton.listRows(count: 5),
              ],
            );
    } else {
      final failures = feed.failures.toList(growable: false);
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const PageTitle(_title),
          for (final failure in failures)
            if (failure.error case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: BriefFailureLine.line(
                  error: error,
                  service: failure.service,
                  instanceId: failure.instanceId,
                  onRetry: () => ref.invalidate(globalBlocklistItemsProvider),
                ),
              ),
          if (feed.items.isEmpty && failures.isEmpty)
            const AppEmptyState(
              icon: Icons.block_rounded,
              title: 'The blocklist is empty',
              message:
                  'A release an arr will not take again, after Try another '
                  'download or by hand, appears here.',
            ),
          for (final item in feed.items) GlobalActivityItemTile(item: item),
        ],
      );
    }
    return AmbientScaffold(
      appBar: const GlassAppBar.inPage(pageTitle: _title),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(globalBlocklistItemsProvider);
          try {
            await ref.read(globalBlocklistItemsProvider.future);
          } catch (_) {}
        },
        child: body,
      ),
    );
  }
}
