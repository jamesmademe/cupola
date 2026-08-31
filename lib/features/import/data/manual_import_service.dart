import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

final manualImportServiceProvider =
    Provider.family<ManualImportService, ServiceKey>((ref, service) {
      if (!service.supportsManualImport) {
        throw Exception('${service.title} does not support manual import');
      }

      // The seventh place settings became a client, and the only one that was
      // building an `ApiClient` by hand. Three consequences, all fixed by
      // going through the choke point: it read `urlFor`/`apiKeyFor`, so an
      // import always went to the FIRST connection whatever the lens said; it
      // watched the whole `SettingsModel`, so every save rebuilt it; and it
      // never registered `onDispose(close)`, so each of those rebuilds leaked a
      // `Dio`.
      return ManualImportService(
        client: watchApiClient(ref, service),
        service: service,
      );
    });

class ManualImportService {
  final ApiClient client;
  final ServiceKey service;

  const ManualImportService({required this.client, required this.service});

  String get _prefix => '/api/${service.apiVersion}';

  Future<List<ManualImportRootFolder>> getRootFolders() async {
    final response = await client.get('$_prefix/rootfolder');
    return jsonObjects(
      response.data,
      ManualImportRootFolder.fromJson,
    ).where((folder) => folder.path.isNotEmpty).toList(growable: false);
  }

  Future<ManualImportFileSystemResult> getFileSystem(String path) async {
    final response = await client.get(
      '$_prefix/filesystem',
      queryParameters: {
        'path': path,
        'includeFiles': false,
        'allowFoldersWithoutTrailingSlashes': true,
      },
      // Listing a directory on a spun-down or network-mounted volume can stall
      // well past the client default.
      receiveTimeout: kSlowScanReceiveTimeout,
    );
    return ManualImportFileSystemResult.fromJson(stringKeyMap(response.data));
  }

  /// Scans [folder] for importable files.
  ///
  /// [filterExistingFiles] is the service's own switch for hiding files it has
  /// already taken into the library. Left on, a file that was imported earlier
  /// simply never comes back — which is usually what you want, and is also why
  /// "is this one already imported?" had no visible answer. Turn it off to have
  /// the service report them, flagged with the library file they belong to.
  Future<List<ManualImportItem>> getManualImportItems({
    required String folder,
    bool filterExistingFiles = true,
  }) async {
    final response = await client.get(
      '$_prefix/manualimport',
      queryParameters: {
        'folder': folder,
        'filterExistingFiles': filterExistingFiles,
        if (service == ServiceKey.lidarr) 'replaceExistingFiles': false,
      },
      // The server walks the folder, parses each release name and probes every
      // file with MediaInfo before it answers — minutes, not seconds.
      receiveTimeout: kSlowScanReceiveTimeout,
    );
    return jsonObjects(response.data, ManualImportItem.fromJson);
  }

  Future<List<ManualImportLookupResult>> lookup(String term) async {
    final normalized = term.trim();
    if (normalized.isEmpty) return const [];

    final response = await client.get(
      '$_prefix/${_lookupEndpoint()}',
      queryParameters: {'term': normalized},
    );
    return jsonObjects(
      response.data,
      (item) => ManualImportLookupResult.fromJson(service, item),
    ).where((item) => item.id > 0).toList(growable: false);
  }

  Future<List<ManualImportLookupResult>> getLibraryMatches() async {
    final response = await client.get(
      '$_prefix/${_libraryEndpoint()}',
      // The whole library in one payload; large collections are slow to serialise.
      receiveTimeout: kSlowScanReceiveTimeout,
    );
    return jsonObjects(
      response.data,
      (item) => ManualImportLookupResult.fromJson(service, item),
    ).where((item) => item.id > 0).toList(growable: false);
  }

  Future<ManualImportCommandStatus> importItem(
    ManualImportItem item, {
    required ManualImportMode importMode,
  }) async {
    final response = await client.post(
      '$_prefix/command',
      data: {
        'name': 'ManualImport',
        'importMode': importMode.apiValue,
        if (service == ServiceKey.lidarr) 'replaceExistingFiles': false,
        'files': [item.toCommandFileJson(service)],
      },
    );
    return ManualImportCommandStatus.fromJson(stringKeyMap(response.data));
  }

  Future<List<ManualImportEpisode>> getEpisodes({
    required int seriesId,
    int? seasonNumber,
  }) async {
    final response = await client.get(
      '$_prefix/episode',
      queryParameters: {'seriesId': seriesId, 'seasonNumber': ?seasonNumber},
    );
    return jsonObjects(
      response.data,
      ManualImportEpisode.fromJson,
    ).where((item) => item.id > 0).toList(growable: false);
  }

  Future<List<ManualImportAlbum>> getAlbums(int artistId) async {
    final response = await client.get(
      '$_prefix/album',
      queryParameters: {'artistId': artistId},
    );
    return jsonObjects(
      response.data,
      ManualImportAlbum.fromJson,
    ).where((item) => item.id > 0).toList(growable: false);
  }

  Future<List<ManualImportTrack>> getTracks({required int albumId}) async {
    final response = await client.get(
      '$_prefix/track',
      queryParameters: {'albumId': albumId},
    );
    return jsonObjects(
      response.data,
      ManualImportTrack.fromJson,
    ).where((item) => item.id > 0).toList(growable: false);
  }

  Future<List<ManualImportQualityOption>> getQualityOptions() async {
    final response = await client.get('$_prefix/qualitydefinition');
    return jsonObjects(
      response.data,
      ManualImportQualityOption.fromJson,
    ).where((item) => item.id > 0).toList(growable: false);
  }

  Future<List<ManualImportLanguageOption>> getLanguageOptions() async {
    final response = await client.get('$_prefix/language');
    return jsonObjects(
      response.data,
      ManualImportLanguageOption.fromJson,
    ).where((item) => item.id > 0).toList(growable: false);
  }

  /// Hands [files] to the service as one `ManualImport` command.
  ///
  /// [replaceExistingFiles] is Lidarr's own switch for "this batch may overwrite
  /// tracks I already have", and it is the flag a deliberate re-import needs:
  /// without it Lidarr keeps what it holds and the command quietly does nothing.
  /// Radarr and Sonarr decide per file instead — Sonarr from the `episodeFileId`
  /// carried in the file body, Radarr from its own import decision — so the flag
  /// stays out of their payloads.
  Future<ManualImportCommandStatus> startManualImport(
    List<ManualImportItem> files, {
    required ManualImportMode importMode,
    bool replaceExistingFiles = false,
  }) async {
    final response = await client.post(
      '$_prefix/command',
      data: {
        'name': 'ManualImport',
        'importMode': importMode.apiValue,
        if (service == ServiceKey.lidarr)
          'replaceExistingFiles': replaceExistingFiles,
        'files': files
            .map((item) => item.toCommandFileJson(service))
            .toList(growable: false),
      },
    );
    return ManualImportCommandStatus.fromJson(stringKeyMap(response.data));
  }

  Future<ManualImportCommandStatus> getCommand(int commandId) async {
    final response = await client.get('$_prefix/command/$commandId');
    return ManualImportCommandStatus.fromJson(stringKeyMap(response.data));
  }

  String _lookupEndpoint() {
    return switch (service) {
      ServiceKey.radarr => 'movie/lookup',
      ServiceKey.sonarr => 'series/lookup',
      ServiceKey.lidarr => 'artist/lookup',
      _ => throw ArgumentError('${service.title} does not support lookup'),
    };
  }

  String _libraryEndpoint() {
    return switch (service) {
      ServiceKey.radarr => 'movie',
      ServiceKey.sonarr => 'series',
      ServiceKey.lidarr => 'artist',
      _ => throw ArgumentError('${service.title} does not support lookup'),
    };
  }
}
