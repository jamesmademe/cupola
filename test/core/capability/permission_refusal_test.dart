import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/npm/data/npm_client.dart';

DioException _status(int code) {
  final request = RequestOptions(path: '/api/v3/movie');
  return DioException(
    requestOptions: request,
    response: Response(requestOptions: request, statusCode: code),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  group('a raw Dio write', () {
    test('403 is a refusal', () {
      expect(isPermissionRefusal(_status(403)), isTrue);
    });

    test('401 is a broken credential, never a refusal', () {
      // A mistyped password must never dim a page.
      expect(isPermissionRefusal(_status(401)), isFalse);
      expect(isPermissionRefusal(_status(500)), isFalse);
    });

    test('a transport error is not a refusal', () {
      expect(
        isPermissionRefusal(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        isFalse,
      );
    });
  });

  group('Nginx Proxy Manager', () {
    test('a forbidden NpmException is a refusal', () {
      expect(
        isPermissionRefusal(
          const NpmException(
            'no',
            reason: ServiceFailureReason.unauthorized,
            forbidden: true,
          ),
        ),
        isTrue,
      );
    });

    test('a wrong password is not, though it shares the reason', () {
      expect(
        isPermissionRefusal(
          const NpmException('no', reason: ServiceFailureReason.unauthorized),
        ),
        isFalse,
      );
    });
  });

  test('anything else is not a refusal', () {
    expect(isPermissionRefusal(Exception('boom')), isFalse);
    expect(isPermissionRefusal(StateError('x')), isFalse);
  });
}
