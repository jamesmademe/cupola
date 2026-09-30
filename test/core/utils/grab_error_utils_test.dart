import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/grab_error_utils.dart';

DioException _answered(int status, {Object? data}) => DioException(
  requestOptions: RequestOptions(path: '/api/v3/release'),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/v3/release'),
    statusCode: status,
    data: data,
  ),
);

void main() {
  group('translateGrabError', () {
    test('a 504 is the indexer behind the arr running out of time', () {
      final message = translateGrabError(_answered(504));

      expect(
        message,
        'The indexer took too long to answer, so nothing was grabbed.',
      );
    });

    test('a 500 is the arr answering with an error, in words', () {
      final message = translateGrabError(_answered(500));

      expect(
        message,
        'The server answered with an error. This release may already be '
        'downloading or available, so check the download queue.',
      );
    });

    test('the arr saying it already has it', () {
      final message = translateGrabError(
        _answered(400, data: {'message': 'Item already exists'}),
      );

      expect(
        message,
        'This item is already in your library or download queue.',
      );
    });

    test('an app exception that carries the arr sentence keeps its hint', () {
      final message = translateGrabError(Exception('Not enough disk space'));

      expect(message, 'Not enough disk space for this download.');
    });

    test('a timeout says so and offers Retry, never "try again"', () {
      final message = translateGrabError(
        Exception('Connection timeout after 30s'),
      );

      expect(
        message,
        'The request timed out, so nothing was grabbed. Retry when the '
        'indexer is back.',
      );
    });

    test('a refused key is a refusal, never a status code', () {
      final message = translateGrabError(_answered(403));

      expect(
        message,
        'Nothing was grabbed. The server answered and refused the saved '
        'credentials. Check them in Settings.',
      );
      expect(message, isNot(contains('403')));
      expect(message, isNot(contains('Error')));
    });

    test('silence is the only failure that says nothing answered', () {
      final message = translateGrabError(
        const SocketException('Connection refused'),
      );

      expect(message, startsWith('Nothing was grabbed. Nothing answered'));
    });

    test('the arr own words, verbatim, when it gave any', () {
      final message = translateGrabError(
        _answered(
          400,
          data: [
            {'errorMessage': 'Release rejected by the download client'},
          ],
        ),
      );

      expect(
        message,
        'Nothing was grabbed. Release rejected by the download client',
      );
    });

    test('never the exception text for anything it cannot attribute', () {
      final message = translateGrabError(
        Exception('Request failed: Upstream unavailable'),
      );

      expect(message, 'Nothing was grabbed. The request did not complete.');
    });
  });
}
