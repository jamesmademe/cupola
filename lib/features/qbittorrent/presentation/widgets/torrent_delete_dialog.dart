import 'package:flutter/material.dart';

import 'package:cupola/core/widgets/app_dialog.dart';

/// Result returned by [showTorrentDeleteDialog].
class TorrentDeleteResult {
  final bool confirmed;
  final bool deleteFiles;

  const TorrentDeleteResult({
    required this.confirmed,
    required this.deleteFiles,
  });

  static const cancelled = TorrentDeleteResult(
    confirmed: false,
    deleteFiles: false,
  );
}

/// Shows a confirmation dialog for deleting one or more torrents, with the
/// option to delete their files too. Returns [TorrentDeleteResult.cancelled]
/// when the user dismisses the dialog.
///
/// Built on the shared [showAppConfirmDialog], so it is neutral like every
/// other confirmation: the button says *Delete torrent* until *Delete files* is
/// ticked and *Delete torrent and files* after, and the option's subtitle is
/// the one sentence saying the files cannot come back.
Future<TorrentDeleteResult> showTorrentDeleteDialog({
  required BuildContext context,
  required String title,
  required String message,
  bool multi = false,
}) async {
  final noun = multi ? 'torrents' : 'torrent';
  final result = await showAppConfirmDialog(
    context: context,
    title: title,
    message: message,
    confirmLabel: 'Delete $noun',
    confirmLabelFor: (checked) =>
        checked('deleteFiles') ? 'Delete $noun and files' : 'Delete $noun',
    options: [
      AppConfirmOption(
        key: 'deleteFiles',
        label: 'Delete files',
        subtitle: multi
            ? 'Deletes every selected torrent\'s downloaded files from disk. '
                  'This cannot be undone.'
            : 'Deletes the downloaded files from disk. This cannot be undone.',
      ),
    ],
  );

  if (!result.confirmed) return TorrentDeleteResult.cancelled;
  return TorrentDeleteResult(
    confirmed: true,
    deleteFiles: result.option('deleteFiles'),
  );
}
