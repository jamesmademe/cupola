import 'package:dio/dio.dart';

import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_sync.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_file.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_properties.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_tracker.dart';
import 'package:cupola/features/qbittorrent/domain/models/rss.dart';

class QbittorrentService {
  final QbittorrentClient _client;
  final QbittorrentSync _sync;

  /// [sync] is the connection's own copy (`qbittorrentSyncForProvider`); one
  /// made here starts from nothing, so its first read is the whole state, as
  /// a test or a one-off check wants.
  QbittorrentService(this._client, [QbittorrentSync? sync])
    : _sync = sync ?? QbittorrentSync(_client);

  String? get baseUrl => _client.baseUrl.isNotEmpty ? _client.baseUrl : null;

  Future<bool> authenticate() => _client.authenticate();

  /// Whether the WebUI refused a sign-in and the client is holding it.
  bool get loginRefused => _client.loginRefused;

  /// For a user's explicit Retry only: see
  /// [QbittorrentClient.clearLoginRefusal].
  void clearLoginRefusal() => _client.clearLoginRefusal();

  Future<String> getVersion() => _client.getVersion();

  /// Every torrent and the session's figures, from the connection's copy
  /// after asking what changed ([QbittorrentSync]). What the list, the
  /// Overview, Home and Activity read.
  Future<QbittorrentMainData> mainData() => _sync.read();

  /// Every write below goes through here, so a read in flight when it was
  /// made is not taken as the answer after it ([QbittorrentSync.noteWrite]).
  Future<void> _write(
    String path, {
    Map<String, dynamic>? data,
    FormData? formData,
  }) async {
    _sync.noteWrite();
    await _client.post(path, data: data, formData: formData);
  }

  Future<List<TorrentFile>> getTorrentFiles(String hash) async {
    final response = await _client.get(
      '/api/v2/torrents/files',
      queryParameters: {'hash': hash},
    );

    final List<dynamic> raw = response.data is List
        ? response.data as List<dynamic>
        : [];
    return raw
        .cast<Map<String, dynamic>>()
        .map(TorrentFile.fromJson)
        .toList(growable: false);
  }

  Future<List<TorrentTracker>> getTorrentTrackers(String hash) async {
    final response = await _client.get(
      '/api/v2/torrents/trackers',
      queryParameters: {'hash': hash},
    );

    final List<dynamic> raw = response.data is List
        ? response.data as List<dynamic>
        : [];
    return raw
        .cast<Map<String, dynamic>>()
        .map(TorrentTracker.fromJson)
        .toList(growable: false);
  }

  /// Per-torrent detail (the WebUI General tab). Lets transport / 4xx errors
  /// propagate so the family provider's `AsyncValue.error` is the right
  /// signal: the UI's `_PropRow` renders "—" per cell on `loading`/`error`.
  Future<TorrentProperties> getTorrentProperties(String hash) async {
    final response = await _client.get(
      '/api/v2/torrents/properties',
      queryParameters: {'hash': hash},
    );
    return TorrentProperties.fromJson(response.data as Map<String, dynamic>);
  }

  /// The configured RSS feed tree, including article state when available.
  Future<List<QbittorrentRssFeed>> getRssFeeds() async {
    final response = await _client.get(
      '/api/v2/rss/items',
      queryParameters: const {'withData': true},
    );
    return qbittorrentRssFeedsFromJson(response.data);
  }

  /// RSS auto-download rules keyed by their server-owned names.
  Future<List<QbittorrentRssRule>> getRssRules() async {
    final response = await _client.get('/api/v2/rss/rules');
    return qbittorrentRssRulesFromJson(response.data);
  }

  Future<void> pauseTorrents(List<String> hashes) => _postAcrossTheRename(
    path: '/api/v2/torrents/stop',
    legacyPath: '/api/v2/torrents/pause',
    data: {'hashes': hashes.join('|')},
  );

  Future<void> resumeTorrents(List<String> hashes) => _postAcrossTheRename(
    path: '/api/v2/torrents/start',
    legacyPath: '/api/v2/torrents/resume',
    data: {'hashes': hashes.join('|')},
  );

  /// POSTs to qBittorrent 5.1's spelling of an endpoint, falling back to the
  /// pre-5.1 one when the server has never heard of it.
  ///
  /// 5.1 renamed pause to stop and resume to start. A 4.x or 5.0 server answers
  /// **404** for `/torrents/start` and `/torrents/stop`, so sending only the new
  /// spelling makes the pause and resume buttons controls that fail on every
  /// install older than 5.1, and 404 is the one answer that says "this server
  /// does not have this endpoint" rather than "this request was wrong".
  ///
  /// New spelling first, legacy second, deliberately: `/pause` and `/resume` are
  /// deprecated from 5.1 on and will eventually go, and the fallback costs a
  /// round trip only on the servers that need it.
  Future<void> _postAcrossTheRename({
    required String path,
    required String legacyPath,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _write(path, data: data);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      await _write(legacyPath, data: data);
    }
  }

  Future<void> deleteTorrents(
    List<String> hashes, {
    bool deleteFiles = false,
  }) async {
    await _write(
      '/api/v2/torrents/delete',
      data: {'hashes': hashes.join('|'), 'deleteFiles': deleteFiles.toString()},
    );
  }

  Future<void> addTorrentUrl(
    String url, {
    String? category,
    String? savePath,
  }) async {
    final data = <String, dynamic>{'urls': url};
    if (category != null) data['category'] = category;
    if (savePath != null) data['savepath'] = savePath;

    await _write('/api/v2/torrents/add', data: data);
  }

  Future<void> addTorrentFiles(
    List<MultipartFile> files, {
    String? category,
    String? savePath,
  }) async {
    final form = FormData();
    for (final f in files) {
      form.files.add(MapEntry('torrents', f));
    }
    if (category != null) form.fields.add(MapEntry('category', category));
    if (savePath != null) form.fields.add(MapEntry('savepath', savePath));

    await _write('/api/v2/torrents/add', formData: form);
  }

  Future<void> setCategory(List<String> hashes, String category) async {
    await _write(
      '/api/v2/torrents/setCategory',
      data: {'hashes': hashes.join('|'), 'category': category},
    );
  }

  Future<void> addTags(List<String> hashes, List<String> tags) async {
    await _write(
      '/api/v2/torrents/addTags',
      data: {'hashes': hashes.join('|'), 'tags': tags.join(',')},
    );
  }

  Future<void> removeTags(List<String> hashes, List<String> tags) async {
    await _write(
      '/api/v2/torrents/removeTags',
      data: {'hashes': hashes.join('|'), 'tags': tags.join(',')},
    );
  }

  Future<void> setDownloadLimit(
    List<String> hashes,
    int limitBytesPerSecond,
  ) async {
    await _write(
      '/api/v2/torrents/setDownloadLimit',
      data: {'hashes': hashes.join('|'), 'limit': limitBytesPerSecond},
    );
  }

  Future<void> setUploadLimit(
    List<String> hashes,
    int limitBytesPerSecond,
  ) async {
    await _write(
      '/api/v2/torrents/setUploadLimit',
      data: {'hashes': hashes.join('|'), 'limit': limitBytesPerSecond},
    );
  }

  Future<void> setForceStart(List<String> hashes, bool value) async {
    await _write(
      '/api/v2/torrents/setForceStart',
      data: {'hashes': hashes.join('|'), 'value': value.toString()},
    );
  }

  Future<void> toggleAlternativeSpeedLimits() async {
    await _write('/api/v2/transfer/toggleSpeedLimitsMode');
  }

  Future<void> filePrio({
    required String hash,
    required List<int> fileIndexes,
    required int priority,
  }) async {
    await _write(
      '/api/v2/torrents/filePrio',
      data: {'hash': hash, 'id': fileIndexes.join('|'), 'priority': priority},
    );
  }

  Future<void> recheck(String hash) async {
    await _write('/api/v2/torrents/recheck', data: {'hashes': hash});
  }

  Future<void> reannounce(List<String> hashes) async {
    await _write(
      '/api/v2/torrents/reannounce',
      data: {'hashes': hashes.join('|')},
    );
  }
}
