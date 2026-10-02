@Tags(['catalog'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

const _access = AccessGatewayAnswer(
  kind: AccessGatewayKind.cloudflareAccess,
  credentialsSent: false,
  gatewayHost: 'cupola-home.cloudflareaccess.com',
  serviceHost: 'radarr.example.com',
);

void main() {
  catalogCard(
    'AppErrorState',
    scenes: [
      CatalogScene(
        'AppErrorState(serviceName:, onRetry:) · cold open, nothing answered: '
        'red, the detail is the classified sentence, never the exception, '
        'and Retry is a ghost in ink',
        (_) => AppErrorState(
          serviceName: 'Radarr',
          error: DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v3/movie'),
            reason: 'Connection refused',
          ),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'AppErrorState · a read whose client a settings change closed under '
        'it: no failure and no words, the loading state while onRetry asks '
        'again on the rebuilt client',
        (_) => AppErrorState(
          serviceName: 'Radarr',
          // Dio's own refusal of a request on a closed client.
          error: DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v3/movie'),
            reason: "Dio can't establish a new connection after it was closed.",
          ),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'AppErrorState · a server that answered with 401: an amber fault whose '
        'remedy leads in the amber fill, Paste the key again, and no Retry: '
        'the same key can only be refused again',
        (_) => AppErrorState(
          serviceName: 'Radarr',
          error: DioException(
            requestOptions: RequestOptions(path: '/api/v3/movie'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/v3/movie'),
              statusCode: 401,
            ),
          ),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'AppErrorState · 404, the API is not at this address: Check the '
        'address leads in the amber fill, Retry follows as text in ink',
        (_) => AppErrorState(
          serviceName: 'Radarr',
          error: DioException(
            requestOptions: RequestOptions(path: '/api/v3/movie'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/v3/movie'),
              statusCode: 404,
            ),
          ),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'AppErrorState(service:) · qBittorrent refused the sign-in: the '
        'headline names what it refused, Sign in again leads in the amber '
        'fill, and Retry follows as text in ink, because a ban runs out',
        (_) => AppErrorState(
          service: ServiceKey.qbittorrent,
          error: DioException(
            requestOptions: RequestOptions(path: '/api/v2/torrents/info'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/v2/torrents/info'),
              statusCode: 403,
            ),
          ),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'AppErrorState(service:) · Cloudflare Access answered in Radarr\'s '
        'place: the gateway named, Add a service token leads in the amber '
        'fill, and no Retry: the same request meets the same gateway',
        (_) => AppErrorState(
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
        'AppErrorState · 401 with no service named: Retry only, because it '
        'cannot say whose form to open, in the amber fill as the fault\'s '
        'remedy',
        (_) => AppErrorState(
          error: DioException(
            requestOptions: RequestOptions(path: '/api/v3/movie'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/v3/movie'),
              statusCode: 401,
            ),
          ),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'AppErrorState(service:) · a Seerr account whose session ended: blue, '
        'the person\'s own step and not a fault, Sign in again leads in the '
        'ink fill, and no Retry: no request revives a session',
        (_) => AppErrorState(
          service: ServiceKey.seerr,
          error: DioException(
            requestOptions: RequestOptions(path: '/api/v1/request'),
            type: DioExceptionType.badResponse,
            error: const SeerrSessionEnded(),
          ),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'AppErrorState.compact() · no serviceName, no onRetry, a failure '
        'nobody can attribute: amber, never read as silence',
        (_) => const AppErrorState.compact(error: 'Exception: parser'),
        width: 280,
      ),
      CatalogScene(
        'InlineErrorRetry · one section of a page did not answer, '
        'self-sizing: red, the one thing red means',
        (_) => InlineErrorRetry(
          message:
              'Unraid did not answer, so its virtual machines are not shown.',
          error: const SocketException('Connection refused'),
          onRetry: () {},
        ),
        width: 360,
      ),
      CatalogScene(
        'InlineErrorRetry(error:) · a Discover rail Seerr refused: the glyph '
        'takes the classification, amber, and the remedy takes the place of '
        'Retry as the compact amber fill',
        (_) => InlineErrorRetry(
          message:
              'Seerr answered but refused the key, so this row is missing.',
          error: DioException(
            requestOptions: RequestOptions(path: '/api/v1/discover/trending'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/v1/discover/trending'),
              statusCode: 403,
            ),
          ),
          onRetry: () {},
        ),
        width: 360,
      ),
      CatalogScene(
        'InlineErrorRetry(service:) · signed out of Seerr: the glyph blue, '
        'Sign in again in the compact ink fill, and no Retry',
        (_) => InlineErrorRetry(
          message: 'Signed out of Seerr, so this row is missing.',
          error: const ClassifiedFailure(ServiceFailureReason.sessionEnded),
          service: ServiceKey.seerr,
          onRetry: () {},
        ),
        width: 360,
      ),
      CatalogScene(
        'InlineErrorRetry(service:) · a certificate Cupola does not trust: both '
        'verbs, '
        'the amber remedy first, Retry in ink, on their own row under the '
        'sentence',
        (_) => InlineErrorRetry(
          message:
              'Unraid has a certificate Cupola does not trust, so its shares '
              'are not shown.',
          error: const ClassifiedFailure(ServiceFailureReason.tls),
          service: ServiceKey.unraid,
          onRetry: () {},
        ),
        width: 360,
      ),
      CatalogScene(
        "AppErrorState, in the requester's app · Seerr did not answer: one "
        'line with its time, no service named and no cause, and Retry as '
        'a ghost in ink',
        (_) => AppErrorState(
          service: ServiceKey.seerr,
          error: const SocketException('Connection refused'),
          onRetry: () {},
        ),
        overrides: _requester,
        width: 320,
      ),
      CatalogScene(
        "AppErrorState, in the requester's app · her session ended: You were "
        'signed out, blue, and Sign in again in the ink fill',
        (_) => AppErrorState(
          service: ServiceKey.seerr,
          error: const SeerrSessionEnded(),
          onRetry: () {},
        ),
        overrides: _requester,
        width: 320,
      ),
      CatalogScene(
        "InlineErrorRetry, in the requester's app · a rail Seerr answered "
        'with a 5xx: the same one line, amber, and Retry in the amber fill',
        (_) => InlineErrorRetry(
          message: 'Seerr answered with an error, so this rail is not shown.',
          error: DioException(
            requestOptions: RequestOptions(path: '/api/v1/discover/movies'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/v1/discover/movies'),
              statusCode: 502,
            ),
          ),
          service: ServiceKey.seerr,
          onRetry: () {},
        ),
        overrides: _requester,
        width: 360,
      ),
      CatalogScene(
        'Text at 200% · AppErrorState, nothing answered: the red headline, the '
        'classified sentence and the ghost Retry at twice the reading size',
        (_) => AppErrorState(
          serviceName: 'Radarr',
          error: DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v3/movie'),
            reason: 'Connection refused',
          ),
          onRetry: () {},
        ),
        width: 320,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · AppErrorState, a 401: the amber fault with its remedy '
        'as the one amber fill',
        (_) => AppErrorState(
          serviceName: 'Radarr',
          error: DioException(
            requestOptions: RequestOptions(path: '/api/v3/movie'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/v3/movie'),
              statusCode: 401,
            ),
          ),
          onRetry: () {},
        ),
        width: 320,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · AppErrorState, a Seerr account whose session ended: '
        'the blue state with its ink fill',
        (_) => AppErrorState(
          service: ServiceKey.seerr,
          error: const SeerrSessionEnded(),
          onRetry: () {},
        ),
        overrides: _requester,
        width: 320,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · AppErrorState.compact, a failure nobody can attribute',
        (_) => const AppErrorState.compact(error: 'Exception: parser'),
        width: 280,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · InlineErrorRetry, a certificate Cupola does not trust: '
        'the amber remedy first and Retry in ink, under the sentence',
        (_) => InlineErrorRetry(
          message:
              'Unraid has a certificate Cupola does not trust, so its shares '
              'are not shown.',
          error: const ClassifiedFailure(ServiceFailureReason.tls),
          service: ServiceKey.unraid,
          onRetry: () {},
        ),
        width: 360,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · InlineErrorRetry with Retry alone: under the sentence, '
        'at the trailing edge, the sentence keeping the line',
        (_) => InlineErrorRetry(
          message: 'Unraid did not answer, so its containers are not shown.',
          error: const SocketException('Connection refused'),
          service: ServiceKey.unraid,
          onRetry: () {},
        ),
        width: 360,
        textScale: catalogTextScale,
      ),
    ],
  );
}

/// The app as a household member's: every failure in the brief voice.
final _requester = [audienceProvider.overrideWithValue(Audience.requester)];
