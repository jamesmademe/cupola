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

    test('parses the session capability and queue settings', () {
      final session = _session(const {
        'peer-port': 51413,
        'peer-port-random-on-start': true,
        'port-forwarding-enabled': true,
        'encryption': 'preferred',
        'peer-limit-global': 400,
        'peer-limit-per-torrent': 60,
        'seedRatioLimit': 2.0,
        'seedRatioLimited': true,
        'idle-seeding-limit': 30,
        'idle-seeding-limit-enabled': true,
        'blocklist-enabled': true,
        'blocklist-size': 1200,
        'download-queue-enabled': true,
        'download-queue-size': 5,
        'seed-queue-enabled': false,
        'seed-queue-size': 10,
        'start-added-torrents': true,
        'rename-partial-files': true,
        'cache-size-mb': 16,
      });

      expect(session.rpcVersion, 17);
      expect(session.peerPort, 51413);
      expect(session.peerPortRandomOnStart, isTrue);
      expect(session.portForwardingEnabled, isTrue);
      expect(session.encryption, 'preferred');
      expect(session.peerLimitGlobal, 400);
      expect(session.peerLimitPerTorrent, 60);
      expect(session.seedRatioLimit, 2.0);
      expect(session.seedRatioLimited, isTrue);
      expect(session.idleSeedingLimitMinutes, 30);
      expect(session.blocklistSize, 1200);
      expect(session.downloadQueueSize, 5);
      expect(session.seedQueueEnabled, isFalse);
      expect(session.startAddedTorrents, isTrue);
      expect(session.renamePartialFiles, isTrue);
      expect(session.cacheSizeMb, 16);
    });

    // A field the daemon never sent is **null**, and that is the whole point:
    // `0` used to come back for both a missing `cache-size-mb` and a cache
    // switched off, so the Session tab stated a figure nobody reported. The
    // flags stay false; a switch has to be drawn in one position, and off is
    // the safe one for a setting that was never mentioned.
    test('a field the daemon did not send is null, not zero', () {
      final session = _session(const {});

      expect(session.peerPort, isNull);
      expect(session.encryption, isEmpty);
      expect(session.seedRatioLimit, isNull);
      expect(session.peerLimitGlobal, isNull);
      expect(session.peerLimitPerTorrent, isNull);
      expect(session.idleSeedingLimitMinutes, isNull);
      expect(session.downloadQueueSize, isNull);
      expect(session.seedQueueSize, isNull);
      expect(session.blocklistSize, isNull);
      expect(session.cacheSizeMb, isNull);
      expect(session.downloadQueueEnabled, isFalse);
    });

    test('a reported zero survives as a zero', () {
      final session = _session(const {
        'cache-size-mb': 0,
        'blocklist-size': 0,
        'seedRatioLimit': 0,
      });

      expect(session.cacheSizeMb, 0);
      expect(session.blocklistSize, 0);
      expect(session.seedRatioLimit, 0);
    });
  });
}
