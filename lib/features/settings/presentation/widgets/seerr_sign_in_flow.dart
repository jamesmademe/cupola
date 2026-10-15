import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/browser_opener.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/discover/data/plex_tv_client.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/data/seerr_auth_service.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/discover/presentation/seerr_sign_in_notice.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// How long the Plex page is waited on at most, whatever plex.tv says of its
/// PIN: Seerr's own web client stops at 15 minutes too.
const _plexPatience = Duration(minutes: 15);

/// plex.tv is asked once a second, as its documentation asks of a native app,
/// through the page's own gate (`VisibilityPoller`).
const seerrPlexPollEvery = Duration(seconds: 1);

/// Seerr is asked whether a Quick Connect code was approved every 2 seconds.
const seerrQuickConnectPollEvery = Duration(seconds: 2);

/// Where a sign-in to Seerr stands.
enum SeerrSignInStage {
  /// Nothing asked yet, or back after a notice that ends the way.
  start,

  /// Reading the server's ways in.
  asking,

  /// The ways in, to choose from.
  methods,

  /// A login and a password.
  form,

  /// The credentials are with the server.
  signingIn,

  /// Waiting on the Plex page.
  plex,

  /// Waiting on a Quick Connect code.
  quickConnect,
}

/// Asks the person whether to trust the certificate [probe] found at
/// [origin]; true when they do.
typedef SeerrCertificateConsent =
    Future<bool> Function({
      required String origin,
      required UntrustedCertificateProbe probe,
      String? previousFingerprint,
    });

/// The way into a Seerr with an account of one's own, apart from how it is
/// drawn: read the server, offer the ways in it has, sign in, keep the
/// session.
///
/// One for each draft of a connection, owned by the widget that draws it:
/// the connection's form in Settings and the sign-in of the first run draw
/// the same sign-in from it, so the two never say it two ways. The password
/// lives in [password] until it is sent and is then emptied; the Plex token
/// lives in a local until Seerr has it. Neither is saved, printed or shown.
///
/// [connection] is the connection as the draft stands: the address typed,
/// its access, its name. Signing in saves it with the account.
class SeerrSignInFlow extends ChangeNotifier {
  SeerrSignInFlow({
    required WidgetRef ref,
    required ServiceInstance Function() connection,
    required SeerrCertificateConsent consent,
    CertificateProber certificateProber = probeUntrustedCertificate,
  }) : _ref = ref,
       _connectionOf = connection,
       _consent = consent,
       _certificateProber = certificateProber;

  final WidgetRef _ref;
  final ServiceInstance Function() _connectionOf;
  final SeerrCertificateConsent _consent;
  final CertificateProber _certificateProber;

  /// The login of the password form: an email, or a media server's username.
  final login = TextEditingController();

  /// The password of the password form, emptied the moment it is sent.
  final password = TextEditingController();

  SeerrSignInStage get stage => _stage;
  SeerrSignInStage _stage = SeerrSignInStage.start;

  /// What the server said of itself and its ways in, once read.
  SeerrServerFacts? get facts => _facts;
  SeerrServerFacts? _facts;

  /// The way in chosen.
  SeerrSignInMethod? get method => _method;
  SeerrSignInMethod? _method;

  /// What the last step ended with, when it did not end signed in.
  SeerrSignInNotice? get notice => _notice;
  SeerrSignInNotice? _notice;

  /// The same step again, when the notice says it can still succeed.
  VoidCallback? get retry => _retry;
  VoidCallback? _retry;

  /// The person read the warning about an `http://` address and went on.
  bool _cleartextAccepted = false;

  /// Quick Connect failed to start: Jellyfin has it off, and the server does
  /// not say so in its settings.
  bool _quickConnectOff = false;

  SeerrAuthService? _auth;
  PlexTvClient? _plexTv;
  PlexTvPin? _pin;

  /// How long the Plex page has been waited on, counted by the poll: plex.tv
  /// lets an unapproved PIN go by itself, and this is the app's own limit.
  Duration _plexWaited = Duration.zero;

  /// The Quick Connect code to enter in Jellyfin, once Seerr gave one.
  SeerrQuickConnect? get code => _code;
  SeerrQuickConnect? _code;

  bool _checking = false;
  bool _disposed = false;

  /// Whether the Plex page is being waited on: what gates its poll.
  bool get waitingOnPlex => _stage == SeerrSignInStage.plex && _pin != null;

  /// Whether a Quick Connect code is being waited on: what gates its poll.
  bool get waitingOnCode =>
      _stage == SeerrSignInStage.quickConnect && _code != null;

  ServiceInstance get _connection => _connectionOf();

  /// The host the sign-in goes to, as prose names it.
  String get host =>
      UrlUtils.hostInProse(ServiceKey.seerr.extractHost(_connection.url) ?? '');

  /// Where the server was last read, or where it will be: what Seerr's own
  /// pages (the password reset) open at.
  String get readAt => _authReach?.url ?? _reach.url;

  SeerrAuthService _authService() {
    _auth?.close();
    final reach = _authReach = _reach;
    return _auth = SeerrAuthService.forConnection(_connection, reach: reach);
  }

  /// Where the last [_authService] sends its requests: the address a failure
  /// it met belongs to.
  ConnectionReach? _authReach;

  /// Where a sign-in goes now. The saved connection, at the address it was
  /// saved with, is reached where its route is: signing in again away from
  /// home goes to the address away. An address being typed is tried where it
  /// is typed, as every connection test is.
  ConnectionReach get _reach {
    final connection = _connection;
    final settings = _ref.read(currentSettingsProvider);
    final saved = settings.instanceById(connection.id);
    final route = saved != null && saved.url == connection.url
        ? _ref.read(connectionRouteProvider(connection.id))
        : ConnectionRoute.home;
    return reachOf(settings, connection, route);
  }

  void _set(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  // === Reading the server ==================================================

  /// Reads the server's ways in. With [again], an account signing in again
  /// goes straight to the way it came in.
  Future<void> readServer({SeerrAccountSignIn? again}) async {
    _stopWaiting();
    _set(() {
      _stage = SeerrSignInStage.asking;
      _notice = null;
    });
    final auth = _authService();
    SeerrServerFacts facts;
    try {
      facts = await auth.readServer();
    } catch (error) {
      if (_disposed) return;
      if (await _trustedCertificateFor(error)) {
        if (!_disposed) return readServer(again: again);
        return;
      }
      if (_disposed) return;
      return _stop(
        SeerrSignInNotice.ofServerRead(error, url: _connection.url),
        retry: () => readServer(again: again),
      );
    }
    if (_disposed) return;
    final closed = SeerrSignInNotice.ofMethods(facts.signIn);
    _set(() {
      _facts = facts;
      _notice = closed;
      _retry = null;
      _stage = closed == null
          ? SeerrSignInStage.methods
          : SeerrSignInStage.start;
    });
    // Signing in again goes straight to the way the account came in, past
    // the warning about an unencrypted address only once it was read.
    if (closed == null && again != null) {
      final method = _methodOf(again.kind);
      if (offered.contains(method)) {
        login.text = again.login;
        if (!cleartextGate) choose(method);
      }
    }
  }

  /// Whether a password is about to go over `http://` to a host this device
  /// cannot tell is on the local network, and the person has not read the
  /// warning yet.
  bool get cleartextGate =>
      !_cleartextAccepted && passwordTravelsInClear(_reach.url);

  /// The person read the warning about an `http://` address and goes on.
  void acceptCleartext() => _set(() => _cleartextAccepted = true);

  /// When the server's certificate is one nothing trusts, asks the person to
  /// trust it before anything secret is sent. True when it is now trusted.
  Future<bool> _trustedCertificateFor(Object error) async {
    if (!certProbeWorthwhile(classifyConnectionFailure(error))) return false;
    final settings = _ref.read(currentSettingsProvider);
    // The address the request that failed went to: away from home, the
    // certificate in question is the one in front of the address away.
    final url = readAt;
    final previous = settings.pinForUrl(url);
    final probe = await _certificateProber(
      url,
      pinnedFingerprint: previous ?? '',
    );
    if (probe == null || _disposed) return false;
    final trust = await _consent(
      origin: UrlUtils.certOrigin(url) ?? url,
      probe: probe,
      previousFingerprint: previous,
    );
    if (!trust || _disposed) return false;
    await _ref
        .read(settingsProvider.notifier)
        .updateSettings(
          _ref
              .read(currentSettingsProvider)
              .copyWithTrustedCertificate(
                url: url,
                fingerprint: probe.certificate.fingerprint,
              ),
        );
    return true;
  }

  /// The ways in the server offers, less one found off on the way.
  List<SeerrSignInMethod> get offered => [
    for (final method in _facts?.signIn.offered ?? const <SeerrSignInMethod>[])
      if (!(_quickConnectOff &&
          method == SeerrSignInMethod.jellyfinQuickConnect))
        method,
  ];

  static SeerrSignInMethod _methodOf(SeerrAccountKind kind) => switch (kind) {
    SeerrAccountKind.local => SeerrSignInMethod.local,
    SeerrAccountKind.plex => SeerrSignInMethod.plex,
    SeerrAccountKind.emby => SeerrSignInMethod.emby,
    SeerrAccountKind.jellyfin => SeerrSignInMethod.jellyfin,
  };

  /// Takes the way in [method].
  void choose(SeerrSignInMethod method) {
    _set(() {
      _method = method;
      _notice = null;
    });
    switch (method) {
      case SeerrSignInMethod.local ||
          SeerrSignInMethod.jellyfin ||
          SeerrSignInMethod.emby:
        _set(() => _stage = SeerrSignInStage.form);
      case SeerrSignInMethod.plex:
        unawaited(startPlex());
      case SeerrSignInMethod.jellyfinQuickConnect:
        unawaited(startQuickConnect());
    }
  }

  /// Back to the ways in, with the password emptied.
  void showMethods() {
    password.clear();
    _set(() {
      _notice = null;
      _stage = SeerrSignInStage.methods;
    });
  }

  // === Email, Jellyfin, Emby ===============================================

  /// Whether the password form has what it needs to be sent.
  bool get readyToSend =>
      _facts != null &&
      _method != null &&
      _auth != null &&
      login.text.trim().isNotEmpty &&
      password.text.isNotEmpty;

  /// Sends the login and the password; the password leaves the form first.
  Future<void> signInWithPassword() async {
    final facts = _facts;
    final method = _method;
    final auth = _auth;
    if (!readyToSend || facts == null || method == null || auth == null) {
      return;
    }
    final typed = login.text.trim();
    final secret = password.text;
    // Out of the form the moment it is sent: whatever comes back, it is not
    // kept on this screen.
    password.clear();
    _set(() {
      _stage = SeerrSignInStage.signingIn;
      _notice = null;
    });
    try {
      final account = method == SeerrSignInMethod.local
          ? await auth.signInWithEmail(facts, email: typed, password: secret)
          : await auth.signInWithMediaServer(
              facts,
              username: typed,
              password: secret,
            );
      await _signedIn(account);
    } catch (error) {
      if (_disposed) return;
      _signInStopped(error, method, back: SeerrSignInStage.form);
    }
  }

  // === Plex ================================================================

  /// Asks plex.tv for a PIN and opens its page.
  Future<void> startPlex() async {
    _stopWaiting();
    _set(() {
      _stage = SeerrSignInStage.plex;
      _notice = null;
    });
    final plexTv = _plexTv = PlexTvClient(
      clientIdentifier: _ref.read(currentSettingsProvider).plexClientId,
    );
    final PlexTvPin pin;
    try {
      pin = await plexTv.createPin();
    } catch (error) {
      if (_disposed) return;
      return _plexStopped(error);
    }
    if (_disposed) return;
    _set(() {
      _pin = pin;
      _plexWaited = Duration.zero;
    });
    await openPlexPage();
  }

  /// One second of waiting on the Plex page, while the sign-in is on screen:
  /// ask plex.tv, until the app's own patience runs out.
  void onPlexTick() {
    _plexWaited += seerrPlexPollEvery;
    if (_plexWaited >= _plexPatience) return _plexTimedOut();
    unawaited(_checkNow());
  }

  /// One tick of waiting on the Quick Connect code.
  void onQuickConnectTick() => unawaited(_checkNow());

  /// Opens the Plex page of the PIN again.
  Future<void> openPlexPage() async {
    final plexTv = _plexTv;
    final pin = _pin;
    if (plexTv == null || pin == null) return;
    await _ref.read(browserOpenerProvider).open(plexTv.authUrl(pin));
  }

  Future<void> _checkPlex() async {
    final plexTv = _plexTv;
    final pin = _pin;
    final facts = _facts;
    final auth = _auth;
    if (plexTv == null || pin == null || facts == null || auth == null) return;
    final String? token;
    try {
      token = await plexTv.authTokenOf(pin);
    } on PlexTvPinExpired {
      return _plexTimedOut();
    } catch (_) {
      // One missed answer is not the end: the next second asks again.
      return;
    }
    if (token == null || _disposed || _stage != SeerrSignInStage.plex) return;
    _stopWaiting();
    _set(() => _stage = SeerrSignInStage.signingIn);
    unawaited(_ref.read(browserOpenerProvider).close());
    try {
      await _signedIn(await auth.signInWithPlex(facts, authToken: token));
    } catch (error) {
      if (_disposed) return;
      _signInStopped(
        error,
        SeerrSignInMethod.plex,
        back: SeerrSignInStage.methods,
      );
    }
  }

  void _plexTimedOut() {
    _stopWaiting();
    if (_disposed) return;
    unawaited(_ref.read(browserOpenerProvider).close());
    _stop(SeerrSignInNotice.plexTimedOut, back: SeerrSignInStage.methods);
  }

  void _plexStopped(Object error) {
    _stopWaiting();
    final notice = failureDidNotAnswer(classifyConnectionFailure(error))
        ? SeerrSignInNotice.plexDidNotAnswer
        : SeerrSignInNotice.ofSignIn(error, method: SeerrSignInMethod.plex);
    _stop(notice, back: SeerrSignInStage.methods, retry: startPlex);
  }

  // === Quick Connect =======================================================

  /// Asks Seerr for a Quick Connect code.
  Future<void> startQuickConnect() async {
    final facts = _facts;
    final auth = _auth;
    if (facts == null || auth == null) return;
    _stopWaiting();
    _set(() {
      _stage = SeerrSignInStage.quickConnect;
      _code = null;
      _notice = null;
    });
    final SeerrQuickConnect code;
    try {
      code = await auth.startQuickConnect(facts);
    } catch (error) {
      if (_disposed) return;
      if (classifyConnectionFailure(error) ==
          ServiceFailureReason.serverError) {
        // Jellyfin's own Quick Connect is off, which the server's settings
        // do not say: the way is not offered again.
        _set(() => _quickConnectOff = true);
        return _stop(
          SeerrSignInNotice.methodTurnedOff,
          back: SeerrSignInStage.methods,
        );
      }
      return _signInStopped(
        error,
        SeerrSignInMethod.jellyfinQuickConnect,
        back: SeerrSignInStage.methods,
      );
    }
    if (_disposed) return;
    _set(() => _code = code);
  }

  Future<void> _checkQuickConnect() async {
    final code = _code;
    final facts = _facts;
    final auth = _auth;
    if (code == null || facts == null || auth == null) return;
    final bool approved;
    try {
      approved = await auth.quickConnectApproved(code);
    } on SeerrQuickConnectExpired {
      _stopWaiting();
      if (_disposed) return;
      return _stop(
        SeerrSignInNotice.codeExpired,
        back: SeerrSignInStage.methods,
      );
    } catch (error) {
      final notice = SeerrSignInNotice.ofSignIn(
        error,
        method: SeerrSignInMethod.jellyfinQuickConnect,
      );
      // Anything but Jellyfin turning its Quick Connect off is one missed
      // answer, and the next tick asks again.
      if (notice.kind != SeerrSignInNoticeKind.methodTurnedOff) return;
      if (_disposed || _stage != SeerrSignInStage.quickConnect) return;
      // The server's settings do not say so, so reading them again would
      // offer the code once more: the way is not offered again.
      _set(() {
        _quickConnectOff = true;
        _code = null;
      });
      return _stop(notice, back: SeerrSignInStage.methods);
    }
    if (!approved || _disposed || _stage != SeerrSignInStage.quickConnect) {
      return;
    }
    _stopWaiting();
    _set(() => _stage = SeerrSignInStage.signingIn);
    try {
      await _signedIn(await auth.finishQuickConnect(facts, code));
    } catch (error) {
      if (_disposed) return;
      _signInStopped(
        error,
        SeerrSignInMethod.jellyfinQuickConnect,
        back: SeerrSignInStage.methods,
      );
    }
  }

  // === Waiting =============================================================

  Future<void> _checkNow() async {
    if (_checking) return;
    _checking = true;
    try {
      switch (_stage) {
        case SeerrSignInStage.plex:
          await _checkPlex();
        case SeerrSignInStage.quickConnect:
          await _checkQuickConnect();
        case SeerrSignInStage.start ||
            SeerrSignInStage.asking ||
            SeerrSignInStage.methods ||
            SeerrSignInStage.form ||
            SeerrSignInStage.signingIn:
          break;
      }
    } finally {
      _checking = false;
    }
  }

  void _stopWaiting() {
    _plexTv?.close();
    _plexTv = null;
    _pin = null;
    _plexWaited = Duration.zero;
  }

  /// Stops waiting on Plex or on a code, back to the ways in.
  void cancel() {
    final wasPlex = _stage == SeerrSignInStage.plex;
    _stopWaiting();
    if (wasPlex) unawaited(_ref.read(browserOpenerProvider).close());
    _set(() {
      _code = null;
      _notice = null;
      _stage = _facts == null
          ? SeerrSignInStage.start
          : SeerrSignInStage.methods;
    });
  }

  /// Back to the start with nothing read: the address is about to change.
  void restart() {
    final wasPlex = _stage == SeerrSignInStage.plex;
    _stopWaiting();
    if (wasPlex) unawaited(_ref.read(browserOpenerProvider).close());
    _auth?.close();
    _auth = null;
    _authReach = null;
    password.clear();
    _set(() {
      _stage = SeerrSignInStage.start;
      _facts = null;
      _method = null;
      _notice = null;
      _retry = null;
      _code = null;
      _cleartextAccepted = false;
      _quickConnectOff = false;
    });
  }

  // === The outcome =========================================================

  Future<void> _signedIn(SeerrAccountSignIn account) async {
    final at = _auth?.url;
    final connection = _connection;
    await _ref
        .read(seerrAccountsProvider)
        .signedIn(
          at == null ? connection : connection.copyWith(url: at),
          account,
        );
    if (_disposed) return;
    _auth?.close();
    _auth = null;
    login.clear();
    _set(() {
      _stage = SeerrSignInStage.start;
      _notice = null;
      _method = null;
    });
  }

  void _signInStopped(
    Object error,
    SeerrSignInMethod method, {
    required SeerrSignInStage back,
  }) {
    final notice = SeerrSignInNotice.ofSignIn(error, method: method);
    if (notice.kind == SeerrSignInNoticeKind.methodTurnedOff ||
        notice.kind == SeerrSignInNoticeKind.notSetUp) {
      // Read the server again: its ways in are no longer the ones drawn.
      unawaited(readServer().then((_) => _set(() => _notice = notice)));
      return;
    }
    _stop(
      notice,
      back: back,
      retry: notice.retryHelps ? () => choose(method) : null,
    );
  }

  void _stop(
    SeerrSignInNotice notice, {
    SeerrSignInStage back = SeerrSignInStage.start,
    VoidCallback? retry,
  }) {
    _set(() {
      _notice = notice;
      _retry = retry;
      _stage = back;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _stopWaiting();
    _auth?.close();
    login.dispose();
    password.dispose();
    super.dispose();
  }
}
