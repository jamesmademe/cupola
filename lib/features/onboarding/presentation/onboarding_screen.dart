import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_walk.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_access_rules.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/connection_access_fields.dart';
import 'package:cupola/features/shell/presentation/desktop/window_chrome.dart';

/// First run, in four beats: the claim, the choice, one service at a time, and
/// what it actually achieved.
///
/// The flow's length is the user's — two fixed beats plus one page per chosen
/// service plus the close — which is why progress is the ring closing rather
/// than a fixed bar of segments.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({
    super.key,
    this.certificateProber = probeUntrustedCertificate,
    this.localNetworkProbe = probeLocalNetworkAccess,
  });

  /// Injectable so a widget test can stay off a real socket — see
  /// [CertificateProber].
  final CertificateProber certificateProber;

  /// Injectable for the same reason as [certificateProber]: the real one reaches
  /// the host OS and, on iOS, can put a permission alert on screen.
  final LocalNetworkProbe localNetworkProbe;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  static const _doorPage = 0;
  static const _pickPage = 1;
  static const _firstWalkPage = 2;

  final _pageController = PageController();

  /// The ring's entrance. One authored moment on the door, then stillness.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: AppAnimation.durationXl,
  );

  final Set<ServiceKey> _picked = {};

  final Map<ServiceKey, TextEditingController> _urlCtrl = {
    for (final k in ServiceKey.values) k: TextEditingController(),
  };
  final Map<ServiceKey, TextEditingController> _apiKeyCtrl = {
    for (final k in ServiceKey.values) k: TextEditingController(),
  };
  final Map<ServiceKey, TextEditingController> _usernameCtrl = {
    for (final k in ServiceKey.values) k: TextEditingController(),
  };
  final Map<ServiceKey, TextEditingController> _passwordCtrl = {
    for (final k in ServiceKey.values) k: TextEditingController(),
  };

  /// Each service's Access row: what it presents to a gateway in front of
  /// it. The same controller and row the connection form uses, so a gateway
  /// met on the first run is answered in the step rather than in a form for a
  /// connection that does not exist yet.
  final Map<ServiceKey, ConnectionAccessController> _accessCtrl = {};

  /// The form each Access row validates in, before its test runs.
  final Map<ServiceKey, GlobalKey<FormState>> _accessForm = {
    for (final k in ServiceKey.values) k: GlobalKey<FormState>(),
  };

  /// The services whose step shows its Access row: one with access already
  /// set, one whose address carried a password, or one whose gateway remedy
  /// was taken. Everyone else's first run is the form it always was.
  final Set<ServiceKey> _accessShown = {};

  /// The access each service's last test sent, which decides how its outcome
  /// is said.
  final Map<ServiceKey, ConnectionAccess> _testedAccess = {};

  final Map<ServiceKey, ServiceConnectionStatus?> _status = {};
  final Map<ServiceKey, ServiceFailureReason?> _reason = {};

  /// What answered in a service's place, when its last test met a gateway.
  final Map<ServiceKey, AccessGatewayAnswer?> _gateway = {};

  /// The Cloudflare service tokens that passed a test in this walk, by the
  /// Access team they passed (`myteam.cloudflareaccess.com`), with the service
  /// they passed for. A later step stopped by the same team is offered the
  /// token instead of an empty Access row: one team, one token, typed once.
  final Map<String, ({ServiceKey from, CloudflareServiceToken token})>
  _passedTokens = {};

  /// The verbatim sentence a failure carried, for the few that carry one — see
  /// `ServiceDiagnosis.detail`. Kept beside [_reason] rather than folded into it
  /// so the walk renders the same words the settings screen does.
  final Map<ServiceKey, String?> _failureDetail = {};

  /// The version each service named while its test ran — see
  /// `ServiceDiagnosis.serverVersion`. Beside [_failureDetail] for the same
  /// reason: the walk prints what the settings screen prints.
  final Map<ServiceKey, String?> _serverVersion = {};
  final Map<ServiceKey, bool> _verifying = {};

  /// Self-signed fingerprints the user chose to trust, persisted on save
  /// (ADR-6) — one per service's *origin*, so two services typed at the same
  /// host:port share the value a save later stores under one key.
  ///
  /// Never read directly: go through [_pinFor], which is what ties an entry to
  /// [_certOriginOf].
  final Map<ServiceKey, String> _certFingerprint = {};

  /// The TLS origin each [_certFingerprint] entry was decided against.
  ///
  /// A trust decision is about a certificate a *specific host* presented, so it
  /// stops applying the moment the address does. Without this, resuming a walk
  /// with a pinned service and then editing its address carried the old host's
  /// fingerprint onto the new one: `_save` writes every ready service, not only
  /// the one on screen, so paging forward was enough. Because a pin is keyed by
  /// origin alone, that bogus entry then failed the handshake closed for every
  /// service later pointed at the new host, with no trust prompt to explain it.
  final Map<ServiceKey, String> _certOriginOf = {};

  /// A certificate probe the last test ran into, waiting for the user to
  /// trust it inside the step rather than in a dialog that lands on top of
  /// the failure. Carries whether this origin already had a *different* pin
  /// (ADR-6) — that is a certificate change, not a first trust, and the card
  /// escalates rather than offering it as routine.
  final Map<ServiceKey, UntrustedCertificateProbe> _pendingCert = {};

  /// The field values a verification result belongs to. Editing an address after
  /// a successful check would otherwise leave a green verdict standing for an
  /// instance that is no longer the one configured.
  final Map<ServiceKey, String> _verifiedAgainst = {};

  /// Services the user explicitly walked past. They keep their place in the ring
  /// but are not written to settings.
  final Set<ServiceKey> _skipped = {};

  @override
  void initState() {
    super.initState();
    // Resume, rather than restart. Saving happens as the walk proceeds, so an
    // interrupted setup leaves settings on disk that this screen must show —
    // otherwise finishing a second time writes empty fields over a real
    // configuration.
    final settings = ref.read(currentSettingsProvider);
    for (final k in ServiceKey.values) {
      final saved = settings.primaryOf(k)?.access ?? const NoAccess();
      _accessCtrl[k] = ConnectionAccessController(k, initial: saved);
      if (!saved.isEmpty) _accessShown.add(k);
    }
    for (final k in ServiceKey.values) {
      final url = settings.urlFor(k);
      if (url.isEmpty) continue;
      _picked.add(k);
      _urlCtrl[k]!.text = url;
      // Which fields a service even has is the registry's answer, so a new
      // credential-authenticated service resumes correctly without an arm here.
      if (k.usesApiKey) {
        _apiKeyCtrl[k]!.text = settings.apiKeyFor(k);
      } else {
        _usernameCtrl[k]!.text = settings.usernameFor(k);
        _passwordCtrl[k]!.text = settings.passwordFor(k);
      }
      final pin = settings.pinForUrl(url);
      final origin = UrlUtils.certOrigin(url);
      if (pin != null && origin != null) {
        _certFingerprint[k] = pin;
        _certOriginOf[k] = origin;
      }
    }
    // Reduce Motion removes the animator rather than shortening it: the ring
    // simply starts seated.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entrance.dispose();
    for (final c in _urlCtrl.values) {
      c.dispose();
    }
    for (final c in _apiKeyCtrl.values) {
      c.dispose();
    }
    for (final c in _usernameCtrl.values) {
      c.dispose();
    }
    for (final c in _passwordCtrl.values) {
      c.dispose();
    }
    for (final c in _accessCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── The walk ──────────────────────────────────────────────────────────────

  /// Chosen services in registry order — the same order the ring draws.
  List<ServiceKey> get _walk =>
      ServiceRing.order.where(_picked.contains).toList(growable: false);

  int get _closePage => _firstWalkPage + _walk.length;

  bool _isReady(ServiceKey k) {
    if (!_picked.contains(k) || _skipped.contains(k)) return false;
    if (_urlCtrl[k]!.text.trim().isEmpty) return false;
    if (!k.usesApiKey) return true;
    return _apiKeyCtrl[k]!.text.trim().isNotEmpty;
  }

  List<ServiceKey> get _configured =>
      ServiceRing.order.where(_isReady).toList(growable: false);

  List<ServiceKey> get _answering => _configured
      .where((k) => _status[k] == ServiceConnectionStatus.connected)
      .toList(growable: false);

  List<ServiceKey> get _silent => _configured
      .where((k) => _status[k] != ServiceConnectionStatus.connected)
      .toList(growable: false);

  /// The ring's state, derived rather than stored: one map, four beats.
  Map<ServiceKey, ServiceRingState> get _ringStates => {
    for (final k in _picked)
      k: switch (_status[k]) {
        ServiceConnectionStatus.connected => ServiceRingState.connected,
        null => ServiceRingState.picked,
        _ => _isReady(k) ? ServiceRingState.silent : ServiceRingState.picked,
      },
  };

  /// The fingerprint [k]'s *currently typed* address is trusted under, or null.
  ///
  /// The gate on [_certFingerprint]: a pin only applies while the address still
  /// resolves to the origin the user accepted the certificate for. Retyping the
  /// old address brings its pin back, which is right — the trust decision was
  /// about that host and still holds.
  String? _pinFor(ServiceKey k) {
    final pin = _certFingerprint[k];
    if (pin == null) return null;
    final origin = UrlUtils.certOrigin(_urlCtrl[k]!.text);
    return origin != null && origin == _certOriginOf[k] ? pin : null;
  }

  String _fingerprintOf(ServiceKey k) => [
    _urlCtrl[k]!.text.trim(),
    _apiKeyCtrl[k]!.text.trim(),
    _usernameCtrl[k]!.text.trim(),
    _passwordCtrl[k]!.text,
    _pinFor(k) ?? '',
    // By its hash, so the fingerprint never holds a secret.
    '${_accessCtrl[k]!.access.hashCode}',
  ].join(' ');

  bool _needsCheck(ServiceKey k) =>
      _status[k] == null || _verifiedAgainst[k] != _fingerprintOf(k);

  /// Every service in this walk whose typed address shares [service]'s TLS
  /// origin — the set a trust decision on it actually covers, computed from
  /// the in-progress form fields rather than saved settings, since several
  /// services can be typed in the same walk before anything is saved.
  List<ServiceKey> _servicesSharingOrigin(ServiceKey service) {
    final origin = UrlUtils.certOrigin(_urlCtrl[service]!.text);
    if (origin == null) return [service];
    return ServiceKey.values
        .where((k) {
          final url = _urlCtrl[k]!.text.trim();
          return url.isNotEmpty && UrlUtils.certOrigin(url) == origin;
        })
        .toList(growable: false);
  }

  // ── Address help ──────────────────────────────────────────────────────────

  // The address is never filled in on arrival. The walk used to carry the
  // previous service's host over on this one's default port, which assumed one
  // box answering on bare ports. Behind a reverse proxy — one subdomain per
  // service, TLS on 443 — that guess was wrong every time and had to be
  // deleted before typing the real one. The port chip below ([_suggestPort])
  // still offers the same guess, as a tap the user chooses to make.

  String? _lastKnownHost({required ServiceKey exclude}) {
    for (final k in _walk.reversed) {
      if (k == exclude) continue;
      final raw = _urlCtrl[k]!.text.trim();
      if (raw.isEmpty) continue;
      final host = Uri.tryParse(UrlUtils.normalizeBaseUrl(raw))?.host ?? '';
      if (host.isNotEmpty) return host;
    }
    return null;
  }

  String? _lastKnownScheme({required ServiceKey exclude}) {
    for (final k in _walk.reversed) {
      if (k == exclude) continue;
      final raw = _urlCtrl[k]!.text.trim();
      if (raw.isEmpty) continue;
      final uri = Uri.tryParse(UrlUtils.normalizeBaseUrl(raw));
      if (uri == null || uri.scheme.isEmpty) continue;
      return uri.scheme.toLowerCase() == 'http' ? 'http' : 'https';
    }
    return null;
  }

  /// Puts this service's default port on whatever host is already typed.
  void _suggestPort(ServiceKey service) {
    final controller = _urlCtrl[service]!;
    final normalized = UrlUtils.normalizeBaseUrl(controller.text);
    final uri = Uri.tryParse(normalized);
    final host = uri?.host ?? '';
    final target = host.isEmpty ? _lastKnownHost(exclude: service) ?? '' : host;
    if (target.isEmpty) return;
    final scheme = host.isEmpty
        ? _lastKnownScheme(exclude: service) ?? 'https'
        : uri?.scheme.toLowerCase() == 'http'
        ? 'http'
        : 'https';
    setState(() {
      controller.text = '$scheme://$target:${service.defaultPort}';
    });
  }

  // ── Verification ──────────────────────────────────────────────────────────

  /// Takes an address's `user:password@` off it and puts it where the
  /// connection form puts it, showing the Access row when the password went
  /// there.
  void _liftCredentials(ServiceKey service) {
    final access = _accessCtrl[service]!;
    final lifted = access.liftCredentialsFrom(
      _urlCtrl[service]!,
      username: _usernameCtrl[service]!,
      password: _passwordCtrl[service]!,
    );
    if (lifted && access.kind == AccessKind.password) {
      _accessShown.add(service);
    }
  }

  /// Shows [service]'s Access row with [kind] chosen: a gateway's remedy,
  /// answered in the step.
  void _showAccess(ServiceKey service, AccessKind kind) {
    setState(() {
      _accessShown.add(service);
      _accessCtrl[service]!.select(kind);
    });
  }

  /// The token another step of this walk passed with, when [service]'s last
  /// test was stopped, with no token, by the same Access team.
  ({ServiceKey from, CloudflareServiceToken token})? _sharedTokenFor(
    ServiceKey service,
  ) {
    final gateway = _gateway[service];
    if (gateway == null || gateway.credentialsSent) return null;
    final team = accessTeamOf(gateway);
    if (team == null) return null;
    final passed = _passedTokens[team];
    if (passed == null || passed.from == service) return null;
    return passed;
  }

  /// A service left out of the walk is not offered as the source of a token:
  /// "Use Radarr's token" would name a service the user dropped.
  void _forgetPassedToken(ServiceKey service) =>
      _passedTokens.removeWhere((_, passed) => passed.from == service);

  /// Takes the token another step passed with: the Access row shows it, so
  /// what is sent is on screen, and the step tests again with it.
  Future<void> _useSharedToken(
    ServiceKey service,
    CloudflareServiceToken token,
  ) async {
    final access = _accessCtrl[service]!;
    setState(() {
      _accessShown.add(service);
      access.select(AccessKind.cloudflare);
      access.cloudflareId.text = token.clientId;
      access.cloudflareSecret.text = token.clientSecret;
    });
    await _test(service);
  }

  Future<void> _test(ServiceKey service) async {
    // An Access row with half a token says so under its field, and nothing is
    // sent until it is whole.
    if (_accessForm[service]!.currentState?.validate() == false) return;
    setState(() => _liftCredentials(service));
    // The test's outcome is a sentence under the form, and the button rolls to
    // `Next service` when it succeeds — both of them behind the keyboard while
    // it is up. Dismissed here rather than in each caller, so the button, the
    // return key and the retest after trusting a certificate all agree.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _verifying[service] = true;
      _pendingCert.remove(service);
    });
    try {
      await _runTest(service);
    } finally {
      // A throw anywhere above used to leave the button spinning for the rest of
      // the session: a client constructor that rejects the address raises rather
      // than returning a failed status.
      if (mounted) setState(() => _verifying[service] = false);
    }
  }

  Future<void> _runTest(ServiceKey service) async {
    // The first connection this app ever opens usually happens right here, which
    // is what makes the local-network gate an onboarding problem before it is a
    // settings one: on iOS the very act of dialling a LAN address raises the
    // permission alert, and the connection racing it fails. Going through the
    // gate means the alert is *waited on* rather than raced — allow it and the
    // test simply runs again, deny it and the step says so instead of blaming
    // the address the user just typed.
    final access = _accessCtrl[service]!.access;
    // The team this step's last failure named, read before the test replaces
    // it: a token that passes now passed that team.
    final previousTeam = accessTeamOf(_gateway[service]);
    final result = await diagnoseThroughLocalNetworkGate(
      () => diagnoseCredentials(
        service,
        access: access,
        url: _urlCtrl[service]!.text,
        apiKey: _apiKeyCtrl[service]!.text,
        username: _usernameCtrl[service]!.text,
        password: _passwordCtrl[service]!.text,
        certFingerprint: _pinFor(service) ?? '',
        // Plex's persisted per-install identity. Minted once by
        // `SettingsService` and read rather than generated here, because a fresh
        // value registers another "device" row on the user's server.
        clientIdentifier: ref.read(currentSettingsProvider).plexClientId,
      ),
      url: _urlCtrl[service]!.text,
      probe: widget.localNetworkProbe,
    );

    // A TLS failure resolves *in the step*: probe for the certificate and let
    // the card offer to trust it. Probing after the server rejected a key is
    // a wasted round trip that can only return null. Every service can reach
    // this since ADR-6 — there is no pinning-capability gate left to check.
    UntrustedCertificateProbe? certProbe;
    if (result.status == ServiceConnectionStatus.disconnected &&
        certProbeWorthwhile(result.reason)) {
      certProbe = await widget.certificateProber(
        _urlCtrl[service]!.text,
        pinnedFingerprint: _pinFor(service) ?? '',
      );
    }

    if (!mounted) return;
    if (result.status == ServiceConnectionStatus.connected) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _status[service] = result.status;
      _reason[service] = result.reason;
      _gateway[service] = result.gateway;
      // The test's own sentence, from the failure: a gateway or a web page
      // names what answered, which the reason alone cannot.
      _failureDetail[service] = result.isDisconnected
          ? result.messageFor(service)
          : result.detail;
      _serverVersion[service] = result.serverVersion;
      _testedAccess[service] = access;
      _verifiedAgainst[service] = _fingerprintOf(service);
      if (certProbe != null) _pendingCert[service] = certProbe;
    });
    if (result.status == ServiceConnectionStatus.connected &&
        access is CloudflareServiceToken) {
      await _rememberPassedToken(service, access, previousTeam);
    }
  }

  /// Records that [token] passed [service]'s Access team. When no earlier
  /// failure named the team (the token was typed before the first test), the
  /// address is asked once without it: Access answers an unauthenticated
  /// request by sending it to its team's sign-in, which names the team.
  Future<void> _rememberPassedToken(
    ServiceKey service,
    CloudflareServiceToken token,
    String? knownTeam,
  ) async {
    var team = knownTeam;
    if (team == null) {
      final bare = await diagnoseCredentials(
        service,
        access: const NoAccess(),
        url: _urlCtrl[service]!.text,
        apiKey: _apiKeyCtrl[service]!.text,
        username: _usernameCtrl[service]!.text,
        password: _passwordCtrl[service]!.text,
        certFingerprint: _pinFor(service) ?? '',
        clientIdentifier: ref.read(currentSettingsProvider).plexClientId,
      );
      team = accessTeamOf(bare.gateway);
    }
    if (team == null || !mounted) return;
    setState(() => _passedTokens[team!] = (from: service, token: token));
  }

  Future<void> _trustCertificate(ServiceKey service) async {
    final probe = _pendingCert[service];
    if (probe == null) return;
    // Recorded against the address the certificate was actually presented by,
    // so a later edit of that address drops the pin rather than carrying it to
    // a host that never presented it — see [_certOriginOf].
    final origin = UrlUtils.certOrigin(_urlCtrl[service]!.text);
    if (origin == null) return;
    setState(() {
      _certFingerprint[service] = probe.certificate.fingerprint;
      _certOriginOf[service] = origin;
      _pendingCert.remove(service);
    });
    await _test(service);
  }

  /// Checks every configured service the user did not test by hand.
  ///
  /// The close is the last chance to learn that an address or a key is wrong
  /// while the fields are still one tap away. Runs non-interactively: the result
  /// is information, not a gate.
  Future<void> _testUntested() async {
    final pending = _configured.where(_needsCheck).toList();
    if (pending.isEmpty) return;
    await Future.wait(pending.map(_test));
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Writes what this walk actually configured, and **only** that.
  ///
  /// Additive on purpose: a service the user skipped, left half-filled, or
  /// unpicked is not written at all. It used to be written *blank*, which
  /// deleted the saved address and the secure credential of a service that was
  /// working — reachable from the settings screen's "Revisit onboarding", which
  /// promises in as many words that nothing about your services is changed or
  /// removed, and from "Skip for now" on the very first beat. Removing a
  /// connection is a deliberate, confirmed action and lives in the settings
  /// screen; walking past one here means "not now", never "delete it".
  ///
  /// On a first run this is indistinguishable from the old behaviour, because
  /// there is nothing on disk to preserve.
  Future<bool> _save() async {
    final current = ref.read(currentSettingsProvider);
    var updated = current;

    // Addresses this walk moves a service *away from*. Their pins can only be
    // reconsidered once every URL has settled, so they are collected here and
    // resolved in the pass below.
    final abandonedUrls = <String>[];

    for (final k in ServiceKey.values) {
      if (!_isReady(k)) continue;
      _liftCredentials(k);
      // Store the scheme the client will actually use: saving the bare host
      // the user typed left the settings form showing a value its own
      // stricter validator rejects.
      final url = UrlUtils.normalizeBaseUrl(_urlCtrl[k]!.text);
      final priorUrl = current.urlFor(k);
      if (priorUrl.isNotEmpty && priorUrl != url) abandonedUrls.add(priorUrl);
      updated = k.usesApiKey
          ? updated.copyWithService(
              k,
              url: url,
              apiKey: _apiKeyCtrl[k]!.text.trim(),
            )
          : updated.copyWithCredentials(
              k,
              url: url,
              username: _usernameCtrl[k]!.text.trim(),
              password: _passwordCtrl[k]!.text,
            );
      // The access goes with the connection the walk just wrote, as the
      // connection form saves it.
      final written = updated.primaryOf(k);
      if (written != null) {
        updated = updated.copyWithInstance(
          written.copyWith(access: _accessCtrl[k]!.access),
        );
      }
    }

    // Trust-map bookkeeping runs as its own pass, once every service's final
    // URL is known — an abandoned address's pin is only forgotten when no
    // configured service still reaches its origin, and that can only be
    // answered after the loop above has settled every URL, including services
    // later than `k` in registry order.
    for (final k in ServiceKey.values) {
      if (!_isReady(k)) continue;
      // [_pinFor], not the raw map: this loop runs for every ready service, not
      // just the one on screen, so an address edited after a trust decision
      // would otherwise file the old host's fingerprint under the new one.
      final pin = _pinFor(k);
      if (pin == null) continue;
      updated = updated.copyWithTrustedCertificate(
        url: updated.urlFor(k),
        fingerprint: pin,
      );
    }
    for (final priorUrl in abandonedUrls) {
      updated = updated.copyWithoutUnusedCertificate(priorUrl);
    }

    try {
      await ref.read(settingsProvider.notifier).updateSettings(updated);
      return true;
    } catch (_) {
      if (!mounted) return false;
      SnackBarHelper.error(
        context,
        "Couldn't save your services. Retry, and restart Cupola if it "
        'keeps failing.',
      );
      return false;
    }
  }

  /// Marks onboarding complete — triggers the router redirect to /services.
  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    try {
      await markOnboardingComplete(ref);
    } catch (_) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't finish setup. Retry, and restart Cupola if it keeps "
        'failing.',
      );
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  /// The beat on screen. Held in state rather than read off the controller
  /// because `PageController.page` is fractional mid-flight, and the ring above
  /// the pager needs the destination to aim at, not the halfway point.
  int _page = _doorPage;

  void _goTo(int page) {
    if (!_pageController.hasClients) return;
    // Leaving a beat means leaving the field you were in.
    //
    // A focused `EditableText` registers a keep-alive with the pager, so the step
    // the user walked away from stayed mounted *and* focused. The keyboard
    // therefore rode along: the close arrived with half of it covered by keys
    // belonging to a form that was no longer on screen, and anything typed went
    // into that invisible field. Unfocusing here rather than in each caller is
    // the point — every way out of a step, forward, back, skip or fix, comes
    // through this method.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _page = page);
    // Reduce Motion removes the slide rather than shortening it, the same way
    // the ring's entrance is removed: the beat is simply the next one. This is
    // the flow's most frequent movement — every Continue, Skip, Back and Next
    // goes through here — so leaving it running was most of what "the whole
    // flow must be completable without one tween" was still failing on.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(page);
      return;
    }
    _pageController.animateToPage(
      page,
      duration: AppAnimation.durationMd,
      curve: AppAnimation.standardCurve,
    );
  }

  Future<void> _enterWalk() async {
    if (_walk.isEmpty) {
      // Nothing chosen is a legitimate outcome; the close says so plainly.
      await _save();
      if (!mounted) return;
      setState(() {});
      _goTo(_closePage);
      return;
    }
    _goTo(_firstWalkPage);
  }

  /// Saves what has been entered so far, then moves on. Saving per service
  /// rather than once at the end is what makes an interrupted setup resumable.
  Future<void> _advanceFrom(ServiceKey service) async {
    final index = _walk.indexOf(service);
    await _save();
    if (!mounted) return;
    if (index >= 0 && index + 1 < _walk.length) {
      _goTo(_firstWalkPage + index + 1);
      return;
    }
    setState(() {});
    _goTo(_closePage);
    // Not awaited: the close is on screen while the checks run, and the way out
    // stays usable throughout.
    _testUntested();
  }

  void _skip(ServiceKey service) {
    setState(() {
      _skipped.add(service);
      _testedAccess.remove(service);
      _status.remove(service);
      _reason.remove(service);
      _gateway.remove(service);
      _forgetPassedToken(service);
      _failureDetail.remove(service);
      _serverVersion.remove(service);
      _pendingCert.remove(service);
    });
    _advanceFrom(service);
  }

  void _backFrom(ServiceKey service) {
    final index = _walk.indexOf(service);
    _goTo(index <= 0 ? _pickPage : _firstWalkPage + index - 1);
  }

  Future<void> _skipEverything() async {
    await _save();
    if (!mounted) return;
    setState(() {});
    _goTo(_closePage);
  }

  void _fix(ServiceKey service) {
    final index = _walk.indexOf(service);
    if (index < 0) {
      _goTo(_pickPage);
      return;
    }
    setState(() => _skipped.remove(service));
    _goTo(_firstWalkPage + index);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  /// The ring's size in its **full** register, given the height the column
  /// actually has — or zero, which is the signal to try the compact one.
  ///
  /// Two preferred sizes, not four: the door and the close are about the whole
  /// stack, so the instrument is the subject there; picking and configuring are
  /// about one service at a time, so it steps down to leave the form room — but
  /// it is the *same* ring resizing, never a second one.
  ///
  /// [available] is what keeps it honest. The ring takes what is left after the
  /// beat's own content is served, so it shrinks smoothly on a short screen. An
  /// earlier version hid it on `viewInsets > 0` alone, which was wrong twice
  /// over: a hardware or floating keyboard reports a small inset and left half
  /// the screen empty with no ring in it, and a tall phone with the software
  /// keyboard up has room for a reduced one.
  double _fullRingDiameter(BuildContext context, double available) {
    final preferred = _page == _doorPage || _page >= _closePage ? 300.0 : 190.0;
    final wanted = serviceRingDiameter(context, preferred: preferred);
    if (!available.isFinite) return wanted;

    // What the rest of the column needs before the ring gets anything: the
    // subject line, a two-field form, and the pinned actions. Scaled by the
    // reading size, since every one of them is text-driven.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final reserved = _contentFloor * scale.clamp(1.0, 2.0);
    final spare = available - reserved;

    // Below its own floor a ring is a smudge rather than an instrument. This is
    // not the ring leaving, though — it is the point where the compact register
    // takes over.
    if (spare < _ringFloor) return 0;
    return spare < wanted ? spare : wanted;
  }

  /// The ring's size in its **compact** register: a medallion in the header row,
  /// beside the step's eyebrow.
  ///
  /// The full register asks for whatever the beat leaves over, and with a
  /// software keyboard up that is nothing — a 6.1" phone keeps about 420pt of
  /// column and the beat's own content wants more than that on its own, so the
  /// ring came out at zero on every phone rather than merely smaller. The
  /// compact register does not compete: it *replaces* the subject line's row
  /// instead of sitting above it, so it is sized from a share of the short
  /// screen rather than from its leftovers, and the form still ends up with
  /// roughly 100pt more than it had.
  ///
  /// Returns zero only in the genuine squeeze — an accessibility reading size on
  /// a small phone — where even a medallion would eat the one field the user is
  /// typing into. The caller falls back to the full register's answer there,
  /// which is the ring standing down and the subject line staying whole.
  double _compactRingDiameter(BuildContext context, double available) {
    if (!available.isFinite) {
      return serviceRingDiameter(context, preferred: _compactCeiling);
    }
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    // One labelled field with its help line, the pinned actions, and the beat's
    // own gutters. Far less than [_contentFloor] because the fields below the
    // focused one are allowed to be scrolled to — the return key walks the form
    // one field at a time, so the header only has to leave room for the field
    // under the cursor.
    final room = available - _compactContentFloor * scale.clamp(1.0, 2.0);
    if (room < _ringFloor) return 0;
    final wanted = serviceRingDiameter(
      context,
      preferred: (available * _compactShare).clamp(_ringFloor, _compactCeiling),
    );
    return wanted > room ? room : wanted;
  }

  /// Height the beat's own content wants before the ring is served: subject
  /// line, two fields with labels, and the action block. Deliberately generous
  /// — erring here costs a smaller ring, while erring the other way costs a
  /// clipped field, which is the defect this whole arrangement exists to fix.
  static const double _contentFloor = 450;

  /// The same figure for the compact register, where only the focused field has
  /// to be on screen.
  static const double _compactContentFloor = 260;

  /// Share of a short screen the medallion may take. Tuned so a 6.1" phone with
  /// the keyboard up lands near [_compactCeiling] and a 4.7" one near the floor.
  static const double _compactShare = 0.28;

  /// Past this a medallion stops reading as a medallion and starts competing
  /// with the form again.
  static const double _compactCeiling = 132;

  /// The mark's share of the medallion, a little under
  /// [ServiceRing.defaultMarkFraction].
  ///
  /// The ring's nodes keep an absolute radius while the mark scales with the
  /// diameter, so shrinking the ring closes the gap between the two: 49pt of air
  /// at 190, 32pt at 132, 24pt at the floor. Giving the mark proportionally less
  /// buys that air back — at 132 the gap returns to ~38pt — and the nodes stay
  /// the thing the eye reads first, which is the whole point of a dial.
  static const double _compactMarkFraction = 0.34;

  /// [serviceRingDiameter]'s own clamp floor. Under this the ring stops being
  /// legible, so it leaves instead.
  static const double _ringFloor = 96;

  @override
  Widget build(BuildContext context) {
    final walk = _walk;
    final ringStates = _ringStates;
    final activeWalk = _page >= _firstWalkPage && _page < _closePage
        ? walk[_page - _firstWalkPage]
        : null;

    // Resolved here, outside the `Scaffold`: a Scaffold that resizes for the
    // keyboard removes the bottom inset from the MediaQuery it hands its body,
    // so anything below this point is told the keyboard is down while it is up.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

    // The room the walk happens in: lit by the neutral lamp throughout. Null on
    // the door, the pick and the close, where `AmbientBackground`'s own default
    // is the lamp; per service in between, where the service's accent is the
    // lamp too — so the light holds steady while the page and the ring move,
    // and the service being set up is named by its mark and its form, never by
    // a colour.
    //
    // The drift itself lives in `AmbientBackground` now, so this passes the
    // colour and nothing else: a private `_AmbientRoom` here tweened on the way
    // in, and with the widget tweening too the room would have crossed the same
    // 300ms twice and arrived late.
    return AmbientBackground(
      accent: activeWalk?.accent,
      child: OnboardingKeyboardScope(
        up: keyboardUp,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                // Onboarding gates the shell, so on Windows and Linux this
                // strip is the only thing standing between a frameless window
                // and a window nobody can move or close. Nothing on a phone or
                // a Mac, where AppKit still drags by the background.
                const WindowDragStrip(),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        // A desktop window finally gives the ring room to be the
                        // subject rather than a hat on a form, so the well widens to
                        // hold the two of them side by side. Unchanged on a phone.
                        maxWidth: onboardingSideBySide(context)
                            ? onboardingDesktopMaxWidth
                            : onboardingMaxWidth,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // The register follows the space, not the keyboard. Where the
                          // full one still fits, nothing changes; where it used to
                          // collapse to nothing, the medallion takes over instead.
                          var diameter = _fullRingDiameter(
                            context,
                            constraints.maxHeight,
                          );
                          var compact = false;
                          if (diameter == 0) {
                            diameter = _compactRingDiameter(
                              context,
                              constraints.maxHeight,
                            );
                            compact = diameter > 0;
                          }
                          // Side by side, the ring stops being a header and becomes
                          // the thing the step is about — the instrument at the size
                          // DESIGN.md protects it at, beside the form. It also removes
                          // the reason the ring ever had to collapse: there is no
                          // competition for vertical space in a landscape window, so
                          // the compact medallion is a phone answer to a phone problem
                          // and stays there.
                          final sideBySide = onboardingSideBySide(context);
                          if (sideBySide) {
                            // Two drawn sizes, because the compact window is a
                            // landscape frame rather than a small one: 396 at
                            // 1440x900 and 230 at 720x450. Taking the full
                            // constant in a 450pt window resolved to ~286,
                            // which is a ring wearing the beat rather than the
                            // other way round.
                            diameter = math.min(
                              AppBreakpoints.isCompactDesktop(context)
                                  ? onboardingCompactRingDiameter
                                  : onboardingDesktopRingDiameter,
                              constraints.maxHeight - 120,
                            );
                            compact = false;
                          }

                          // Where the ring settles, and — under Reduce Motion — where
                          // it simply *is*. Both tweens below are removed rather than
                          // shortened for the reason the entrance is: an instrument
                          // that rescales itself every time the keyboard opens is the
                          // most repeated movement on the beat a user has to type on.
                          final settledMark = compact
                              ? _compactMarkFraction
                              : ServiceRing.defaultMarkFraction;
                          final still = MediaQuery.disableAnimationsOf(context);
                          Widget ringAt(double d, double mark) =>
                              AnimatedBuilder(
                                animation: _entrance,
                                builder: (context, _) => ServiceRing(
                                  states: ringStates,
                                  diameter: d,
                                  markFraction: mark,
                                  entrance: AppAnimation.emphasizedCurve
                                      .transform(_entrance.value),
                                  activeService: activeWalk,
                                  progress: activeWalk == null
                                      ? (_page >= _closePage &&
                                                _silent.isEmpty &&
                                                _answering.isNotEmpty
                                            ? 1
                                            : 0)
                                      : (_page - _firstWalkPage) / walk.length,
                                  spin: true,
                                ),
                              );

                          // The step itself: its subject and the pager. One list, two
                          // arrangements — stacked under the ring on a phone, beside it in a
                          // window — so neither layout can grow a step the other does not have.
                          final steps = <Widget>[
                            // The step's subject, hoisted for the same reason the ring is:
                            // a `PageView` builds one element per page, so a headline held
                            // inside the pager can only ever be replaced, never rolled.
                            // Held here it is one widget across the whole walk and the
                            // service name rolls inside a sentence that stays put.
                            if (activeWalk case final service?)
                              // Folds away as the instrument takes its eyebrow over,
                              // on the same clock, so the label reads as moving into
                              // the medallion's row rather than as two labels.
                              OnboardingCollapsible(
                                collapsed: compact,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.md,
                                  ),
                                  child: OnboardingWalkSubject(
                                    service: service,
                                    position: _page - _firstWalkPage + 1,
                                    total: walk.length,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: PageView(
                                controller: _pageController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  OnboardingDoor(
                                    onStart: () => _goTo(_pickPage),
                                    onSkip: _skipEverything,
                                  ),
                                  OnboardingPick(
                                    picked: _picked,
                                    onToggle: (service) => setState(() {
                                      if (_picked.remove(service)) {
                                        _status.remove(service);
                                        _reason.remove(service);
                                        _gateway.remove(service);
                                        _forgetPassedToken(service);
                                        _serverVersion.remove(service);
                                        _pendingCert.remove(service);
                                      } else {
                                        _picked.add(service);
                                        _skipped.remove(service);
                                      }
                                    }),
                                    onContinue: _enterWalk,
                                    onBack: () => _goTo(_doorPage),
                                  ),
                                  for (var i = 0; i < walk.length; i++)
                                    OnboardingWalk(
                                      service: walk[i],
                                      urlController: _urlCtrl[walk[i]]!,
                                      apiKeyController: _apiKeyCtrl[walk[i]]!,
                                      usernameController:
                                          _usernameCtrl[walk[i]]!,
                                      passwordController:
                                          _passwordCtrl[walk[i]]!,
                                      accessController: _accessCtrl[walk[i]]!,
                                      accessFormKey: _accessForm[walk[i]]!,
                                      showAccess: _accessShown.contains(
                                        walk[i],
                                      ),
                                      testedAccess: _testedAccess[walk[i]],
                                      onShowAccess: (kind) =>
                                          _showAccess(walk[i], kind),
                                      status: _status[walk[i]],
                                      reason: _reason[walk[i]],
                                      gateway: _gateway[walk[i]],
                                      sharedTokenFrom: _sharedTokenFor(
                                        walk[i],
                                      )?.from,
                                      onUseSharedToken: () {
                                        final shared = _sharedTokenFor(walk[i]);
                                        if (shared == null) return;
                                        _useSharedToken(walk[i], shared.token);
                                      },
                                      failureDetail: _failureDetail[walk[i]],
                                      serverVersion: _serverVersion[walk[i]],
                                      verifying: _verifying[walk[i]] ?? false,
                                      certificateProbe: _pendingCert[walk[i]],
                                      trustedFingerprint: _pinFor(walk[i]),
                                      affectedServices: _servicesSharingOrigin(
                                        walk[i],
                                      ),
                                      next: i + 1 < walk.length
                                          ? walk[i + 1]
                                          : null,
                                      onTest: () => _test(walk[i]),
                                      onTrustCertificate: () =>
                                          _trustCertificate(walk[i]),
                                      onSuggestPort: () =>
                                          _suggestPort(walk[i]),
                                      onSkip: () => _skip(walk[i]),
                                      onAdvance: () => _advanceFrom(walk[i]),
                                      onBack: () => _backFrom(walk[i]),
                                    ),
                                  OnboardingClose(
                                    connected: _answering,
                                    silent: _silent,
                                    onFix: _fix,
                                    onFinish: _finish,
                                    onReview: () => _goTo(_pickPage),
                                  ),
                                ],
                              ),
                            ),
                          ];

                          return Flex(
                            direction: sideBySide
                                ? Axis.horizontal
                                : Axis.vertical,
                            crossAxisAlignment: sideBySide
                                ? CrossAxisAlignment.center
                                : CrossAxisAlignment.center,
                            children: [
                              // The instrument, outside the pager on purpose. One ring for
                              // the whole flow: it holds its place while the forms page
                              // behind it, rotates the active service to noon, and grows a
                              // spoke the moment one answers. Hoisting it out is what stops
                              // the ring and the shell arriving from two different places on
                              // every step.
                              OnboardingInstrument(
                                collapsed: diameter == 0,
                                compact: compact,
                                label: activeWalk == null
                                    ? null
                                    : OnboardingWalkSubject.eyebrow(
                                        service: activeWalk,
                                        position: _page - _firstWalkPage + 1,
                                        total: walk.length,
                                      ),
                                child: still
                                    ? ringAt(diameter, settledMark)
                                    : TweenAnimationBuilder<double>(
                                        tween: Tween(end: diameter),
                                        // The page slide's own timing, so the resize
                                        // and the shell's travel read as one movement.
                                        duration: AppAnimation.durationMd,
                                        curve: AppAnimation.standardCurve,
                                        builder: (context, animated, _) =>
                                            TweenAnimationBuilder<double>(
                                              // On the same clock as the diameter, so
                                              // the medallion contracts as one object
                                              // rather than as a mark that catches up
                                              // with its ring.
                                              tween: Tween(end: settledMark),
                                              duration: AppAnimation.durationMd,
                                              curve: AppAnimation.standardCurve,
                                              builder: (context, mark, _) =>
                                                  ringAt(animated, mark),
                                            ),
                                      ),
                              ),
                              if (sideBySide)
                                Expanded(child: Column(children: steps))
                              else
                                ...steps,
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
