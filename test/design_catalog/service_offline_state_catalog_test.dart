@Tags(['catalog'])
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

DioException _status(int code) => DioException(
  requestOptions: RequestOptions(path: '/api'),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api'),
    statusCode: code,
  ),
);

void main() {
  catalogCard(
    'ServiceOfflineState',
    overrides: () async => [
      currentSettingsProvider.overrideWith(
        (ref) =>
            settingsWithServices(const [ServiceKey.radarr, ServiceKey.plex]),
      ),
    ],
    scenes: [
      CatalogScene(
        'ServiceOfflineState(since:, onOpenSettings:) · did not answer: the '
        'red glyph, a known first-failure age, Retry and Settings',
        (_) => ServiceOfflineState(
          serviceName: 'SABnzbd',
          accent: ServiceKey.sabnzbd.accent,
          since: const Duration(minutes: 40),
          onRetry: () {},
          onOpenSettings: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'ServiceOfflineState · no first-failure time known, span dropped — '
        'Retry only, no onOpenSettings',
        (_) => ServiceOfflineState(
          serviceName: 'Transmission',
          accent: ServiceKey.transmission.accent,
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'ServiceOfflineState.failure · connection refused: red glyph, '
        'the lens host, the connection form\'s sentence, Retry and Settings',
        (_) => ServiceOfflineState.failure(
          service: ServiceKey.plex,
          error: DioException.connectionError(
            requestOptions: RequestOptions(path: '/status/sessions'),
            reason: 'Connection refused',
          ),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'ServiceOfflineState.failure · 401: it answered, so an amber fault, '
        'never "did not answer", and its remedy leads with no Retry',
        (_) => ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: _status(401),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'ServiceOfflineState.failure · a certificate Cupola does not trust: '
        'Check the certificate leads, Retry follows',
        (_) => ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: const ClassifiedFailure(ServiceFailureReason.tls),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'ServiceOfflineState.failure · 500: amber, the service spoke',
        (_) => ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: _status(500),
          onRetry: () {},
        ),
        width: 320,
      ),
    ],
  );
}
