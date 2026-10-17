import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/domain/models/transfer_info.dart';

/// What one connection's qBittorrent holds, as of the last answer of
/// `/api/v2/sync/maindata`: every torrent, and the session's figures.
@immutable
class QbittorrentMainData {
  QbittorrentMainData({required List<Torrent> torrents, required this.transfer})
    : torrents = List.unmodifiable(torrents),
      _byHash = {for (final t in torrents) t.hash: t};

  /// Every torrent, in no particular order: the list sorts and filters on
  /// the phone, as qBittorrent's own WebUI does over the same answer.
  final List<Torrent> torrents;

  /// The session's speeds, totals, limits, alternative-limits switch and
  /// free space, from `server_state`: the keys `/api/v2/transfer/info`
  /// answers with, plus the two that endpoint leaves out.
  final TransferInfo transfer;

  final Map<String, Torrent> _byHash;

  /// The torrent with [hash], or null when the server holds none.
  Torrent? torrent(String hash) => _byHash[hash];
}

/// One connection's copy of what its qBittorrent holds, kept current by
/// `/api/v2/sync/maindata`.
///
/// The list used to be read whole: `/torrents/info` every three seconds, the
/// whole library parsed each time, so a client seeding a thousand torrents cost
/// a phone a megabyte or more of JSON every tick for a page where one figure
/// moved. `maindata` answers with what changed since the response id the client
/// last saw (`rid`): the first answer is the whole state, each later one only
/// the torrents and fields that moved, the ones removed, and the session
/// figures that changed. This class holds the merged state and parses again
/// only the torrents an answer touched.
///
/// **One per connection, beside its client** (`qbittorrentSyncForProvider`),
/// because the server keeps the response ids per session: a second copy
/// asking with its own id would make the server answer twice. A new client
/// (new credentials, a new address) gets a new copy, and its first answer is
/// whole again.
///
/// **Reads go one at a time.** An answer moves the response id, so two in
/// flight would merge out of order. A read asked for while one is in flight
/// joins it, since the poll's two readers (the list and the session figures)
/// tick together and need the same answer, **unless something was written
/// since that read went out** ([noteWrite]): its answer may predate the pause
/// or delete the person just made, so the new read waits for it and then asks
/// again.
///
/// A read that fails changes nothing: the state and the response id stay as
/// they were, the error reaches the provider, and the next read asks from the
/// same point. An answer that says `full_update` replaces everything, which is
/// how the server starts over after a restart or a new session.
class QbittorrentSync {
  QbittorrentSync(this._client, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final QbittorrentClient _client;
  final DateTime Function() _clock;

  int _rid = 0;
  final Map<String, Map<String, dynamic>> _raw = {};
  final Map<String, Torrent> _torrents = {};
  final Map<String, dynamic> _serverState = {};

  Future<QbittorrentMainData>? _pending;
  int _writes = 0;
  int _pendingWrites = 0;

  /// The response id this copy will ask from next: 0 before the first
  /// answer, when the server answers with everything.
  @visibleForTesting
  int get rid => _rid;

  /// Says that something was just written to this connection (a pause, a
  /// delete, a new category), so a read already in flight is no longer the
  /// answer to the next one.
  void noteWrite() => _writes++;

  /// The connection's state, after asking the server what changed.
  Future<QbittorrentMainData> read() {
    final pending = _pending;
    if (pending != null && _pendingWrites == _writes) return pending;

    final writes = _writes;
    final next = _after(pending);
    _pending = next;
    _pendingWrites = writes;
    // Clears the slot once this read is over. On a derived future that
    // swallows the error: the read itself still fails for whoever awaits it.
    unawaited(
      next.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        if (identical(_pending, next)) _pending = null;
      }),
    );
    return next;
  }

  Future<QbittorrentMainData> _after(
    Future<QbittorrentMainData>? previous,
  ) async {
    if (previous != null) {
      try {
        await previous;
      } on Object {
        // Its failure is its caller's: this read asks again from the same id.
      }
    }
    final response = await _client.get(
      '/api/v2/sync/maindata',
      queryParameters: {'rid': _rid},
    );
    final data = response.data;
    if (data is! Map) {
      throw const FormatException('sync/maindata answered something else');
    }
    await _apply(data.cast<String, dynamic>());
    return _snapshot();
  }

  Future<void> _apply(Map<String, dynamic> answer) async {
    final full = parseBool(answer['full_update']);
    final changed = <String, Map<String, dynamic>>{};

    final torrents = answer['torrents'];
    if (torrents is Map) {
      for (final MapEntry(:key, :value) in torrents.entries) {
        if (key is! String || value is! Map) continue;
        final before = _raw[key];
        final merged = full ? <String, dynamic>{} : {...?before};
        merged
          ..addAll(value.cast<String, dynamic>())
          // The hash is the entry's key, not one of its fields.
          ..['hash'] = key;
        _stampResume(merged, before);
        changed[key] = merged;
      }
    }

    final parsed = await _parse(changed);

    // Nothing is replaced until the answer is whole and parsed: a parse that
    // throws leaves the copy as it was, response id included.
    if (full) {
      _raw.clear();
      _torrents.clear();
      _serverState.clear();
    }
    _raw.addAll(changed);
    _torrents.addAll(parsed);
    final removed = answer['torrents_removed'];
    if (removed is List) {
      for (final hash in removed) {
        _raw.remove(hash);
        _torrents.remove(hash);
      }
    }
    final serverState = answer['server_state'];
    if (serverState is Map) {
      _serverState.addAll(serverState.cast<String, dynamic>());
    }
    _rid = parseInt(answer['rid']);
  }

  /// Writes down when this copy saw a stopped torrent start again.
  ///
  /// qBittorrent keeps no such date: `last_activity` is the last byte, so a
  /// torrent stopped for weeks and started a minute ago, still waiting for a
  /// peer, read as stuck for weeks. The moment the state leaves a stopped one
  /// is the only witness, so it is kept on the entry ([kQbittorrentResumedOn])
  /// and survives a full update, which starts the merge from nothing.
  void _stampResume(Map<String, dynamic> merged, Map<String, dynamic>? before) {
    final seen = before?[kQbittorrentResumedOn];
    if (seen != null) merged.putIfAbsent(kQbittorrentResumedOn, () => seen);
    if (before == null) return;
    if (_isStopped(before['state']) && !_isStopped(merged['state'])) {
      merged[kQbittorrentResumedOn] = _clock().millisecondsSinceEpoch ~/ 1000;
    }
  }

  static bool _isStopped(Object? state) =>
      state is String &&
      (state.startsWith('paused') || state.startsWith('stopped'));

  QbittorrentMainData _snapshot() => QbittorrentMainData(
    torrents: _torrents.values.toList(growable: false),
    transfer: TransferInfo.fromJson(_serverState),
  );
}

/// The first answer of a large library is parsed off the UI isolate, as the
/// whole list always was; the small ones after it are not worth the hop.
const int _isolateParseThreshold = 200;

Future<Map<String, Torrent>> _parse(Map<String, Map<String, dynamic>> raw) {
  if (raw.length > _isolateParseThreshold) {
    return compute(_parseTorrents, raw);
  }
  return SynchronousFuture(_parseTorrents(raw));
}

Map<String, Torrent> _parseTorrents(Map<String, Map<String, dynamic>> raw) => {
  for (final MapEntry(:key, :value) in raw.entries)
    key: Torrent.fromJson(value),
};
