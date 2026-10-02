/// The array is its parity and cache drives as well as its data drives, and an
/// empty slot is not a fault.
///
/// The array query asked for `disks` alone, which in Unraid's schema are the
/// data drives: a disabled parity drive, the fault Unraid users fear most,
/// never reached the app. And every `DISK_*` status but OK and NEW was
/// flagged, `DISK_NP` included, so an array with a second parity slot nobody
/// fitted reported a fault on every read.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_overview_provider.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// World B's Unraid beside P3.
final _profile = Profiles.p3.withConnection(WorldConnections.unraid);

void main() {
  test('parity and cache are drives of the array, and the free parity slot '
      'is neither a drive nor a fault', () async {
    final harness = await ProfileHarness.start(_profile);
    final container = harness.container(retry: (_, _) => null);

    final array = await container.read(unraidArrayProvider.future);
    final digest = unraidArrayDigest(array);

    expect(array.drives.map((disk) => disk.name), [
      'parity',
      'disk1',
      'disk2',
      'cache',
    ]);
    expect(digest.diskCount, 4);
    expect(digest.faultCount, 0);
    expect(digest.headline, isNot(contains('flagged')));
  });

  test('a disabled parity drive is flagged, and leads the preview', () async {
    final harness = await ProfileHarness.start(_profile);
    harness.network.on(
      'unraid',
      'POST',
      '/graphql',
      (r) => '${(r.json as Map)['query']}'.contains('array {')
          ? NetworkReply.json({
              'data': {
                'array': {
                  'state': 'STARTED',
                  'parities': [
                    {'name': 'parity', 'status': 'DISK_DSBL', 'temp': 34},
                    {'name': 'parity2', 'status': 'DISK_NP', 'temp': null},
                  ],
                  'disks': [
                    {'name': 'disk1', 'status': 'DISK_OK', 'temp': 38},
                  ],
                  'caches': const <Object?>[],
                },
              },
            })
          : null,
    );
    final container = harness.container(retry: (_, _) => null);

    final digest = unraidArrayDigest(
      await container.read(unraidArrayProvider.future),
    );

    expect(digest.faultCount, 1);
    expect(digest.preview.first.name, 'parity');
    expect(digest.headline, contains('1 slot flagged'));
  });

  test('an empty slot is not a fault; a missing or disabled one is', () {
    UnraidDisk slot(String status) =>
        UnraidDisk(name: 'parity2', status: status, temp: null);

    expect(slot('DISK_NP').flagged, isFalse);
    expect(slot('DISK_NP').empty, isTrue);
    expect(slot('DISK_NP_MISSING').flagged, isTrue);
    expect(slot('DISK_NP_DSBL').flagged, isTrue);
    expect(slot('DISK_DSBL').flagged, isTrue);
  });
}
