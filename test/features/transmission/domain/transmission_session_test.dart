import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

TransmissionSession _session(Map<String, dynamic> extra) =>
    TransmissionSession.fromJson({
      'version': '4.0.6',
      'rpc-version': 17,
      'download-dir': '/mnt/media/complete',
      'alt-speed-enabled': false,
      'speed-limit-down': 4096,
      'speed-limit-down-enabled': true,
      'speed-limit-up': 1024,
      'speed-limit-up-enabled': false,
      ...extra,
    });

void main() {
  group('TransmissionSession', () {
    test('reads the incomplete directory and its flag', () {
      final session = _session({
        'incomplete-dir': '/mnt/fast/incomplete',
        'incomplete-dir-enabled': true,
      });

      expect(session.incompleteDir, '/mnt/fast/incomplete');
      expect(session.incompleteDirEnabled, isTrue);
    });

    test('the volume a download fills is the incomplete one when in force', () {
      // Transmission writes into `incomplete-dir` and only moves the file to
      // `download-dir` once it finishes, so measuring `download-dir` describes
      // a disk the running grab is not touching.
      final session = _session({
        'incomplete-dir': '/mnt/fast/incomplete',
        'incomplete-dir-enabled': true,
      });

      expect(session.activeDownloadDir, '/mnt/fast/incomplete');
      expect(session.usesIncompleteDir, isTrue);
    });

    test('a stored incomplete directory that is off is not in force', () {
      // The daemon keeps the path while the flag is false, exactly as it keeps
      // a speed limit that is switched off.
      final session = _session({
        'incomplete-dir': '/mnt/fast/incomplete',
        'incomplete-dir-enabled': false,
      });

      expect(session.incompleteDir, '/mnt/fast/incomplete');
      expect(session.activeDownloadDir, '/mnt/media/complete');
      expect(session.usesIncompleteDir, isFalse);
    });

    test('the flag on with a blank path falls back to the download dir', () {
      final session = _session({
        'incomplete-dir': '   ',
        'incomplete-dir-enabled': true,
      });

      expect(session.activeDownloadDir, '/mnt/media/complete');
      expect(session.usesIncompleteDir, isFalse);
    });

    test('a daemon that reported neither key keeps the download dir', () {
      final session = _session(const {});

      expect(session.incompleteDir, isEmpty);
      expect(session.incompleteDirEnabled, isFalse);
      expect(session.activeDownloadDir, '/mnt/media/complete');
    });

    test('the active directory is trimmed, so a blank one reads empty', () {
      final session = _session({'download-dir': '  '});

      expect(session.activeDownloadDir, isEmpty);
    });
  });
}
