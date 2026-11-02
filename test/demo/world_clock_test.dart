import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/demo/world/profiles.dart';

/// What the world calls today stays today whatever the hour the demo opens
/// at: Sprite Fright, the Home's "Out on digital today", is out on digital on
/// the visitor's own day, just after midnight on the last day of a month too.
void main() {
  Future<Object?> get(String url, {String? key}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      if (key != null) request.headers.set('x-api-key', key);
      final response = await request.close();
      return jsonDecode(await response.transform(utf8.decoder).join());
    } finally {
      client.close();
    }
  }

  DateTime dayOf(String iso) {
    final local = DateTime.parse(iso).toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  final spriteFright = WorldTitles.spriteFright;

  for (final now in [
    DateTime(2026, 10, 31),
    DateTime(2026, 10, 31, 0, 25),
    DateTime(2026, 10, 31, 5, 59),
    DateTime(2026, 10, 30, 15),
  ]) {
    group('opened at $now', () {
      final today = DateTime(now.year, now.month, now.day);

      setUp(() {
        final network = ProfileNetwork(demoProfile, now: now)..live();
        addTearDown(network.install());
      });

      test(
        "Radarr's calendar has Sprite Fright out on digital today",
        () async {
          final calendar =
              (await get('${WorldHosts.radarr}/api/v3/calendar'))! as List;
          final movie = calendar.cast<Map<String, Object?>>().firstWhere(
            (m) => m['tmdbId'] == spriteFright.tmdbId,
          );
          expect(dayOf(movie['digitalRelease']! as String), today);
        },
      );

      test("Seerr dates Sprite Fright's digital release today", () async {
        final movie =
            (await get(
                  '${WorldHosts.seerr}/api/v1/movie/${spriteFright.tmdbId}',
                  key: worldKey(WorldIds.seerr),
                ))!
                as Map;
        final dates =
            (((movie['releases']! as Map)['results']! as List).first
                    as Map)['release_dates']!
                as List;
        final digital = dates.cast<Map<String, Object?>>().firstWhere(
          (d) => d['type'] == 4,
        );
        expect(dayOf(digital['release_date']! as String), today);
      });
    });
  }
}
