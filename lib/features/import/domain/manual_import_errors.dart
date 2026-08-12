import 'package:dio/dio.dart';

import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

String mapImportError(Object error, ServiceKey service) {
  if (error is DioException) {
    final title = service.title;
    final status = error.response?.statusCode;
    // A receive timeout means the connection succeeded and $title simply took
    // too long to answer — telling the user to check the URL sends them after
    // the wrong problem.
    if (error.type == DioExceptionType.receiveTimeout) {
      return '$title took too long to answer. Scanning a large folder, or one '
          'on a slow or spun-down drive, can outlast the request — try a '
          'narrower subfolder, or check $title → Activity → Queue in case the '
          'scan is still running.';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return "Couldn't reach $title. Check the URL and that the service is running.";
    }
    if (status == 500) {
      final hint = switch (service) {
        ServiceKey.radarr =>
          "the file's name isn't parseable by $title "
              '(missing year, ambiguous title) or the folder name gives no hint. '
              'Try moving the file into a folder named after the movie and '
              'including the year, e.g. `Title (YEAR)/Title (YEAR).ext`, '
              'then rescan.',
        ServiceKey.sonarr =>
          "the file's name doesn't match a known series/episode pattern, "
              'or the folder name gives no hint. '
              'Try naming the folder after the series, e.g. '
              '`Series Title/S01E01.ext`, then rescan.',
        ServiceKey.lidarr =>
          "the file's name doesn't match a known artist/album/track pattern, "
              'or the folder name gives no hint. '
              'Try organising into `Artist/Album/Track.ext`, then rescan.',
        _ => 'check the service logs for the full error.',
      };
      return '$title returned 500 while processing the manual import. '
          'Check $title → System → Logs for the full error. '
          'Common cause: $hint';
    }
    if (status != null) {
      final data = error.response?.data;
      final message = data is Map ? data['message'] : null;
      final messageStr = message is String && message.isNotEmpty ? message : '';
      return messageStr.isEmpty
          ? '$title returned $status.'
          : '$title returned $status: $messageStr';
    }
    return '$title request failed. Check the URL and that the service is running.';
  }
  if (error is Exception) {
    final s = error.toString();
    // Strip the "Exception: " prefix for a cleaner user-facing message.
    if (s.startsWith('Exception: ')) return s.substring('Exception: '.length);
    return s;
  }
  return error.toString();
}

String? libraryGuardError(ServiceKey service, ManualImportFixAssignment a) {
  if (a.match.id <= 0) {
    return 'This title isn\'t in your ${service.title} library — add it '
        'from the ${_libraryTabLabel(service)} tab first.';
  }
  switch (service) {
    case ServiceKey.sonarr:
      if (a.episodes.isEmpty) {
        return 'Pick at least one episode from your ${service.title} library '
            'before importing.';
      }
    case ServiceKey.lidarr:
      if (a.tracks.isEmpty || a.album == null) {
        return 'Pick an album and at least one track from your ${service.title} '
            'library before importing.';
      }
    case ServiceKey.radarr:
      // Radarr only needs a movieId; match.id > 0 is sufficient.
      break;
    case _:
      return 'This service does not support manual import.';
  }
  return null;
}

String _libraryTabLabel(ServiceKey service) => switch (service) {
  ServiceKey.radarr => 'Movies',
  ServiceKey.sonarr => 'Series',
  ServiceKey.lidarr => 'Music',
  _ => 'Library',
};
