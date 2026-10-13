import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/found_address.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/reel_command_button.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/onboarding/data/known_candidates_provider.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_candidate.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_content.dart';

// ── Found: the services another one already knows ───────────────────────────

/// A service that answered from this device and is on, as the beat hands it
/// over to be saved.
///
/// [instance] carries what the person did not have to type: the address that
/// answered, the key (the source's, or the one pasted), the label when the
/// source named it something other than the service's own title, and the
/// address away from home when the source's External URL accepted the key.
/// [certFingerprint] is the certificate trusted in this beat for the address'
/// origin, to be pinned with `SettingsModel.copyWithTrustedCertificate`, or
/// null when nothing was trusted here (a pin already saved covers it).
///
/// The key is a secret: [toString] never prints it.
@immutable
class FoundConnection {
  const FoundConnection({required this.instance, this.certFingerprint});

  final ServiceInstance instance;
  final String? certFingerprint;

  @override
  String toString() =>
      'FoundConnection(${instance.service.name}, "${instance.label}"'
      '${instance.away == null ? '' : ', away'}'
      '${certFingerprint == null ? '' : ', certificate trusted'})';
}

/// Tries one connection from this device: the shape of
/// [diagnoseInstanceWithCertProbe], so a widget test can answer for it and
/// stay off the network.
typedef FoundDiagnose =
    Future<ServiceDiagnosis> Function(
      ServiceInstance instance,
      SettingsModel settings, {
      CertificateProber probe,
    });

/// The step right after the first service answers: the services it already
/// knows, each tried from this device before it joins.
///
/// Reads what [source] (a Seerr or a Prowlarr connection, already saved) knows
/// through `knownCandidatesProvider`, and for each candidate:
///
/// - tries it at the address proposed for it (`ConnectionCandidate.proposal`),
///   with the key the source gave, or the one the person pastes when the source
///   gives none (Prowlarr hides them); a row that answers is on, and can be
///   switched off;
/// - a certificate it does not trust is asked inline, and the row joins once
///   trusted; trusting covers every row at the same origin;
/// - a key refused at the proposed address, which is a guess when the source
///   reaches the service by a name only it resolves, opens an address field in
///   the row and tries again at what is typed;
/// - what does not answer says so in its own row and never holds another.
///
/// The exit counts only what answered and is on (`Add 2 services`), and is
/// `Go to Home` when there is nothing to add. [onBack] is the other way out;
/// there is no skip.
///
/// **Saves nothing.** [onAdd] gets the connections to save, with ids minted
/// against the saved ones, and the screen that owns the flow writes them.
/// The key is tried from this device and sent nowhere else; an address that
/// would carry it in the clear off the local network is never tried.
///
/// [nothingKnownBody] sits under the sentence of a source that knows nothing:
/// the screen that owns the list of services to add one by one puts it there.
class OnboardingFound extends ConsumerStatefulWidget {
  const OnboardingFound({
    super.key,
    required this.source,
    required this.onAdd,
    required this.onGoHome,
    required this.onBack,
    this.nothingKnownBody,
    this.diagnose = diagnoseInstanceWithCertProbe,
    this.certificateProber = probeUntrustedCertificate,
  });

  /// The connection just set up, a Seerr or a Prowlarr, already saved.
  final ServiceInstance source;

  /// Saves what answered and is on. Not called with an empty list: that is
  /// [onGoHome].
  final Future<void> Function(List<FoundConnection> found) onAdd;

  final VoidCallback onGoHome;
  final VoidCallback onBack;

  final Widget? nothingKnownBody;

  /// Injectable so a widget test can stay off the network: see
  /// [FoundDiagnose].
  final FoundDiagnose diagnose;

  /// Injectable for the same reason as `OnboardingScreen.certificateProber`.
  final CertificateProber certificateProber;

  @override
  ConsumerState<OnboardingFound> createState() => _OnboardingFoundState();
}

/// Where a row is. Whether it is on is [_FoundRow.on], and what failed is
/// [_FoundRow.reason].
enum _Phase { needsKey, trying, answered, certificate, failed }

/// What a failure's remedy does: open the row's address field, or bring the
/// certificate back.
enum _Remedy { address, certificate }

class _FoundRow {
  _FoundRow(this.candidate)
    : key = candidate.apiKey ?? '',
      phase = (candidate.apiKey ?? '').isEmpty
          ? _Phase.needsKey
          : _Phase.trying;

  final ConnectionCandidate candidate;

  /// The key tried: the source's, or the one pasted.
  String key;

  /// The address the person typed, normalized; null while the proposal is the
  /// one tried.
  String? typedUrl;

  _Phase phase;
  bool on = false;

  /// What failed, for [_Phase.failed].
  ServiceFailureReason? reason;
  ServiceDiagnosis? diagnosis;

  /// The certificate waiting to be trusted, for [_Phase.certificate] (and kept
  /// while the person has said `Not now`, so the remedy can bring it back).
  UntrustedCertificateProbe? probe;

  /// The address away from home, once the source's External URL accepted the
  /// key.
  String? awayUrl;

  bool addressOpen = false;

  /// Counts the runs, so a stale answer is dropped.
  int attempt = 0;

  final keyController = TextEditingController();
  final addressController = TextEditingController();

  void dispose() {
    keyController.dispose();
    addressController.dispose();
  }

  ServiceKey get service => candidate.service;
  String get name => candidate.displayName;
  String get sourceTitle => candidate.source.service.title;

  /// The address tried: the one typed, or the proposal. Null when the source
  /// reported none that names a host.
  String? get url => typedUrl ?? candidate.proposal?.url;

  /// The address as a sentence says it: `nas.home.arpa:7878`.
  String get hostAndPort => url == null ? '' : _hostAndPort(url!);

  /// The address as the row prints it: `nas.home.arpa:7879 · https`.
  String get addressLine {
    final address = url;
    if (address == null) return '';
    final scheme = Uri.tryParse(address)?.scheme;
    return scheme == 'https'
        ? '${_hostAndPort(address)} · https'
        : _hostAndPort(address);
  }

  /// The address as the source reports it, printed whenever the one tried is
  /// not it: what it is, and why this device tries another.
  String? get foundLine {
    final proposal = candidate.proposal;
    if (typedUrl != null ||
        proposal == null ||
        proposal.basis != FoundAddressBasis.sourceHost) {
      return null;
    }
    return '$sourceTitle has ${_hostAndPort(candidate.reportedUrl)} · '
        "$sourceTitle's own host, with $name's port";
  }

  /// Where the key came from, said in the row.
  String get keyLine => candidate.hasKey
      ? 'key included'
      : key.isNotEmpty
      ? 'key pasted'
      : '$sourceTitle shows ********';

  bool get keyFieldShown =>
      !candidate.hasKey &&
      (phase == _Phase.needsKey ||
          (phase == _Phase.failed &&
              reason == ServiceFailureReason.unauthorized));

  bool get answeredAndOn => phase == _Phase.answered && on;

  /// The failure as one sentence, its cause stated once.
  String get failureSentence {
    final reason = this.reason ?? ServiceFailureReason.unknown;
    return switch (reason) {
      ServiceFailureReason.unreachable =>
        '${failureHeadline(reason, subject: name, gateway: diagnosis?.gateway)} '
            'at $hostAndPort from this device',
      ServiceFailureReason.unauthorized =>
        "$hostAndPort answered but refused $name's key",
      _ => describeFailure(
        service,
        reason,
        subject: name,
        gateway: diagnosis?.gateway,
      ).headline,
    };
  }

  /// The second line of a refused key at an address that was only a guess.
  String? get failureNote =>
      reason == ServiceFailureReason.unauthorized && foundLine != null
      ? "That is $sourceTitle's own host with $name's port, so another "
            "server may be there. Type the address $name has on your server."
      : null;

  /// What fixes the failure in this row, when it is not asking again.
  (_Remedy, String)? get remedy {
    final reason = this.reason;
    if (phase != _Phase.failed || reason == null) return null;
    return switch (reason) {
      ServiceFailureReason.unauthorized => (
        _Remedy.address,
        'Type its address',
      ),
      ServiceFailureReason.notFound ||
      ServiceFailureReason.redirected ||
      ServiceFailureReason.insecureTransport => (
        _Remedy.address,
        failureRemedy(reason, gateway: diagnosis?.gateway)!,
      ),
      ServiceFailureReason.tls when probe != null => (
        _Remedy.certificate,
        failureRemedy(reason, gateway: diagnosis?.gateway)!,
      ),
      _ => null,
    };
  }

  /// The state the row's second line says, with its tone; null where the
  /// row says it by a block of its own (a failure, a key to paste).
  (StatusTone, String)? get state => switch (phase) {
    _Phase.trying => (StatusTone.info, 'Trying from this device'),
    _Phase.answered => (StateWord.answering.tone!, StateWord.answering.label),
    _Phase.certificate => (StatusTone.info, 'Waiting for you'),
    _Phase.needsKey || _Phase.failed => null,
  };

  /// The one sentence a screen reader speaks for the row's text.
  String get sentence {
    final subject = [name, addressLine, keyLine].where((p) => p.isNotEmpty);
    final found = foundLine;
    final head = [subject.join(', '), ?found].join('. ');
    final tail = switch (phase) {
      _Phase.needsKey => 'Paste its key to try it',
      _Phase.failed => [failureSentence, ?failureNote].join('. '),
      _ => state!.$2,
    };
    return '$head. $tail';
  }
}

/// A fingerprint (`AB:CD:…`) in lines of eight bytes.
String _fingerprintLines(String fingerprint) {
  final bytes = fingerprint.split(':');
  return [
    for (var i = 0; i < bytes.length; i += 8)
      bytes.sublist(i, i + 8 > bytes.length ? bytes.length : i + 8).join(':'),
  ].join('\n');
}

String _hostAndPort(String address) {
  final uri = Uri.tryParse(address);
  if (uri == null || uri.host.isEmpty) return address;
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return '$host:$port$path';
}

class _OnboardingFoundState extends ConsumerState<OnboardingFound> {
  List<_FoundRow>? _rows;

  /// Certificates trusted in this beat, by TLS origin: what a row at that
  /// origin is tried with, and what the connection it becomes is pinned to.
  final Map<String, String> _trusted = {};

  @override
  void initState() {
    super.initState();
    ref.listenManual(knownCandidatesProvider(widget.source.id), (_, next) {
      if (_rows == null && next.hasValue) _begin(next.requireValue);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    for (final row in _rows ?? const <_FoundRow>[]) {
      row.dispose();
    }
    super.dispose();
  }

  /// Draws a row for each candidate and tries the ones that hold a key. Kept
  /// once drawn: the list follows the saved connections for whoever reads it
  /// next, and a row that joined does not leave the screen under the person's
  /// finger.
  void _begin(List<ConnectionCandidate> candidates) {
    final rows = [for (final candidate in candidates) _FoundRow(candidate)];
    _rows = rows;
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() {});
      for (final row in rows) {
        if (row.phase == _Phase.trying) unawaited(_run(row));
      }
    });
  }

  // ── Trying ────────────────────────────────────────────────────────────────

  /// The saved settings, and the certificates trusted so far in this beat.
  SettingsModel _settingsNow() {
    var settings = ref.read(currentSettingsProvider);
    for (final MapEntry(:key, :value) in _trusted.entries) {
      settings = settings.copyWithTrustedCertificate(
        url: key,
        fingerprint: value,
      );
    }
    return settings;
  }

  Future<void> _run(_FoundRow row) async {
    final url = row.url;
    if (url == null) {
      setState(() {
        row.phase = _Phase.failed;
        row.reason = ServiceFailureReason.notFound;
        row.diagnosis = null;
        row.addressOpen = true;
      });
      return;
    }
    final attempt = ++row.attempt;
    setState(() {
      row.phase = _Phase.trying;
      row.reason = null;
      row.diagnosis = null;
      row.probe = null;
      row.addressOpen = false;
      row.on = false;
    });
    bool current() => mounted && row.attempt == attempt;

    // The key never leaves the device in the clear off the local network:
    // nothing is sent, and the person is told why.
    if (UrlUtils.cleartextWarning(url) != null) {
      setState(() {
        row.phase = _Phase.failed;
        row.reason = ServiceFailureReason.insecureTransport;
      });
      return;
    }

    ServiceDiagnosis diagnosis;
    try {
      diagnosis = await widget.diagnose(
        _instanceFor(row, url),
        _settingsNow(),
        probe: widget.certificateProber,
      );
    } catch (error) {
      diagnosis = ServiceDiagnosis.failed(error);
    }
    if (!current()) return;

    if (diagnosis.isConnected) {
      setState(() {
        row.phase = _Phase.answered;
        row.on = true;
      });
      unawaited(_tryAway(row, attempt));
      return;
    }
    final probe = diagnosis.certificateProbe;
    setState(() {
      if (probe != null) {
        row.phase = _Phase.certificate;
        row.probe = probe;
      } else {
        row.phase = _Phase.failed;
        row.reason = diagnosis.reason ?? ServiceFailureReason.unknown;
        row.diagnosis = diagnosis;
      }
    });
  }

  ServiceInstance _instanceFor(_FoundRow row, String url) => ServiceInstance(
    id: '',
    service: row.service,
    url: url,
    credential: row.key,
  );

  /// Asks the source's External URL for the same key, once the row answered.
  /// The row never waits for it: an address that does not accept the key is
  /// simply not set.
  Future<void> _tryAway(_FoundRow row, int attempt) async {
    final external = row.candidate.externalUrl?.trim() ?? '';
    if (external.isEmpty) return;
    final away = UrlUtils.normalizeBaseUrl(
      UrlUtils.withoutCredentials(external),
    );
    if (away.isEmpty ||
        UrlUtils.validateServiceHost(away) != null ||
        isSameAddress(away, row.url) ||
        UrlUtils.cleartextWarning(away) != null) {
      return;
    }
    ServiceDiagnosis diagnosis;
    try {
      diagnosis = await widget.diagnose(
        _instanceFor(row, away),
        _settingsNow(),
        // An address that needs a certificate nobody trusted is not offered:
        // no prompt for an address the person did not choose.
        probe: (url, {pinnedFingerprint = ''}) async => null,
      );
    } catch (_) {
      return;
    }
    if (!mounted || row.attempt != attempt || !diagnosis.isConnected) return;
    setState(() => row.awayUrl = away);
  }

  // ── What the person does ──────────────────────────────────────────────────

  void _retry(_FoundRow row) => unawaited(_run(row));

  void _toggle(_FoundRow row, bool on) => setState(() => row.on = on);

  /// Trusts the certificate [row] is waiting on, for its origin, and tries
  /// again every row at that origin: one decision covers them all.
  void _trust(_FoundRow row) {
    final probe = row.probe;
    final url = row.url;
    final origin = url == null ? null : UrlUtils.certOrigin(url);
    if (probe == null || origin == null) return;
    _trusted[origin] = probe.certificate.fingerprint;
    for (final other in _rows!) {
      final otherUrl = other.url;
      if (other.phase == _Phase.certificate &&
          otherUrl != null &&
          UrlUtils.certOrigin(otherUrl) == origin) {
        unawaited(_run(other));
      }
    }
  }

  /// `Not now`: the row stays out, with its remedy to bring the certificate
  /// back.
  void _declineCertificate(_FoundRow row) => setState(() {
    row.phase = _Phase.failed;
    row.reason = ServiceFailureReason.tls;
    row.diagnosis = null;
  });

  void _takeRemedy(_FoundRow row) {
    final (kind, _) = row.remedy!;
    setState(() {
      switch (kind) {
        case _Remedy.address:
          row.addressController.text = row.url ?? '';
          row.addressOpen = true;
        case _Remedy.certificate:
          row.phase = _Phase.certificate;
      }
    });
  }

  void _submitAddress(_FoundRow row) {
    final raw = row.addressController.text.trim();
    // The field says what is wrong with an address while it is typed.
    if (raw.isEmpty || UrlUtils.validateServiceHost(raw) != null) return;
    row.typedUrl = UrlUtils.normalizeBaseUrl(raw);
    unawaited(_run(row));
  }

  void _submitKey(_FoundRow row) {
    final key = row.keyController.text.trim();
    if (key.isEmpty) return;
    row.key = key;
    unawaited(_run(row));
  }

  Future<void> _pasteKey(_FoundRow row) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    row.keyController.text = text;
    _submitKey(row);
  }

  /// Hands over what answered and is on, each as the connection to save.
  Future<void> _add() async {
    final settings = ref.read(currentSettingsProvider);
    final taken = {for (final i in settings.instances) i.id};
    final found = <FoundConnection>[];
    for (final row in _rows!) {
      if (!row.answeredAndOn) continue;
      final id = ServiceInstance.mintId(row.service, taken);
      taken.add(id);
      final url = UrlUtils.normalizeBaseUrl(row.url!);
      final origin = UrlUtils.certOrigin(url);
      found.add(
        FoundConnection(
          instance: ServiceInstance(
            id: id,
            service: row.service,
            label: row.name == row.service.title ? '' : row.name,
            url: url,
            credential: row.key,
            away: row.awayUrl == null
                ? null
                : ConnectionAddress(url: row.awayUrl!),
          ),
          certFingerprint: origin == null ? null : _trusted[origin],
        ),
      );
    }
    await widget.onAdd(found);
  }

  // ── Drawing ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final known = ref.watch(knownCandidatesProvider(widget.source.id));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = _rows;
    final title = widget.source.service.title;

    String headline;
    String? subtitle;
    Widget body;
    if (rows == null) {
      switch (known) {
        case AsyncError(:final error):
          final failure = describeFailureOf(
            widget.source.service,
            error,
            subject: title,
          );
          headline = failure.headline;
          body = _SourceFailure(
            failure: failure,
            onRetry: () =>
                ref.invalidate(knownCandidatesProvider(widget.source.id)),
          );
        default:
          headline = 'Asking $title';
          body = const SizedBox.shrink();
      }
    } else if (rows.isEmpty) {
      headline = "$title doesn't know any other service yet";
      subtitle =
          '$title is set up. Add the others one at a time: each asks for its '
          'address and key.';
      body = widget.nothingKnownBody ?? const SizedBox.shrink();
    } else {
      final count = rows.length;
      headline =
          '$title knows $count more ${count == 1 ? 'service' : 'services'}';
      subtitle = widget.source.service == ServiceKey.prowlarr
          ? 'Prowlarr hides keys: paste each one below.'
          : rows.every((r) => r.foundLine != null)
          ? '$title reaches them by their names inside Docker.'
          : 'It already has their addresses and keys, so there is nothing to '
                'type.';
      body = _FoundList(
        rows: rows,
        onToggle: _toggle,
        onRetry: _retry,
        onTrust: _trust,
        onNotNow: _declineCertificate,
        onRemedy: _takeRemedy,
        onSubmitKey: _submitKey,
        onPasteKey: _pasteKey,
        onSubmitAddress: _submitAddress,
        settings: ref.watch(currentSettingsProvider),
      );
    }

    final chosen = rows?.where((r) => r.answeredAndOn).length ?? 0;
    return OnboardingBeat(
      besideRing: MainAxisAlignment.start,
      actions: OnboardingFooter(
        primary: ReelCommandButton(
          label: chosen == 0 ? _goHome : _addLabel(chosen),
          // Going home navigates and does not wait; adding does.
          busyLabel: chosen == 0 ? null : 'Adding',
          slotLabels: [_goHome, _addLabel(1), _addLabel(rows?.length ?? 2)],
          onPressed: chosen == 0 ? () async => widget.onGoHome() : _add,
        ),
      ),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: widget.onBack,
              tooltip: 'Back',
              icon: const Icon(Icons.chevron_left_rounded),
              style: IconButton.styleFrom(
                // Pinned: the desktop's compact density takes 8 off the
                // minimum size.
                visualDensity: VisualDensity.standard,
                minimumSize: const Size(44, 44),
                backgroundColor: scheme.surfaceContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.borderRadiusMd,
                  side: BorderSide(color: scheme.outlineVariant),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              'Step 2 of 2',
              style: AppTheme.chrome(context, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Semantics(
          header: true,
          child: Text(
            headline,
            style: theme.textTheme.displaySmall!.copyWith(
              color: scheme.onSurface,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            subtitle,
            style: theme.textTheme.bodyLarge!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        body,
      ],
    );
  }
}

const _goHome = 'Go to Home';

String _addLabel(int count) =>
    'Add $count ${count == 1 ? 'service' : 'services'}';

/// The source did not answer when asked what it knows: its own row of words,
/// with the way to ask again where asking again can help.
class _SourceFailure extends StatelessWidget {
  const _SourceFailure({required this.failure, required this.onRetry});

  final FailurePresentation failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final retryHelps = failureRetryHelps(failure.reason);
    if (!retryHelps) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: failure.tone == StatusTone.error
          ? TextButton(
              onPressed: onRetry,
              style: retryInkStyle(scheme),
              child: const Text(Lexicon.retry),
            )
          : FilledButton(
              onPressed: onRetry,
              style: remedyFillStyle(context, compact: true),
              child: const Text(Lexicon.retry),
            ),
    );
  }
}

// ── The list ────────────────────────────────────────────────────────────────

class _FoundList extends StatelessWidget {
  const _FoundList({
    required this.rows,
    required this.settings,
    required this.onToggle,
    required this.onRetry,
    required this.onTrust,
    required this.onNotNow,
    required this.onRemedy,
    required this.onSubmitKey,
    required this.onPasteKey,
    required this.onSubmitAddress,
  });

  final List<_FoundRow> rows;
  final SettingsModel settings;
  final void Function(_FoundRow row, bool on) onToggle;
  final ValueChanged<_FoundRow> onRetry;
  final ValueChanged<_FoundRow> onTrust;
  final ValueChanged<_FoundRow> onNotNow;
  final ValueChanged<_FoundRow> onRemedy;
  final ValueChanged<_FoundRow> onSubmitKey;
  final Future<void> Function(_FoundRow row) onPasteKey;
  final ValueChanged<_FoundRow> onSubmitAddress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusSlab,
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
            _FoundTile(
              row: rows[i],
              settings: settings,
              onToggle: (on) => onToggle(rows[i], on),
              onRetry: () => onRetry(rows[i]),
              onTrust: () => onTrust(rows[i]),
              onNotNow: () => onNotNow(rows[i]),
              onRemedy: () => onRemedy(rows[i]),
              onSubmitKey: () => onSubmitKey(rows[i]),
              onPasteKey: () => onPasteKey(rows[i]),
              onSubmitAddress: () => onSubmitAddress(rows[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _FoundTile extends StatelessWidget {
  const _FoundTile({
    required this.row,
    required this.settings,
    required this.onToggle,
    required this.onRetry,
    required this.onTrust,
    required this.onNotNow,
    required this.onRemedy,
    required this.onSubmitKey,
    required this.onPasteKey,
    required this.onSubmitAddress,
  });

  final _FoundRow row;
  final SettingsModel settings;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRetry;
  final VoidCallback onTrust;
  final VoidCallback onNotNow;
  final VoidCallback onRemedy;
  final VoidCallback onSubmitKey;
  final Future<void> Function() onPasteKey;
  final VoidCallback onSubmitAddress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ground = scheme.surfaceContainer;
    final dim = CupolaThemeColors.of(context).dimText;
    final state = row.state;
    final probe = row.probe;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: _Glyph(service: row.service)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                // The row speaks one sentence; its parts are silenced under
                // it, and the controls beside and below stay their own.
                child: Semantics(
                  container: true,
                  label: row.sentence,
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.name,
                          style: AppTheme.rowTitle(
                            theme.brightness,
                          ).copyWith(color: scheme.onSurface),
                        ),
                        if (row.addressLine.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            row.addressLine,
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: dim,
                            ),
                          ),
                        ],
                        if (row.foundLine case final found?) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            found,
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: dim,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xxs),
                        Row(
                          children: [
                            Icon(
                              row.candidate.hasKey || row.key.isNotEmpty
                                  ? Icons.key_rounded
                                  : Icons.key_off_rounded,
                              size: 15,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                row.keyLine,
                                style: theme.textTheme.bodySmall!.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (state != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          _StateLine(
                            tone: state.$1,
                            text: state.$2,
                            ground: ground,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (row.phase == _Phase.answered)
                MergeSemantics(
                  child: Semantics(
                    label: 'Add ${row.name}',
                    child: SizedBox(
                      height: 48,
                      child: Switch(value: row.on, onChanged: onToggle),
                    ),
                  ),
                ),
            ],
          ),
          if (row.phase == _Phase.certificate && probe != null) ...[
            const SizedBox(height: AppSpacing.md),
            _CertificateBlock(
              row: row,
              probe: probe,
              settings: settings,
              onTrust: onTrust,
              onNotNow: onNotNow,
            ),
          ],
          if (row.phase == _Phase.failed) ...[
            const SizedBox(height: AppSpacing.md),
            _FailureBlock(
              row: row,
              ground: ground,
              onRetry: onRetry,
              onRemedy: onRemedy,
            ),
          ],
          if (row.keyFieldShown) ...[
            const SizedBox(height: AppSpacing.md),
            OnboardingField(
              label: "${row.name}'s ${row.service.credentialLabel}",
              controller: row.keyController,
              isSecret: true,
              hint: 'Paste the ${row.service.credentialLabel}',
              help: 'In ${row.name}: Settings › General › Security',
              action: TextInputAction.done,
              onSubmitted: (_) => onSubmitKey(),
              trailing: IconButton(
                onPressed: onPasteKey,
                icon: Icon(
                  Icons.content_paste_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                tooltip: 'Paste',
              ),
            ),
          ],
          if (row.addressOpen) ...[
            const SizedBox(height: AppSpacing.md),
            OnboardingField(
              label: "${row.name}'s address",
              controller: row.addressController,
              isUrl: true,
              action: TextInputAction.go,
              onSubmitted: (_) => onSubmitAddress(),
              trailing: IconButton(
                onPressed: onSubmitAddress,
                icon: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                tooltip: 'Try this address',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The service's identity, as the walk draws it: a tile that gives the glyph a
/// ground to measure against.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.service});

  final ServiceKey service;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: service.accent.withValues(alpha: 0.16),
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: service.accent.withValues(alpha: 0.5)),
      ),
      child: Icon(
        service.icon,
        size: 22,
        color: ServiceTheme.onTint(
          service.accent,
          surface: scheme.surfaceContainer,
          tintAlpha: 0.16,
        ),
      ),
    );
  }
}

/// A lamp and a word in the state's tone: `Trying from this device`.
class _StateLine extends StatelessWidget {
  const _StateLine({
    required this.tone,
    required this.text,
    required this.ground,
  });

  final StatusTone tone;
  final String text;
  final Color ground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusToneColor(theme.colorScheme, tone, surface: ground);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodySmall!
                .weight(FontWeight.w600)
                .copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// A certificate waiting for the person, inside its row. A first trust is the
/// short form; a pin that no longer matches is the walk's own escalation,
/// the same content the walk and Settings show.
class _CertificateBlock extends StatelessWidget {
  const _CertificateBlock({
    required this.row,
    required this.probe,
    required this.settings,
    required this.onTrust,
    required this.onNotNow,
  });

  final _FoundRow row;
  final UntrustedCertificateProbe probe;
  final SettingsModel settings;
  final VoidCallback onTrust;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final url = row.url!;
    final rotated = probe.rotated;
    final ground = scheme.surfaceContainerHighest;
    final alarm = statusToneColor(scheme, StatusTone.error, surface: ground);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: AppRadius.borderRadiusMd,
        border: rotated ? Border.all(color: alarm) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rotated)
            CertTrustContent(
              origin: UrlUtils.certOrigin(url) ?? url,
              probe: probe,
              previousFingerprint: settings.pinForUrl(url),
              sharedWith: settings.servicesSharingOriginOf(url),
              surface: ground,
            )
          else ...[
            Text(
              '${row.name} uses a self-signed certificate',
              style: theme.textTheme.bodyMedium!.weight(FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'SHA-256',
              style: theme.textTheme.labelSmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            // Eight bytes to a line: the person reads it against the one the
            // server shows, and a line broken mid-pair is a misread.
            SelectableText(
              _fingerprintLines(probe.certificate.displayFingerprint),
              style: theme.textTheme.bodySmall!.mono,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Trust it if this matches the fingerprint on your server. '
              'Cupola remembers it and tells you if it ever changes.',
              style: theme.textTheme.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                onPressed: onTrust,
                style: remedyFillStyle(context, compact: true, fault: false),
                child: Text(
                  rotated ? 'Trust this certificate anyway' : 'Trust',
                  semanticsLabel: 'Trust the certificate of ${row.name}',
                ),
              ),
              TextButton(
                onPressed: onNotNow,
                style: retryInkStyle(scheme),
                child: Text(
                  'Not now',
                  semanticsLabel: 'Not now for ${row.name}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A row that did not join: the cause once, in the classification's tone, and
/// the verbs it names. Red stays in its row.
class _FailureBlock extends StatelessWidget {
  const _FailureBlock({
    required this.row,
    required this.ground,
    required this.onRetry,
    required this.onRemedy,
  });

  final _FoundRow row;
  final Color ground;
  final VoidCallback onRetry;
  final VoidCallback onRemedy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reason = row.reason ?? ServiceFailureReason.unknown;
    final tone = failureTone(reason);
    final color = statusToneColor(scheme, tone, surface: ground);
    final remedy = row.remedy;
    final retryHelps = failureRetryHelps(reason);
    // Something in front of the service asks for access the row cannot give:
    // nothing here fixes it, and asking again asks the same.
    final nothingToOffer = remedy == null && !retryHelps;
    // The address field is the remedy taken: its button gives way to it.
    final remedyOpen = row.addressOpen && remedy?.$1 == _Remedy.address;
    final name = row.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The sentence is the row's own, spoken once above.
        ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(failureIcon(reason), size: 18, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.failureSentence,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (row.failureNote case final note?) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        note,
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!nothingToOffer && !(remedyOpen && remedy != null)) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (remedy != null)
                FilledButton(
                  onPressed: onRemedy,
                  style: remedyFillStyle(context, compact: true),
                  child: Text(remedy.$2, semanticsLabel: '${remedy.$2}: $name'),
                ),
              if (remedy == null && tone == StatusTone.warning)
                FilledButton(
                  onPressed: onRetry,
                  style: remedyFillStyle(context, compact: true),
                  child: Text(
                    Lexicon.retry,
                    semanticsLabel: '${Lexicon.retry} $name',
                  ),
                )
              else if (retryHelps)
                TextButton(
                  onPressed: onRetry,
                  style: retryInkStyle(scheme),
                  child: Text(
                    Lexicon.retry,
                    semanticsLabel: '${Lexicon.retry} $name',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
