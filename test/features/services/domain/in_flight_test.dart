/// The in-flight grammar, and the rule that a missing figure is not zero.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/in_flight.dart';

void main() {
  group('done of total', () {
    test('renders both sides on the total\'s unit', () {
      expect(
        formatDoneOfTotal(
          doneBytes: 14 * 1024 * 1024 * 1024,
          totalBytes: 15 * 1024 * 1024 * 1024,
        ),
        '14.0 of 15.0 GB',
      );
    });

    test('a figure the source did not report is —, never 0', () {
      // The whole rule, twice: a count nobody was able to take is not zero, and
      // `0 B of …` would say the transfer has not started.
      expect(formatDoneOfTotal(doneBytes: null, totalBytes: 100), '—');
      expect(formatDoneOfTotal(doneBytes: 100, totalBytes: null), '—');
      expect(formatDoneOfTotal(doneBytes: null, totalBytes: null), '—');
      expect(formatDoneOfTotal(doneBytes: null, totalBytes: 100), isNot('0 B'));
    });

    test('nothing downloaded yet is 0, which is a reading', () {
      // The counterweight: zero *reported* is a fact, and must not be hidden.
      expect(
        formatDoneOfTotal(doneBytes: 0, totalBytes: 2 * 1024 * 1024 * 1024),
        '0.0 of 2.00 GB',
      );
    });
  });

  group('time left', () {
    test('never prints seconds above a minute, and never a bare number', () {
      expect(formatTimeLeft(48), '48 s left');
      expect(formatTimeLeft(180), '3 min left');
      expect(formatTimeLeft(7800), '2 h 10 min left');
      expect(formatTimeLeft(7200), '2 h left');
    });

    test('no estimate is —', () {
      expect(formatTimeLeft(null), '—');
      expect(formatTimeLeft(-1), '—');
    });
  });

  group('the row line', () {
    test('is quality, done of total, time left, client', () {
      expect(
        formatInFlightLine(
          quality: '2160p',
          doneBytes: 14 * 1024 * 1024 * 1024,
          totalBytes: 15 * 1024 * 1024 * 1024,
          etaSeconds: 180,
          client: 'qBittorrent',
        ),
        '2160p · 14.0 of 15.0 GB · 3 min left · qBittorrent',
      );
    });

    test('drops the quality when the source has none, and keeps the rest', () {
      final line = formatInFlightLine(
        doneBytes: null,
        totalBytes: null,
        etaSeconds: null,
        client: 'SABnzbd',
      );

      // Three fields, two of them explicitly absent. A client that knows only
      // its own name still produces a readable row.
      expect(line, '— · — · SABnzbd');
    });
  });

  group('the eyebrow', () {
    test('sums the rate across clients and counts them', () {
      expect(
        inFlightEyebrow(
          active: 2,
          rateBytesPerSecond: 16 * 1024 * 1024,
          clients: 2,
        ),
        '2 downloading · 16 MB/s across 2 clients',
      );
    });

    test('says only the count when nobody reported a rate', () {
      expect(
        inFlightEyebrow(active: 3, rateBytesPerSecond: null, clients: 0),
        '3 downloading',
      );
    });
  });

  test('a stall leaves this region and says so', () {
    expect(inFlightStalledFootnote(0), isNull);
    expect(inFlightStalledFootnote(1), '1 stalled · under a decision above');
    expect(inFlightStalledFootnote(3), contains('under decisions above'));
  });

  test('the spoken row re-separates the dots and leads with progress', () {
    expect(
      inFlightRowValue(line: '2160p · 3 min left · qBittorrent', percent: 92),
      '92% done, 2160p, 3 min left, qBittorrent',
    );
  });
}
