import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/browser_opener.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/data/plex_tv_client.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/data/seerr_auth_service.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/discover/presentation/seerr_sign_in_notice.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_dialog.dart';

/// How a Seerr connection signs in: the instance's API key, or an account of
/// one's own.
enum SeerrSignInWith {
  apiKey('API key'),
  account('An account');

  const SeerrSignInWith(this.label);

  final String label;
}

/// How long the Plex page is waited on at most, whatever plex.tv says of its
/// PIN: Seerr's own web client stops at 15 minutes too.
const _plexPatience = Duration(minutes: 15);

/// plex.tv is asked once a second, as its documentation asks of a native app,
/// through the page's own gate (`VisibilityPoller`).
const _plexPollEvery = Duration(seconds: 1);

/// Seerr is asked whether a Quick Connect code was approved every 2 seconds.
const _quickConnectPollEvery = Duration(seconds: 2);

/// The account half of a Seerr connection's form: signing in, signed in, and
/// signed out.
///
/// The minimal way in, inside the connection's own settings: read the
/// server, offer the ways in it has, sign in, keep the session. The password
/// lives in its field until it is sent and is then emptied; the Plex token
/// lives in a local until Seerr has it. Neither is saved, printed or shown.
///
/// [connection] is the connection as the form stands: the address in its
/// field, its access, its name. Signing in saves it with the account.
class SeerrAccountFields extends ConsumerStatefulWidget {
  const SeerrAccountFields({
    super.key,
    required this.connection,
    required this.onUseApiKey,
    required this.onCheckAddress,
    required this.onUseHttps,
    this.certificateProber = probeUntrustedCertificate,
  });

  final ServiceInstance Function() connection;

  /// The server has every way in off: the key is what is left.
  final VoidCallback onUseApiKey;

  /// Something other than Seerr answered at the address.
  final VoidCallback onCheckAddress;

  /// The address is `http://` off the local network.
  final VoidCallback onUseHttps;

  final CertificateProber certificateProber;

  @override
  ConsumerState<SeerrAccountFields> createState() => _SeerrAccountFieldsState();
}

enum _Stage { start, asking, methods, form, signingIn, plex, quickConnect }

class _SeerrAccountFieldsState extends ConsumerState<SeerrAccountFields> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;

  _Stage _stage = _Stage.start;
  SeerrServerFacts? _facts;
  SeerrSignInMethod? _method;
  SeerrSignInNotice? _notice;
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
  SeerrQuickConnect? _code;
  bool _checking = false;

  @override
  void dispose() {
    _stopWaiting();
    _auth?.close();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  ServiceInstance get _connection => widget.connection();

  String get _host =>
      UrlUtils.hostInProse(ServiceKey.seerr.extractHost(_connection.url) ?? '');

  /// What the server calls itself: from the methods read, else from what
  /// the saved account's server said, else Seerr.
  String get _title => _facts?.title ?? _savedTitle ?? 'Seerr';

  String? _savedTitle;

  SeerrAuthService _authService() {
    _auth?.close();
    final connection = _connection;
    return _auth = SeerrAuthService.forConnection(
      connection,
      pinnedCertFingerprint: ref
          .read(currentSettingsProvider)
          .pinForUrl(connection.url),
    );
  }

  // === Reading the server ==================================================

  Future<void> _readServer({SeerrAccountSignIn? again}) async {
    _stopWaiting();
    setState(() {
      _stage = _Stage.asking;
      _notice = null;
    });
    final auth = _authService();
    SeerrServerFacts facts;
    try {
      facts = await auth.readServer();
    } catch (error) {
      if (!mounted) return;
      if (await _trustedCertificateFor(error)) {
        if (mounted) return _readServer(again: again);
        return;
      }
      if (!mounted) return;
      return _stop(
        SeerrSignInNotice.ofServerRead(error, url: _connection.url),
        retry: () => _readServer(again: again),
      );
    }
    if (!mounted) return;
    final closed = SeerrSignInNotice.ofMethods(facts.signIn);
    setState(() {
      _facts = facts;
      _notice = closed;
      _retry = null;
      _stage = closed == null ? _Stage.methods : _Stage.start;
    });
    // Signing in again goes straight to the way the account came in, past
    // the warning about an unencrypted address only once it was read.
    if (closed == null && again != null) {
      final method = _methodOf(again.kind, facts);
      if (method != null && _offered(facts).contains(method)) {
        _login.text = again.login;
        if (!_cleartextGate) _choose(method);
      }
    }
  }

  /// Whether a password is about to go over `http://` to a host this device
  /// cannot tell is on the local network, and the person has not read the
  /// warning yet.
  bool get _cleartextGate =>
      !_cleartextAccepted && passwordTravelsInClear(_connection.url);

  /// When the server's certificate is one nothing trusts, asks the person to
  /// trust it before anything secret is sent. True when it is now trusted.
  Future<bool> _trustedCertificateFor(Object error) async {
    if (!certProbeWorthwhile(classifyConnectionFailure(error))) return false;
    final settings = ref.read(currentSettingsProvider);
    final url = _connection.url;
    final previous = settings.pinForUrl(url);
    final probe = await widget.certificateProber(
      url,
      pinnedFingerprint: previous ?? '',
    );
    if (probe == null || !mounted) return false;
    final trust = await showCertTrustDialog(
      context,
      origin: UrlUtils.certOrigin(url) ?? url,
      probe: probe,
      previousFingerprint: previous,
    );
    if (!trust || !mounted) return false;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          ref
              .read(currentSettingsProvider)
              .copyWithTrustedCertificate(
                url: url,
                fingerprint: probe.certificate.fingerprint,
              ),
        );
    return true;
  }

  List<SeerrSignInMethod> _offered(SeerrServerFacts facts) => [
    for (final method in facts.signIn.offered)
      if (!(_quickConnectOff &&
          method == SeerrSignInMethod.jellyfinQuickConnect))
        method,
  ];

  static SeerrSignInMethod? _methodOf(
    SeerrAccountKind kind,
    SeerrServerFacts facts,
  ) => switch (kind) {
    SeerrAccountKind.local => SeerrSignInMethod.local,
    SeerrAccountKind.plex => SeerrSignInMethod.plex,
    SeerrAccountKind.emby => SeerrSignInMethod.emby,
    SeerrAccountKind.jellyfin => SeerrSignInMethod.jellyfin,
  };

  void _choose(SeerrSignInMethod method) {
    setState(() {
      _method = method;
      _notice = null;
    });
    switch (method) {
      case SeerrSignInMethod.local ||
          SeerrSignInMethod.jellyfin ||
          SeerrSignInMethod.emby:
        setState(() => _stage = _Stage.form);
      case SeerrSignInMethod.plex:
        unawaited(_startPlex());
      case SeerrSignInMethod.jellyfinQuickConnect:
        unawaited(_startQuickConnect());
    }
  }

  // === Email, Jellyfin, Emby ===============================================

  Future<void> _signInWithPassword() async {
    final facts = _facts;
    final method = _method;
    final auth = _auth;
    if (facts == null || method == null || auth == null) return;
    if (_login.text.trim().isEmpty || _password.text.isEmpty) return;
    FocusScope.of(context).unfocus();
    final login = _login.text.trim();
    final password = _password.text;
    // Out of the form the moment it is sent: whatever comes back, it is not
    // kept on this screen.
    _password.clear();
    setState(() {
      _stage = _Stage.signingIn;
      _notice = null;
    });
    try {
      final account = method == SeerrSignInMethod.local
          ? await auth.signInWithEmail(facts, email: login, password: password)
          : await auth.signInWithMediaServer(
              facts,
              username: login,
              password: password,
            );
      await _signedIn(account);
    } catch (error) {
      if (!mounted) return;
      _signInStopped(error, method, back: _Stage.form);
    }
  }

  // === Plex ================================================================

  Future<void> _startPlex() async {
    _stopWaiting();
    setState(() {
      _stage = _Stage.plex;
      _notice = null;
    });
    final plexTv = _plexTv = PlexTvClient(
      clientIdentifier: ref.read(currentSettingsProvider).plexClientId,
    );
    final PlexTvPin pin;
    try {
      pin = await plexTv.createPin();
    } catch (error) {
      if (!mounted) return;
      return _plexStopped(error);
    }
    if (!mounted) return;
    setState(() {
      _pin = pin;
      _plexWaited = Duration.zero;
    });
    await _openPlexPage();
  }

  /// One second of waiting on the Plex page, while this form is on screen:
  /// ask plex.tv, until the app's own patience runs out.
  void _onPlexTick() {
    _plexWaited += _plexPollEvery;
    if (_plexWaited >= _plexPatience) return _plexTimedOut();
    unawaited(_checkNow());
  }

  Future<void> _openPlexPage() async {
    final plexTv = _plexTv;
    final pin = _pin;
    if (plexTv == null || pin == null) return;
    await ref.read(browserOpenerProvider).open(plexTv.authUrl(pin));
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
    if (token == null || !mounted || _stage != _Stage.plex) return;
    _stopWaiting();
    setState(() => _stage = _Stage.signingIn);
    unawaited(ref.read(browserOpenerProvider).close());
    try {
      await _signedIn(await auth.signInWithPlex(facts, authToken: token));
    } catch (error) {
      if (!mounted) return;
      _signInStopped(error, SeerrSignInMethod.plex, back: _Stage.methods);
    }
  }

  void _plexTimedOut() {
    _stopWaiting();
    if (!mounted) return;
    unawaited(ref.read(browserOpenerProvider).close());
    _stop(SeerrSignInNotice.plexTimedOut, back: _Stage.methods);
  }

  void _plexStopped(Object error) {
    _stopWaiting();
    final notice = failureDidNotAnswer(classifyConnectionFailure(error))
        ? SeerrSignInNotice.plexDidNotAnswer
        : SeerrSignInNotice.ofSignIn(error, method: SeerrSignInMethod.plex);
    _stop(notice, back: _Stage.methods, retry: _startPlex);
  }

  // === Quick Connect =======================================================

  Future<void> _startQuickConnect() async {
    final facts = _facts;
    final auth = _auth;
    if (facts == null || auth == null) return;
    _stopWaiting();
    setState(() {
      _stage = _Stage.quickConnect;
      _code = null;
      _notice = null;
    });
    final SeerrQuickConnect code;
    try {
      code = await auth.startQuickConnect(facts);
    } catch (error) {
      if (!mounted) return;
      if (classifyConnectionFailure(error) ==
          ServiceFailureReason.serverError) {
        // Jellyfin's own Quick Connect is off, which the server's settings
        // do not say: the way is not offered again.
        setState(() => _quickConnectOff = true);
        return _stop(SeerrSignInNotice.methodTurnedOff, back: _Stage.methods);
      }
      return _signInStopped(
        error,
        SeerrSignInMethod.jellyfinQuickConnect,
        back: _Stage.methods,
      );
    }
    if (!mounted) return;
    setState(() => _code = code);
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
      if (!mounted) return;
      return _stop(SeerrSignInNotice.codeExpired, back: _Stage.methods);
    } catch (error) {
      final notice = SeerrSignInNotice.ofSignIn(
        error,
        method: SeerrSignInMethod.jellyfinQuickConnect,
      );
      // Anything but Jellyfin turning its Quick Connect off is one missed
      // answer, and the next tick asks again.
      if (notice.kind != SeerrSignInNoticeKind.methodTurnedOff) return;
      if (!mounted || _stage != _Stage.quickConnect) return;
      // The server's settings do not say so, so reading them again would
      // offer the code once more: the way is not offered again.
      setState(() {
        _quickConnectOff = true;
        _code = null;
      });
      return _stop(notice, back: _Stage.methods);
    }
    if (!approved || !mounted || _stage != _Stage.quickConnect) return;
    _stopWaiting();
    setState(() => _stage = _Stage.signingIn);
    try {
      await _signedIn(await auth.finishQuickConnect(facts, code));
    } catch (error) {
      if (!mounted) return;
      _signInStopped(
        error,
        SeerrSignInMethod.jellyfinQuickConnect,
        back: _Stage.methods,
      );
    }
  }

  // === Waiting =============================================================

  Future<void> _checkNow() async {
    if (_checking) return;
    _checking = true;
    try {
      switch (_stage) {
        case _Stage.plex:
          await _checkPlex();
        case _Stage.quickConnect:
          await _checkQuickConnect();
        case _Stage.start ||
            _Stage.asking ||
            _Stage.methods ||
            _Stage.form ||
            _Stage.signingIn:
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

  void _cancel() {
    _stopWaiting();
    if (_stage == _Stage.plex) {
      unawaited(ref.read(browserOpenerProvider).close());
    }
    setState(() {
      _code = null;
      _notice = null;
      _stage = _facts == null ? _Stage.start : _Stage.methods;
    });
  }

  // === The outcome =========================================================

  Future<void> _signedIn(SeerrAccountSignIn account) async {
    final at = _auth?.url;
    final connection = _connection;
    await ref
        .read(seerrAccountsProvider)
        .signedIn(
          at == null ? connection : connection.copyWith(url: at),
          account,
        );
    if (!mounted) return;
    _auth?.close();
    _auth = null;
    _login.clear();
    setState(() {
      _stage = _Stage.start;
      _notice = null;
      _method = null;
    });
  }

  void _signInStopped(
    Object error,
    SeerrSignInMethod method, {
    required _Stage back,
  }) {
    final notice = SeerrSignInNotice.ofSignIn(error, method: method);
    if (notice.kind == SeerrSignInNoticeKind.methodTurnedOff ||
        notice.kind == SeerrSignInNoticeKind.notSetUp) {
      // Read the server again: its ways in are no longer the ones drawn.
      unawaited(
        _readServer().then((_) {
          if (mounted) setState(() => _notice = notice);
        }),
      );
      return;
    }
    _stop(
      notice,
      back: back,
      retry: notice.retryHelps ? () => _choose(method) : null,
    );
  }

  void _stop(
    SeerrSignInNotice notice, {
    _Stage back = _Stage.start,
    VoidCallback? retry,
  }) {
    setState(() {
      _notice = notice;
      _retry = retry;
      _stage = back;
    });
  }

  Future<void> _signOut(SeerrAccountSignIn account) async {
    final title = _title;
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.logout_rounded,
      title: 'Sign out of $title?',
      message: account.kind == SeerrAccountKind.plex
          ? "You'll sign in with Plex again."
          : "You'll need your password to sign in again.",
      confirmLabel: Lexicon.signOut,
    );
    if (!result.confirmed || !mounted) return;
    await ref.read(seerrAccountsProvider).signOut(_connection.id);
  }

  // === Drawing =============================================================

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.instanceById(_connection.id)?.account,
      ),
    );
    final idle = _stage == _Stage.start;
    // Only for a saved account: a key's form has no title to name.
    if (account != null) {
      _savedTitle = ref
          .watch(seerrServerFactsProvider(_connection.id))
          .whenOrNull(data: (facts) => facts.title);
    }
    // The waits ask again only while this form is on screen and the app is in
    // front: coming back from the browser or from a Jellyfin app, the gate's
    // catch-up asks at once.
    return VisibilityPoller(
      id: 'seerr.signIn.plex',
      interval: _plexPollEvery,
      enabled: _stage == _Stage.plex && _pin != null,
      onTick: _onPlexTick,
      child: VisibilityPoller(
        id: 'seerr.signIn.quickConnect',
        interval: _quickConnectPollEvery,
        enabled: _stage == _Stage.quickConnect && _code != null,
        onTick: _onQuickConnectTick,
        child: _content(context, account, idle: idle),
      ),
    );
  }

  void _onQuickConnectTick() => unawaited(_checkNow());

  Widget _content(
    BuildContext context,
    SeerrAccountSignIn? account, {
    required bool idle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The password form places its notice under its own title, beside the
        // fields it is about; every other stage leads with it.
        if (_notice case final notice? when _stage != _Stage.form) ...[
          _NoticeLine(notice: notice, actions: _noticeActions(notice)),
          const SizedBox(height: AppSpacing.md),
        ],
        ...switch (_stage) {
          _Stage.start when account != null && account.isSignedIn && idle => [
            _signedInBlock(context, account),
          ],
          _Stage.start when account != null && !account.isSignedIn => [
            if (_notice == null) ...[
              _NoticeLine(notice: _signedOutNotice, actions: const []),
              const SizedBox(height: AppSpacing.md),
            ],
            _primary(
              Lexicon.signInAgain,
              () => _readServer(again: account),
              fault: false,
            ),
          ],
          _Stage.start => [
            if (_notice == null ||
                _notice!.kind != SeerrSignInNoticeKind.turnedOff &&
                    _notice!.kind != SeerrSignInNoticeKind.notSetUp)
              _primary('Continue', _readServer, fault: false),
          ],
          _Stage.asking => [_busy('Asking Seerr')],
          _Stage.methods => _methods(context),
          _Stage.form => _passwordForm(context),
          _Stage.signingIn => [_busy('Signing in')],
          _Stage.plex => _plexWaiting(context),
          _Stage.quickConnect => _quickConnectWaiting(context),
        },
      ],
    );
  }

  SeerrSignInNotice get _signedOutNotice => SeerrSignInNotice.signedOut(_title);

  List<Widget> _noticeActions(SeerrSignInNotice notice) {
    final facts = _facts;
    final others = facts == null ? 0 : _offered(facts).length;
    return [
      if (notice.kind == SeerrSignInNoticeKind.turnedOff)
        _action('Use the API key', widget.onUseApiKey, fill: notice.tone),
      if (notice.kind == SeerrSignInNoticeKind.notSeerr ||
          notice.kind == SeerrSignInNoticeKind.didNotAnswer)
        _action(
          'Check the address',
          widget.onCheckAddress,
          fill: notice.kind == SeerrSignInNoticeKind.notSeerr
              ? notice.tone
              : null,
        ),
      if (notice.kind == SeerrSignInNoticeKind.plexTimedOut)
        _action('Start again', _startPlex, fill: notice.tone),
      if (notice.kind == SeerrSignInNoticeKind.codeExpired)
        _action('Get a new code', _startQuickConnect, fill: notice.tone),
      if (notice.kind == SeerrSignInNoticeKind.accountNotAllowed && others > 1)
        _action('Sign in another way', () {
          setState(() {
            _notice = null;
            _stage = _Stage.methods;
          });
        }),
      if (notice.retryHelps && _retry != null)
        _action(
          Lexicon.retry,
          _retry!,
          // Beside silence, text in ink; for a fault, its amber fill.
          fill: notice.tone == StatusTone.warning ? notice.tone : null,
        ),
    ];
  }

  Widget _signedInBlock(BuildContext context, SeerrAccountSignIn account) {
    final theme = Theme.of(context);
    final title = _title;
    return Row(
      children: [
        Expanded(
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Lexicon.signedInAs(account.displayName),
                  style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '$title · $_host',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(
          onPressed: () => _signOut(account),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.standard,
            minimumSize: const Size(64, 44),
          ),
          child: const Text(Lexicon.signOut),
        ),
      ],
    );
  }

  List<Widget> _methods(BuildContext context) {
    final facts = _facts!;
    final theme = Theme.of(context);
    if (_cleartextGate) {
      return [
        _NoticeLine(
          notice: SeerrSignInNotice.notEncrypted,
          actions: [
            _action(
              'Use https',
              widget.onUseHttps,
              fill: SeerrSignInNotice.notEncrypted.tone,
            ),
            _action('Continue anyway', () {
              setState(() => _cleartextAccepted = true);
            }),
          ],
        ),
      ];
    }
    return [
      Text(
        'Sign in to ${facts.title}',
        style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
      ),
      const SizedBox(height: AppSpacing.md),
      for (final method in _offered(facts)) ...[
        _primary(_methodLabel(method), () => _choose(method), fault: false),
        const SizedBox(height: AppSpacing.sm),
      ],
      Text(
        "Your password goes only to $_host. Cupola doesn't keep it.",
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  static String _methodLabel(SeerrSignInMethod method) => switch (method) {
    SeerrSignInMethod.plex => 'Continue with Plex',
    SeerrSignInMethod.jellyfin => 'Sign in with Jellyfin',
    SeerrSignInMethod.jellyfinQuickConnect =>
      'Sign in with a code from Jellyfin',
    SeerrSignInMethod.emby => 'Sign in with Emby',
    SeerrSignInMethod.local => 'Sign in with email',
  };

  List<Widget> _passwordForm(BuildContext context) {
    final facts = _facts!;
    final method = _method!;
    final theme = Theme.of(context);
    final local = method == SeerrSignInMethod.local;
    final forgot = local
        ? (facts.emailEnabled
              ? Uri.tryParse(
                  '${UrlUtils.normalizeBaseUrl(_connection.url)}/resetpassword',
                )
              : null)
        : Uri.tryParse(facts.jellyfinForgotPasswordUrl ?? '');
    final serverName = facts.jellyfinServerName;
    return [
      Text(
        'Sign in to ${facts.title}',
        style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
      ),
      if (!local && serverName != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Use the account you watch with on $serverName.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      // A refused password reads under the title it answers ("Sign in to
      // Jellyseerr"), next to the fields to change, not above the heading.
      if (_notice case final notice?) ...[
        _NoticeLine(notice: notice, actions: _noticeActions(notice)),
        const SizedBox(height: AppSpacing.md),
      ],
      TextField(
        controller: _login,
        decoration: InputDecoration(labelText: local ? 'Email' : 'Username'),
        keyboardType: local ? TextInputType.emailAddress : TextInputType.text,
        autocorrect: false,
        textInputAction: TextInputAction.next,
        autofillHints: [local ? AutofillHints.email : AutofillHints.username],
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _password,
        decoration: InputDecoration(
          labelText: 'Password',
          suffixIcon: IconButton(
            icon: Icon(
              _showPassword
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
            ),
            tooltip: _showPassword ? 'Hide password' : 'Show password',
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
        obscureText: !_showPassword,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (_) => _signInWithPassword(),
      ),
      const SizedBox(height: AppSpacing.md),
      _primary('Sign in', _signInWithPassword, fault: false),
      if (forgot != null && UrlUtils.isLaunchableWebUrl(forgot.toString()))
        _action(
          'Forgot your password?',
          () => ref.read(browserOpenerProvider).open(forgot),
        ),
      if (_offered(facts).length > 1)
        _action('Sign in another way', () {
          _password.clear();
          setState(() {
            _notice = null;
            _stage = _Stage.methods;
          });
        }),
    ];
  }

  List<Widget> _plexWaiting(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text(
        'Finish signing in with Plex',
        style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Approve Cupola on the Plex page, then come back here.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: AppSpacing.md),
      _primary('Open the Plex page again', _openPlexPage, fault: false),
      _action('Cancel', _cancel),
    ];
  }

  List<Widget> _quickConnectWaiting(BuildContext context) {
    final theme = Theme.of(context);
    final code = _code;
    if (code == null) return [_busy('Asking Seerr')];
    return [
      Semantics(
        label: 'Code ${code.code.split('').join(' ')}',
        excludeSemantics: true,
        child: Text(
          code.code,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium!.weight(FontWeight.w600),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        "Open Jellyfin on a device where you're signed in, then enter this "
        'code under Quick Connect.',
        style: theme.textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: AppSpacing.md),
      _action('Cancel', _cancel),
    ];
  }

  Widget _busy(String label) => FilledButton.icon(
    onPressed: null,
    style: FilledButton.styleFrom(
      visualDensity: VisualDensity.standard,
      minimumSize: const Size(64, 44),
    ),
    icon: const SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    label: Text(label),
  );

  Widget _primary(
    String label,
    VoidCallback onPressed, {
    required bool fault,
  }) => FilledButton(
    onPressed: onPressed,
    style: fault
        ? remedyFillStyle(context)
        : FilledButton.styleFrom(
            visualDensity: VisualDensity.standard,
            minimumSize: const Size(64, 44),
          ),
    child: Text(label),
  );

  /// A verb. [fill] is the tone of the notice it remedies, for the one fill
  /// a notice gets: amber for a fault, ink otherwise. Without it, text in
  /// ink.
  Widget _action(String label, VoidCallback onPressed, {StatusTone? fill}) =>
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: fill != null
            ? FilledButton(
                onPressed: onPressed,
                style: remedyFillStyle(
                  context,
                  compact: true,
                  fault: fill == StatusTone.warning,
                ),
                child: Text(label),
              )
            : TextButton(
                onPressed: onPressed,
                style: retryInkStyle(Theme.of(context).colorScheme),
                child: Text(label),
              ),
      );
}

/// One notice of the sign-in, the quiet way a failure line is: the glyph in
/// its tone, the title, the sentence, and its verbs. Heard as one sentence.
class _NoticeLine extends StatelessWidget {
  const _NoticeLine({required this.notice, required this.actions});

  final SeerrSignInNotice notice;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tone = statusToneColor(
      colorScheme,
      notice.tone,
      surface: colorScheme.surface,
    );
    final glyph = switch (notice.tone) {
      StatusTone.error => Icons.cloud_off_rounded,
      StatusTone.info => Icons.info_outline_rounded,
      _ => Icons.error_outline_rounded,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          label: notice.spoken,
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(glyph, size: 16, color: tone),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notice.title,
                        style: theme.textTheme.titleSmall!
                            .weight(FontWeight.w600)
                            .copyWith(color: tone),
                      ),
                      if (notice.sentence case final sentence?)
                        Text(
                          sentence,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: actions,
          ),
        ],
      ],
    );
  }
}
