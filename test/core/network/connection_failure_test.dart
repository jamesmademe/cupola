import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_only_at_home.dart';

DioException _badResponse(int code) => DioException(
  requestOptions: RequestOptions(path: '/'),
  type: DioExceptionType.badResponse,
  response: Response(
    requestOptions: RequestOptions(path: '/'),
    statusCode: code,
  ),
);

DioException _wrapping(Object? inner, DioExceptionType type) => DioException(
  requestOptions: RequestOptions(path: '/'),
  type: type,
  error: inner,
);

class _KnowsWhy implements Exception, HasFailureReason {
  const _KnowsWhy(this.reason);
  @override
  final ServiceFailureReason reason;
}

class _KnowsWhyAndSaysSo
    implements Exception, HasFailureReason, HasFailureDetail {
  const _KnowsWhyAndSaysSo(this.reason, this.failureDetail);
  @override
  final ServiceFailureReason reason;
  @override
  final String failureDetail;
}

void main() {
  group('classifyConnectionFailure', () {
    test('trusts an exception that already knows why it failed', () {
      expect(
        classifyConnectionFailure(
          const _KnowsWhy(ServiceFailureReason.unauthorized),
        ),
        ServiceFailureReason.unauthorized,
      );
    });

    test('401 and 403 are rejected credentials, not unreachability', () {
      expect(
        classifyConnectionFailure(_badResponse(401)),
        ServiceFailureReason.unauthorized,
      );
      expect(
        classifyConnectionFailure(_badResponse(403)),
        ServiceFailureReason.unauthorized,
      );
    });

    test('404 points at the wrong base path', () {
      expect(
        classifyConnectionFailure(_badResponse(404)),
        ServiceFailureReason.notFound,
      );
    });

    test('5xx is the server, not the client config', () {
      expect(
        classifyConnectionFailure(_badResponse(503)),
        ServiceFailureReason.serverError,
      );
    });

    test('an unmapped status stays unknown', () {
      expect(
        classifyConnectionFailure(_badResponse(418)),
        ServiceFailureReason.unknown,
      );
    });

    test('a timeout after connecting is a timeout', () {
      for (final type in [
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(
          classifyConnectionFailure(_wrapping(null, type)),
          ServiceFailureReason.timeout,
          reason: '$type should be a timeout',
        );
      }
    });

    test('a connection that never completed did not answer', () {
      // Nothing replied at the address: the brand book's red, not the amber
      // of a server that was reached and then ran out of time.
      expect(
        classifyConnectionFailure(
          _wrapping(null, DioExceptionType.connectionTimeout),
        ),
        ServiceFailureReason.unreachable,
      );
    });

    test('a body nobody can read is an invalid response, not silence', () {
      expect(
        classifyConnectionFailure(
          _wrapping(
            const FormatException('Unexpected character <'),
            DioExceptionType.unknown,
          ),
        ),
        ServiceFailureReason.invalidResponse,
      );
      expect(
        classifyConnectionFailure(const FormatException('<html>')),
        ServiceFailureReason.invalidResponse,
      );
    });

    test('badCertificate is a TLS problem', () {
      expect(
        classifyConnectionFailure(
          _wrapping(null, DioExceptionType.badCertificate),
        ),
        ServiceFailureReason.tls,
      );
    });

    test('unwraps the cause Dio buries in connectionError', () {
      expect(
        classifyConnectionFailure(
          _wrapping(
            const SocketException('refused'),
            DioExceptionType.connectionError,
          ),
        ),
        ServiceFailureReason.unreachable,
      );
      expect(
        classifyConnectionFailure(
          _wrapping(
            const HandshakeException(
              'Handshake error in client',
              OSError('CERTIFICATE_VERIFY_FAILED: unable to get local issuer'),
            ),
            DioExceptionType.connectionError,
          ),
        ),
        ServiceFailureReason.tls,
      );
    });

    test('a connectionError with no inner cause is still unreachable', () {
      expect(
        classifyConnectionFailure(
          _wrapping(null, DioExceptionType.connectionError),
        ),
        ServiceFailureReason.unreachable,
      );
    });

    test('bare socket, TLS and timeout errors are classified', () {
      expect(
        classifyConnectionFailure(const SocketException('no route')),
        ServiceFailureReason.unreachable,
      );
      expect(
        classifyConnectionFailure(
          const HandshakeException(
            'CERTIFICATE_VERIFY_FAILED: certificate has expired',
          ),
        ),
        ServiceFailureReason.tls,
      );
      // A deadline around a whole request cannot prove the host was reached,
      // and what it does know is that nothing came back.
      expect(
        classifyConnectionFailure(TimeoutException('slow')),
        ServiceFailureReason.unreachable,
      );
    });

    test('an unattributable error returns the caller fallback', () {
      // Socket.IO reports connect failures as an untyped string.
      expect(classifyConnectionFailure('boom'), ServiceFailureReason.unknown);
      expect(
        classifyConnectionFailure(
          'boom',
          fallback: ServiceFailureReason.unreachable,
        ),
        ServiceFailureReason.unreachable,
      );
      expect(
        classifyConnectionFailure(
          null,
          fallback: ServiceFailureReason.unreachable,
        ),
        ServiceFailureReason.unreachable,
      );
    });

    test('the fallback never overrides an attributed cause', () {
      expect(
        classifyConnectionFailure(
          _badResponse(401),
          fallback: ServiceFailureReason.unreachable,
        ),
        ServiceFailureReason.unauthorized,
      );
    });

    // An interceptor that refuses a request reaches its verdict *and* has Dio
    // wrap it in a DioException carrying whatever status happened to trigger
    // the refusal. Re-deriving the reason from that status throws the verdict
    // away, which is how refused redirects once all collapsed to `unknown`.
    // The status here maps to something real now, so this asserts the verdict
    // still wins rather than merely filling a gap.
    test('an interceptor verdict wrapped by Dio beats the status code', () {
      final wrapped = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 302,
        ),
        error: const _KnowsWhy(ServiceFailureReason.unauthorized),
      );
      expect(
        classifyConnectionFailure(wrapped),
        ServiceFailureReason.unauthorized,
      );
    });

    test('a wrapped verdict still wins over the caller fallback', () {
      expect(
        classifyConnectionFailure(
          _wrapping(
            const _KnowsWhy(ServiceFailureReason.unauthorized),
            DioExceptionType.unknown,
          ),
          fallback: ServiceFailureReason.unreachable,
        ),
        ServiceFailureReason.unauthorized,
      );
    });
  });

  group('https to a port that speaks plain http', () {
    // What dart:io raises on nginx, Kestrel, Jellyfin or Transmission's http
    // port, verbatim.
    const plainReply = HandshakeException(
      'Handshake error in client',
      OSError('\n\tWRONG_VERSION_NUMBER(tls_record.cc:127)'),
    );

    test('is a port without https, not a certificate to trust', () {
      expect(
        classifyConnectionFailure(plainReply),
        ServiceFailureReason.plainHttp,
      );
      expect(
        classifyConnectionFailure(
          _wrapping(plainReply, DioExceptionType.connectionError),
        ),
        ServiceFailureReason.plainHttp,
      );
      expect(
        classifyConnectionFailure(
          _wrapping(plainReply, DioExceptionType.unknown),
        ),
        ServiceFailureReason.plainHttp,
      );
    });

    test('a certificate that did not verify is a certificate, on every '
        'platform', () {
      for (final said in const [
        // Android and Linux.
        'CERTIFICATE_VERIFY_FAILED: self signed certificate',
        'CERTIFICATE_VERIFY_FAILED: Hostname mismatch',
        // macOS and iOS, where the platform's trust decides.
        'CERTIFICATE_VERIFY_FAILED: application verification failure',
      ]) {
        expect(
          classifyConnectionFailure(
            HandshakeException('Handshake error in client', OSError(said)),
          ),
          ServiceFailureReason.tls,
          reason: said,
        );
      }
      expect(
        classifyConnectionFailure(const CertificateException('pin')),
        ServiceFailureReason.tls,
      );
    });

    test('a handshake that broke off before any certificate is no secure '
        'connection, not a certificate', () {
      for (final error in const [
        // NZBGet on its http port: it hangs up on the TLS hello.
        HandshakeException('Connection terminated during handshake'),
        HandshakeException(
          'Handshake error in client',
          OSError('TLSV1_ALERT_PROTOCOL_VERSION'),
        ),
      ]) {
        expect(
          classifyConnectionFailure(error),
          ServiceFailureReason.noSecureConnection,
        );
        expect(
          classifyConnectionFailure(
            _wrapping(error, DioExceptionType.connectionError),
          ),
          ServiceFailureReason.noSecureConnection,
        );
      }
    });

    test('no secure connection is amber, with the address to check', () {
      const reason = ServiceFailureReason.noSecureConnection;
      expect(failureTone(reason), StatusTone.warning);
      expect(failureLabel(reason), 'No secure connection');
      expect(
        failureHeadline(reason, subject: 'NZBGet'),
        'NZBGet did not open a secure connection',
      );
      expect(failureRemedy(reason), 'Check the address');
      expect(failureDidNotAnswer(reason), isFalse);
    });

    test('is an amber fault, with the port to check and no retry', () {
      const reason = ServiceFailureReason.plainHttp;
      expect(failureTone(reason), StatusTone.warning);
      expect(failureLabel(reason), 'No https on this port');
      expect(
        failureHeadline(reason, subject: 'TrueNAS'),
        'TrueNAS answered in plain http',
      );
      expect(
        failureGroupHeadline(reason, subjects: 'Radarr, Sonarr'),
        'Radarr, Sonarr answered in plain http',
      );
      expect(failureRemedy(reason), 'Check the port');
      expect(failureRetryHelps(reason), isFalse);
      expect(
        connectionFailureSentence(plainReply, remedyBeside: true),
        'Its address names a port that serves http. Use the one that serves '
        'https.',
      );
    });
  });

  group('connectionFailureDetail', () {
    test('reads the sentence off the failure itself', () {
      expect(
        connectionFailureDetail(
          const _KnowsWhyAndSaysSo(
            ServiceFailureReason.notFound,
            'the proxy sent you to another host',
          ),
        ),
        'the proxy sent you to another host',
      );
    });

    test('unwraps the DioException Dio puts around it', () {
      expect(
        connectionFailureDetail(
          _wrapping(
            const _KnowsWhyAndSaysSo(ServiceFailureReason.notFound, 'why'),
            DioExceptionType.badResponse,
          ),
        ),
        'why',
      );
    });

    test('is null for the ordinary failures that carry no sentence', () {
      expect(connectionFailureDetail(_badResponse(401)), isNull);
      expect(
        connectionFailureDetail(const SocketException('no route')),
        isNull,
      );
      expect(connectionFailureDetail(null), isNull);
      expect(connectionFailureDetail('boom'), isNull);
    });
  });

  group('looksUnauthorizedMessage', () {
    test('matches the wording SABnzbd and Unraid actually use', () {
      for (final message in [
        'API Key Incorrect',
        'Unauthorized',
        'Forbidden',
        'Access denied',
        'Not logged in',
      ]) {
        expect(
          looksUnauthorizedMessage(message),
          isTrue,
          reason: '"$message" should read as an auth failure',
        );
      }
    });

    test('does not claim auth failure for unrelated errors', () {
      expect(looksUnauthorizedMessage('Queue is empty'), isFalse);
      expect(looksUnauthorizedMessage('Disk full'), isFalse);
    });
  });

  group('reasonForStatusCode', () {
    test('maps the statuses the UI can act on', () {
      expect(reasonForStatusCode(401), ServiceFailureReason.unauthorized);
      expect(reasonForStatusCode(404), ServiceFailureReason.notFound);
      expect(reasonForStatusCode(500), ServiceFailureReason.serverError);
    });

    // These used to collapse to `unknown`, which reaches the user as "Could
    // not verify the instance. Double-check the address and credentials.":
    // sending them to re-check a credential the server never looked at.
    test('an unfollowable 3xx is a redirect, not an unknown', () {
      for (final status in const [300, 301, 302, 303, 304, 307, 308]) {
        expect(
          reasonForStatusCode(status),
          ServiceFailureReason.redirected,
          reason: '$status',
        );
      }
    });

    test('an unmapped 4xx stays unknown', () {
      expect(reasonForStatusCode(418), ServiceFailureReason.unknown);
    });
  });

  group('connectionFailureSentence', () {
    test('never prints the exception, only the cause in plain words', () {
      final refused = DioException.connectionError(
        requestOptions: RequestOptions(path: '/'),
        reason: 'Connection refused',
      );
      final sentence = connectionFailureSentence(refused);

      expect(sentence, isNot(contains('DioException')));
      expect(sentence, isNot(contains('solved by the library')));
      expect(sentence, startsWith('Nothing answered at the saved address.'));
    });

    test('names the fault a reachable server reported', () {
      expect(
        connectionFailureSentence(_badResponse(401)),
        'The server answered and refused the saved credentials. Check them in '
        'Settings.',
      );
      expect(
        connectionFailureSentence(_badResponse(503)),
        'The server answered with an error of its own. Its logs will say why.',
      );
    });

    test('keeps a failure\'s own verbatim sentence', () {
      expect(
        connectionFailureSentence(const _Explained('Redirected to evil.test.')),
        'Redirected to evil.test.',
      );
    });

    test('an error nobody can attribute says so, without its class', () {
      expect(
        connectionFailureSentence(StateError('bad state: parser')),
        'The request did not complete.',
      );
    });
  });

  group('failureIsFault', () {
    test('red is silence and nothing else; everything else is amber', () {
      // Silence at the address in use, or at both of a connection's.
      for (final silent in [
        ServiceFailureReason.unreachable,
        ServiceFailureReason.unreachableAtBoth,
      ]) {
        expect(failureIsFault(silent), isFalse, reason: silent.name);
        expect(failureDidNotAnswer(silent), isTrue, reason: silent.name);
        expect(failureTone(silent), StatusTone.error, reason: silent.name);
      }
      for (final reason in ServiceFailureReason.values.where(
        (r) =>
            r != ServiceFailureReason.unreachable &&
            r != ServiceFailureReason.unreachableAtBoth &&
            r != ServiceFailureReason.sessionEnded &&
            r != ServiceFailureReason.onlyAtHome,
      )) {
        // `unknown` included: a failure nobody can attribute is no evidence
        // that the host is silent.
        expect(failureIsFault(reason), isTrue, reason: reason.name);
        expect(failureDidNotAnswer(reason), isFalse, reason: reason.name);
        expect(failureTone(reason), StatusTone.warning, reason: reason.name);
      }
    });
  });

  group('a connection only at home, away from it', () {
    test('is neutral, never a fault, never silence', () {
      const reason = ServiceFailureReason.onlyAtHome;
      expect(failureTone(reason), StatusTone.neutral);
      expect(failureIsFault(reason), isFalse);
      expect(failureDidNotAnswer(reason), isFalse);
      expect(failureLabel(reason), 'Only at home');
      expect(
        failureHeadline(reason, subject: 'Lidarr'),
        'Lidarr only works at home',
      );
      expect(
        failureGroupHeadline(reason, subjects: 'Lidarr and SABnzbd'),
        'Lidarr and SABnzbd only work at home',
      );
      expect(failureRemedy(reason), 'Add an address away');
      // Nothing was asked, and asking again from here asks nothing.
      expect(failureRetryHelps(reason), isFalse);
    });

    test('is what the transport throws, read by its reason', () {
      expect(
        classifyConnectionFailure(const ServiceOnlyAtHome(ServiceKey.lidarr)),
        ServiceFailureReason.onlyAtHome,
      );
    });
  });

  group('a Seerr session that ended', () {
    test('is blue, the person\'s own step, and never a fault', () {
      const reason = ServiceFailureReason.sessionEnded;
      expect(failureTone(reason), StatusTone.info);
      expect(failureIsFault(reason), isFalse);
      expect(failureDidNotAnswer(reason), isFalse);
    });

    test('says signed out, and leads to signing in again', () {
      const reason = ServiceFailureReason.sessionEnded;
      expect(failureLabel(reason), 'Signed out');
      expect(failureHeadline(reason, subject: 'Seerr'), 'Signed out of Seerr');
      expect(failureRemedy(reason), 'Sign in again');
      expect(
        connectionFailureSentence(const ClassifiedFailure(reason)),
        'Sign in again to keep asking for movies and series.',
      );
      // No request revives a session: no Retry beside the remedy.
      expect(failureRetryHelps(reason), isFalse);
    });
  });

  group('a CSRF token Seerr refused twice', () {
    test('is an amber fault that Retry may still clear', () {
      const reason = ServiceFailureReason.csrfRefused;
      expect(failureTone(reason), StatusTone.warning);
      expect(
        failureHeadline(reason, subject: 'Seerr'),
        "Seerr refused the request's security token",
      );
      expect(failureLabel(reason), 'Security token refused');
      expect(failureRemedy(reason), isNull);
      expect(failureRetryHelps(reason), isTrue);
      expect(
        connectionFailureSentence(const ClassifiedFailure(reason)),
        'Nothing changed. Retry in a moment.',
      );
    });
  });

  group('the failure words', () {
    test('"Did not answer" is the only red label, and never contracted', () {
      expect(failureLabel(ServiceFailureReason.unreachable), 'Did not answer');
      expect(
        failureHeadline(ServiceFailureReason.unreachable, subject: 'Radarr'),
        'Radarr did not answer',
      );
      for (final reason in ServiceFailureReason.values) {
        final words = [
          failureLabel(reason),
          failureHeadline(reason, subject: 'Radarr'),
          ?failureRemedy(reason),
        ];
        for (final word in words) {
          expect(word, isNot(contains("n't")), reason: reason.name);
          // The brand book's banned list, for the words this owns.
          for (final banned in const [
            'Unreachable',
            'unreachable',
            'Offline',
            'Online',
            'not answering',
            'did not respond',
            'Try again',
            'Error 401',
          ]) {
            expect(word, isNot(contains(banned)), reason: reason.name);
          }
        }
      }
    });

    test('a refusal says it answered, and names what it refused', () {
      expect(
        failureHeadline(ServiceFailureReason.unauthorized, subject: 'Radarr'),
        'Radarr answered but refused the key',
      );
      expect(
        failureRemedy(ServiceFailureReason.unauthorized),
        'Paste the key again',
      );
      expect(
        failureHeadline(
          ServiceFailureReason.unauthorized,
          subject: 'qBittorrent',
          credential: kRefusedSignIn,
        ),
        'qBittorrent answered but refused the sign-in',
      );
      expect(
        failureRemedy(
          ServiceFailureReason.unauthorized,
          credential: kRefusedSignIn,
        ),
        'Sign in again',
      );
    });

    test('Retry is the remedy where the form cannot fix it', () {
      for (final reason in const [
        ServiceFailureReason.unreachable,
        ServiceFailureReason.timeout,
        ServiceFailureReason.serverError,
      ]) {
        expect(failureRemedy(reason), isNull, reason: reason.name);
      }
      expect(
        failureRemedy(ServiceFailureReason.insecureTransport),
        'Change the address',
      );
    });

    test('a classified failure keeps its verdict and its own sentence', () {
      final kept = ClassifiedFailure.of(
        const _KnowsWhyAndSaysSo(
          ServiceFailureReason.insecureTransport,
          'TrueNAS needs an https:// address.',
        ),
      );
      expect(
        classifyConnectionFailure(kept),
        ServiceFailureReason.insecureTransport,
      );
      expect(
        connectionFailureDetail(kept),
        'TrueNAS needs an https:// address.',
      );
      // Without a sentence of its own, it lends none: the reason's copy wins.
      expect(
        connectionFailureDetail(ClassifiedFailure.of(_badResponse(401))),
        isNull,
      );
    });
  });

  test('a failure a provider rethrows is classified by its cause', () {
    // A client provider that refused to build, read by another while in
    // error: Riverpod rethrows it wrapped, and the wrapper alone said
    // nothing, so every such failure read as one nobody could attribute.
    final client = Provider<Object>(
      (ref) => throw DioException(
        requestOptions: RequestOptions(path: '/api/v3/movie'),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/v3/movie'),
          statusCode: 401,
        ),
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Object? failure;
    try {
      container.read(client);
    } catch (error) {
      failure = error;
    }

    expect(failure, isNot(isA<DioException>()));
    expect(
      classifyConnectionFailure(failure),
      ServiceFailureReason.unauthorized,
    );
    expect(unwrapFailure(failure), isA<DioException>());
  });

  group('a parallel wait', () {
    test('is classified by the request that failed, not as unknown', () async {
      // `(a, b).wait` throws a ParallelWaitError, which carries no reason of
      // its own: without unwrapping, a Radarr that did not answer the add
      // sheet's two reads read as a failure nobody could attribute.
      Object? caught;
      try {
        await (
          Future<int>.value(1),
          Future<int>.error(const SocketException('Connection refused')),
        ).wait;
      } catch (error) {
        caught = error;
      }
      expect(caught, isA<ParallelWaitError>());
      expect(
        classifyConnectionFailure(caught),
        ServiceFailureReason.unreachable,
      );
    });

    test('over a list unwraps too', () async {
      Object? caught;
      try {
        await [Future<int>.value(1), Future<int>.error(_badResponse(401))].wait;
      } catch (error) {
        caught = error;
      }
      expect(
        classifyConnectionFailure(caught),
        ServiceFailureReason.unauthorized,
      );
    });
  });

  group('failureServiceMessage', () {
    DioException answered(Object? data) => DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/'),
        statusCode: 400,
        data: data,
      ),
    );

    test('reads a message field verbatim', () {
      expect(
        failureServiceMessage(answered({'message': 'Movie already added'})),
        'Movie already added',
      );
    });

    test('reads every validation entry of an arr 400', () {
      expect(
        failureServiceMessage(
          answered([
            {'propertyName': 'Path', 'errorMessage': 'Path is required'},
            {'propertyName': 'Title', 'errorMessage': 'Title is required'},
          ]),
        ),
        'Path is required Title is required',
      );
    });

    test('leaves a bare string body alone: it is often a proxy page', () {
      expect(failureServiceMessage(answered('<html>502</html>')), isNull);
      expect(failureServiceMessage(Exception('x')), isNull);
    });
  });

  group('failureDiagnostic', () {
    test('never the text of a transport failure', () {
      final line = failureDiagnostic(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
          error: const SocketException('Connection refused'),
        ),
      );
      expect(line, startsWith('Nothing answered at the saved address.'));
      expect(line, isNot(contains('DioException')));
    });

    test("keeps the app's own sentence without Dart's type prefix", () {
      expect(failureDiagnostic(Exception('empty folder')), 'empty folder');
      expect(
        failureDiagnostic(StateError('refuses http://')),
        'refuses http://',
      );
    });

    test('reads internals as the classification sentence', () {
      expect(failureDiagnostic(TypeError()), 'The request did not complete.');
    });
  });
}

class _Explained implements Exception, HasFailureDetail {
  const _Explained(this.failureDetail);

  @override
  final String failureDetail;
}
