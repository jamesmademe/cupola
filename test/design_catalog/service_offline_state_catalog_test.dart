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

const _access = AccessGatewayAnswer(
  kind: AccessGatewayKind.cloudflareAccess,
  credentialsSent: false,
  gatewayHost: 'cupola-home.cloudflareaccess.com',
  serviceHost: 'radarr.example.com',
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
        'red glyph, a known first-failure age, Retry as a ghost and Settings',
        (_) => ServiceOfflineState(
          serviceName: 'SABnzbd',
          since: const Duration(minutes: 40),
          onRetry: () {},
          onOpenSettings: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'ServiceOfflineState · no first-failure time known, span dropped — '
        'Retry only, no onOpenSettings',
        (_) => ServiceOfflineState(serviceName: 'Transmission', onRetry: () {}),
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
        'never "did not answer", and its remedy leads in the amber fill with '
        'no Retry',
        (_) => ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: _status(401),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'ServiceOfflineState.failure · a certificate Cupola does not trust: '
        'Check the certificate leads in the amber fill, Retry follows in ink',
        (_) => ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: const ClassifiedFailure(ServiceFailureReason.tls),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'ServiceOfflineState.failure · a web page answered for Radarr: the '
        'address\'s fault, its sentence naming where with the path hint, Check '
        'the address in the amber fill',
        (_) => ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: DioException(
            requestOptions: RequestOptions(path: '/api/v3/movie'),
            type: DioExceptionType.badResponse,
            error: UnexpectedAnswer(
              status: 200,
              body:
                  '<!DOCTYPE html><html><body>Welcome to nginx!</body></html>',
              host: 'radarr.example.com',
              baseUrl: 'https://radarr.example.com',
            ),
          ),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'ServiceOfflineState.failure · Cloudflare Access answered in Radarr\'s '
        'place: the gateway named in the title and the sentence, Add a service '
        'token in the amber fill, no Retry',
        (_) => ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: DioException(
            requestOptions: RequestOptions(path: '/api/v3/movie'),
            type: DioExceptionType.badResponse,
            error: _access,
          ),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'ServiceOfflineState.failure · 500: amber, the service spoke, and '
        'Retry is its remedy in the amber fill',
        (_) => ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: _status(500),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'Text at 200% · ServiceOfflineState, did not answer: the red glyph, '
        'the age, Retry as a ghost and Settings',
        (_) => ServiceOfflineState(
          serviceName: 'SABnzbd',
          since: const Duration(minutes: 40),
          onRetry: () {},
          onOpenSettings: () {},
        ),
        width: 320,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · ServiceOfflineState.failure, a 401: the amber fault '
        'with its remedy as the one amber fill',
        (_) => ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: _status(401),
          onRetry: () {},
        ),
        width: 320,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · ServiceOfflineState.failure, Cloudflare Access answered '
        'in Radarr\'s place, with its service-token remedy',
        (_) => ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: DioException(
            requestOptions: RequestOptions(path: '/api/v3/movie'),
            type: DioExceptionType.badResponse,
            error: _access,
          ),
          onRetry: () {},
        ),
        width: 320,
        textScale: catalogTextScale,
      ),
    ],
  );
}
