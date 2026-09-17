import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/qbittorrent/domain/tracker_tone.dart';

void main() {
  group('trackerStatusTone', () {
    test('a working tracker is the only green one', () {
      expect(trackerStatusTone(2), StatusTone.success);
    });

    test('an announce in flight is informational, not a fault', () {
      // `3` is *Updating*. Amber here would flag every tracker on every torrent
      // for the second or two an announce takes.
      expect(trackerStatusTone(3), StatusTone.info);
    });

    test('a dead tracker is amber, never red', () {
      // Red claims the client never replied. qB replied — with the news that
      // the tracker is down, which is a fault on a server that is plainly
      // alive. Same reading a stalled torrent gets one tab away.
      expect(trackerStatusTone(4), StatusTone.warning);
      expect(trackerStatusTone(4), isNot(StatusTone.error));
    });

    test('disabled and not-yet-contacted are backlog', () {
      expect(trackerStatusTone(0), StatusTone.neutral);
      expect(trackerStatusTone(1), StatusTone.neutral);
    });

    test('a code the app has no name for never falls through to green', () {
      for (final unknown in [-1, 5, 9, 42]) {
        expect(
          trackerStatusTone(unknown),
          StatusTone.neutral,
          reason: '$unknown is not evidence of anything',
        );
      }
    });

    test('no tracker status claims the client is unreachable', () {
      for (var status = -1; status <= 6; status++) {
        expect(
          trackerStatusTone(status),
          isNot(StatusTone.error),
          reason: 'red is reserved for a qBittorrent that did not answer',
        );
      }
    });
  });
}
