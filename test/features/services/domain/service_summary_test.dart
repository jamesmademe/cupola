import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('ServiceSummary', () {
    test('formats online status and version', () {
      const summary = ServiceSummary(
        service: ServiceKey.radarr,
        status: ServiceSummaryStatus.online,
        host: 'radarr.local:7878',
        version: '5.4.6',
      );

      expect(summary.isOnline, isTrue);
      expect(summary.failureReason, isNull);
      expect(summary.versionLabel, 'v5.4.6');
    });

    test('leaves an already-prefixed version alone', () {
      const summary = ServiceSummary(
        service: ServiceKey.seerr,
        status: ServiceSummaryStatus.online,
        host: 'seerr.local:5055',
        version: 'v2.5.1',
      );

      expect(summary.versionLabel, 'v2.5.1');
    });

    test('falls back to the registry API label when there is no version', () {
      const offline = ServiceSummary(
        service: ServiceKey.lidarr,
        status: ServiceSummaryStatus.offline,
        host: 'lidarr.local:8686',
        version: null,
      );

      expect(offline.isOnline, isFalse);
      expect(offline.didNotAnswer, isTrue);
      expect(offline.failureReason, ServiceFailureReason.unreachable);
      expect(offline.versionLabel, 'v1 API');
    });

    test('a failed probe is classified: silence is offline, a refusal is a '
        'fault', () {
      final silent = ServiceSummary.failed(
        ServiceKey.radarr,
        host: 'radarr.local:7878',
        error: const SocketException('Connection refused'),
      );
      expect(silent.status, ServiceSummaryStatus.offline);
      expect(silent.didNotAnswer, isTrue);
      expect(silent.isFault, isFalse);

      final refused = ServiceSummary.failed(
        ServiceKey.radarr,
        host: 'radarr.local:7878',
        error: DioException(
          requestOptions: RequestOptions(path: '/api/v3/system/status'),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/v3/system/status'),
            statusCode: 401,
          ),
        ),
      );
      expect(refused.status, ServiceSummaryStatus.fault);
      expect(refused.isFault, isTrue);
      expect(refused.didNotAnswer, isFalse);
      expect(refused.isOnline, isFalse);
      expect(refused.failureReason, ServiceFailureReason.unauthorized);
    });

    test('treats a blank version as absent rather than printing "v"', () {
      const blank = ServiceSummary(
        service: ServiceKey.radarr,
        status: ServiceSummaryStatus.online,
        host: 'radarr.local:7878',
        version: '   ',
      );

      expect(blank.versionLabel, 'v3 API');
    });
  });
}
