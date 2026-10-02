import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/discover_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The "By genre" rows read the genres from the route Seerr serves them on.
///
/// The fake once answered `/genres/movie` while the app reads
/// `/discover/genreslider/movie`, so every profile's genre rail failed and no
/// test noticed. The lab's Seerr 3.4.1 answers both; the app reads the slider.
void main() {
  test('P1 reads its movie genres from the genre slider', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container();

    final genres = await container.read(movieGenresProvider.future);

    expect(genres.map((g) => (g.id, g.name)), [(16, 'Animation')]);
  });
}
