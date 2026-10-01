import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/download_client_faults.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

TransmissionTorrent _torrent({
  int status = 4,
  int error = 0,
  String errorString = '',
  bool isStalled = false,
}) => TransmissionTorrent.fromJson({
  'hashString': 'abc',
  'name': 'Night.Shift.S02E04.1080p.WEB',
  'status': status,
  'error': error,
  'errorString': errorString,
  'isStalled': isStalled,
});

void main() {
  group('transmissionInFlight', () {
    test('a downloading, queued or verifying torrent is a transfer', () {
      for (final status in [4, 3, 2, 1]) {
        expect(
          transmissionInFlight(_torrent(status: status)),
          const InFlightReading.moving(),
          reason: 'status $status',
        );
      }
    });

    test('a seeding or stopped torrent is not in flight', () {
      for (final status in [6, 5, 0]) {
        expect(
          transmissionInFlight(_torrent(status: status)),
          isNull,
          reason: 'status $status',
        );
      }
    });

    test('a stalled download is a stall', () {
      expect(
        transmissionInFlight(_torrent(isStalled: true)),
        const InFlightReading.fault(InFlightFault.stalled),
      );
    });

    test('a local error is a failure on any torrent, in the daemon\'s '
        'words', () {
      for (final status in [0, 4, 6]) {
        expect(
          transmissionInFlight(
            _torrent(status: status, error: 3, errorString: 'No data found!'),
          ),
          const InFlightReading.fault(
            InFlightFault.failed,
            reason: 'No data found!',
          ),
          reason: 'status $status',
        );
      }
    });

    test('a tracker error fails a download; a tracker warning does not', () {
      expect(
        transmissionInFlight(
          _torrent(error: 2, errorString: 'Torrent not registered'),
        ),
        const InFlightReading.fault(
          InFlightFault.failed,
          reason: 'Torrent not registered',
        ),
      );
      expect(
        transmissionInFlight(_torrent(error: 1, errorString: 'Timed out')),
        const InFlightReading.moving(),
      );
    });
  });
}
