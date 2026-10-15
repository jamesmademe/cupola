/// A connection neither of whose addresses answered the route probe: its red
/// names both, on every client and in every sentence.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/core/network/unanswered_addresses.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/domain/connection_unanswered.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

const _radarr = ConnectionUnanswered(
  home: 'nas.home.arpa:7878',
  away: 'radarr.example.net',
);

/// An adapter whose every request opens no connection, as a dead host's.
class _DeadHost implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => Future.error(
    DioException.connectionError(
      requestOptions: options,
      reason: 'refused',
      error: const SocketException('Connection refused'),
    ),
  );

  @override
  void close({bool force = false}) {}
}

Future<DioException> _failed(String baseUrl, String path) async {
  final dio = guardedDio(baseUrl: baseUrl)..httpClientAdapter = _DeadHost();
  try {
    await dio.get<Object?>(path);
  } on DioException catch (error) {
    return error;
  }
  fail('the request answered');
}

void main() {
  tearDown(UnansweredAddresses.reset);

  group('the words', () {
    test('red, did not answer, said of home and away', () {
      const reason = ServiceFailureReason.unreachableAtBoth;
      expect(failureTone(reason), StatusTone.error);
      expect(failureLabel(reason), 'Did not answer');
      expect(
        failureHeadline(reason, subject: 'Radarr'),
        'Radarr did not answer at home or away',
      );
      expect(
        failureGroupHeadline(reason, subjects: 'Radarr and Sonarr'),
        'Radarr and Sonarr did not answer at home or away',
      );
      expect(failureRemedy(reason), isNull, reason: 'Retry is the remedy');
      expect(failureRetryHelps(reason), isTrue);
    });

    test('the sentence names both addresses, one a line', () {
      expect(
        connectionFailureSentence(_radarr),
        'At home · nas.home.arpa:7878\nAway · radarr.example.net',
      );
      expect(classifyConnectionFailure(_radarr), _radarr.reason);
    });

    test('without the addresses, the sentence says either', () {
      expect(
        connectionFailureSentence(
          const ClassifiedFailure(ServiceFailureReason.unreachableAtBoth),
        ),
        'Nothing answered at either saved address: the server may be down, '
        'or this device may have no network.',
      );
    });
  });

  group('a client', () {
    test('names both addresses for a request to either', () async {
      UnansweredAddresses.update([
        (
          urls: ['http://nas.home.arpa:7878', 'https://radarr.example.net:443'],
          unanswered: _radarr,
        ),
      ]);

      for (final base in [
        'http://nas.home.arpa:7878',
        'https://radarr.example.net',
      ]) {
        final error = await _failed(base, '/api/v3/movie');
        expect(error.type, DioExceptionType.connectionError, reason: base);
        expect(error.error, same(_radarr), reason: base);
        expect(
          classifyConnectionFailure(error),
          ServiceFailureReason.unreachableAtBoth,
          reason: base,
        );
      }
    });

    test('says only what it says of any other address', () async {
      UnansweredAddresses.update([
        (urls: ['http://nas.home.arpa:7878/radarr'], unanswered: _radarr),
      ]);

      // Another service on the same host, under another path.
      final error = await _failed(
        'http://nas.home.arpa:7878/sonarr',
        '/api/v3/series',
      );

      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.unreachable,
      );
    });
  });

  group('the silence of the stack', () {
    test('said of both addresses when every service named was', () {
      expect(
        servicesDidNotAnswer(['Radarr'], scope: SilenceScope.atBoth),
        'Radarr did not answer at home or away',
      );
      expect(
        servicesDidNotAnswer([
          'Radarr',
          'Sonarr',
        ], scope: SilenceScope.nothingAnywhere),
        'No service answered, at home or away',
      );
      expect(
        servicesDidNotAnswer(['Radarr'], at: DateTime(2026, 10, 15, 12, 27)),
        'Radarr did not answer at 12:27',
      );
    });

    test('a scope for what each sentence names', () {
      const silence = StackSilence(
        silent: 2,
        atBoth: {ServiceKey.radarr},
        everyService: true,
      );
      expect(
        silence.scopeOf([ServiceKey.radarr, ServiceKey.sonarr]),
        SilenceScope.nothingAnywhere,
      );
      expect(silence.scopeOf([ServiceKey.radarr]), SilenceScope.atBoth);
      expect(silence.scopeOf([ServiceKey.sonarr]), SilenceScope.asked);

      const someAnswer = StackSilence(
        silent: 2,
        atBoth: {ServiceKey.radarr, ServiceKey.sonarr},
      );
      expect(
        someAnswer.scopeOf([ServiceKey.radarr, ServiceKey.sonarr]),
        SilenceScope.atBoth,
      );
    });
  });
}
