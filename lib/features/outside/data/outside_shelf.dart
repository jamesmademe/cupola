/// Where what Cupola shows outside itself lives on disk: the snapshot the
/// widgets draw, the pictures it names, and what the notifications have said.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/outside/domain/outside_snapshot.dart';

/// The folder the widgets can read: the App Group's on iOS, which only the
/// native side can name, and the app's own support folder where there is no
/// such thing (Android's widget runs in the app's process and reads it there;
/// a desktop has no widget and keeps it only for the notifications' memory).
Future<Directory> outsideFolder() async {
  try {
    final path = await const MethodChannel(
      'cupola/outside',
    ).invokeMethod<String>('sharedFolder');
    if (path != null && path.isNotEmpty) return Directory(path);
  } on MissingPluginException {
    // No native side: the folder below.
  } on PlatformException {
    // An App Group the build does not carry: the folder below.
  }
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/outside');
}

/// A picture's file name: what names its address, never the address, and
/// nothing of the headers that fetched it.
String outsidePictureName(String url) =>
    '${sha256.convert(utf8.encode(url)).toString().substring(0, 24)}.img';

/// The largest picture kept: a widget draws a poster a few hundred points
/// wide, and a widget's memory is small (about 30 MB on iOS).
const outsidePictureMaxBytes = 1536 * 1024;

/// What a run writes: the snapshot in the file's shape, with the widgets a
/// run did not read kept as they were, and the pictures it names.
typedef OutsidePlan = ({Map<String, Object?> json, Set<String> pictures});

class OutsideShelf {
  OutsideShelf(this.folder);

  final Directory folder;

  File get _snapshot => File('${folder.path}/outside.json');
  File get _said => File('${folder.path}/outside_said.json');
  Directory get pictures => Directory('${folder.path}/outside_pictures');

  /// The snapshot of [snapshot]'s read, over the one on disk: a widget whose
  /// read did not answer (null frames) keeps the frames it had, which say
  /// their own age, rather than go blank because the phone left home. The
  /// file before is dropped whole when it was another person's (the
  /// audience changed) or another version.
  Future<OutsidePlan> plan(
    OutsideSnapshot snapshot, {
    required Set<OutsideWidget> unread,
  }) async {
    final json = snapshot.toJson();
    final before = await _readJson(_snapshot);
    final widgets = Map<String, Object?>.of(
      json['widgets']! as Map<String, Object?>,
    );
    if (before != null &&
        before['version'] == OutsideSnapshot.version &&
        before['audience'] == snapshot.audience &&
        before['widgets'] is Map) {
      final kept = before['widgets'] as Map;
      for (final widget in unread) {
        if (kept[widget.name] case final List frames) {
          widgets[widget.name] = frames;
        }
      }
    }
    json['widgets'] = widgets;
    return (json: json, pictures: _picturesIn(widgets));
  }

  /// Writes [plan], whole or not at all: a widget reading the file while it
  /// is written reads the one before.
  Future<void> write(OutsidePlan plan) =>
      _writeAtomically(_snapshot, jsonEncode(plan.json));

  /// Fetches the pictures [plan] names that are not on disk yet and removes
  /// the ones it no longer names. A picture that cannot be fetched is a
  /// widget without it, never a failed run.
  Future<void> keepPictures(
    OutsidePlan plan,
    Map<String, ImageSource> sources,
    Future<List<int>?> Function(ImageSource source) fetch,
  ) async {
    await pictures.create(recursive: true);
    await Future.wait([
      for (final name in plan.pictures)
        if (sources[name] case final source?)
          () async {
            final file = File('${pictures.path}/$name');
            if (await file.exists()) return;
            try {
              final bytes = await fetch(source);
              if (bytes == null || bytes.length > outsidePictureMaxBytes) {
                return;
              }
              await _writeBytesAtomically(file, bytes);
            } catch (_) {
              // The widget draws without it.
            }
          }(),
    ]);
    await for (final entry in pictures.list()) {
      final name = entry.uri.pathSegments.last;
      if (entry is File && !plan.pictures.contains(name)) {
        try {
          await entry.delete();
        } catch (_) {
          // Gone already, or in use: the next run tries again.
        }
      }
    }
  }

  Future<OutsideSaid> readSaid() async =>
      OutsideSaid.fromJson(await _readJson(_said));

  Future<void> writeSaid(OutsideSaid said) =>
      _writeAtomically(_said, jsonEncode(said.toJson()));

  /// The file at [file] as a map, or null when it is missing or unreadable:
  /// nothing on this shelf is worth a failed run.
  static Future<Map<String, Object?>?> _readJson(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeAtomically(File file, String contents) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(file.path);
  }

  Future<void> _writeBytesAtomically(File file, List<int> bytes) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
  }
}

/// Every picture the frames in [widgets] name.
Set<String> _picturesIn(Object? json) {
  final names = <String>{};
  void walk(Object? node) {
    switch (node) {
      case Map():
        for (final MapEntry(:key, :value) in node.entries) {
          if ((key == 'poster' || key == 'backdrop' || key == 'picture') &&
              value is String) {
            names.add(value);
          } else {
            walk(value);
          }
        }
      case List():
        node.forEach(walk);
    }
  }

  walk(json);
  return names;
}
