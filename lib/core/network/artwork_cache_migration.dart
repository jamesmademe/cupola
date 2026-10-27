import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// The directory `DefaultCacheManager` wrote posters into, under the temporary
/// directory, before the artwork cache moved to its own key.
const legacyArtworkCacheDirectory = 'libCachedImageData';

const _migratedFlag = 'artwork_cache_legacy_removed';

/// Deletes the poster files the default cache left behind, once.
///
/// Those files are not reachable through the new cache, so without this they
/// would sit on the device for good. Best effort and never awaited by startup:
/// a failure is ignored and the flag stays unset, so the next launch tries
/// again. Returns whether this call removed the directory or found nothing.
Future<bool> removeLegacyArtworkCache({
  required SharedPreferences prefs,
  required Future<Directory> Function() temporaryDirectory,
}) async {
  try {
    if (prefs.getBool(_migratedFlag) ?? false) return false;
    final base = await temporaryDirectory();
    final legacy = Directory('${base.path}/$legacyArtworkCacheDirectory');
    if (await legacy.exists()) {
      await legacy.delete(recursive: true);
    }
    await prefs.setBool(_migratedFlag, true);
    return true;
  } catch (_) {
    return false;
  }
}
