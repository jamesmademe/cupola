import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_found.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_walk.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/connection_access_fields.dart';
import 'package:cupola/features/shell/presentation/desktop/window_chrome.dart';

/// Where a visit to the way in starts.
enum OnboardingEntry {
  /// The Welcome: a first run, or "Revisit onboarding".
  welcome,

  /// Connect, with Seerr proposed: the Home at zero's "Set up a service",
  /// which is already past the claim.
  connect,
}

/// The way in: the Welcome, Connect (one service, Seerr proposed), and what
/// that service already knows of the others.
///
/// One ring for the whole of it, outside the pager: it greets on the Welcome,
/// turns the service being set up to noon on Connect, and lights each node that
/// answers.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({
    super.key,
    this.entry = OnboardingEntry.welcome,
    this.certificateProber = probeUntrustedCertificate,
    this.localNetworkProbe = probeLocalNetworkAccess,
  });

  final OnboardingEntry entry;

  /// Injectable so a widget test can stay off a real socket: see
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
  static const _welcomePage = 0;
  static const _startPage = 1;
  static const _connectPage = 2;
  static const _foundPage = 3;
  static const _closePage = 4;

  late final _pageController = PageController(initialPage: _page);

  /// The service Connect is setting up: Seerr unless the person chose another.
  ServiceKey _target = ServiceKey.seerr;

  /// The connection Found reads what it knows from, once Seerr or Prowlarr
  /// answered and was saved.
  ServiceInstance? _foundSource;

  /// What the close says: the names that answered in this visit, the ones
  /// known and not added, and the services the ring lights for them.
  List<String> _answering = const [];
  List<String> _notJoined = const [];
  Set<ServiceKey> _lit = const {};

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

  /// The verbatim sentence a failure carried, for the few that carry one: see
  /// `ServiceDiagnosis.detail`. Kept beside [_reason] rather than folded into it
  /// so the walk renders the same words the settings screen does.
  final Map<ServiceKey, String?> _failureDetail = {};

  /// The version each service named while its test ran: see
  /// `ServiceDiagnosis.serverVersion`. Beside [_failureDetail] for the same
  /// reason: the walk prints what the settings screen prints.
  final Map<ServiceKey, String?> _serverVersion = {};
  final Map<ServiceKey, bool> _verifying = {};

  /// Self-signed fingerprints the user chose to trust, persisted on save
  /// (ADR-6): one per service's *origin*, so two services typed at the same
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
  /// (ADR-6): that is a certificate change, not a first trust, and the card
  /// escalates rather than offering it as routine.
  final Map<ServiceKey, UntrustedCertificateProbe> _pendingCert = {};

  /// The field values a verification result belongs to. Editing an address after
  /// a successful check would otherwise leave a green verdict standing for an
  /// instance that is no longer the one configured.
  final Map<ServiceKey, String> _verifiedAgainst = {};

  /// Services left behind by choosing another one in Connect. They keep their
  /// place in the ring but are not written to settings.
  final Set<ServiceKey> _skipped = {};

  @override
  void initState() {
    super.initState();
    // Resume, rather than restart. Saving happens as the walk proceeds, so an
    // interrupted setup leaves settings on disk that this screen must show:
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
    if (widget.entry == OnboardingEntry.connect) {
      _page = _connectPage;
      _picked.add(_target);
    }
    _edits.addListener(_onEdited);
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
    // Before the controllers go: a disposed notifier cannot be listened to.
    _edits.removeListener(_onEdited);
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

  bool _isReady(ServiceKey k) {
    if (!_picked.contains(k) || _skipped.contains(k)) return false;
    if (_urlCtrl[k]!.text.trim().isEmpty) return false;
    if (!k.usesApiKey) return true;
    return _apiKeyCtrl[k]!.text.trim().isNotEmpty;
  }

  /// The ring's state, derived rather than stored: one map, every beat. On
  /// the close it is what answered, lit.
  Map<ServiceKey, ServiceRingState> get _ringStates => _page == _closePage
      ? {for (final k in _lit) k: ServiceRingState.connected}
      : {
          for (final k in _picked)
            k: switch (_verdictOf(k)) {
              ServiceConnectionStatus.connected => ServiceRingState.connected,
              null => ServiceRingState.picked,
              _ =>
                _isReady(k) ? ServiceRingState.silent : ServiceRingState.picked,
            },
        };

  /// The fingerprint [k]'s *currently typed* address is trusted under, or null.
  ///
  /// The gate on [_certFingerprint]: a pin only applies while the address still
  /// resolves to the origin the user accepted the certificate for. Retyping the
  /// old address brings its pin back, which is right: the trust decision was
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

  /// What [service]'s last test found, for as long as it still holds.
  ///
  /// A verdict is about the address, key and access it was given. Edit any of
  /// them after "answered" and it says nothing about what is on screen, so the
  /// step asks for a test again instead of saving a connection nobody tested:
  /// the primary stops being the way forward, and the ring takes the node
  /// back. A failure is left standing, since its outcome and its remedy are
  /// what the person is editing against.
  ServiceConnectionStatus? _verdictOf(ServiceKey service) {
    final status = _status[service];
    if (status != ServiceConnectionStatus.connected) return status;
    return _verifiedAgainst[service] == _fingerprintOf(service) ? status : null;
  }

  /// Every field an edit can retire a verdict through.
  late final Listenable _edits = Listenable.merge([
    ..._urlCtrl.values,
    ..._apiKeyCtrl.values,
    ..._usernameCtrl.values,
    ..._passwordCtrl.values,
    ..._accessCtrl.values,
  ]);

  void _onEdited() {
    // Only an answer that is on screen has anything to lose: the rest of the
    // typing is the form's own business, and rebuilding the screen for every
    // key of it would cost more than it says.
    if (!mounted || _status[_target] != ServiceConnectionStatus.connected) {
      return;
    }
    setState(() {});
  }

  /// Every service in this walk whose typed address shares [service]'s TLS
  /// origin: the set a trust decision on it actually covers, computed from
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

  /// Puts this service's default port on whatever host is already typed.
  void _suggestPort(ServiceKey service) {
    final controller = _urlCtrl[service]!;
    final normalized = UrlUtils.normalizeBaseUrl(controller.text);
    final uri = Uri.tryParse(normalized);
    final host = uri?.host ?? '';
    if (host.isEmpty) return;
    final scheme = uri?.scheme.toLowerCase() == 'http' ? 'http' : 'https';
    setState(() {
      controller.text = '$scheme://$host:${service.defaultPort}';
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

  Future<void> _test(ServiceKey service) async {
    // An Access row with half a token says so under its field, and nothing is
    // sent until it is whole.
    if (_accessForm[service]!.currentState?.validate() == false) return;
    setState(() => _liftCredentials(service));
    // The test's outcome is a sentence under the form, and the button rolls to
    // `Next service` when it succeeds, both of them behind the keyboard while
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
    // gate means the alert is *waited on* rather than raced: allow it and the
    // test simply runs again, deny it and the step says so instead of blaming
    // the address the user just typed.
    final access = _accessCtrl[service]!.access;
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
    // this since ADR-6: there is no pinning-capability gate left to check.
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
  }

  Future<void> _trustCertificate(ServiceKey service) async {
    final probe = _pendingCert[service];
    if (probe == null) return;
    // Recorded against the address the certificate was actually presented by,
    // so a later edit of that address drops the pin rather than carrying it to
    // a host that never presented it: see [_certOriginOf].
    final origin = UrlUtils.certOrigin(_urlCtrl[service]!.text);
    if (origin == null) return;
    setState(() {
      _certFingerprint[service] = probe.certificate.fingerprint;
      _certOriginOf[service] = origin;
      _pendingCert.remove(service);
    });
    await _test(service);
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Writes what this walk actually configured, and **only** that.
  ///
  /// Additive on purpose: a service the user skipped, left half-filled, or
  /// unpicked is not written at all. It used to be written *blank*, which
  /// deleted the saved address and the secure credential of a service that was
  /// working, reachable from the settings screen's "Revisit onboarding", which
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
    // URL is known: an abandoned address's pin is only forgotten when no
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
        "Could not save your services. Retry, and restart Cupola if it "
        'keeps failing.',
      );
      return false;
    }
  }

  /// Marks the way in finished and goes to the Home. The router never sends
  /// anyone away from the way in, so leaving it is this method's to do.
  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    try {
      await markOnboardingComplete(ref);
    } catch (_) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        "Could not finish setup. Retry, and restart Cupola if it keeps "
        'failing.',
      );
      return;
    }
    if (mounted) context.go(ServiceRoutes.home);
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  /// The beat on screen. Held in state rather than read off the controller
  /// because `PageController.page` is fractional mid-flight, and the ring above
  /// the pager needs the destination to aim at, not the halfway point.
  int _page = _welcomePage;

  void _goTo(int page) {
    if (!_pageController.hasClients) return;
    // Leaving a beat means leaving the field you were in.
    //
    // A focused `EditableText` registers a keep-alive with the pager, so the step
    // the user walked away from stayed mounted *and* focused. The keyboard
    // therefore rode along: the close arrived with half of it covered by keys
    // belonging to a form that was no longer on screen, and anything typed went
    // into that invisible field. Unfocusing here rather than in each caller is
    // the point: every way out of a step, forward, back, skip or fix, comes
    // through this method.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _page = page);
    // Reduce Motion removes the slide rather than shortening it, the same way
    // the ring's entrance is removed: the beat is simply the next one. This is
    // the flow's most frequent movement: every Continue, Skip, Back and Next
    // goes through here, so leaving it running was most of what "the whole
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

  /// Connect for [service]: the one this visit sets up. A service set aside
  /// by choosing another stays in the ring and out of settings.
  void _connect(ServiceKey service) {
    setState(() {
      if (service != _target && _picked.remove(_target)) {
        _skipped.add(_target);
      }
      _target = service;
      _picked.add(service);
      _skipped.remove(service);
    });
    _goTo(_connectPage);
  }

  /// Seerr and Prowlarr lead somewhere: they know the others.
  bool get _targetKnowsOthers => _target.knowsOthers != null;

  /// The service answered: saved, then on to what it knows, or the close.
  Future<void> _advance() async {
    final saved = await _save();
    if (!saved || !mounted) return;
    if (_targetKnowsOthers) {
      final source = ref.read(currentSettingsProvider).primaryOf(_target);
      if (source != null) {
        setState(() => _foundSource = source);
        _goTo(_foundPage);
        return;
      }
    }
    _close(answering: [_target.title], lit: {_target});
  }

  /// Found's way on: what answered written in one save with the certificates
  /// trusted for it, then the close.
  Future<void> _foundDone(
    List<FoundConnection> found,
    List<String> notJoined,
  ) async {
    final source = _foundSource!;
    if (found.isNotEmpty && !await _saveFound(found)) return;
    if (!mounted) return;
    _close(
      answering: [source.service.title, for (final c in found) c.name],
      notJoined: notJoined,
      lit: {source.service, for (final c in found) c.instance.service},
    );
  }

  Future<bool> _saveFound(List<FoundConnection> found) async {
    var updated = ref.read(currentSettingsProvider);
    for (final connection in found) {
      updated = updated.copyWithInstance(connection.instance);
      if (connection.certFingerprint case final pin?) {
        updated = updated.copyWithTrustedCertificate(
          url: connection.instance.url,
          fingerprint: pin,
        );
      }
    }
    try {
      await ref.read(settingsProvider.notifier).updateSettings(updated);
      return true;
    } catch (_) {
      if (!mounted) return false;
      SnackBarHelper.error(
        context,
        "Could not save your services. Retry, and restart Cupola if it "
        'keeps failing.',
      );
      return false;
    }
  }

  /// The close: what answered, and the way into the app.
  void _close({
    required List<String> answering,
    List<String> notJoined = const [],
    required Set<ServiceKey> lit,
  }) {
    setState(() {
      _answering = answering;
      _notJoined = notJoined;
      _lit = lit;
    });
    _goTo(_closePage);
  }

  /// Out of Connect: to the Welcome on a first run, back where the visit came
  /// from when it started at Connect.
  void _backFromConnect() {
    if (widget.entry == OnboardingEntry.connect) {
      _leave();
      return;
    }
    _goTo(_welcomePage);
  }

  /// Back where a visit from inside the app came from.
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(ServiceRoutes.home);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  /// The ring's size in its **full** register, given the height the column
  /// actually has (zero is the signal to try the compact one).
  ///
  /// Two preferred sizes, not four: the door and the close are about the whole
  /// stack, so the instrument is the subject there; picking and configuring are
  /// about one service at a time, so it steps down to leave the form room; but
  /// it is the *same* ring resizing, never a second one.
  ///
  /// [available] is what keeps it honest. The ring takes what is left after the
  /// beat's own content is served, so it shrinks smoothly on a short screen. An
  /// earlier version hid it on `viewInsets > 0` alone, which was wrong twice
  /// over: a hardware or floating keyboard reports a small inset and left half
  /// the screen empty with no ring in it, and a tall phone with the software
  /// keyboard up has room for a reduced one.
  double _fullRingDiameter(BuildContext context, double available) {
    // The Welcome and the close are about the whole stack, so the instrument
    // is the subject there.
    final preferred = _page == _welcomePage || _page == _closePage
        ? 300.0
        : 190.0;
    final wanted = serviceRingDiameter(context, preferred: preferred);
    if (!available.isFinite) return wanted;

    // What the rest of the column needs before the ring gets anything: the
    // subject line, a two-field form, and the pinned actions. Scaled by the
    // reading size, since every one of them is text-driven.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final reserved = _contentFloor * scale.clamp(1.0, 2.0);
    final spare = available - reserved;

    // Below its own floor a ring is a smudge rather than an instrument. This is
    // not the ring leaving, though: it is the point where the compact register
    // takes over.
    if (spare < _ringFloor) return 0;
    return spare < wanted ? spare : wanted;
  }

  /// The ring's size in its **compact** register: a medallion in the header row,
  /// beside the step's eyebrow.
  ///
  /// The full register asks for whatever the beat leaves over, and with a
  /// software keyboard up that is nothing: a 6.1" phone keeps about 420pt of
  /// column and the beat's own content wants more than that on its own, so the
  /// ring came out at zero on every phone rather than merely smaller. The
  /// compact register does not compete: it *replaces* the subject line's row
  /// instead of sitting above it, so it is sized from a share of the short
  /// screen rather than from its leftovers, and the form still ends up with
  /// roughly 100pt more than it had.
  ///
  /// Returns zero only in the genuine squeeze: an accessibility reading size on
  /// a small phone, where even a medallion would eat the one field the user is
  /// typing into. The caller falls back to the full register's answer there,
  /// which is the ring standing down and the subject line staying whole.
  double _compactRingDiameter(BuildContext context, double available) {
    if (!available.isFinite) {
      return serviceRingDiameter(context, preferred: _compactCeiling);
    }
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    // One labelled field with its help line, the pinned actions, and the beat's
    // own gutters. Far less than [_contentFloor] because the fields below the
    // focused one are allowed to be scrolled to: the return key walks the form
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
  /// line, two fields with labels, and the action block. Deliberately generous.
  /// Erring here costs a smaller ring, while erring the other way costs a
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
  /// buys that air back (at 132 the gap returns to ~38pt) and the nodes stay
  /// the thing the eye reads first, which is the whole point of a dial.
  static const double _compactMarkFraction = 0.34;

  /// [serviceRingDiameter]'s own clamp floor. Under this the ring stops being
  /// legible, so it leaves instead.
  static const double _ringFloor = 96;

  /// Connect's form for [service]: the step every way in goes through.
  ///
  /// [compact] is the instrument's short-screen register, where the subject
  /// above the form is folded away: the link to another service goes to the
  /// foot of the form then, rather than with it.
  Widget _connectStep(ServiceKey service, bool compact) => OnboardingWalk(
    key: ValueKey(service),
    service: service,
    urlController: _urlCtrl[service]!,
    apiKeyController: _apiKeyCtrl[service]!,
    usernameController: _usernameCtrl[service]!,
    passwordController: _passwordCtrl[service]!,
    accessController: _accessCtrl[service]!,
    accessFormKey: _accessForm[service]!,
    showAccess: _accessShown.contains(service),
    testedAccess: _testedAccess[service],
    onShowAccess: (kind) => _showAccess(service, kind),
    status: _verdictOf(service),
    reason: _reason[service],
    gateway: _gateway[service],
    failureDetail: _failureDetail[service],
    serverVersion: _serverVersion[service],
    verifying: _verifying[service] ?? false,
    certificateProbe: _pendingCert[service],
    trustedFingerprint: _pinFor(service),
    affectedServices: _servicesSharingOrigin(service),
    onTest: () => _test(service),
    onTrustCertificate: () => _trustCertificate(service),
    onSuggestPort: () => _suggestPort(service),
    onAdvance: _advance,
    onBack: _backFromConnect,
    onStartElsewhere: compact ? () => _goTo(_startPage) : null,
  );

  @override
  Widget build(BuildContext context) {
    final ringStates = _ringStates;
    final activeWalk = _page == _connectPage ? _target : null;
    final step = _targetKnowsOthers ? 'Step 1 of 2' : null;

    // Resolved here, outside the `Scaffold`: a Scaffold that resizes for the
    // keyboard removes the bottom inset from the MediaQuery it hands its body,
    // so anything below this point is told the keyboard is down while it is up.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

    // The room the walk happens in: lit by the neutral lamp throughout. Null on
    // the Welcome, Start and the close, where `AmbientBackground`'s own default
    // is the lamp; per service in between, where the service's accent is the
    // lamp too, so the light holds steady while the page and the ring move,
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
                          // the thing the step is about: the instrument at the size
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

                          // Where the ring settles, and, under Reduce Motion, where
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
                                  progress: 0,
                                  spin: true,
                                ),
                              );

                          // The step itself: its subject and the pager. One list, two
                          // arrangements: stacked under the ring on a phone, beside it in a
                          // window, so neither layout can grow a step the other does not have.
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
                                    step: step,
                                    onStartElsewhere: () => _goTo(_startPage),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: PageView(
                                controller: _pageController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  OnboardingWelcome(
                                    onSetUp: () => _connect(ServiceKey.seerr),
                                    onBack: context.canPop() ? _leave : null,
                                  ),
                                  OnboardingStart(
                                    onPick: _connect,
                                    onBack: () => _goTo(_connectPage),
                                  ),
                                  _connectStep(_target, compact),
                                  if (_foundSource case final source?)
                                    OnboardingFound(
                                      key: ValueKey(source.id),
                                      source: source,
                                      onDone: _foundDone,
                                      onBack: () => _goTo(_connectPage),
                                      certificateProber:
                                          widget.certificateProber,
                                    )
                                  else
                                    const SizedBox.shrink(),
                                  if (_answering.isNotEmpty)
                                    OnboardingClose(
                                      answering: _answering,
                                      notJoined: _notJoined,
                                      setUp: {
                                        for (final s in ServiceKey.values)
                                          if (ref
                                              .watch(currentSettingsProvider)
                                              .hasServiceConnection(s))
                                            s,
                                      },
                                      onEnter: _finish,
                                    )
                                  else
                                    const SizedBox.shrink(),
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
                                        step: step,
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
