/// "Queued" reads one tone in every queue the app draws: blue, in line.
///
/// It was neutral in qBittorrent and Transmission and blue in SABnzbd, NZBGet
/// and an arr's queue, so the same word on the same page took two tones. The
/// brand book has one answer: queued is blue.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_overview_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_overview_provider.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/domain/transmission_tone.dart';

void main() {
  test('queued is blue in an arr, SABnzbd, NZBGet and Transmission', () {
    expect(
      const MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.queued,
      ).tone,
      StatusTone.info,
    );
    expect(sabnzbdStatusTone('Queued'), StatusTone.info);
    expect(NzbgetGroupState.queued.tone, StatusTone.info);
    for (final code in [1, 3, 5]) {
      expect(
        transmissionTorrentTone(
          TransmissionTorrent.fromJson({
            'id': 1,
            'name': 'Sintel.2010.1080p.BluRay',
            'status': code,
          }),
        ),
        StatusTone.info,
        reason: 'Transmission status $code is a queue',
      );
    }
  });
}
