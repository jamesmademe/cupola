@Tags(['catalog'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';

import 'catalog.dart';

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
        'InlineErrorRetry · a certificate Cupola does not trust: both verbs, '
        'the amber remedy first, Retry in ink, on their own row under the '
        'sentence',
        (_) => InlineErrorRetry(
          message:
              'Unraid has a certificate Cupola does not trust, so its shares '
              'are not shown.',
          error: const ClassifiedFailure(ServiceFailureReason.tls),
          onRetry: () {},
        ),
        width: 360,
      ),
      CatalogScene(
        'InlineErrorRetry.fixedHeight · locked to 120px so a carousel row does '
        'not jump between loading, loaded and failed',
        (_) => DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0x40808080),
              style: BorderStyle.solid,
            ),
          ),
          child: InlineErrorRetry.fixedHeight(
            message: 'Unraid did not answer, so its containers are not shown.',
            error: const SocketException('Connection refused'),
            onRetry: () {},
          ),
        ),
        width: 360,
      ),
    ],
  );
}
