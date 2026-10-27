import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';

/// A refused address is a fault the service reports, in amber, with no remedy
/// button: the fix is in the service's own settings, which its sentence names.
/// Never the sign-in's words or remedy.
void main() {
  group('a service that refused the address, not the password', () {
    const reason = ServiceFailureReason.addressRefused;

    test('reads as the address, in amber, with Retry and no remedy button', () {
      expect(failureLabel(reason), 'Refused this address');
      expect(
        failureHeadline(reason, subject: 'qBittorrent'),
        'qBittorrent answered but refused this address',
      );
      expect(
        failureGroupHeadline(reason, subjects: 'qBittorrent and Transmission'),
        'qBittorrent and Transmission answered but refused this address',
      );
      expect(failureRemedy(reason), isNull);
      expect(failureTone(reason), StatusTone.warning);
      expect(failureDidNotAnswer(reason), isFalse);
    });

    test('a retry helps once the service allows the address', () {
      expect(failureRetryHelps(reason), isTrue);
    });

    test('a qBittorrent refusal carries its own sentence and reason', () {
      const error = QbittorrentException(
        'qBittorrent refused this address (401).',
        reason: ServiceFailureReason.addressRefused,
        detail:
            'Add this address to Server domains in qBittorrent\'s Web UI '
            'settings, or turn off Host header validation there.',
      );
      expect(classifyConnectionFailure(error), reason);
      expect(connectionFailureSentence(error), contains('Server domains'));
      expect(connectionFailureSentence(error), isNot(contains('sign-in')));
    });
  });
}
