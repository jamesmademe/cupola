import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/seerr_refusal.dart';

/// Seerr writes an error in two shapes. Its error handler turns
/// `next({status, message})` into `{message, errors}` (`server/index.ts:271-286`,
/// `errors` dropped when undefined); `isAuthenticated` and a few early
/// returns write `{status?, error}` themselves.
Map<String, dynamic> _message(String text) => {'message': text};
Map<String, dynamic> _error(String text) => {'status': 403, 'error': text};

SeerrRefusal? _classify(int status, String method, String path, Object? body) =>
    classifySeerrRefusal(
      status: status,
      method: method,
      path: path,
      body: body,
    );

const _endpoint = 'You do not have permission to access this endpoint';

void main() {
  group('the literal refusals of Seerr v3.5.0', () {
    // (status, method, path, body, verdict), each with the line that sends it.
    final rows = <(int, String, String, Object, SeerrRefusal)>[
      // `@dr.pogodin/csurf` 1.16.9 `build/cjs/index.js:256`, any write.
      (
        403,
        'POST',
        '/api/v1/request',
        _message('invalid csrf token'),
        SeerrRefusal.csrfToken,
      ),
      (
        403,
        'DELETE',
        '/api/v1/media/12',
        _message('invalid csrf token'),
        SeerrRefusal.csrfToken,
      ),
      // `server/middleware/auth.ts:49-52`.
      (
        403,
        'POST',
        '/api/v1/request/4/approve',
        _error(_endpoint),
        SeerrRefusal.endpointRefused,
      ),
      (
        403,
        'GET',
        '/api/v1/settings/radarr',
        _error(_endpoint),
        SeerrRefusal.endpointRefused,
      ),
      // `server/routes/auth.ts:33`: `/me` behind `isAuthenticated()`.
      (
        403,
        'GET',
        '/api/v1/auth/me',
        _error(_endpoint),
        SeerrRefusal.sessionEnded,
      ),
      // `server/entity/MediaRequest.ts:118-138`.
      for (final text in [
        'You do not have permission to make movie requests.',
        'You do not have permission to make 4K movie requests.',
        'You do not have permission to make series requests.',
        'You do not have permission to make 4K series requests.',
      ])
        (
          403,
          'POST',
          '/api/v1/request',
          _message(text),
          SeerrRefusal.requestNotAllowed,
        ),
      // `MediaRequest.ts:153-154`, bypass asked for without MANAGE_REQUESTS.
      (
        403,
        'POST',
        '/api/v1/request',
        _message('You do not have permission to bypass user quota limits.'),
        SeerrRefusal.permissionDenied,
      ),
      // `MediaRequest.ts:160,165,421`, and the edit at `request.ts:536,664`.
      (
        403,
        'POST',
        '/api/v1/request',
        _message('Movie Quota exceeded.'),
        SeerrRefusal.quotaReached,
      ),
      (
        403,
        'POST',
        '/api/v1/request',
        _message('Series Quota exceeded.'),
        SeerrRefusal.quotaReached,
      ),
      (
        403,
        'PUT',
        '/api/v1/request/9',
        _message('Series Quota exceeded.'),
        SeerrRefusal.quotaReached,
      ),
      // `MediaRequest.ts:198`.
      (
        403,
        'POST',
        '/api/v1/request',
        _message('This media is blocklisted.'),
        SeerrRefusal.blocklisted,
      ),
      // `MediaRequest.ts:243-261`.
      (
        409,
        'POST',
        '/api/v1/request',
        _message('Request for this media already exists.'),
        SeerrRefusal.alreadyRequested,
      ),
      (
        409,
        'POST',
        '/api/v1/request',
        _message('Auto-request for this media and user already exists.'),
        SeerrRefusal.alreadyRequested,
      ),
      // `MediaRequest.ts:415` through `request.ts:334`, and `request.ts:633`.
      (
        202,
        'POST',
        '/api/v1/request',
        _message('No seasons available to request'),
        SeerrRefusal.noSeasonsLeft,
      ),
      (
        202,
        'PUT',
        '/api/v1/request/9',
        _message('No seasons available to request'),
        SeerrRefusal.noSeasonsLeft,
      ),
      // `request.ts:717-726`: a 401, not a 403.
      (
        401,
        'DELETE',
        '/api/v1/request/9',
        _message('You do not have permission to delete this request.'),
        SeerrRefusal.noLongerCancellable,
      ),
      // A route's own check: `request.ts:155-156,492-493`, `issue.ts:349-350`.
      (
        403,
        'GET',
        '/api/v1/request?requestedBy=3',
        _message("You do not have permission to view this user's requests."),
        SeerrRefusal.permissionDenied,
      ),
      (
        403,
        'PUT',
        '/api/v1/request/9',
        _message('You do not have permission to modify this request.'),
        SeerrRefusal.permissionDenied,
      ),
      (
        401,
        'POST',
        '/api/v1/issue/3/resolved',
        _message('You do not have permission to modify this issue.'),
        SeerrRefusal.permissionDenied,
      ),
      // `auth.ts:853-903`.
      (
        403,
        'POST',
        '/api/v1/auth/local',
        _message('Access denied.'),
        SeerrRefusal.wrongEmailOrPassword,
      ),
      (
        500,
        'POST',
        '/api/v1/auth/local',
        {'error': 'Password sign-in is disabled.'},
        SeerrRefusal.signInTurnedOff,
      ),
      (
        500,
        'POST',
        '/api/v1/auth/local',
        {'error': 'You must provide both an email address and a password.'},
        SeerrRefusal.malformedSignIn,
      ),
      // `auth.ts:246-638`, over `server/api/jellyfin.ts:211-216`.
      (
        401,
        'POST',
        '/api/v1/auth/jellyfin',
        _message('INVALID_CREDENTIALS'),
        SeerrRefusal.wrongUsernameOrPassword,
      ),
      (
        403,
        'POST',
        '/api/v1/auth/jellyfin',
        _message('Access denied.'),
        SeerrRefusal.accountNotAllowed,
      ),
      (
        404,
        'POST',
        '/api/v1/auth/jellyfin',
        _message('INVALID_URL'),
        SeerrRefusal.mediaServerUnreachable,
      ),
      (
        502,
        'POST',
        '/api/v1/auth/jellyfin',
        _message('CONNECTION_ERROR'),
        SeerrRefusal.mediaServerUnreachable,
      ),
      (
        500,
        'POST',
        '/api/v1/auth/jellyfin',
        {'error': 'Jellyfin login is disabled'},
        SeerrRefusal.signInTurnedOff,
      ),
      (
        500,
        'POST',
        '/api/v1/auth/jellyfin',
        {'error': 'Jellyfin hostname already configured'},
        SeerrRefusal.malformedSignIn,
      ),
      (
        403,
        'POST',
        '/api/v1/auth/jellyfin',
        _message('NOT_ADMIN'),
        SeerrRefusal.serverNotSetUp,
      ),
      // `auth.ts:69-244`.
      (
        403,
        'POST',
        '/api/v1/auth/plex',
        _message('Access denied.'),
        SeerrRefusal.accountNotAllowed,
      ),
      (
        500,
        'POST',
        '/api/v1/auth/plex',
        {'error': 'Plex login is disabled'},
        SeerrRefusal.signInTurnedOff,
      ),
      (
        500,
        'POST',
        '/api/v1/auth/plex',
        _message('Unable to authenticate.'),
        SeerrRefusal.plexCheckFailed,
      ),
      (
        500,
        'POST',
        '/api/v1/auth/plex',
        _message('Authentication token required.'),
        SeerrRefusal.malformedSignIn,
      ),
      // `auth.ts:640-851`, Seerr 3.4.0 and later.
      (
        403,
        'POST',
        '/api/v1/auth/jellyfin/quickconnect/initiate',
        _message('Quick Connect is only supported by Jellyfin.'),
        SeerrRefusal.signInTurnedOff,
      ),
      (
        403,
        'POST',
        '/api/v1/auth/jellyfin/quickconnect/authenticate',
        _message('Quick Connect is not available during initial setup.'),
        SeerrRefusal.serverNotSetUp,
      ),
      (
        403,
        'POST',
        '/api/v1/auth/jellyfin/quickconnect/authenticate',
        _message('Access denied.'),
        SeerrRefusal.accountNotAllowed,
      ),
    ];

    for (final (status, method, path, body, verdict) in rows) {
      test('$status $method $path → ${verdict.name}', () {
        expect(_classify(status, method, path, body), verdict);
      });
    }
  });

  group('the shapes of an answer', () {
    test('the body may be its JSON text', () {
      expect(
        _classify(
          403,
          'POST',
          '/api/v1/request',
          jsonEncode({'message': 'Movie Quota exceeded.', 'errors': null}),
        ),
        SeerrRefusal.quotaReached,
      );
    });

    test('message is read before error', () {
      expect(
        _classify(403, 'GET', '/api/v1/auth/me', {
          'message': 'invalid csrf token',
          'error': _endpoint,
        }),
        SeerrRefusal.csrfToken,
      );
    });

    test('the route reads the same from a URL, a sub-path or bare', () {
      for (final path in [
        'https://requests.example.com/api/v1/request/9',
        'https://example.com/seerr/api/v1/request/9?x=1',
        '/request/9',
        'request/9/',
      ]) {
        expect(
          _classify(
            401,
            'delete',
            path,
            _message('You do not have permission to delete this request.'),
          ),
          SeerrRefusal.noLongerCancellable,
          reason: path,
        );
      }
    });
  });

  group('what is not a Seerr refusal', () {
    test('a bare status, without the server\'s own words', () {
      // An access gateway in front of the server answers 401 and 403 too.
      for (final (status, body) in <(int, Object?)>[
        (401, null),
        (403, '<html>Forbidden</html>'),
        (401, {'message': 'Unauthorized'}),
        (403, {'error': 'Forbidden'}),
        (403, const <String, dynamic>{}),
      ]) {
        expect(
          _classify(status, 'DELETE', '/api/v1/request/9', body),
          isNull,
          reason: '$status $body',
        );
      }
    });

    test('the right words on the wrong route', () {
      // "Access denied." means wrong credentials only where `/auth/local`
      // says it.
      expect(
        _classify(403, 'POST', '/api/v1/request', _message('Access denied.')),
        isNull,
      );
      // A 409 off `POST /request` is not "already requested".
      expect(
        _classify(
          409,
          'POST',
          '/api/v1/request/4/approve',
          _message('Only pending requests can be approved or declined.'),
        ),
        isNull,
      );
      // The 401 belongs to DELETE alone.
      expect(
        _classify(
          401,
          'GET',
          '/api/v1/request/9',
          _message('You do not have permission to delete this request.'),
        ),
        SeerrRefusal.permissionDenied,
      );
    });

    test('a success, or no status at all', () {
      expect(_classify(200, 'GET', '/api/v1/auth/me', {'id': 1}), isNull);
      expect(
        classifySeerrRefusal(
          status: null,
          method: 'GET',
          path: '/api/v1/auth/me',
          body: _error(_endpoint),
        ),
        isNull,
      );
    });
  });

  group('after /auth/me', () {
    test('a 403 there is an ended session, whatever asked', () {
      for (final verdict in [
        SeerrRefusal.endpointRefused,
        SeerrRefusal.permissionDenied,
        SeerrRefusal.requestNotAllowed,
      ]) {
        expect(verdict.asksWhoAmI, isTrue, reason: '$verdict');
        expect(verdict.afterWhoAmI(403), SeerrRefusal.sessionEnded);
      }
    });

    test('a 200 there makes the refusal a missing permission', () {
      expect(
        SeerrRefusal.endpointRefused.afterWhoAmI(200),
        SeerrRefusal.permissionDenied,
      );
      expect(
        SeerrRefusal.requestNotAllowed.afterWhoAmI(200),
        SeerrRefusal.requestNotAllowed,
      );
    });

    test('no answer there settles nothing', () {
      expect(
        SeerrRefusal.endpointRefused.afterWhoAmI(null),
        SeerrRefusal.endpointRefused,
      );
      expect(
        SeerrRefusal.endpointRefused.afterWhoAmI(502),
        SeerrRefusal.endpointRefused,
      );
    });

    test('a verdict that needs no /auth/me is left alone', () {
      for (final verdict in SeerrRefusal.values.where((v) => !v.asksWhoAmI)) {
        expect(verdict.afterWhoAmI(403), verdict, reason: '$verdict');
      }
    });
  });
}
