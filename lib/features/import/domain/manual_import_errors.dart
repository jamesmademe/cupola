import 'package:dio/dio.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A manual-import failure in the words a person acts on.
///
/// Two failures keep the import's own hint, because only the import knows it:
/// a receive timeout (the scan outlasted the request) and a 500 (the arr
/// could not parse a name). Everything else reads the classification, so a
/// refused key is "Radarr answered but refused the key" rather than
/// "Radarr returned 401", and only silence reads "did not answer".
String mapImportError(Object error, ServiceKey service) {
  final title = service.title;
  if (error is DioException) {
    // A receive timeout means the connection succeeded and $title simply took
    // too long to answer. Telling the user to check the URL sends them after
    // the wrong problem.
    if (error.type == DioExceptionType.receiveTimeout) {
      return '$title took too long to answer. Scanning a large folder, or one '
          'on a slow or spun-down drive, can outlast the request, try a '
          'narrower subfolder, or check $title → Activity → Queue in case the '
          'scan is still running.';
    }
    if (error.response?.statusCode == 500) {
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
              'Try organizing into `Artist/Album/Track.ext`, then rescan.',
        _ => 'check the service logs for the full error.',
      };
      return '$title answered with an error while processing the manual '
          'import. Check $title → System → Logs for the full error. '
          'Common cause: $hint';
    }
  }
  if (isTransportFailure(error)) {
    final reason = classifyConnectionFailure(error);
    final headline = describeFailureOf(service, error).headline;
    if (failureDidNotAnswer(reason)) {
      return '$headline. Check that it is running and reachable from this '
          'device.';
    }
    // The arr's own words, verbatim, when it gave any.
    final said = failureServiceMessage(error);
    final remedy = failureRemedy(
      reason,
      credential: refusedCredentialOf(service),
      gateway: accessGatewayOf(error),
    );
    return [
      '$headline.',
      if (said != null) '$title said: ${said.endsWith('.') ? said : '$said.'}',
      if (remedy != null) '$remedy in Settings.',
    ].join(' ');
  }
  // The app's own message without the type Dart prefixes it with.
  return failureDiagnostic(error);
}

String? libraryGuardError(ServiceKey service, ManualImportFixAssignment a) {
  if (a.match.id <= 0) {
    return 'This title isn\'t in your ${service.title} library, add it '
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
