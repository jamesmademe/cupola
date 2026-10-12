import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a page last drew, kept on disk so a cold start can draw it again at
/// once, said for what it is (old), while the live answer comes.
///
/// **What is kept is what is drawn, never what was downloaded.** A response
/// cache was the obvious design and the wrong one: SABnzbd puts its key in the
/// URL, Seerr's bodies carry the household's email addresses, a library list
/// has no size limit, `/history/since?date=` never asks the same URL twice,
/// and a body replayed under today's clock makes the derivations that read it
/// state things that are no longer true. Each slot here holds the input of
/// one drawing, through a codec its feature writes: instants and not the words
/// made of them (the words are made again against the time of the drawing),
/// artwork as a `StoredImage` that carries no credential, nothing secret.
///
/// **An entry is valid for the connections it was read from**, as they were:
/// address, account, viewer (`validity`, built by the slot's owner). The
/// connection id alone is not enough: it survives a change of address and a
/// sign-in as somebody else, and a slot read for one account must never be
/// drawn for another. An entry whose validity no longer matches is dropped
/// when read.
///
/// One small JSON file in the system's cache folder (`Library/Caches` on iOS),
/// where a file the system may purge and must not back up belongs. Reading it
/// is part of the start, so it is small (each entry capped at [maxEntryBytes])
/// and a start never waits on it for long (`main.dart`). Writes are gathered
/// and written once a burst of answers has passed ([flushDelay]), and when the
/// app leaves the screen.
///
/// The memory-only store ([LastKnownStore.memory]) is what a test and a start
/// with no file get: the same behaviour with nothing written.
class LastKnownStore {
  LastKnownStore.memory() : _file = null;

  LastKnownStore._(this._file, Map<String, LastKnownEntry> entries) {
    _entries.addAll(entries);
  }

  /// Opens the store at [file], with what it holds. A missing, unreadable or
  /// foreign file is an empty store: nothing here is worth a failed start.
  static Future<LastKnownStore> open(File file) async {
    try {
      if (!await file.exists()) return LastKnownStore._(file, const {});
      final decoded = jsonDecode(await file.readAsString());
      return LastKnownStore._(file, _entriesOf(decoded));
    } catch (_) {
      return LastKnownStore._(file, const {});
    }
  }

  /// The version of the file's shape. A file of another version is read as
  /// empty; what changes shape inside one slot is that slot's own `schema`.
  static const version = 1;

  /// The largest entry kept, encoded. A slot that grows past it was asked to
  /// keep something that is not a first screen.
  static const maxEntryBytes = 256 * 1024;

  /// How long the store waits after a write before it writes the file: the
  /// Home's modules answer within a second or two of each other, and one write
  /// for all of them is enough.
  static const flushDelay = Duration(seconds: 2);

  final File? _file;
  final Map<String, LastKnownEntry> _entries = {};
  Timer? _pending;

  /// The entry for [slot], when it was written for [validity] in the same
  /// [schema]; else null, and an entry that no longer matches is forgotten.
  LastKnownEntry? read(
    String slot, {
    required String validity,
    required int schema,
  }) {
    final entry = _entries[slot];
    if (entry == null) return null;
    if (entry.validity != validity || entry.schema != schema) {
      _entries.remove(slot);
      _schedule();
      return null;
    }
    return entry;
  }

  /// Keeps [data] (JSON-encodable) for [slot], read at [takenAt] from the
  /// connections [validity] names. Too large, or not encodable, is not kept,
  /// and the slot's old entry goes with it: an old drawing is not kept in
  /// place of one that could not be.
  void write(
    String slot, {
    required String validity,
    required int schema,
    required Object? data,
    required DateTime takenAt,
  }) {
    final String encoded;
    try {
      encoded = jsonEncode(data);
    } catch (_) {
      if (_entries.remove(slot) != null) _schedule();
      return;
    }
    if (utf8.encode(encoded).length > maxEntryBytes) {
      if (_entries.remove(slot) != null) _schedule();
      return;
    }
    _entries[slot] = LastKnownEntry(
      takenAt: takenAt,
      validity: validity,
      schema: schema,
      data: jsonDecode(encoded),
    );
    _schedule();
  }

  /// Forgets every entry, on disk too: a reset of the app, the last connection
  /// removed.
  Future<void> clear() {
    _entries.clear();
    return flush();
  }

  /// Writes what is pending now, rather than after [flushDelay]: the app is
  /// leaving the screen, and may not come back to finish.
  Future<void> flush() async {
    _pending?.cancel();
    _pending = null;
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      // Written beside the file and moved over it, so a write cut short
      // leaves the last whole file rather than half of a new one.
      final next = File('${file.path}.next');
      await next.writeAsString(jsonEncode(_fileOf(_entries)), flush: true);
      await next.rename(file.path);
    } catch (error) {
      // A full disk or a purged folder costs the next cold start its last
      // known drawing, and nothing else.
      debugPrint('Last known state not written: $error');
    }
  }

  void _schedule() {
    if (_file == null) return;
    _pending?.cancel();
    _pending = Timer(flushDelay, flush);
  }

  static Map<String, Object?> _fileOf(Map<String, LastKnownEntry> entries) => {
    'version': version,
    'entries': {
      for (final MapEntry(:key, :value) in entries.entries)
        key: {
          'takenAt': value.takenAt.toUtc().toIso8601String(),
          'validity': value.validity,
          'schema': value.schema,
          'data': value.data,
        },
    },
  };

  static Map<String, LastKnownEntry> _entriesOf(Object? decoded) {
    if (decoded is! Map || decoded['version'] != version) return const {};
    final entries = decoded['entries'];
    if (entries is! Map) return const {};
    final result = <String, LastKnownEntry>{};
    for (final MapEntry(:key, :value) in entries.entries) {
      if (key is! String || value is! Map) continue;
      final takenAt = DateTime.tryParse('${value['takenAt']}');
      final validity = value['validity'];
      final schema = value['schema'];
      if (takenAt == null || validity is! String || schema is! int) continue;
      result[key] = LastKnownEntry(
        takenAt: takenAt.toLocal(),
        validity: validity,
        schema: schema,
        data: value['data'],
      );
    }
    return result;
  }
}

/// One slot's last drawing: its data (JSON), when it was read, and for which
/// connections.
@immutable
class LastKnownEntry {
  const LastKnownEntry({
    required this.takenAt,
    required this.validity,
    required this.schema,
    required this.data,
  });

  /// When the live answer this drawing came from was read: what the page says
  /// it is as of.
  final DateTime takenAt;
  final String validity;
  final int schema;
  final Object? data;
}

/// The app's store of last drawings. Memory-only unless `main.dart` opens the
/// file, which a test never does.
final lastKnownStoreProvider = Provider<LastKnownStore>(
  (ref) => LastKnownStore.memory(),
);
