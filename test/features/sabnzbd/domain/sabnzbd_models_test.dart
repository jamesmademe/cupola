import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';

/// The queue slot's two sizes.
///
/// A row that prints only `mbleft` reads the same sentence a third of the way
/// through a job as it does at the end, so `mb` — the total `mode=queue`
/// already carries beside it — is parsed and printed with it. The rules below
/// are the ones that keep the second figure honest: it is absent rather than
/// zero, and the clause goes away whole rather than wearing a dash.
void main() {
  group('SabnzbdQueueSlot — the total beside the remainder', () {
    test('parses `mb` from the same payload `mbleft` comes from', () {
      final slot = SabnzbdQueueSlot.fromJson(const {
        'nzo_id': 'SABnzbd_nzo_abc',
        'filename': 'Ubuntu.24.04.iso',
        'status': 'Downloading',
        'percentage': '50',
        'cat': 'software',
        'timeleft': '0:12:30',
        'mbleft': '1500.0',
        'mb': '3000.0',
      });

      expect(slot.sizeLeftLabel, '1.5 GB');
      expect(slot.sizeLabel, '2.9 GB');
      expect(slot.sizeProgressLabel, '1.5 GB left of 2.9 GB');
    });

    test('reads the server locale separator, like every other figure here', () {
      // SABnzbd renders decimals with the host's separator, which is why the
      // parser is not `double.tryParse` on its own.
      final slot = SabnzbdQueueSlot.fromJson(const {
        'mbleft': '1024,0',
        'mb': '2048,0',
      });

      expect(slot.sizeProgressLabel, '1.0 GB left of 2.0 GB');
    });

    test('a slot with no `mb` drops the clause rather than inventing one', () {
      // Never `of 0 B`, and never a dash mid-sentence: a dash inside a dotted
      // detail line reads as a figure that failed to load, where the truth is
      // that this server never claimed one.
      final slot = SabnzbdQueueSlot.fromJson(const {'mbleft': '1024.0'});

      expect(slot.mb, isNull);
      expect(slot.sizeLabel, isNull);
      expect(slot.sizeProgressLabel, '1.0 GB left');
      expect(slot.sizeProgressLabel, isNot(contains('of')));
      expect(slot.sizeProgressLabel, isNot(contains('—')));
      expect(slot.sizeProgressLabel, isNot(contains('0 B')));
    });

    test('a zero or unreadable total is the same absence as a missing one', () {
      // SABnzbd answers `mb: 0` for a job whose size it does not know yet. Zero
      // beside a gigabyte still to fetch is a contradiction, not a measurement,
      // so it folds into the one "no total" branch instead of printing.
      for (final total in <dynamic>[0, '0.0', '-5', '', 'unknown', null]) {
        final slot = SabnzbdQueueSlot.fromJson({
          'mbleft': '1024.0',
          'mb': total,
        });
        expect(slot.mb, isNull, reason: 'mb: $total');
        expect(slot.sizeProgressLabel, '1.0 GB left', reason: 'mb: $total');
      }
    });

    test('the remainder still prints its own legitimate zero', () {
      // The em-dash rule is about a figure nobody could compute, not a small
      // one: a job with nothing left to fetch reported that, and it is a fact.
      final slot = SabnzbdQueueSlot.fromJson(const {
        'mbleft': '0',
        'mb': '2048.0',
      });

      expect(slot.sizeProgressLabel, '0 B left of 2.0 GB');
    });

    test('the total does not become a second progress figure', () {
      // `percentage` is SABnzbd's own, and a scale re-derived from a total that
      // may be missing is exactly the guess this pair refuses to make.
      final slot = SabnzbdQueueSlot.fromJson(const {
        'percentage': '72',
        'mbleft': '1024.0',
        'mb': '4096.0',
      });

      expect(slot.percentage, 72);
      expect(slot.progress, closeTo(0.72, 0.001));
    });
  });

  group('SABnzbd server surfaces', () {
    test('parses rollups and per-server failure counts', () {
      final stats = SabnzbdServerStats.fromJson(const {
        'total': 1000,
        'month': 400,
        'week': 200,
        'day': 50,
        'servers': {
          'news.example.test': {
            'total': 800,
            'articles_tried': 120,
            'articles_success': 115,
          },
        },
      });

      expect(stats.month, 400);
      expect(stats.week, 200);
      expect(stats.day, 50);
      expect(stats.servers.single.articlesFailed, 5);
      expect(stats.servers.single.name, 'news.example.test');
    });

    test('server config accepts SAB booleans without exposing credentials', () {
      final server = SabnzbdServerConfig.fromJson(const {
        'displayname': 'Primary',
        'host': 'news.example.test',
        'port': '563',
        'connections': '12',
        'enable': 1,
        'ssl': 'true',
        'optional': false,
        'priority': '0',
        'password': 'secret',
      });

      expect(server.name, 'Primary');
      expect(server.port, 563);
      expect(server.connections, 12);
      expect(server.enabled, isTrue);
      expect(server.ssl, isTrue);
    });
  });
}
