import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/activity_history.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_download_row.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart'
    show serviceWithConnection;

/// One record of what happened: what was imported, in green, with the file
/// it became; a download that failed, in amber, with why. Finished today's
/// row and History's.
class ActivityHistoryRow extends ConsumerWidget {
  const ActivityHistoryRow({
    super.key,
    required this.entry,
    this.divided = false,
  });

  final ArrHistoryEntry entry;

  /// Whether a hairline separates it from the row above.
  final bool divided;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final room = CupolaRoom.of(context);
    final failed = entry.outcome == ArrImportOutcome.failed;
    final tone = statusToneColor(
      scheme,
      failed ? StatusTone.warning : StatusTone.success,
      surface: room.slab,
    );
    final detail = entry.detail;
    final title = detail == null || detail.isEmpty
        ? entry.title
        : '${entry.title} · $detail';
    final event = historyEventLine(entry);
    final source = serviceWithConnection(
      entry.service,
      entry.connectionName,
      joiner: ' ',
    );
    final reason = failed ? entry.reason : null;

    return ActivityRowFrame(
      divided: divided,
      label: title,
      value: [event, ?reason, source].join(', '),
      onTap: () => openArrTitle(
        context,
        service: entry.service,
        mediaId: entry.mediaId,
        instanceId: entry.instanceId,
      ),
      art: HomeRowArt.large(
        posterUrl: entry.posterUrl.isEmpty ? null : entry.posterUrl,
        icon: entry.service.icon,
      ),
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppType.row.copyWith(color: room.ink),
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tone,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  event,
                  style: AppType.meta
                      .weight(FontWeight.w600)
                      .tabular
                      .copyWith(color: tone),
                ),
              ),
            ],
          ),
        ),
        if (reason != null && reason.isNotEmpty)
          Text(
            reason,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
        Text(
          source,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.meta.copyWith(color: room.inkSecondary),
        ),
      ],
    );
  }
}
