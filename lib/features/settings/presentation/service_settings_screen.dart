import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/platform/secure_clipboard.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/release_search/presentation/widgets/search_headroom_card.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/stream/presentation/widgets/jellyfin_viewer_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_access_rules.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_content.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_dialog.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart';

/// One service's address and credentials, and the state of that connection.
///
/// This is where a red service gets fixed, so the screen leads with what is
/// wrong: the header states the saved connection in the service's own colour,
/// and a failed test names the actual cause — a rejected key, a wrong base
/// path, an untrusted certificate — rather than listing everything it could be.
class ServiceSettingsScreen extends ConsumerStatefulWidget {
  final ServiceKey service;

  /// Which connection this form edits. Null means the service's first one,
  /// which is what every caller meant before there could be a second.
  final String? instanceId;

  /// Whether this form is adding a connection rather than editing one.
  ///
  /// Distinct from a null [instanceId] because a new instance has no id to name
  /// until it is saved: minting one and passing it here would have the form
  /// look for something that is not in settings yet and quietly fall back to
  /// editing the first.
  final bool isNew;

  /// Injectable so a widget test can stay off a real socket — see
  /// [CertificateProber].
  final CertificateProber certificateProber;

  /// Injectable for the same reason: the real one reaches the host OS and, on
  /// iOS, can put a permission alert on screen.
  final LocalNetworkProbe localNetworkProbe;

  /// The Access choice to open on, for a gateway's remedy: the form scrolls to
  /// its Access row, with this choice made when the connection has none yet.
  final AccessKind? initialAccess;

  const ServiceSettingsScreen({
    super.key,
    required this.service,
    this.instanceId,
    this.isNew = false,
    this.certificateProber = probeUntrustedCertificate,
    this.localNetworkProbe = probeLocalNetworkAccess,
    this.initialAccess,
  });

  @override
  ConsumerState<ServiceSettingsScreen> createState() =>
      _ServiceSettingsScreenState();
}

class _ServiceSettingsScreenState extends ConsumerState<ServiceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _labelController;

  // The Access row: what this connection presents to a gateway in front of
  // the service. One controller per field of every choice, so switching
  // choices and back keeps what was typed.
  late AccessKind _accessKind;
  late final TextEditingController _cloudflareIdController;
  late final TextEditingController _cloudflareSecretController;
  late final TextEditingController _proxyUsernameController;
  late final TextEditingController _proxyPasswordController;
  final List<_HeaderFields> _headers = [];
  late final ConnectionAccess _initialAccess;
  final _accessKey = GlobalKey();

  /// The access the last test sent, which decides how its outcome is said.
  ConnectionAccess _testedAccess = const NoAccess();

  /// The connections a token that just passed its test could also reach:
  /// their last failure was the same Access team. Empty when there is no
  /// offer to make.
  List<ServiceInstance> _shareCandidates = const [];

  /// The connection being edited, as it stood when the form opened.
  ///
  /// Only [ServiceInstance.id] is relied on afterwards — every write re-reads
  /// the live one by that id, so a value changed elsewhere while this form sat
  /// open is not clobbered by a stale copy.
  late final ServiceInstance _target;

  bool _saving = false;
  bool _testing = false;
  bool _revealApiKey = false;

  /// Result of the last "Test connection", or null when it has not been run
  /// since the fields last changed.
  ServiceDiagnosis? _testResult;

  /// Field values as loaded, so leaving with edits can warn instead of silently
  /// discarding them.
  late final Map<String, String> _initialValues;

  ServiceKey get service => widget.service;

  bool get isPlex => service == ServiceKey.plex;

  /// Services authenticated with username/password rather than an API key.
  ///
  /// The registry owns this fact — see [ServiceKeyExtension.usesApiKey]. Spelled
  /// out here as its own three-way check, adding a credential-authenticated
  /// service meant this screen and the persistence layer could disagree about
  /// which fields the service even has.
  bool get usesCredentials => !service.usesApiKey;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(currentSettingsProvider);
    final named = widget.instanceId == null
        ? null
        : settings.instanceById(widget.instanceId!);
    _target = widget.isNew
        ? settings.newInstanceFor(service)
        // An id belonging to another service is ignored rather than trusted:
        // writing this form's fields onto a Sonarr would be silent corruption.
        : (named != null && named.service == service
              ? named
              : settings.primaryOf(service) ??
                    settings.newInstanceFor(service));

    _urlController = TextEditingController(text: _target.url);
    _apiKeyController = TextEditingController(
      text: usesCredentials ? '' : _target.credential,
    );
    _usernameController = TextEditingController(
      text: usesCredentials ? _target.username : '',
    );
    _passwordController = TextEditingController(
      text: usesCredentials ? _target.credential : '',
    );
    _labelController = TextEditingController(text: _target.label);

    final access = _target.access;
    _initialAccess = access;
    _cloudflareIdController = TextEditingController(
      text: access is CloudflareServiceToken ? access.clientId : '',
    );
    _cloudflareSecretController = TextEditingController(
      text: access is CloudflareServiceToken ? access.clientSecret : '',
    );
    _proxyUsernameController = TextEditingController(
      text: access is ProxyPassword ? access.username : '',
    );
    _proxyPasswordController = TextEditingController(
      text: access is ProxyPassword ? access.password : '',
    );
    if (access is CustomHeaders) {
      for (final entry in access.entries) {
        _headers.add(_HeaderFields(entry.name, entry.value, _onFieldChanged));
      }
    }
    final asked = widget.initialAccess;
    _accessKind =
        access is NoAccess &&
            asked != null &&
            accessKindsFor(service).contains(asked)
        ? asked
        : access.kind;
    if (_accessKind == AccessKind.custom && _headers.isEmpty) {
      _headers.add(_HeaderFields('', '', _onFieldChanged));
    }
    if (asked != null) {
      // Opened by a gateway's remedy: the fix is on the Access row.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _accessKey.currentContext;
        if (row != null && row.mounted) Scrollable.ensureVisible(row);
      });
    }

    _initialValues = {
      for (final entry in _controllers.entries) entry.key: entry.value.text,
    };
    for (final controller in _controllers.values) {
      controller.addListener(_onFieldChanged);
    }
  }

  Map<String, TextEditingController> get _controllers => {
    'url': _urlController,
    'apiKey': _apiKeyController,
    'username': _usernameController,
    'password': _passwordController,
    'label': _labelController,
    'cloudflareId': _cloudflareIdController,
    'cloudflareSecret': _cloudflareSecretController,
    'proxyUsername': _proxyUsernameController,
    'proxyPassword': _proxyPasswordController,
  };

  /// Whether any field differs from what was loaded.
  bool get _isDirty => _accessFromFields() != _initialAccess
      ? true
      : _controllers.entries.any(
          (entry) =>
              !entry.key.startsWith('cloudflare') &&
              !entry.key.startsWith('proxy') &&
              entry.value.text != _initialValues[entry.key],
        );

  /// The access the Access row describes, as it would be saved: a choice
  /// whose fields are all empty is no access at all, so a form opened on
  /// Cloudflare Access by a remedy and left alone saves nothing new.
  ConnectionAccess _accessFromFields() {
    switch (_accessKind) {
      case AccessKind.none:
        return const NoAccess();
      case AccessKind.cloudflare:
        final id = _cloudflareIdController.text.trim();
        final secret = _cloudflareSecretController.text.trim();
        if (id.isEmpty && secret.isEmpty) return const NoAccess();
        return CloudflareServiceToken(clientId: id, clientSecret: secret);
      case AccessKind.password:
        final username = _proxyUsernameController.text.trim();
        final password = _proxyPasswordController.text;
        if (username.isEmpty && password.isEmpty) return const NoAccess();
        return ProxyPassword(username: username, password: password);
      case AccessKind.custom:
        final entries = [
          for (final header in _headers)
            if (!header.isBlank)
              (name: header.name.text.trim(), value: header.value.text),
        ];
        return entries.isEmpty ? const NoAccess() : CustomHeaders(entries);
    }
  }

  /// Takes on a name this connection was given somewhere other than here.
  ///
  /// There is exactly one writer: the *sibling's* form. Saving a second
  /// connection derives a name for the first one — see [_deriveSiblingLabels]
  /// — and the first one's form is very often still on the stack underneath,
  /// holding the empty string it loaded when that connection was the only one
  /// there was. Coming back to it, [_needsLabel] is now true, so the field
  /// appears empty and its validator refuses to save a connection the user
  /// never touched and which *has* a name — one already on the badge, in the
  /// lens sheet and above its section in search.
  ///
  /// Only when the field holds exactly what it loaded. An adoption that
  /// overwrote a half-typed name would trade a stale field for a lost edit,
  /// which is the worse of the two.
  ///
  /// The listener is detached across the write so the assignment does not read
  /// as the user typing: that would clear a test result the values are still
  /// good for, and mark a form dirty that nobody has edited. Moving
  /// `_initialValues` along with it is the other half of the same point — the
  /// adopted name is the new baseline, not an unsaved change to warn about on
  /// the way out.
  void _adoptPersistedLabel(String persisted) {
    if (persisted == _labelController.text) return;
    if (_labelController.text != _initialValues['label']) return;

    _labelController.removeListener(_onFieldChanged);
    _labelController.text = persisted;
    _labelController.addListener(_onFieldChanged);
    _initialValues['label'] = persisted;
  }

  void _onFieldChanged() {
    // A test result describes the values that were tested; once they change it
    // is stale and claiming otherwise would be worse than showing nothing. The
    // header also switches to "unsaved changes" on the first edit, so the row
    // has to rebuild either way.
    setState(() {
      _testResult = null;
      _shareCandidates = const [];
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.removeListener(_onFieldChanged);
    }
    _urlController.dispose();
    _apiKeyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _labelController.dispose();
    for (final controller in [
      _cloudflareIdController,
      _cloudflareSecretController,
      _proxyUsernameController,
      _proxyPasswordController,
    ]) {
      controller.dispose();
    }
    for (final header in _headers) {
      header.dispose();
    }
    super.dispose();
  }

  /// Verifies the values currently in the form without saving them.
  ///
  /// Onboarding has always had this; settings did not, so the only way to find
  /// out whether an edited URL or key worked was to save it and watch the
  /// service list go offline.
  Future<void> _testConnection() async {
    if (_testing || _saving) return;
    if (!_formKey.currentState!.validate()) return;

    // The answer to a test is rendered under the fields, and behind a reverse
    // proxy the wait for it can run to fifteen seconds — spending them behind
    // half a screen of keys is the one thing this screen can avoid. Dismissed
    // here rather than in each caller: the button, the return key and the
    // retest after trusting a certificate all come through this method.
    // After validation, so a rejected field keeps the caret where the fix is.
    FocusScope.of(context).unfocus();

    // The Access team this connection's last failure named, read before the
    // test replaces it: the offer to share a token that passes needs it.
    final team = _lastAccessTeam();
    setState(() {
      _testing = true;
      _testResult = null;
      _shareCandidates = const [];
    });
    try {
      final candidate = _updateServiceSettings(
        ref.read(currentSettingsProvider),
      );
      _testedAccess =
          candidate.instanceById(_target.id)?.access ?? const NoAccess();
      // Through the local-network gate: a LAN address that fails because the OS
      // has not been allowed onto the network reports the permission, and one
      // the user allows while the alert is up is simply tested again — the
      // retest that used to be theirs to work out.
      final candidateInstance = candidate.instanceById(_target.id) ?? _target;
      var result = await diagnoseThroughLocalNetworkGate(
        () => diagnoseInstance(candidateInstance, candidate),
        url: candidateInstance.url,
        probe: widget.localNetworkProbe,
      );

      // TLS exception flow: when the failure could be explained by a
      // certificate, offer to trust it and test again. Every service can
      // reach this since ADR-6. Skipped once the server has answered —
      // probing for a certificate after a rejected API key is a round trip
      // that can only come back null.
      if (mounted &&
          result.isDisconnected &&
          certProbeWorthwhile(result.reason)) {
        final url = candidateInstance.url;
        final previousPin = candidate.pinForUrl(url);
        final probe = await widget.certificateProber(
          url,
          pinnedFingerprint: previousPin ?? '',
        );
        if (probe != null && mounted) {
          final trust = await showCertTrustDialog(
            context,
            origin: UrlUtils.certOrigin(url) ?? url,
            probe: probe,
            previousFingerprint: previousPin,
            sharedWith: candidate
                .servicesSharingOriginOf(url)
                .where((s) => s != service)
                .toList(),
          );
          if (trust && mounted) {
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
            if (!mounted) return;
            // The retest goes to the same connection the first test did.
            // `diagnoseService` folds every connection of the service, so it
            // could answer about a sibling that was never part of this trust
            // decision.
            final retried = _updateServiceSettings(
              ref.read(currentSettingsProvider),
            );
            result = await diagnoseInstance(
              retried.instanceById(_target.id) ?? candidateInstance,
              retried,
            );
          }
        }
      }

      if (!mounted) return;
      HapticFeedback.lightImpact();
      final shareable = result.isConnected
          ? _sameTeamConnections(team, _testedAccess)
          : const <ServiceInstance>[];
      setState(() {
        _testResult = result;
        _shareCandidates = shareable;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = ServiceDiagnosis.failed(e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// Confirms before dropping unsaved edits.
  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Discard changes?',
      message:
          'Your edits to the ${service.title} settings have not been saved.',
      confirmLabel: 'Discard changes',
      cancelLabel: 'Keep editing',
    );
    return result.confirmed;
  }

  Future<void> _saveSettings() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final current = ref.read(currentSettingsProvider);
    // Captured before the write: an edited URL moves this service off an origin
    // whose certificate may have been pinned, and `_maybePromptCertTrust` below
    // can only ever *add* a pin. Left behind, the entry outlives the address —
    // and because `pinForUrl` is keyed purely by origin, any service later
    // pointed back at it would silently reuse the stale trust with no prompt.
    final priorUrl = current.instanceById(_target.id)?.url ?? '';
    var updated = _updateServiceSettings(
      current,
    ).copyWithoutUnusedCertificate(priorUrl);

    final notifier = ref.read(settingsProvider.notifier);
    await notifier.updateSettings(updated);
    if (!mounted) return;

    // Offer to trust a self-signed certificate so the connection is
    // authenticated rather than blindly accepted. Only prompts when the
    // failure is specifically an untrusted certificate; a reachable server or
    // an unrelated failure just saves as before.
    final pinned = await _maybePromptCertTrust(updated, notifier);
    if (!mounted) return;
    if (pinned != null) updated = pinned;

    if (!mounted) return;
    Navigator.of(context).pop();
    SnackBarHelper.success(context, '${service.title} settings saved');
  }

  /// Returns the updated settings when the user trusts a certificate, else null.
  Future<SettingsModel?> _maybePromptCertTrust(
    SettingsModel updated,
    SettingsNotifier notifier,
  ) async {
    setState(() => _saving = true);
    try {
      // This connection, not the service: the origin whose certificate is about
      // to be probed — and offered for trust — has to be the one whose address
      // is in the field above.
      final target = updated.instanceById(_target.id);
      if (target == null) return null;
      final result = await diagnoseInstanceWithCertProbe(
        target,
        updated,
        probe: widget.certificateProber,
      );
      if (!mounted) return null;
      final probe = result.certificateProbe;
      if (probe == null) return null;

      final url = target.url;
      final trust = await showCertTrustDialog(
        context,
        origin: UrlUtils.certOrigin(url) ?? url,
        probe: probe,
        previousFingerprint: updated.pinForUrl(url),
        sharedWith: updated
            .servicesSharingOriginOf(url)
            .where((s) => s != service)
            .toList(),
      );
      if (!mounted || !trust) return null;

      final pinned = updated.copyWithTrustedCertificate(
        url: url,
        fingerprint: probe.certificate.fingerprint,
      );
      await notifier.updateSettings(pinned);
      return pinned;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  SettingsModel _updateServiceSettings(SettingsModel current) {
    // Same normalisation onboarding applies, so a trailing slash or a scheme
    // typed in either screen ends up stored the one way the clients use.
    final url = UrlUtils.normalizeBaseUrl(_urlController.text);
    var next = _writeService(
      current,
      url: url,
      apiKey: _apiKeyController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      label: _labelController.text.trim(),
    );

    // The sibling that was alone until a moment ago has no name, and it is
    // about to need one: with two connections and one nameless, the badge and
    // every badge-bearing row would fall back to showing its id. Derived from
    // whatever actually tells the two apart — the port when they share a host,
    // the host when they do not — and editable in its own form afterwards.
    // Never the word "Default": that names a role, and the role moves.
    if (_labelController.text.trim().isNotEmpty) {
      next = _deriveSiblingLabels(next, url);
    }
    return next;
  }

  /// Writes this service's fields onto [current].
  ///
  /// Which of the two shapes to write is the registry's answer — one branch on
  /// the capability rather than a per-service chain. Routing a
  /// credential-authenticated service through the API-key path is what used to
  /// leave a saved username and password behind on a clear.
  SettingsModel _writeService(
    SettingsModel current, {
    required String url,
    required String apiKey,
    required String username,
    required String password,
    String? label,
  }) {
    // Re-read by id rather than reusing the copy captured at initState: the
    // chosen viewer, say, may have moved while this form was open and the
    // captured copy would put it back.
    final live = current.instanceById(_target.id) ?? _target;
    return current.copyWithInstance(
      live.copyWith(
        url: url,
        credential: usesCredentials ? password : apiKey,
        username: usesCredentials ? username : '',
        label: label,
        access: _accessFromFields(),
      ),
    );
  }

  Future<void> _removeConnection() async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.link_off_rounded,
      title: 'Remove ${service.title}?',
      message:
          'This deletes the saved address and credentials for ${service.title}. '
          'Nothing on the server itself is touched. This cannot be undone.',
      confirmLabel: 'Remove ${service.title}',
    );
    if (!result.confirmed || !mounted) return;

    final before = ref.read(currentSettingsProvider);
    final priorUrl = before.instanceById(_target.id)?.url ?? '';
    final cleared = before
        // Drops the whole connection rather than blanking its fields, which
        // takes the chosen viewer with it. `copyWithoutServiceExtras` used to
        // do that job and is deliberately not called any more: it clears the
        // viewer on *every* instance of the service, so removing one Jellyfin
        // would have reset which person the other one reads through.
        .copyWithoutInstance(_target.id)
        // Forget this origin's pin too, but only when nothing else configured
        // still reaches it — removing Sonarr must never break Radarr's trust
        // in the same reverse proxy, and with instances that includes the
        // service's own second connection behind it.
        .copyWithoutUnusedCertificate(priorUrl);

    await ref.read(settingsProvider.notifier).updateSettings(cleared);

    // The lens outlives the connection it names unless something says
    // otherwise. Harmless while it is only ever *resolved* — `activeInstance`
    // falls back to the first instance when the id matches nothing — but the id
    // stays on disk for good, and the day a badge or a `?i=` NAMES it rather
    // than resolving it, the app is carrying a pointer to a server that was
    // deleted months ago.
    //
    // Only when it was this connection: clearing unconditionally would send a
    // lens deliberately parked on the second connection back to the first
    // because the user removed the third.
    if (ref.read(activeInstancesProvider)[service] == _target.id) {
      await ref.read(activeInstancesProvider.notifier).clear(service);
    }
    if (!mounted) return;

    Navigator.of(context).pop();
    SnackBarHelper.info(context, '${service.title} removed');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Never blocks the iOS back gesture outright — `canPop` stays true unless
      // there is something to lose, and the guard only asks.
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !context.mounted) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    // Written by the sibling's form while this one sat open — see
    // [_adoptPersistedLabel]. Listened for rather than read: this form is not
    // rebuilt by being returned to, so nothing else would notice.
    ref.listen(
      currentSettingsProvider.select(
        (s) => s.instanceById(_target.id)?.label ?? '',
      ),
      (_, persisted) => _adoptPersistedLabel(persisted),
    );

    final settings = ref.watch(currentSettingsProvider);
    // **This connection's** state, not the service's. `isServiceConfigured` is
    // true as soon as *any* instance is set up, which on the add-a-connection
    // form meant an empty page announcing "Answering" (the first connection's
    // status), offering a viewer picker bound to the first server, and showing
    // a Remove row for a connection that does not exist yet — its confirm
    // dialog removed nothing and simply popped the screen.
    final isConfigured =
        settings.instanceById(_target.id)?.isConfigured ?? false;

    return AmbientScaffold(
      // The room takes the colour of the service being worked on.
      accent: service.accent,
      appBar: GlassAppBar(
        // The service's name alone. It read "Radarr Settings", which is the
        // name of a different page: *Service settings* is Radarr's own
        // configuration, read and written through Radarr's API, while this form
        // is how Cupola reaches it — address, key, certificate, connection
        // name. Two pages one word apart is how a user ends up on the wrong
        // one; the breadcrumb above already says Settings › Connections.
        title: Text(service.title),
        actions: [_buildSaveAction()],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            _buildHeader(context, isConfigured: isConfigured),
            // Setup guidance is registry data, alongside the default port and
            // the credential breadcrumb this screen already reads from there.
            if (service.setupNote case final note?) ...[
              const SizedBox(height: AppSpacing.md),
              _buildInfoNote(context, note),
            ],
            const SizedBox(height: AppSpacing.xl),
            // Before the address on purpose: name the thing, then say where it
            // lives. By the time someone is here for a second connection they
            // are already thinking "these two are different" — that is the
            // moment the name costs nothing to give.
            if (_needsLabel(settings)) ...[
              _buildLabelField(settings),
              const SizedBox(height: AppSpacing.lg),
            ],
            _buildUrlField(),
            _buildTrustedCertificateIndicator(settings),
            const SizedBox(height: AppSpacing.lg),
            if (usesCredentials) _buildUsernameField() else _buildApiKeyField(),
            if (usesCredentials) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildPasswordField(),
            ],
            const SizedBox(height: AppSpacing.xl),
            _buildAccessSection(context),
            const SizedBox(height: AppSpacing.xl),
            _buildTestConnectionRow(context),
            if (_testResult != null) ...[
              const SizedBox(height: AppSpacing.md),
              _buildTestResult(context, _testResult!),
            ],
            if (_shareCandidates.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _buildShareOffer(context),
            ],
            // Directly under the connection test, because the ceiling is a
            // property of *this instance's path* — a stack can easily have Sonarr
            // behind a proxy and Radarr direct over Tailscale.
            if (SearchHeadroomCard.appliesTo(widget.service)) ...[
              const SizedBox(height: AppSpacing.lg),
              SearchHeadroomCard(service: widget.service),
            ],
            // A capability check, the same shape as `appliesTo` two lines up:
            // the picker belongs to any service whose library has to be entered
            // through a person, not to "Jellyfin" by name. Only once a
            // connection exists, because the viewer list comes from `/Users` on
            // the server — offering it before there is a server to ask would be
            // a control that can only fail.
            // Bound to the connection this form edits. Read and written through
            // the service's flat projection, it listed the users of *this*
            // server and saved the chosen one onto the FIRST connection —
            // leaving that server pointed at a user id from a different user
            // table, which is the exact failure `ServiceInstance.viewerId`
            // exists to prevent.
            if (service.needsViewerSelection && isConfigured) ...[
              const SizedBox(height: AppSpacing.xxl),
              JellyfinViewerPicker(instanceId: _target.id),
            ],
            const SizedBox(height: AppSpacing.xxl),
            _buildConnectionsSection(context, settings),
            if (isConfigured) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildRemoveRow(context),
            ],
          ],
        ),
      ),
    );
  }

  /// The service, its host, and the state of the saved connection.
  ///
  /// Once the form is dirty the saved state no longer describes what is on
  /// screen, so it steps aside rather than contradicting the fields.
  Widget _buildHeader(BuildContext context, {required bool isConfigured}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final serviceTheme = ServiceTheme.fromAccent(service.accent);

    return AppCard.filled(
      accentColor: service.accent,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: serviceTheme.softContainer,
              borderRadius: AppRadius.borderRadiusMd,
            ),
            // The mark on its 14% tile over the card, walked rather than raw.
            child: Icon(
              service.icon,
              color: ServiceTheme.onTint(
                service.accent,
                surface: colorScheme.surfaceContainer,
                tintAlpha: 0.14,
              ),
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  service.title,
                  style: theme.textTheme.titleMedium!.weight(FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${service.domain.label} · ${service.apiVersion}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_isDirty)
                  _HeaderStatus(
                    icon: Icons.edit_note_rounded,
                    label: 'Unsaved changes',
                    color: colorScheme.onSurfaceVariant,
                  )
                else if (isConfigured)
                  _SavedConnectionStatus(instanceId: _target.id)
                else
                  _HeaderStatus(
                    icon: Icons.add_link_rounded,
                    label: 'Not set up yet',
                    color: colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // === Access ==============================================================

  /// What this connection presents to a gateway in front of the service, on
  /// every request: None, a Cloudflare Access service token, a proxy's
  /// password, or custom headers. Today's form, with the row added under the
  /// credential; nothing here is sent until the form is tested or saved.
  Widget _buildAccessSection(BuildContext context) {
    final kinds = accessKindsFor(service);
    return KeyedSubtree(
      key: _accessKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SettingsSectionLabel('Access'),
          const SizedBox(height: AppSpacing.sm),
          SelectionPills<AccessKind>(
            values: kinds,
            selected: _accessKind,
            labelBuilder: (kind) => kind.label,
            onSelected: _selectAccess,
            padding: SelectionPills.flush,
          ),
          if (service.proxyPasswordUnavailable case final why?)
            _buildAccessNote(context, why),
          ...switch (_accessKind) {
            AccessKind.none => const <Widget>[],
            AccessKind.cloudflare => _buildCloudflareFields(context),
            AccessKind.password => _buildProxyPasswordFields(),
            AccessKind.custom => _buildCustomHeaderFields(context),
          },
        ],
      ),
    );
  }

  void _selectAccess(AccessKind kind) {
    if (kind == _accessKind) return;
    setState(() {
      _accessKind = kind;
      if (kind == AccessKind.custom && _headers.isEmpty) {
        _headers.add(_HeaderFields('', '', _onFieldChanged));
      }
    });
    _onFieldChanged();
  }

  /// A line of explanation under the Access row, in the page's quiet voice.
  Widget _buildAccessNote(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  List<Widget> _buildCloudflareFields(BuildContext context) {
    bool started() =>
        _cloudflareIdController.text.trim().isNotEmpty ||
        _cloudflareSecretController.text.trim().isNotEmpty;
    return [
      const SizedBox(height: AppSpacing.md),
      TextFormField(
        controller: _cloudflareIdController,
        decoration: const InputDecoration(labelText: 'Client ID'),
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
        // A choice left empty saves no access at all; once one half is in,
        // the other is needed.
        validator: (value) => started() && (value ?? '').trim().isEmpty
            ? 'Add the client ID'
            : null,
      ),
      const SizedBox(height: AppSpacing.lg),
      _buildSecretField(
        controller: _cloudflareSecretController,
        label: 'Client secret',
        validator: (value) => started() && (value ?? '').trim().isEmpty
            ? 'Add the client secret'
            : null,
      ),
      _buildAccessNote(
        context,
        'On Cloudflare: create a service token, then add a Service Auth '
        'policy for it to this application.',
      ),
    ];
  }

  List<Widget> _buildProxyPasswordFields() {
    bool started() =>
        _proxyUsernameController.text.trim().isNotEmpty ||
        _proxyPasswordController.text.isNotEmpty;
    return [
      const SizedBox(height: AppSpacing.md),
      // "Proxy" in both labels: a service that signs in with a username and
      // a password of its own shows that pair above these.
      TextFormField(
        controller: _proxyUsernameController,
        decoration: const InputDecoration(labelText: 'Proxy username'),
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
        validator: (value) =>
            started() ? proxyUsernameProblem((value ?? '').trim()) : null,
      ),
      const SizedBox(height: AppSpacing.lg),
      _buildSecretField(
        controller: _proxyPasswordController,
        label: 'Proxy password',
      ),
    ];
  }

  List<Widget> _buildCustomHeaderFields(BuildContext context) {
    return [
      for (final (index, header) in _headers.indexed) ...[
        const SizedBox(height: AppSpacing.md),
        _buildHeaderRow(context, index, header),
      ],
      const SizedBox(height: AppSpacing.sm),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _addHeader,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add a header'),
        ),
      ),
    ];
  }

  Widget _buildHeaderRow(
    BuildContext context,
    int index,
    _HeaderFields header,
  ) {
    List<AccessHeader> entries() => [
      for (final other in _headers)
        if (!other.isBlank)
          (name: other.name.text.trim(), value: other.value.text),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: header.name,
                decoration: const InputDecoration(labelText: 'Header name'),
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (header.isBlank) return null;
                  final name = (value ?? '').trim();
                  // Not saved while it stands: Cupola's own header would win
                  // and this one would never be sent.
                  if (duplicatesCredentialHeader(service, name)) {
                    return credentialHeaderClash(service);
                  }
                  return customHeaderNameProblem(
                    service,
                    name,
                    earlier: [
                      for (final other in _headers.take(index))
                        if (!other.isBlank) other.name.text,
                    ],
                  );
                },
              ),
            ),
            IconButton(
              onPressed: () => _removeHeader(index),
              icon: const Icon(Icons.remove_circle_outline_rounded),
              tooltip: 'Remove header',
            ),
          ],
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: header.name,
          builder: (context, name, _) {
            if (!duplicatesCredentialHeader(service, name.text)) {
              return const SizedBox.shrink();
            }
            return Row(
              children: [
                Expanded(
                  child: _buildAccessNote(
                    context,
                    credentialHeaderClash(service),
                  ),
                ),
                TextButton(
                  onPressed: () => _moveToCredential(index),
                  child: const Text('Move it'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildSecretField(
          controller: header.value,
          label: 'Header value',
          validator: (value) {
            if (header.isBlank) return null;
            final problem = customHeaderValueProblem(value ?? '');
            if (problem != null) return problem;
            // Said once, under the last value, for the list as a whole.
            final isLast = index == _headers.length - 1;
            return isLast && exceedsAccessHeadersLimit(entries())
                ? kAccessHeadersTooLarge
                : null;
          },
        ),
      ],
    );
  }

  /// A secret of the Access row: hidden, with Paste beside it, since a token
  /// or a password is copied from somewhere else rather than typed.
  Widget _buildSecretField({
    required TextEditingController controller,
    required String label,
    FormFieldValidator<String>? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          onPressed: () => _paste(controller),
          icon: const Icon(Icons.content_paste_rounded),
          tooltip: 'Paste',
        ),
      ),
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.next,
      validator: validator,
    );
  }

  Future<void> _paste(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    controller.text = text;
  }

  void _addHeader() {
    setState(() => _headers.add(_HeaderFields('', '', _onFieldChanged)));
    _onFieldChanged();
  }

  void _removeHeader(int index) {
    final removed = _headers[index];
    setState(() {
      _headers.removeAt(index);
      if (_headers.isEmpty) {
        _headers.add(_HeaderFields('', '', _onFieldChanged));
      }
    });
    _onFieldChanged();
    // After the frame: the row's fields still hold these controllers until
    // the rebuild above lands.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  /// Resolves a custom header that duplicates the service's credential: its
  /// value goes to the credential field, and the header goes.
  void _moveToCredential(int index) {
    final value = _headers[index].value.text.trim();
    if (value.isNotEmpty) _apiKeyController.text = value;
    _removeHeader(index);
  }

  /// The Cloudflare Access team this connection's last failure named, from
  /// the form's own last test or from Home's probe, or null.
  ///
  /// Read only where it was already asked (`ref.exists`): the form never
  /// probes on its own to find out.
  String? _lastAccessTeam() {
    final fromTest = accessTeamOf(_testResult?.gateway);
    if (fromTest != null) return fromTest;
    final key = (service: service, instanceId: _target.id);
    if (!ref.exists(instanceSummaryProvider(key))) return null;
    return accessTeamOf(
      ref.read(instanceSummaryProvider(key)).value?.failure?.gateway,
    );
  }

  /// The other connections whose last failure was the Access team [team],
  /// which a token that just passed its test may let through too.
  List<ServiceInstance> _sameTeamConnections(
    String? team,
    ConnectionAccess tested,
  ) {
    if (team == null || tested is! CloudflareServiceToken) return const [];
    final settings = ref.read(currentSettingsProvider);
    return [
      for (final other in settings.configuredInstances)
        if (other.id != _target.id && other.access != tested)
          if (_lastTeamOf(other) == team) other,
    ];
  }

  String? _lastTeamOf(ServiceInstance instance) {
    final key = (service: instance.service, instanceId: instance.id);
    if (!ref.exists(instanceSummaryProvider(key))) return null;
    return accessTeamOf(
      ref.read(instanceSummaryProvider(key)).value?.failure?.gateway,
    );
  }

  List<String> _shareNames() {
    final settings = ref.read(currentSettingsProvider);
    return [
      for (final other in _shareCandidates)
        settings.connectionTitle(other.id, other.service, joiner: ' '),
    ];
  }

  /// The offer after a token passed its test: the same token for the
  /// connections the same Access team turned away.
  Widget _buildShareOffer(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            sharedTokenOffer(_shareNames()),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        TextButton(onPressed: _shareToken, child: const Text('Use it')),
      ],
    );
  }

  Future<void> _shareToken() async {
    final token = _testedAccess;
    if (token is! CloudflareServiceToken) return;
    final names = _shareNames();
    var settings = ref.read(currentSettingsProvider);
    for (final other in _shareCandidates) {
      final live = settings.instanceById(other.id);
      if (live == null) continue;
      settings = settings.copyWithInstance(live.copyWith(access: token));
    }
    await ref.read(settingsProvider.notifier).updateSettings(settings);
    if (!mounted) return;
    setState(() => _shareCandidates = const []);
    SnackBarHelper.success(context, sharedTokenSaved(names));
  }

  Widget _buildTestConnectionRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final serviceTheme = ServiceTheme.fromAccent(service.accent);

    // Tonal rather than a saturated accent slab. Two reasons, and both hold for
    // all thirteen accents: a full-strength fill in Readarr's red or Unraid's
    // orange reads as an alarm on a control nothing is wrong with — red means
    // unreachable, amber a fault — and the accent cannot be its own
    // label colour over its own tint (Radarr amber measures ≈1.80:1 there in
    // light theme). The tint carries the identity, `onSurface` carries the
    // words.
    return FilledButton.icon(
      onPressed: _testing || _saving ? null : _testConnection,
      icon: _testing
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onSurface,
              ),
            )
          : const Icon(Icons.wifi_tethering_rounded, size: 18),
      label: Text(_testing ? 'Testing…' : 'Test connection'),
      style: FilledButton.styleFrom(
        // Grows with the reading size instead of clipping its own label: a
        // 46pt button around a 20pt label has 26pt of chrome that must not
        // move when the label does.
        minimumSize: Size.fromHeight(
          TextScaleMetrics.boxHeight(context, base: 46, textHeight: 20),
        ),
        backgroundColor: serviceTheme.softContainer,
        foregroundColor: colorScheme.onSurface,
        side: BorderSide(color: service.accent.withValues(alpha: 0.28)),
      ),
    );
  }

  Widget _buildTestResult(BuildContext context, ServiceDiagnosis result) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presentation = describeConnection(
      service,
      status: result.status,
      reason: result.reason,
      gateway: result.gateway,
    );
    final tone = result.isConnected ? StatusTone.success : presentation.tone;
    // The wash keeps the tone's byte; the glyph and the verdict are walked
    // against that 10% wash over the page, which is what they land on.
    final fill = statusToneFill(colorScheme, tone);
    final color = statusToneColor(
      colorScheme,
      tone,
      surface: colorScheme.surface,
      tintAlpha: 0.10,
    );
    final outcome = result.isConnected
        ? 'Connection test succeeded'
        : 'Connection test failed';
    final message = switch (result.status) {
      ServiceConnectionStatus.connected =>
        '${service.title} answered as expected.',
      ServiceConnectionStatus.notConfigured =>
        'Fill in the address and credentials first.',
      // `messageFor`, not `connectionFailureMessage`: a failure that already
      // reached its own verdict (a refused cross-origin redirect naming where
      // it was sent) says so verbatim, and everything else falls back to the
      // reason-derived sentence exactly as before.
      ServiceConnectionStatus.disconnected ||
      ServiceConnectionStatus.checking => result.messageFor(service),
    };
    // A Cloudflare service token's test says what Access did with it.
    final tokenOutcome = _testedAccess is CloudflareServiceToken
        ? cloudflareTokenTestOutcome(
            service,
            answered: result.isConnected,
            reason: result.reason,
            gateway: result.gateway,
          )
        : null;
    final said = tokenOutcome ?? message;

    // The version the server named, when it named one. A separate line rather
    // than more of [message] because it can carry its own tone: an answering
    // server on an unsupported release is a qualified pass, not a plain one.
    final versionNote = describeServerVersion(service, result.serverVersion);

    // A live region rather than an announcement: this panel appears below the
    // button while focus stays on it, so the verdict — the whole point of the
    // action — would otherwise have to be hunted for. `liveRegion` is the
    // mechanism both platforms honour; a programmatic announcement is dropped on
    // Android. The outcome is spelled out because the glyph and the tint are the
    // only things carrying it (the "Fill in the address" message, for one, never
    // says it failed).
    final banner = Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: [
        '$outcome.',
        said,
        // Read out with the verdict rather than after it: a caveat the eye
        // catches from its amber has nothing carrying it to a screen reader.
        ?versionNote?.message,
      ].join(' '),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: fill.withValues(alpha: 0.10),
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: fill.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              result.isConnected
                  ? Icons.check_circle_outline_rounded
                  : presentation.icon,
              size: 18,
              color: color,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    result.isConnected ? 'Answering' : presentation.label,
                    style: theme.textTheme.labelLarge?.copyWith(color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    said,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (versionNote case final note?) ...[
                    const SizedBox(height: 2),
                    Text(
                      note.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: note.isWarning
                            ? statusToneColor(
                                colorScheme,
                                StatusTone.warning,
                                surface: colorScheme.surface,
                                tintAlpha: 0.10,
                              )
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (result.reason != ServiceFailureReason.localNetworkBlocked) {
      return banner;
    }
    // The one control that fixes this sits *outside* the banner, because the
    // banner excludes its own subtree from the semantics tree to read as a
    // single live region — a button in there would be unreachable to a screen
    // reader, which is precisely the user least able to go hunting through the
    // OS settings for a toggle nobody named.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        banner,
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _openLocalNetworkSettings,
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: const Text('Open Settings'),
          ),
        ),
      ],
    );
  }

  /// Takes the user to the toggle. When the host cannot get there, the route is
  /// spelled out instead of failing silently.
  Future<void> _openLocalNetworkSettings() async {
    final opened = await LocalNetworkPermission.openSettings();
    if (!opened && mounted) {
      SnackBarHelper.info(context, LocalNetworkPermission.remedy);
    }
  }

  /// A name for [instance], derived from what distinguishes it from [otherUrl].
  ///
  /// Three shapes, in the order they tell the two apart:
  ///
  /// * the **port**, when they share a host — two arrs on one box, the
  ///   overwhelmingly common homelab;
  /// * the **first path segment**, when they share a host *and* a port —
  ///   `media.lan/radarr` beside `media.lan/radarr4k`, which is one reverse
  ///   proxy fronting both. This branch is not an edge case worth skipping: it
  ///   is the deployment ADR-6 exists to serve, those two instances necessarily
  ///   share a single certificate pin, and it is precisely where the user has
  ///   the least other signal to tell them apart. Without it both were labelled
  ///   `media` — what they have in **common**;
  /// * the **hostname**, when they are on different boxes.
  ///
  /// Falls back to the id only when nothing parses, which is better than empty.
  /// Never the word "Default": that names a role, and the role moves the first
  /// time the list is reordered.
  ///
  /// Uniqueness is the caller's job — see [_deriveSiblingLabels]. This answers
  /// "what is different about it", which can legitimately come out the same for
  /// two connections that really are near-identical.
  String _derivedLabel(ServiceInstance instance, String otherUrl) {
    final mine = Uri.tryParse(instance.url);
    final other = Uri.tryParse(otherUrl);
    if (mine == null || mine.host.isEmpty) return instance.id;

    final sameHost = other != null && other.host == mine.host;
    if (sameHost) {
      if (mine.port != other.port) return '${mine.port}';
      final segment = mine.pathSegments
          .where((part) => part.isNotEmpty)
          .firstOrNull;
      if (segment != null) return segment;
    }
    return mine.host.split('.').first;
  }

  /// Names every sibling that has no name yet, and makes sure no two of them
  /// come out the same.
  ///
  /// The uniqueness pass is the half that was missing, and its absence was
  /// invisible from the field validator: that compares the typed name against
  /// the siblings *as they stand in the model*, where the one being derived
  /// still has an empty label. So a derivation that collided with what the user
  /// had just typed — or with another derivation — was written anyway, and two
  /// connections ended up sharing a name in the badge, the lens sheet and every
  /// provenance chip, with nothing on screen able to tell them apart.
  ///
  /// A colliding name is suffixed with what is left to distinguish it: the
  /// port, or failing that a counter. Ugly beats ambiguous — and it is editable
  /// in the sibling's own form the moment the user disagrees.
  SettingsModel _deriveSiblingLabels(SettingsModel next, String url) {
    final taken = <String>{
      for (final instance in _siblings(next))
        if (instance.label.isNotEmpty) instance.label.toLowerCase(),
      _labelController.text.trim().toLowerCase(),
    };

    var updated = next;
    for (final sibling in _siblings(next)) {
      if (sibling.label.isNotEmpty) continue;
      final base = _derivedLabel(sibling, url);
      var candidate = base;
      if (taken.contains(candidate.toLowerCase())) {
        final port = Uri.tryParse(sibling.url)?.port;
        candidate = port == null || port == 0 ? base : '$base:$port';
      }
      var counter = 2;
      while (taken.contains(candidate.toLowerCase())) {
        candidate = '$base $counter';
        counter++;
      }
      taken.add(candidate.toLowerCase());
      updated = updated.copyWithInstance(sibling.copyWith(label: candidate));
    }
    return updated;
  }

  /// The connections of this service other than the one on screen.
  List<ServiceInstance> _siblings(SettingsModel settings) => settings
      .instancesOf(service)
      .where((instance) => instance.id != _target.id)
      .toList(growable: false);

  /// Whether this form needs to ask for a name.
  ///
  /// Exactly when there is something to tell it apart from. One connection
  /// needs no name — it is "Radarr" — and asking for one would be a field that
  /// earns nothing on the install almost everyone has.
  bool _needsLabel(SettingsModel settings) => _siblings(settings).isNotEmpty;

  Widget _buildLabelField(SettingsModel settings) {
    return TextFormField(
      controller: _labelController,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Name',
        hintText: '4K, HD, Anime…',
        helperText:
            'Short. This is what tells it apart in search, in the queue, and '
            'before every add.',
        helperMaxLines: 2,
        prefixIcon: const Icon(Icons.sell_outlined),
      ),
      validator: (value) {
        final name = (value ?? '').trim();
        if (name.isEmpty) return 'Give this one a name';
        final clash = _siblings(
          settings,
        ).any((other) => other.label.toLowerCase() == name.toLowerCase());
        // Two rows both called "4K" is the state this whole field exists to
        // prevent, so it is refused rather than allowed and disambiguated by
        // host somewhere downstream.
        if (clash) return 'Another ${service.title} already uses that name';
        return null;
      },
    );
  }

  /// The other connections of this service, and the way to add one.
  Widget _buildConnectionsSection(
    BuildContext context,
    SettingsModel settings,
  ) {
    final siblings = _siblings(settings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Connections',
          showChevron: false,
          subtitle: siblings.isEmpty
              ? 'One ${service.title}. Add another if you run a second.'
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        SettingsGroupCard(
          children: [
            for (final sibling in siblings)
              SettingsCard.grouped(
                leading: Icon(service.icon),
                // The app's one rule for naming a connection, never its id.
                // A sibling that is the only other one set up has nothing to
                // be told apart from yet, and goes by its own label or the
                // service.
                title:
                    settings.connectionName(sibling.id) ??
                    (sibling.label.trim().isEmpty
                        ? service.title
                        : sibling.label.trim()),
                subtitle: service.extractHost(sibling.url) ?? 'No address yet',
                accentColor: service.accent,
                semanticHint: 'edits that ${service.title} connection',
                onTap: () => context.push(
                  '/settings/service/${service.routeParam}?i=${sibling.id}',
                ),
              ),
            SettingsCard.grouped(
              leading: const Icon(Icons.add_rounded),
              title: 'Add another ${service.title}',
              subtitle: 'A second server, with its own address and key',
              accentColor: service.accent,
              semanticHint: 'adds a second ${service.title} connection',
              onTap: () =>
                  context.push('/settings/service/${service.routeParam}?new=1'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRemoveRow(BuildContext context) {
    return SettingsGroupCard(
      children: [
        // The row's default accent, like every other settings row: red means
        // unreachable and nothing else, and the confirmation says what goes.
        SettingsCard.grouped(
          leading: const Icon(Icons.link_off_rounded),
          title: 'Remove ${service.title}',
          subtitle: 'Deletes the saved address and credentials',
          onTap: _removeConnection,
        ),
      ],
    );
  }

  Widget _buildSaveAction() {
    if (_saving) {
      // Labelled, because the button is replaced rather than disabled: an
      // unlabelled spinner drops the control out of the tree entirely, so the
      // action appears to have vanished mid-save.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Semantics(
          label: 'Saving',
          excludeSemantics: true,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return TextButton.icon(
      onPressed: _saveSettings,
      icon: const Icon(Icons.check_rounded),
      label: const Text('Save'),
    );
  }

  /// A neutral, icon-led information banner used for per-service setup hints.
  Widget _buildInfoNote(BuildContext context, String message) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrlField() {
    // Rebuilds on every keystroke so the cleartext warning tracks the field.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _urlController,
      builder: (context, value, _) {
        // The service's own reason first (TrueNAS refuses http:// outright),
        // then the general one.
        final warning =
            transportWarningFor(service, value.text) ??
            UrlUtils.cleartextWarning(value.text);
        return Semantics(
          label: 'Server URL',
          hint: 'Enter the ${service.title} server address',
          child: TextFormField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://your-server:${service.defaultPort}',
              // The default port comes from the registry, so this screen and
              // onboarding cannot disagree about it. The cleartext warning wins
              // the helper slot when it fires — a live problem outranks a hint.
              helperText:
                  warning ??
                  "${service.title}'s default port is "
                      '${service.defaultPort}.',
              helperMaxLines: 3,
              helperStyle: warning == null
                  ? null
                  : Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: statusToneColor(
                        Theme.of(context).colorScheme,
                        StatusTone.warning,
                      ),
                    ),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            // iOS otherwise rewrites `--` and quotes inside a typed address.
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            // Same rule as onboarding: a bare host is accepted here too and
            // normalised to HTTPS on save. Two rules for one field meant an
            // address typed during setup was rejected when reopened here.
            validator: UrlUtils.validateServiceHost,
          ),
        );
      },
    );
  }

  /// A standing confirmation that this address's origin has a trusted
  /// self-signed certificate, with a way to revoke it.
  ///
  /// Rebuilds on every keystroke of the URL field — [settings] is captured
  /// from the enclosing build, but the origin a trust decision applies to
  /// depends on what is actually typed, which the saved value may no longer
  /// match. Renders nothing for the overwhelming majority of services, which
  /// reach a certificate the OS already trusts and have never pinned one.
  Widget _buildTrustedCertificateIndicator(SettingsModel settings) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _urlController,
      builder: (context, value, _) {
        final rawUrl = value.text;
        final pin = settings.pinForUrl(rawUrl);
        if (pin == null) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final origin = displayOrigin(UrlUtils.certOrigin(rawUrl) ?? rawUrl);
        final sharedWith = settings
            .servicesSharingOriginOf(rawUrl)
            .where((s) => s != service)
            .toList();

        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  sharedWith.isEmpty
                      ? 'Trusted self-signed certificate for $origin.'
                      : 'Trusted self-signed certificate for $origin, also '
                            'covers ${sharedWith.map((s) => s.title).join(', ')}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _forgetCertificate(rawUrl),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
                child: const Text('Forget'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Revokes the trusted certificate for [rawUrl]'s origin, after naming
  /// every other configured service the revocation also affects.
  Future<void> _forgetCertificate(String rawUrl) async {
    final settings = ref.read(currentSettingsProvider);
    final sharedWith = settings
        .servicesSharingOriginOf(rawUrl)
        .where((s) => s != service)
        .toList();

    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.gpp_bad_outlined,
      title: 'Forget this certificate?',
      message: sharedWith.isEmpty
          ? 'The next connection to this address will need to be trusted '
                'again.'
          : 'This also affects ${sharedWith.map((s) => s.title).join(', ')}: '
                'the next connection from any of them will need to be '
                'trusted again.',
      // Reversible — the next connection re-offers the trust prompt — so no
      // "cannot be undone" sentence: it would overstate the stakes.
      confirmLabel: 'Forget certificate',
    );
    if (!result.confirmed || !mounted) return;

    final updated = settings.copyWithTrustedCertificate(
      url: rawUrl,
      fingerprint: '',
    );
    await ref.read(settingsProvider.notifier).updateSettings(updated);
    if (!mounted) return;
    SnackBarHelper.info(context, 'Certificate forgotten');
  }

  Widget _buildApiKeyField() {
    final credentialPath = service.credentialPath;
    return Semantics(
      label: service.credentialLabel,
      hint: isPlex ? 'Enter a Plex device token' : 'Enter the API key',
      child: TextFormField(
        controller: _apiKeyController,
        decoration: InputDecoration(
          labelText: service.credentialLabel,
          hintText: isPlex ? 'X-Plex-Token' : 'Enter your API key',
          // Where the credential lives inside the service's own interface. Same
          // registry fact onboarding shows under the same field, so someone who
          // set this up once recognises the breadcrumb when they come back to fix
          // it.
          helperText: credentialPath == null
              ? null
              : '${service.title} → $credentialPath',
          helperMaxLines: 2,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reveal is offered alongside copy: checking a pasted key by eye
              // should not require putting it on the system clipboard, where any
              // other app can read it.
              IconButton(
                icon: Icon(
                  _revealApiKey
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                onPressed: () => setState(() => _revealApiKey = !_revealApiKey),
                tooltip: _revealApiKey ? 'Hide API key' : 'Show API key',
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: _copyApiKey,
                tooltip: 'Copy API key',
              ),
            ],
          ),
        ),
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        // The last field ends the form by *checking* it, not by committing it:
        // saving an address that was never tried is how a wrong key ends up
        // persisted, and the test is one step short of the save anyway.
        onFieldSubmitted: (_) => _testConnection(),
        obscureText: !_revealApiKey,
        validator: _validateApiKey,
      ),
    );
  }

  Widget _buildUsernameField() {
    return Semantics(
      label: service.usernameLabel,
      hint: service == ServiceKey.nginxProxyManager
          ? 'Enter the email you sign in with'
          : 'Optional',
      child: TextFormField(
        controller: _usernameController,
        decoration: InputDecoration(
          labelText: service.usernameLabel,
          // Optional for the download clients, which commonly run without auth
          // behind a reverse proxy. Nginx Proxy Manager is the exception: there
          // is no anonymous mode, and its login needs an email address.
          hintText: service == ServiceKey.nginxProxyManager
              ? 'The email you sign in with'
              : 'Optional',
        ),
        keyboardType: service == ServiceKey.nginxProxyManager
            ? TextInputType.emailAddress
            : TextInputType.text,
        textInputAction: TextInputAction.next,
        autocorrect: false,
      ),
    );
  }

  Widget _buildPasswordField() {
    return Semantics(
      label: 'Password',
      hint: 'Optional',
      child: TextFormField(
        controller: _passwordController,
        decoration: const InputDecoration(
          labelText: 'Password',
          hintText: 'Optional',
        ),
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        // Same as the API-key field: the return key tests, it does not save.
        onFieldSubmitted: (_) => _testConnection(),
        obscureText: true,
      ),
    );
  }

  String? _validateApiKey(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return isPlex ? 'Plex token is required' : 'API Key is required';
    }

    // A Plex JSON Web Token expires after seven days and can only be renewed by
    // calling plex.tv, which this app never does. Accepting one would produce
    // software that works for a week and then fails with a 401 the user has no
    // way to interpret — so it is refused at the point of paste, where the
    // message can still say what to paste instead.
    if (isPlex && trimmed.startsWith('eyJ')) {
      return 'That is a temporary token, it expires in 7 days and Cupola '
          'cannot renew it. Paste a device token instead.';
    }

    return null;
  }

  /// How long a copied credential is left on the clipboard.
  ///
  /// Long enough to switch apps and paste, short enough that it is not still
  /// sitting there an hour later. Password managers land in the same range.
  static const Duration _copiedCredentialLifetime = Duration(seconds: 45);

  Future<void> _copyApiKey() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) return;

    // Two layers, in order of how much they actually protect. The host's own
    // sensitive-clip flags come first — they are the only thing that keeps the
    // key out of Android's copy preview and off Universal Clipboard — and a
    // plain copy is the fallback for every platform and OS version that has no
    // such flag, because a copy button that refuses to copy is worse than an
    // unhardened one. Either way the timed clear below still runs.
    final hardened = await SecureClipboard.copySecret(
      apiKey,
      expiresIn: _copiedCredentialLifetime,
    );
    if (!hardened) {
      await Clipboard.setData(ClipboardData(text: apiKey));
    }
    if (!mounted) return;
    // The wording is part of the mitigation, not chrome: the clipboard is a
    // shared surface — Android 13+ renders a preview of what was copied, and on
    // Apple platforms the general pasteboard syncs to the user's other devices
    // through Universal Clipboard — so the honest thing is to say the key left
    // the app and when it will be taken back.
    SnackBarHelper.info(
      context,
      'API key copied, the clipboard is cleared in '
      '${_copiedCredentialLifetime.inSeconds} seconds',
    );
    unawaited(_expireCopiedCredential(apiKey));
  }

  /// Takes [secret] back off the clipboard once it has had time to be pasted.
  ///
  /// Runs whether or not [SecureClipboard] hardened the copy, and it is the only
  /// half of this that runs at all on Android 12 and below, where there is no
  /// `EXTRA_IS_SENSITIVE` to set. Of the flagged platforms only iOS can expire a
  /// clip by itself, so this stays the thing that bounds how long the key sits
  /// there everywhere else.
  ///
  /// Static, and deliberately not tied to this widget's lifetime: leaving the
  /// screen is not a reason to leave a credential on the clipboard.
  ///
  /// The read-back only *spares* a clipboard it can actually see holding
  /// something else — the user copying over the key in the meantime, which is
  /// worth not destroying. An unreadable clipboard is cleared, not spared:
  /// since Android 10 `getPrimaryClip` answers null to any app that does not
  /// have window focus, and 45 seconds after the copy the user is by
  /// construction in the app they left to paste into. Treating that null as
  /// "something else is on the clipboard" is what used to make this never fire
  /// on Android in exactly the case it exists for, under a SnackBar promising
  /// it would.
  static Future<void> _expireCopiedCredential(String secret) async {
    await Future<void>.delayed(_copiedCredentialLifetime);
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current != null && current.text != secret) return;
    await Clipboard.setData(const ClipboardData(text: ''));
  }
}

/// The saved connection's state, watched live so trusting a certificate or
/// saving a new key updates the header without a reload.
///
/// Keyed on the **connection**, not the service. `serviceDiagnosisProvider`
/// folds every connection into its worst answer — the right shape for a row
/// that says "Radarr", and the wrong one over a form whose address field
/// belongs to exactly one server: it reported the first Radarr's state above
/// the second Radarr's credentials.
class _SavedConnectionStatus extends ConsumerWidget {
  const _SavedConnectionStatus({required this.instanceId});

  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final service = ref
        .watch(
          currentSettingsProvider.select((s) => s.instanceById(instanceId)),
        )
        ?.service;
    if (service == null) return const SizedBox.shrink();

    final async = ref.watch(instanceDiagnosisProvider(instanceId));
    final diagnosis = async.when(
      loading: () => const ServiceDiagnosis.checking(),
      error: (_, _) =>
          const ServiceDiagnosis(ServiceConnectionStatus.disconnected),
      data: (value) => value,
    );
    final presentation = describeConnection(
      service,
      status: diagnosis.status,
      reason: diagnosis.reason,
      gateway: diagnosis.gateway,
    );

    // "Answering · read-only key": a credential that reads and may not write
    // is a fact about this connection worth stating where it is replaced.
    // Asked only once the connection answers, and only of the three services
    // whose one credential can be narrower than their writes.
    final qualifier =
        diagnosis.status == ServiceConnectionStatus.connected &&
            service.hasScopedCredential
        ? credentialScopeQualifier(
            service,
            ref.watch(capabilityGrantForProvider(instanceId)),
          )
        : null;

    return _HeaderStatus(
      icon: presentation.icon,
      label: qualifier == null
          ? presentation.label
          : '${presentation.label} · $qualifier',
      color: statusToneColor(colorScheme, presentation.tone),
      busy: diagnosis.status == ServiceConnectionStatus.checking,
    );
  }
}

class _HeaderStatus extends StatelessWidget {
  const _HeaderStatus({
    required this.icon,
    required this.label,
    required this.color,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium!
                  .weight(FontWeight.w600)
                  .copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// One custom header's two fields on the Access row.
class _HeaderFields {
  _HeaderFields(String name, String value, VoidCallback onChanged)
    : name = TextEditingController(text: name),
      value = TextEditingController(text: value) {
    this.name.addListener(onChanged);
    this.value.addListener(onChanged);
  }

  final TextEditingController name;
  final TextEditingController value;

  /// A row nobody has typed into, which is neither saved nor checked.
  bool get isBlank => name.text.trim().isEmpty && value.text.isEmpty;

  void dispose() {
    name.dispose();
    value.dispose();
  }
}
