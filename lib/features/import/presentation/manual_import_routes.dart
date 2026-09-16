import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

const manualImportPathPrefix = '/import';

/// Station 1 — Locate. Kept at the historical `/browse` path so existing
/// deep links and entry points keep working.
const manualImportBrowsePath = '$manualImportPathPrefix/browse';

/// Station 2 — Review (selection and matching merged into one screen).
const manualImportReviewPath = '$manualImportPathPrefix/review';

/// Station 3 — Track.
const manualImportProgressPath = '$manualImportPathPrefix/progress';

/// Legacy step paths from the four-screen flow. The router redirects both into
/// [manualImportReviewPath] so an old deep link never dead-ends.
const manualImportFolderPath = '$manualImportPathPrefix/folder';
const manualImportMatchPath = '$manualImportPathPrefix/match';

ServiceKey? manualImportServiceFromRoute(String? value) {
  final normalized = value?.trim().toLowerCase();
  for (final service in ServiceKey.values) {
    if (service.supportsManualImport && service.routeParam == normalized) {
      return service;
    }
  }
  return null;
}

/// A wizard location, with the connection it is bound to.
///
/// [instanceId] is the load-bearing one. The flow browses one server's
/// filesystem and moves files into one server's library, and it is bound to
/// that connection for its whole life — so the connection has to travel in the
/// link, exactly like `ServiceRoutes`' own `?i=`. Without it a failed-import row
/// on the HD Radarr opened a wizard pointed at whatever the lens happened to be
/// on, and the files went into the 4K library. That is the one bug in this flow
/// that moves a user's files into the wrong place, which is why the affordance
/// was withheld rather than shipped wrong.
///
/// Empty or null means "whatever the lens is on", which is what every link that
/// predates a service being able to have two connections carries.
String manualImportLocation(
  String path,
  ServiceKey service, {
  int? targetId,
  String? folderPath,
  String? instanceId,
}) {
  return Uri(
    path: path,
    queryParameters: {
      'service': service.routeParam,
      if (targetId != null && targetId > 0) 'targetId': '$targetId',
      if (folderPath != null && folderPath.isNotEmpty) 'path': folderPath,
      if (instanceId != null && instanceId.isNotEmpty) 'i': instanceId,
    },
  ).toString();
}

VoidCallback? openManualImportCallback(
  BuildContext context,
  ServiceKey service,
  int targetId, {
  String? instanceId,
}) {
  if (targetId <= 0) return null;
  return () => context.push(
    manualImportLocation(
      manualImportBrowsePath,
      service,
      targetId: targetId,
      // The detail screen already knows which connection it is reading; a
      // wizard opened from it must not re-resolve that through the lens.
      instanceId: instanceId,
    ),
  );
}

/// Derives a browsable folder from a **history** record's own fields.
///
/// A failed import is the scene manual import exists for, and the queue record
/// that would have carried `outputPath` is gone by the time the failure is in
/// History — so the folder has to come out of the event itself.
///
/// `droppedPath` is where the download client left the release: the folder for
/// a pack, the file itself for a single-file download, which is why it still
/// goes through the same last-segment test as [manualImportFolderFromOutputPath]
/// (the filesystem endpoint lists folders, and handing it a file path returns
/// nothing).
///
/// `importedPath` is the opposite default: it names a file the service *did*
/// place, so it is always trimmed to its parent — never tested, because a
/// library file with no extension the test recognises would otherwise be
/// browsed as if it were a folder.
String? manualImportFolderFromFailedImport({
  String? droppedPath,
  String? importedPath,
}) {
  final dropped = manualImportFolderFromOutputPath(droppedPath);
  if (dropped != null) return dropped;

  final imported = importedPath?.trim();
  if (imported == null || imported.isEmpty) return null;

  final separator = imported.contains('\\') ? '\\' : '/';
  final trimmed = imported.endsWith(separator)
      ? imported.substring(0, imported.length - 1)
      : imported;
  final lastSeparator = trimmed.lastIndexOf(separator);
  if (lastSeparator <= 0) return null;
  return trimmed.substring(0, lastSeparator);
}

/// Derives a browsable folder from a queue item's `outputPath`.
///
/// The \*arr queue reports where the download client put the data — usually a
/// folder, occasionally the file itself for single-file downloads. The
/// filesystem endpoint only lists folders, so a path whose last segment looks
/// like a file name (a short alphanumeric extension) is trimmed to its parent.
/// Separators are preserved as-is: this is the *server's* path, and a Windows
/// \*arr expects its backslashes back.
String? manualImportFolderFromOutputPath(String? outputPath) {
  final path = outputPath?.trim();
  if (path == null || path.isEmpty) return null;

  final separator = path.contains('\\') ? '\\' : '/';
  final trimmed = path.endsWith(separator)
      ? path.substring(0, path.length - 1)
      : path;
  final lastSeparator = trimmed.lastIndexOf(separator);
  if (lastSeparator <= 0) return trimmed.isEmpty ? null : trimmed;

  final lastSegment = trimmed.substring(lastSeparator + 1);
  final dot = lastSegment.lastIndexOf('.');
  final looksLikeFile =
      dot > 0 &&
      dot < lastSegment.length - 1 &&
      lastSegment.length - dot - 1 <= 5 &&
      RegExp(r'^[A-Za-z0-9]+$').hasMatch(lastSegment.substring(dot + 1));

  return looksLikeFile ? trimmed.substring(0, lastSeparator) : trimmed;
}
