import 'dart:convert';

import 'package:flutter/services.dart';

/// Loads the app's bundled faces (Bricolage Grotesque, Onest, Geist Mono), so
/// a widget test measures text as the app draws it.
///
/// Without it `flutter_test` sets every string in Ahem, whose glyphs are
/// square and wide: a sentence wraps onto more lines than it does on a phone,
/// and a test that asks whether it fits answers for a screen that does not
/// exist. Call it from `setUpAll`.
Future<void> loadAppFonts() async {
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}
