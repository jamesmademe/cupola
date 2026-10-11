/// Stop, Resume and Remove for one download, wherever it is shown: its page,
/// its row of the desktop's table, the inspector.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/activity/data/download_writes.dart';
import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/domain/stuck_download_fault.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart'
    show connectionArrServiceProvider;
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart'
    show writeFailureReason;
import 'package:cupola/features/settings/domain/service_key.dart';

/// Reads the downloads again, and the faults Needs you draws from them.
void invalidateDownloads(WidgetRef ref) {
  for (final source in homeDownloadsSources) {
    ref.invalidate(source);
  }
  ref.invalidate(dashboardDecisionSourceProvider(DecisionSource.queue));
}

/// Asks the client moving [item]'s bytes to stop it, keeping what arrived,
/// or to resume it when [stop] is false; says why when it could not. True
/// once the client answered. The queue is read again after.
Future<bool> stopDownload(
  BuildContext context,
  WidgetRef ref,
  ServiceQueueItem item, {
  required bool stop,
}) async {
  final client = downloadClientOf(item);
  if (client == null) return false;
  try {
    await setDownloadStopped(ref, client, stopped: stop);
  } catch (error) {
    if (context.mounted) {
      SnackBarHelper.error(
        context,
        '${stop ? 'Could not stop' : 'Could not resume'} ${item.sentenceTitle}. '
        '${writeFailureReason(client.client, error)}',
        cause: error,
      );
    }
    return false;
  }
  invalidateDownloads(ref);
  return true;
}

/// Removes [item] after the neutral question Needs you asks: through the
/// \*arr's queue, never the client alone, and the title stays wanted.
/// [onConfirmed] runs once the person said yes, before the write. True once
/// it was removed, which a note says.
Future<bool> removeDownload(
  BuildContext context,
  WidgetRef ref,
  ServiceQueueItem item, {
  VoidCallback? onConfirmed,
}) async {
  final ask = removeConfirmation(item);
  final answer = await showAppConfirmDialog(
    context: context,
    title: ask.title,
    message: ask.message,
    confirmLabel: ask.confirm,
    icon: Icons.delete_outline_rounded,
  );
  if (!answer.confirmed || !context.mounted) return false;
  onConfirmed?.call();
  try {
    await ref
        .read(
          connectionArrServiceProvider((
            _typeOf(item.service),
            item.instanceId,
          )),
        )
        .removeFromQueue(
          int.parse(item.id),
          removeFromClient: true,
          blocklist: false,
        );
  } catch (error) {
    if (context.mounted) {
      SnackBarHelper.error(
        context,
        "Could not remove ${item.sentenceTitle}'s download. "
        '${writeFailureReason(item.service, error)}',
        cause: error,
      );
    }
    return false;
  }
  invalidateDownloads(ref);
  if (context.mounted) {
    SnackBarHelper.success(context, stuckActionNote(StuckAction.remove, item));
  }
  return true;
}

ServiceType _typeOf(ServiceKey service) => switch (service) {
  ServiceKey.sonarr => ServiceType.series,
  ServiceKey.lidarr => ServiceType.music,
  _ => ServiceType.movies,
};
