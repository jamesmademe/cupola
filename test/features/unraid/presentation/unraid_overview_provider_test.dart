import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_overview_provider.dart';

/// The Unraid Overview's window and fold rules, as pure functions.
///
/// Every one of them takes its clock as an argument, so these run without a
/// container, without a pump and without waiting — which is the point of
/// writing them as top-level functions in the first place.
void main() {
  group('unraidUptimeLabel', () {
    final now = DateTime.utc(2026, 9, 17, 12);

    test('reads the elapsed time from a boot timestamp, not a duration', () {
      // `info.os.uptime` is the moment the server came up. Printing it would
      // put an ISO string on the identity line; the figure a person wants is
      // how long ago that was.
      expect(unraidUptimeLabel('2026-08-30T12:00:00Z', now: now), '18 days');
    });

    test('steps down through hours and minutes', () {
      expect(unraidUptimeLabel('2026-09-16T12:00:00Z', now: now), '1 day');
      expect(unraidUptimeLabel('2026-09-17T05:00:00Z', now: now), '7 hours');
      expect(unraidUptimeLabel('2026-09-17T11:59:00Z', now: now), '1 minute');
    });

    test('a server up for seconds has just booted, and never "0 minutes"', () {
      // A zero here would read as a figure that failed to load, over the one
      // moment the figure matters most.
      expect(
        unraidUptimeLabel('2026-09-17T11:59:40Z', now: now),
        'just booted',
      );
    });

    test(
      'compares in UTC, so an offset in the answer does not shift a day',
      () {
        // 2026-09-16T14:00+02:00 is 12:00Z — exactly a day. Compared naively
        // against a local `now` it would read 22 hours or 26.
        expect(
          unraidUptimeLabel('2026-09-16T14:00:00+02:00', now: now),
          '1 day',
        );
      },
    );

    test('a figure we cannot compute is null, never a number', () {
      // Absent, blank, not a timestamp, and a boot time in the future — the
      // last one is clock skew between phone and server, and "up minus three
      // hours" is not a fact about anything.
      expect(unraidUptimeLabel(null, now: now), isNull);
      expect(unraidUptimeLabel('   ', now: now), isNull);
      expect(unraidUptimeLabel('18 days', now: now), isNull);
      expect(unraidUptimeLabel('2026-09-17T15:00:00Z', now: now), isNull);
    });
  });

  group('unraidSystemFacts', () {
    final now = DateTime.utc(2026, 9, 17, 12);

    test('an unanswered figure reads an em dash and keeps its row', () {
      final facts = unraidSystemFacts(
        const UnraidInfo(distro: '', version: '', uptime: null),
        now: now,
      );

      expect(facts.map((f) => f.value), ['—', '—']);
      // The rows stay: `info` replied, so the section is there, and a row that
      // vanishes on a missing field makes the page's shape depend on the
      // payload.
      expect(facts.map((f) => f.label), ['Uptime', 'Release']);
    });

    test('a row speaks its label and its figure as one sentence', () {
      final facts = unraidSystemFacts(
        const UnraidInfo(
          distro: 'Unraid',
          version: '7.0.1',
          uptime: '2026-08-30T12:00:00Z',
        ),
        now: now,
      );

      expect(facts.first.spoken, 'Uptime, 18 days');
      expect(facts.last.spoken, 'Release, Unraid 7.0.1');
    });
  });

  group('unraidCapacityLabel', () {
    UnraidArray array({int? used, int? total}) => UnraidArray(
      state: 'STARTED',
      usedFraction: used != null && total != null ? used / total : null,
      disks: const [],
      usedBytes: used,
      totalBytes: total,
    );

    test('prints the unit once when both figures land on it', () {
      expect(
        unraidCapacityLabel(
          array(
            used: 5 * 1024 * 1024 * 1024 * 1024,
            total: 10 * 1024 * 1024 * 1024 * 1024,
          ),
        ),
        '5.0 of 10.0\u00A0TB',
      );
    });

    test('keeps both units when they differ', () {
      // Collapsing here would be off by a factor of a thousand.
      expect(
        unraidCapacityLabel(
          array(
            used: 800 * 1024 * 1024 * 1024,
            total: 10 * 1024 * 1024 * 1024 * 1024,
          ),
        ),
        '800\u00A0GB of 10.0\u00A0TB',
      );
    });

    test('an array that reported no capacity is null, never 0 B', () {
      // `0 B` is a claim that the array is empty. Nobody made it.
      expect(unraidCapacityLabel(array()), isNull);
      expect(unraidCapacityLabel(array(used: 0, total: 0)), isNull);
    });
  });

  group('unraidArrayDigest', () {
    UnraidDisk disk(String name, {String status = 'DISK_OK', int? temp = 30}) =>
        UnraidDisk(name: name, status: status, temp: temp);

    test('the count is the census, and the preview only a sample of it', () {
      final digest = unraidArrayDigest(
        UnraidArray(
          state: 'STARTED',
          usedFraction: null,
          disks: [for (var i = 0; i < 9; i++) disk('disk$i')],
        ),
        limit: 6,
      );

      // `array.disks` is the whole list — the query is not paged — so nine may
      // honestly be stated as a total while six rows are drawn.
      expect(digest.diskCount, 9);
      expect(digest.preview, hasLength(6));
      expect(digest.headline, 'started · 9 disks');
    });

    test('a warm slot and a flagged slot float to the top of the preview', () {
      final digest = unraidArrayDigest(
        UnraidArray(
          state: 'STARTED',
          usedFraction: null,
          disks: [
            disk('disk1'),
            disk('disk2'),
            disk('disk3'),
            disk('disk4', status: 'DISK_DSBL'),
            disk('disk5', temp: 47),
          ],
        ),
        limit: 2,
      );

      // A fault a preview can hide is a fault the page failed to report.
      expect(digest.preview.map((d) => d.name), ['disk4', 'disk5']);
      // Warm and flagged are counted apart, so one drive that is both is not
      // reported twice as two problems.
      expect(digest.warmCount, 1);
      expect(digest.faultCount, 1);
      expect(
        digest.headline,
        'started · 5 disks · 1 above 45\u00A0°C · 1 slot flagged',
      );
    });

    test('a healthy array says nothing about problems it does not have', () {
      final digest = unraidArrayDigest(
        UnraidArray(
          state: 'STARTED',
          usedFraction: 0.5,
          disks: [disk('disk1')],
          usedBytes: 5 * 1024 * 1024 * 1024 * 1024,
          totalBytes: 10 * 1024 * 1024 * 1024 * 1024,
        ),
      );

      // No "0 above 45 °C": a sentence about a problem where there is none is
      // the most expensive kind of noise on a page that exists to say what
      // needs a decision.
      expect(digest.headline, 'started · 5.0 of 10.0\u00A0TB · 1 disk');
    });

    test('a drive that is both flagged and warm is named as flagged', () {
      // DISK_DSBL at 47 °C is the array running without a drive it expected,
      // *while that drive cooks*. The old subtraction dropped it from the fault
      // count because it was warm, so the header said "1 above 45 °C" and never
      // mentioned that a slot was flagged — the more serious of the two facts,
      // suppressed by the less serious one.
      final digest = unraidArrayDigest(
        const UnraidArray(
          state: 'STARTED',
          usedFraction: null,
          disks: [
            UnraidDisk(name: 'parity', status: 'DISK_DSBL', temp: 47),
            UnraidDisk(name: 'disk1', status: 'DISK_OK', temp: 30),
          ],
        ),
      );

      // Each drive is attributed once, to the more serious of its troubles:
      // nothing is double-reported and nothing is dropped.
      expect(digest.faultCount, 1);
      expect(digest.warmCount, 0);
      expect(digest.headline, 'started · 2 disks · 1 slot flagged');
    });

    test('an array that reported no slot list does not claim 0 disks', () {
      // `disks` is nullable in the committed SDL. A header reading "0 disks"
      // over silence is a positive claim that the array has no drives, and the
      // section under it would say "No disks reported" beside it — two
      // assertions built out of a field that never arrived.
      final digest = unraidArrayDigest(
        UnraidArray.fromJson(const {'state': 'STARTED'}),
      );

      expect(digest.diskCount, isNull);
      expect(digest.headline, 'started');

      // An array that *answered* with an empty list still states its census.
      final empty = unraidArrayDigest(
        UnraidArray.fromJson(const {'state': 'STARTED', 'disks': <Object?>[]}),
      );
      expect(empty.diskCount, 0);
      expect(empty.headline, 'started · 0 disks');
    });

    test('an array that reported no state simply does not claim one', () {
      // `UNKNOWN` is the model's stand-in for an absent field, not a state the
      // array reported.
      final digest = unraidArrayDigest(
        const UnraidArray(state: 'UNKNOWN', usedFraction: null, disks: []),
      );

      expect(digest.stateLabel, isNull);
      expect(digest.headline, '0 disks');
    });
  });

  group('disk readings', () {
    test('a spun-down slot says so instead of reading 0 °C', () {
      const sleeping = UnraidDisk(name: 'disk2', status: 'DISK_OK', temp: null);

      expect(unraidDiskReading(sleeping), 'spun down');
      expect(unraidDiskSpoken(sleeping), 'disk2, DISK_OK, spun down');
    });

    test('a row speaks one sentence with the unit said, not glyphed', () {
      const warm = UnraidDisk(name: 'disk1', status: 'DISK_OK', temp: 47);

      expect(unraidDiskReading(warm), '47\u00A0°C');
      expect(unraidDiskSpoken(warm), 'disk1, DISK_OK, 47 degrees');
    });
  });

  group('unraidDockerDigest', () {
    UnraidDockerContainer container(String name, String status) =>
        UnraidDockerContainer.fromJson({
          'id': name,
          'names': ['/$name'],
          'state': status.toLowerCase().startsWith('up') ? 'RUNNING' : 'EXITED',
          'status': status,
          'autoStart': true,
        });

    test('the tally counts every arm it has, and none it does not', () {
      final digest = unraidDockerDigest([
        container('plex', 'Up 12 days'),
        container('radarr', 'Up 3 days'),
        container('sonarr', 'Exited (0) 2 days ago'),
        container('tautulli', 'Up 20 minutes (unhealthy)'),
      ]);

      expect(
        digest.headline,
        '4 containers · 2 running · 1 stopped · 1 unhealthy',
      );
      expect(digest.failed, 0);
    });

    test('a fault floats over the alphabet; a deliberate stop does not', () {
      final digest = unraidDockerDigest([
        container('alpha', 'Up 3 days'),
        container('beta', 'Exited (0) 2 days ago'),
        container('zulu', 'Exited (137) 3 hours ago'),
      ], limit: 2);

      // The OOM-killed container leads even though it sorts last: five rows
      // over forty containers would otherwise report the alphabet rather than
      // the problem. The one somebody stopped stays where it is — that is
      // backlog, and the user already knows.
      expect(digest.preview.map((c) => c.name), ['zulu', 'alpha']);
      expect(digest.failed, 1);
      expect(digest.stopped, 1);
    });

    test('the total is the census, never the rows drawn', () {
      final digest = unraidDockerDigest([
        for (var i = 0; i < 14; i++) container('c$i', 'Up 1 day'),
      ], limit: 5);

      expect(digest.total, 14);
      expect(digest.preview, hasLength(5));
      expect(digest.headline, '14 containers · 14 running');
    });
  });
}
