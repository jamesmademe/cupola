/// The download chosen in the desktop's table, which the inspector shows.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ServiceQueueItem;

/// A download as its page's address names it: the connection it was read
/// from and the client's id for the transfer ([downloadPageKey]).
typedef DownloadSelection = ({String instanceId, String key});

/// The selection of [item].
DownloadSelection selectionOf(ServiceQueueItem item) =>
    (instanceId: item.instanceId, key: downloadPageKey(item));

/// Whether [selection] names [item], as its page's address would
/// ([downloadAt]).
bool isSelectedDownload(DownloadSelection? selection, ServiceQueueItem item) =>
    selection != null &&
    downloadAt([item], instanceId: selection.instanceId, key: selection.key) !=
        null;

/// The chosen download, or null for none: the inspector then shows the
/// queue. Kept for the session, never written down: a choice of the moment.
class SelectedDownload extends Notifier<DownloadSelection?> {
  @override
  DownloadSelection? build() => null;

  void select(ServiceQueueItem item) => state = selectionOf(item);

  void clear() => state = null;
}

final selectedDownloadProvider =
    NotifierProvider<SelectedDownload, DownloadSelection?>(
      SelectedDownload.new,
    );
