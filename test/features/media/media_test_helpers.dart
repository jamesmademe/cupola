import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';

import '../../test_helpers/profiles/profiles.dart';

/// The rows of [title] under [profile] once no source is still waiting, and
/// the container that read them.
Future<({List<MediaRow> rows, ProviderContainer container})> settledRows(
  ConfigProfile profile,
  WorldTitle title, {
  MediaKey? key,
}) async {
  final harness = await ProfileHarness.start(profile);
  final container = harness.container();
  key ??= title.isSeries
      ? MediaKey.tv(title.tmdbId)
      : MediaKey.movie(title.tmdbId);
  final rows = mediaRowsProvider(key);
  container.listen(rows, (_, _) {});
  for (var turn = 0; turn < 200; turn++) {
    final now = container.read(rows);
    final waiting = now.any(
      (row) =>
          (row is MediaConnectionRow && row.reading is MediaReadingWaiting) ||
          (row is MediaServerThroughSeerrRow && row.server == null),
    );
    if (!waiting) return (rows: now, container: container);
    await pumpEventQueue();
  }
  fail('a source of ${title.title} never answered under ${profile.id}');
}
