import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/presentation/stream_library_screen.dart';

/// The line under a library's name counts it in the unit it browses in.
void main() {
  test('movies, series, and music in each server\'s own unit', () {
    const jellyfin = ServiceKey.jellyfin;
    expect(
      streamLibraryCountLine(368, StreamLibraryKind.movies, jellyfin),
      '368 movies',
    );
    expect(
      streamLibraryCountLine(1, StreamLibraryKind.movies, jellyfin),
      '1 movie',
    );
    expect(
      streamLibraryCountLine(86, StreamLibraryKind.shows, jellyfin),
      '86 series',
    );
    expect(
      streamLibraryCountLine(40, StreamLibraryKind.music, jellyfin),
      '40 albums',
    );
    expect(
      streamLibraryCountLine(12, StreamLibraryKind.music, ServiceKey.plex),
      '12 artists',
    );
    expect(streamLibraryCountLine(5, null, jellyfin), '5 items');
  });
}
