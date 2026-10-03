/// The "On your server" rows in the page's words, against the households.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/media/domain/media_row_view.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../test_helpers/profiles/profiles.dart';
import 'media_test_helpers.dart';

Future<List<String>> _words(ConfigProfile profile, WorldTitle title) async {
  final read = await settledRows(profile, title);
  final settings = read.container.read(currentSettingsProvider);
  return [
    for (final row in read.rows)
      if (mediaRowView(
            row,
            title: (connection) =>
                settings.connectionTitle(connection.id, connection.service),
            now: DateTime(2026, 10, 3),
          )
          case final view?)
        view.spoken,
  ];
}

void main() {
  test('P1, Tears of Steel', () async {
    final words = await _words(Profiles.p1, WorldTitles.tearsOfSteel);
    printOnFailure(words.join('\n'));
    expect(words, hasLength(5));
    expect(words.first, startsWith('Jellyfin. Watched. Available'));
    expect(words[3], contains('DE wanted'));
  });

  test('P4: Seerr is one dimmed row that sets it up', () async {
    final words = await _words(Profiles.p4, WorldTitles.tearsOfSteel);
    expect(
      words.last,
      'Seerr. Requests, cast and trailers need it. Not set up. Set up Seerr',
    );
  });

  test("P5: Radarr is Seerr's claim, with a way to add it", () async {
    final words = await _words(Profiles.p5, WorldTitles.tearsOfSteel);
    expect(words[1], 'Radarr. through Seerr. Available. Add Radarr to Cupola');
  });

  test('P7: Jellyfin did not answer, and offers Retry', () async {
    final words = await _words(Profiles.p7, WorldTitles.tearsOfSteel);
    expect(words.first, 'Jellyfin. Did not answer. Retry');
  });
}
