import 'dart:convert';

/// What a refusal from Seerr means, read from the status, the route and the
/// body together.
///
/// One status says too little. A 403 is a missing CSRF token, a session that
/// ended, a permission the account lacks, a full quota or a blocklisted title,
/// and only the body tells them apart; a 401 on cancelling a request is not a
/// rejected credential at all. Each verdict is the server's own literal text
/// (Seerr v3.5.0, the same in Overseerr 1.35.0 and Jellyseerr 1.9.2 and 2.7.3
/// wherever the route exists), matched in [classifySeerrRefusal] and nowhere
/// else.
enum SeerrRefusal {
  /// `403 invalid csrf token`: the server has CSRF protection on and this
  /// write carried no valid token. Fetch one and send the write once more.
  /// Any route, with the API key too.
  csrfToken,

  /// `403 You do not have permission to access this endpoint`: the request
  /// reached the server as nobody, or as somebody without the route's
  /// permission.
  ///
  /// With the API key it can only be the key: user 1 is an admin, and an admin
  /// passes every route. With an account it is ambiguous until `/auth/me`
  /// answers, see [afterWhoAmI].
  endpointRefused,

  /// The account's session is over: it expired, it was signed out, or the
  /// user was deleted. `/auth/me` itself refused. Sign in again.
  sessionEnded,

  /// The session is good and the account lacks the permission. Read
  /// `/auth/me` again so the gate redraws.
  permissionDenied,

  /// `POST /request` 403 `You do not have permission to make … requests.`:
  /// the account may not ask for this kind, or for it in 4K.
  requestNotAllowed,

  /// `403 Movie Quota exceeded.` or `Series Quota exceeded.`: read the quota
  /// again and say the limit.
  quotaReached,

  /// `POST /request` 403 `This media is blocklisted.`: the operator barred
  /// the title.
  blocklisted,

  /// `POST /request` 409: somebody already asked for it.
  alreadyRequested,

  /// `202 No seasons available to request`: every season is on the server or
  /// asked for already. A success status, so the transport has to look.
  noSeasonsLeft,

  /// `DELETE /request/{id}` 401: the request no longer waits for approval, so
  /// its owner can no longer cancel it.
  noLongerCancellable,

  /// `POST /auth/local` 403 `Access denied.`: no such user, or the wrong
  /// password. The server does not say which, on purpose.
  wrongEmailOrPassword,

  /// `POST /auth/jellyfin` 401 `INVALID_CREDENTIALS`: Jellyfin refused the
  /// username and password.
  wrongUsernameOrPassword,

  /// `403 Access denied.` from a Plex, Jellyfin or Quick Connect sign-in: the
  /// account is real but may not sign in here, because it is not imported and
  /// the server takes no new users, or because the Plex account has no access
  /// to the server.
  accountNotAllowed,

  /// `INVALID_URL` or `CONNECTION_ERROR` from a Jellyfin sign-in: Seerr could
  /// not reach its own Jellyfin.
  mediaServerUnreachable,

  /// `POST /auth/plex` 500 `Unable to authenticate.`: Seerr could not check
  /// the Plex account with plex.tv.
  plexCheckFailed,

  /// A sign-in method the server has turned off since the app last read
  /// `/settings/public`. Read it again and redraw the methods. Also Jellyfin's
  /// own Quick Connect turned off while a code waits, which
  /// `/settings/public` never shows.
  signInTurnedOff,

  /// The server is still in its first setup. The app never signs in to one,
  /// so this is the guard answering if it ever does.
  serverNotSetUp,

  /// A sign-in body the server rejects as incomplete. Never sent on purpose:
  /// a defect in the app, not something the user can fix.
  malformedSignIn;

  /// Whether the right next step is to read `/auth/me` again: to tell an ended
  /// session from a missing permission, and to redraw the gate from the
  /// account's current permissions.
  bool get asksWhoAmI => switch (this) {
    endpointRefused || permissionDenied || requestNotAllowed => true,
    csrfToken ||
    sessionEnded ||
    quotaReached ||
    blocklisted ||
    alreadyRequested ||
    noSeasonsLeft ||
    noLongerCancellable ||
    wrongEmailOrPassword ||
    wrongUsernameOrPassword ||
    accountNotAllowed ||
    mediaServerUnreachable ||
    plexCheckFailed ||
    signInTurnedOff ||
    serverNotSetUp ||
    malformedSignIn => false,
  };

  /// This verdict once `GET /auth/me` answered [whoAmIStatus], for an account
  /// connection.
  ///
  /// A 403 there means no session at all, whatever the first refusal said. A
  /// 200 turns an [endpointRefused] into [permissionDenied] and leaves every
  /// other verdict as it was. Anything else, a timeout included, settles
  /// nothing.
  SeerrRefusal afterWhoAmI(int? whoAmIStatus) {
    if (!asksWhoAmI) return this;
    return switch (whoAmIStatus) {
      403 => SeerrRefusal.sessionEnded,
      200 when this == SeerrRefusal.endpointRefused =>
        SeerrRefusal.permissionDenied,
      _ => this,
    };
  }
}

/// What Seerr meant by refusing `method path` with [status] and [body], or
/// null when the answer is not one of Seerr's own refusals.
///
/// [path] may be the whole URL or the route alone, with or without
/// `/api/v1`. [body] is the decoded JSON or its text. Seerr writes its errors
/// in two shapes, `{message}` from its error handler and `{error}` from its
/// permission check and a few early returns, and both are read.
///
/// The literal text is required everywhere. A bare 401 or 403 is not enough:
/// an access gateway in front of the server answers those too, in its own
/// words, and reading one as "the request is no longer cancellable" would be
/// a guess.
SeerrRefusal? classifySeerrRefusal({
  required int? status,
  required String method,
  required String path,
  Object? body,
}) {
  final text = _textOf(body);
  if (status == null || text == null) return null;
  final verb = method.toUpperCase();
  final route = _routeOf(path);

  // `@dr.pogodin/csurf` 1.16.9 (`build/cjs/index.js:256`), mounted ahead of
  // every route (`server/index.ts:195-214`).
  if (status == 403 && text == 'invalid csrf token') {
    return SeerrRefusal.csrfToken;
  }

  if (route.isNotEmpty && route.first == 'auth') {
    final signIn = _signInRefusal(status, verb, route, text);
    if (signIn != null) return signIn;
  }

  if (route.isNotEmpty && route.first == 'request') {
    final request = _requestRefusal(status, verb, route, text);
    if (request != null) return request;
  }

  // `server/middleware/auth.ts:48-52`, every route behind `isAuthenticated`.
  if (status == 403 &&
      text == 'You do not have permission to access this endpoint') {
    return SeerrRefusal.endpointRefused;
  }

  // A route's own check on a signed-in user: "You do not have permission to
  // view this user's requests.", "... to modify this request.", "... to
  // modify this issue." (a 401), and the rest of them.
  if ((status == 401 || status == 403) &&
      text.startsWith('You do not have permission to ')) {
    return SeerrRefusal.permissionDenied;
  }
  return null;
}

/// The sign-in routes, `server/routes/auth.ts` v3.5.0.
SeerrRefusal? _signInRefusal(
  int status,
  String verb,
  List<String> route,
  String text,
) {
  final denied = status == 403 && text == 'Access denied.';
  if (verb == 'GET' && route.length == 2 && route[1] == 'me') {
    // `/me` is the question every other answer is resolved with; refused,
    // it is the answer (`auth.ts:33`).
    final refused =
        status == 403 &&
        text == 'You do not have permission to access this endpoint';
    return refused ? SeerrRefusal.sessionEnded : null;
  }
  // `auth.ts:675-712`, Seerr 3.4.0 and later. With its own Quick Connect off,
  // Jellyfin refuses every check, and Seerr relays its 401 (Seerr 3.4.1 on
  // Jellyfin 12.1, live). `/settings/public` does not say Jellyfin turned it
  // off. Only this route reads so: a 401 anywhere else means something else.
  if (verb == 'GET' &&
      route.length == 4 &&
      route[1] == 'jellyfin' &&
      route[2] == 'quickconnect' &&
      route[3] == 'check') {
    final off = status == 401 && text == 'Failed to check Quick Connect status';
    return off ? SeerrRefusal.signInTurnedOff : null;
  }
  if (verb != 'POST' || route.length < 2) return null;

  // `auth.ts:640-851`, Seerr 3.4.0 and later.
  if (route.length == 4 &&
      route[1] == 'jellyfin' &&
      route[2] == 'quickconnect') {
    if (status != 403) return null;
    if (text == 'Quick Connect is only supported by Jellyfin.') {
      return SeerrRefusal.signInTurnedOff;
    }
    if (text == 'Quick Connect is not available during initial setup.') {
      return SeerrRefusal.serverNotSetUp;
    }
    return denied ? SeerrRefusal.accountNotAllowed : null;
  }
  if (route.length != 2) return null;

  switch (route[1]) {
    case 'local':
      // `auth.ts:853-903`.
      if (denied) return SeerrRefusal.wrongEmailOrPassword;
      if (status == 500 && text == 'Password sign-in is disabled.') {
        return SeerrRefusal.signInTurnedOff;
      }
    case 'jellyfin':
      // `auth.ts:246-638`, with `server/api/jellyfin.ts` naming the cause.
      if (status == 401 && text == 'INVALID_CREDENTIALS') {
        return SeerrRefusal.wrongUsernameOrPassword;
      }
      if (denied) return SeerrRefusal.accountNotAllowed;
      if (text == 'INVALID_URL' || text == 'CONNECTION_ERROR') {
        return SeerrRefusal.mediaServerUnreachable;
      }
      if (status == 500 && text == 'Jellyfin login is disabled') {
        return SeerrRefusal.signInTurnedOff;
      }
      // Thrown only while the server has no media server yet (`:334-350`).
      if (text == 'NOT_ADMIN' || text == 'NO_ADMIN_USER') {
        return SeerrRefusal.serverNotSetUp;
      }
    case 'plex':
      // `auth.ts:69-244`.
      if (denied) return SeerrRefusal.accountNotAllowed;
      if (status == 500 && text == 'Plex login is disabled') {
        return SeerrRefusal.signInTurnedOff;
      }
      if (status == 500 && text == 'Unable to authenticate.') {
        return SeerrRefusal.plexCheckFailed;
      }
  }
  if (status == 500 && _incompleteSignIns.contains(text)) {
    return SeerrRefusal.malformedSignIn;
  }
  return null;
}

/// What the sign-in routes answer a body that lacks a field, or carries one
/// only the first setup sends.
const _incompleteSignIns = {
  'You must provide both an email address and a password.',
  'You must provide an username',
  'Jellyfin hostname already configured',
  'No hostname provided.',
  'Authentication token required.',
};

/// The request routes, `server/routes/request.ts` v3.5.0 over
/// `server/entity/MediaRequest.ts`.
SeerrRefusal? _requestRefusal(
  int status,
  String verb,
  List<String> route,
  String text,
) {
  final create = verb == 'POST' && route.length == 1;
  final one = route.length == 2 && int.tryParse(route[1]) != null;
  final edit = verb == 'PUT' && one;
  if (!create && !edit) {
    // `request.ts:706-737`: the owner of a request that no longer waits.
    if (verb == 'DELETE' &&
        one &&
        status == 401 &&
        text == 'You do not have permission to delete this request.') {
      return SeerrRefusal.noLongerCancellable;
    }
    return null;
  }

  // `MediaRequest.ts:160,165,421` and `request.ts:536,664`.
  if (status == 403 &&
      (text == 'Movie Quota exceeded.' || text == 'Series Quota exceeded.')) {
    return SeerrRefusal.quotaReached;
  }
  // `request.ts:633` and `MediaRequest.ts:415`.
  if (status == 202 && text == 'No seasons available to request') {
    return SeerrRefusal.noSeasonsLeft;
  }
  if (!create) return null;
  // `MediaRequest.ts:118-138`: "You do not have permission to make movie
  // requests.", "... 4K series requests." and the two between.
  if (status == 403 && text.startsWith('You do not have permission to make ')) {
    return SeerrRefusal.requestNotAllowed;
  }
  // `MediaRequest.ts:198`.
  if (status == 403 && text == 'This media is blocklisted.') {
    return SeerrRefusal.blocklisted;
  }
  // `MediaRequest.ts:243-261`: a request, or an auto-request, already there.
  if (status == 409 &&
      (text == 'Request for this media already exists.' ||
          text == 'Auto-request for this media and user already exists.')) {
    return SeerrRefusal.alreadyRequested;
  }
  return null;
}

/// `message ?? error`, from a decoded body or its text.
String? _textOf(Object? body) {
  var value = body;
  if (value is String) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
  if (value is! Map) return null;
  final message = value['message'];
  if (message is String && message.isNotEmpty) return message;
  final error = value['error'];
  if (error is String && error.isNotEmpty) return error;
  return null;
}

/// The route's segments after `/api/v1`, without a query: `['request', '7']`.
List<String> _routeOf(String path) {
  final uri = Uri.tryParse(path);
  var route = uri?.path ?? path;
  const prefix = '/api/v1/';
  final at = route.indexOf(prefix);
  if (at >= 0) route = route.substring(at + prefix.length);
  return route.split('/').where((segment) => segment.isNotEmpty).toList();
}
