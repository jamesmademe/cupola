import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/reel_motion.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/reel_command_button.dart';
import 'package:cupola/core/widgets/reel_line.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_content.dart';

// ── Beat 3: the walk ────────────────────────────────────────────────────────

/// Which service this step is about, and how far in — hoisted out of the pager
/// so it can *roll* from one service to the next.
///
/// It sits beside the ring for the same reason the ring sits outside the
/// `PageView`: a `PageView` builds one child per page, so the walk's nine steps
/// are nine separate elements and nothing in one can animate into its
/// counterpart in the next. Held here it is a single widget across the whole
/// walk, and advancing rolls `Where does Radarr live?` into `Where does Sonarr
/// live?` — one word moving inside a sentence that holds still, on the same beat
/// as the ring rotating that service to noon. Two instruments, one clock,
/// answering the same question.
///
/// The service's accent travels with it: the eyebrow's ink is resolved per
/// service through `onTint`, so the line changes colour as it changes subject and
/// the room's own accent is what the change hands off to.
class OnboardingWalkSubject extends StatelessWidget {
  const OnboardingWalkSubject({
    super.key,
    required this.service,
    required this.position,
    required this.total,
  }) : _eyebrowOnly = false;

  /// The eyebrow on its own, for the ring's compact register — see
  /// [OnboardingInstrument].
  ///
  /// The question goes, and only the question. While the keyboard is up the user
  /// is already answering it, with a field labelled `Address` under the cursor;
  /// what they still need is which service they are answering *for* and how much
  /// is left, which is exactly what the eyebrow says. Dropping the headline is
  /// also what makes the header row cost the height of the medallion and no more.
  const OnboardingWalkSubject.eyebrow({
    super.key,
    required this.service,
    required this.position,
    required this.total,
  }) : _eyebrowOnly = true;

  final ServiceKey service;

  /// 1-based position in the walk, and how many services are in it.
  final int position;
  final int total;

  final bool _eyebrowOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The flow's spoken landmark: which service, and how far in.
    final eyebrow = ReelLine(
      '${service.title} · $position of $total'.toUpperCase(),
      style: AppTheme.eyebrow(
        ServiceTheme.onTint(
          service.accent,
          surface: scheme.surface,
          tintAlpha: 0,
        ),
      ),
      options: ReelMotion.word,
      // Uppercase belongs in the eye, not the ear — and the spoken form
      // also spells out the separator the eye reads as a dot.
      semanticsLabel: '${service.title}, step $position of $total',
    );
    // Beside the ring the row supplies the gutters, and there is no second line
    // to align to.
    if (_eyebrowOnly) return eyebrow;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          eyebrow,
          const SizedBox(height: AppSpacing.sm),
          ReelLine(
            'Where does ${service.title} live?',
            style: theme.textTheme.headlineSmall!
                .weight(FontWeight.w700)
                .copyWith(color: scheme.onSurface),
            options: ReelMotion.word,
            // Wraps rather than rolls once the sentence stops fitting one line,
            // which for the longest service name happens well inside the
            // reading sizes this app supports.
            fallbackMaxLines: null,
          ),
        ],
      ),
    );
  }
}

/// One service, one screen: where it lives, how to authenticate, and whether it
/// answered.
///
/// The step's subject line lives in [OnboardingWalkSubject], above the pager.
///
/// The step owns its fields' [FocusNode]s so the return key can walk down the
/// form: address → credential → done, one field under the cursor at a time. The
/// framework's own handling of [TextInputAction.next] cannot do this, because it
/// moves focus to the next *traversable* widget and the address field has two of
/// its own — the port chip and, on a secret, the reveal toggle. Both stay in the
/// traversal order for keyboard and screen-reader users; they are simply not
/// where the return key goes.
class OnboardingWalk extends StatefulWidget {
  const OnboardingWalk({
    super.key,
    required this.service,
    required this.urlController,
    required this.apiKeyController,
    required this.usernameController,
    required this.passwordController,
    required this.status,
    required this.reason,
    required this.failureDetail,
    required this.serverVersion,
    required this.verifying,
    required this.certificateProbe,
    required this.trustedFingerprint,
    this.affectedServices = const [],
    required this.next,
    required this.onTest,
    required this.onTrustCertificate,
    required this.onSuggestPort,
    required this.onSkip,
    required this.onAdvance,
    required this.onBack,
  });

  final ServiceKey service;

  final TextEditingController urlController;
  final TextEditingController apiKeyController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final ServiceConnectionStatus? status;
  final ServiceFailureReason? reason;

  /// The verbatim sentence the failure carried, when it carried one — see
  /// `ServiceDiagnosis.detail`. Null for almost every failure, where the
  /// reason-derived message is the better one.
  final String? failureDetail;

  /// The version the server named while the test ran, for the services that say
  /// — see `ServiceDiagnosis.serverVersion`. Printed in the outcome, because a
  /// TrueNAS below the supported floor answers this test and then leaves whole
  /// sections of its console empty.
  final String? serverVersion;
  final bool verifying;

  /// A certificate probe the last test ran into, waiting to be trusted.
  final UntrustedCertificateProbe? certificateProbe;
  final String? trustedFingerprint;

  /// Other services in this walk whose typed address shares this one's TLS
  /// origin — trusting or forgetting the certificate here covers them too.
  final List<ServiceKey> affectedServices;

  /// The next service in the walk, so the step can say how far there is to go.
  final ServiceKey? next;

  final Future<void> Function() onTest;
  final VoidCallback onTrustCertificate;
  final VoidCallback onSuggestPort;
  final VoidCallback onSkip;
  final VoidCallback onAdvance;
  final VoidCallback onBack;

  @override
  State<OnboardingWalk> createState() => _OnboardingWalkState();
}

class _OnboardingWalkState extends State<OnboardingWalk> {
  /// One node per field the step can show. Three rather than two because a
  /// credential-authenticated service has a username *and* a password, and the
  /// address node is shared by both shapes.
  final _address = FocusNode(debugLabel: 'onboarding address');
  final _credential = FocusNode(debugLabel: 'onboarding credential');
  final _password = FocusNode(debugLabel: 'onboarding password');

  @override
  void dispose() {
    _address.dispose();
    _credential.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Hands the keyboard to [next], keeping it up. Requesting focus rather than
  /// unfocusing first is what stops the keyboard closing and reopening between
  /// two fields, which on iOS costs two animations and a relayout of the beat.
  void _pass(FocusNode next) => next.requestFocus();

  /// The end of the form: the return key does what the primary button does —
  /// runs the test. The keyboard goes with it (the test itself dismisses it), so
  /// the outcome and the pinned actions — Test, Skip, Back — come back into
  /// view instead of being answered behind the keys.
  ///
  /// Guarded on [OnboardingWalk.verifying] the same way the button is: a second
  /// return while a probe is in flight would start another one.
  void _submit() {
    if (widget.verifying) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    widget.onTest();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingBeat(
      actions: Column(
        children: [
          OnboardingFooter(
            secondary: OutlinedButton(
              onPressed: widget.onSkip,
              child: Text('Skip ${widget.service.title}'),
            ),
            primary: _TestOrAdvance(
              status: widget.status,
              verifying: widget.verifying,
              isLast: widget.next == null,
              onTest: widget.onTest,
              onAdvance: widget.onAdvance,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Back keeps the row to itself until the keyboard is up, at which
          // point the dismiss control joins it rather than taking a third row —
          // that row cost more height than the ring it was competing with.
          if (OnboardingKeyboardScope.of(context))
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: widget.onBack, child: const Text('Back')),
                const OnboardingKeyboardDismiss(),
              ],
            )
          else
            // No "Add another <Service>" here, and it is not an omission.
            //
            // It was tried, as a push to `/settings/service/<param>?new=1` the
            // moment the server answered. The router's own redirect sends every
            // location other than `/onboarding` back to `/onboarding` until the
            // walk is finished (`router.dart`, `redirect:`), and go_router
            // applies that to imperative pushes too — so the button pushed a
            // *second* onboarding screen on top of the one in progress. Widening
            // the redirect is not the fix either: the destination lives inside
            // the Settings branch of the `StatefulShellRoute`, so honouring it
            // would drop the user into the tabbed shell, nav bar and all, in the
            // middle of a flow that has no tabs.
            //
            // A second connection during onboarding therefore belongs to the
            // walk itself — another page in the flow, not a door out of it —
            // which is its own change. Settings → Connections offers it the
            // moment the walk ends.
            TextButton(onPressed: widget.onBack, child: const Text('Back')),
        ],
      ),
      children: _form(context),
    );
  }

  List<Widget> _form(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final service = widget.service;
    return [
      OnboardingField(
        label: 'Address',
        controller: widget.urlController,
        isUrl: true,
        focusNode: _address,
        action: TextInputAction.next,
        onSubmitted: (_) => _pass(_credential),
        help:
            "${service.title}'s default port is ${service.defaultPort}. "
            'Behind a reverse proxy, use the address you reach it on.',
        trailing: _PortChip(
          port: service.defaultPort,
          onTap: widget.onSuggestPort,
        ),
      ),
      if (service.usesApiKey) ...[
        const SizedBox(height: AppSpacing.lg),
        OnboardingField(
          label: service.credentialLabel,
          controller: widget.apiKeyController,
          isSecret: true,
          focusNode: _credential,
          action: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          hint: 'Paste the ${service.credentialLabel.toLowerCase()}',
          help: service.credentialPath == null
              ? null
              : '${service.title} → ${service.credentialPath}',
          warningFor: service == ServiceKey.plex ? _plexTokenWarning : null,
        ),
      ] else ...[
        const SizedBox(height: AppSpacing.lg),
        OnboardingField(
          label: service.usernameLabel,
          controller: widget.usernameController,
          focusNode: _credential,
          action: TextInputAction.next,
          onSubmitted: (_) => _pass(_password),
          hint: service == ServiceKey.nginxProxyManager
              ? 'The email you sign in with'
              : 'Optional',
        ),
        const SizedBox(height: AppSpacing.lg),
        OnboardingField(
          label: 'Password',
          controller: widget.passwordController,
          isSecret: true,
          focusNode: _password,
          action: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          hint: 'Optional',
          help:
              'Leave both empty if your ${service.title} instance does not '
              'require a login.',
        ),
      ],
      // Per-service facts worth saying at the moment they matter — registry
      // data, so Settings and the walk cannot drift apart on which services
      // have something to say.
      if (service.walkNote case final note?) ...[
        const SizedBox(height: AppSpacing.lg),
        Text(
          note,
          style: theme.textTheme.bodySmall!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      if (widget.certificateProbe case final probe?) ...[
        const SizedBox(height: AppSpacing.xl),
        _CertificateCard(
          service: service,
          origin:
              UrlUtils.certOrigin(widget.urlController.text) ??
              widget.urlController.text.trim(),
          probe: probe,
          previousFingerprint: widget.trustedFingerprint,
          sharedWith: widget.affectedServices
              .where((s) => s != service)
              .toList(),
          onTrust: widget.onTrustCertificate,
        ),
      ],
      if (widget.status case final status? when !widget.verifying) ...[
        const SizedBox(height: AppSpacing.xl),
        _Outcome(
          service: service,
          status: status,
          reason: widget.reason,
          failureDetail: widget.failureDetail,
          serverVersion: widget.serverVersion,
        ),
      ],
      if (widget.trustedFingerprint != null &&
          widget.certificateProbe == null) ...[
        const SizedBox(height: AppSpacing.md),
        Text(
          widget.affectedServices.length > 1
              ? "You trusted this server's own certificate — it also covers "
                    '${widget.affectedServices.where((s) => s != service).map((s) => s.title).join(', ')}.'
              : "You trusted this server's own certificate.",
          style: theme.textTheme.bodySmall!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      if (widget.next case final upcoming?) ...[
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: upcoming.accent,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Next: ${upcoming.title}',
              style: theme.textTheme.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    ];
  }
}

/// One button that changes its job once the service has answered: there is no
/// reason to make someone press Test and then press Next.
///
/// It is a **single** [ReelCommandButton] across that change rather than two
/// widgets swapped by a conditional, and that is the whole point: the same
/// control rolls `Test connection` → `Testing…` → `Next service`, so the reward
/// for a service answering is the button itself turning into the way forward.
/// Swapping widgets would reset the label controller and replace the text
/// instead of rolling it.
///
/// The spinner this replaced is not missed. A test behind a reverse proxy can
/// take fifteen seconds, and for all fifteen the old button said nothing at all
/// — the label had been swapped out for an 18pt ring. Here the label stays and
/// being in motion is what says busy.
class _TestOrAdvance extends StatelessWidget {
  const _TestOrAdvance({
    required this.status,
    required this.verifying,
    required this.isLast,
    required this.onTest,
    required this.onAdvance,
  });

  final ServiceConnectionStatus? status;
  final bool verifying;
  final bool isLast;
  final Future<void> Function() onTest;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final connected = status == ServiceConnectionStatus.connected;
    final advanceLabel = isLast ? 'Finish' : 'Next service';

    return ReelCommandButton(
      label: connected ? advanceLabel : 'Test connection',
      // Absent on the advance arm: that press navigates, it does not wait, and a
      // waiting label would flash for one frame on the way out.
      busyLabel: connected ? null : 'Testing',
      // Not "Failed". The outcome card below already names the cause in a
      // sentence the user can act on; the button's job is to say what pressing
      // it again will do.
      failureLabel: connected ? null : 'Test again',
      // Both arms measured now, so the one transition this reservation exists
      // for — answered — moves a word and not the button's width.
      slotLabels: ['Test connection', 'Test again', advanceLabel],
      onPressed: verifying
          ? null
          : connected
          ? () async => onAdvance()
          : onTest,
    );
  }
}

/// The result of a test as a sentence. A badge saying UNREACHABLE names nothing
/// the user can act on; the resolved failure message names the cause.
class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.service,
    required this.status,
    required this.reason,
    required this.failureDetail,
    required this.serverVersion,
  });

  final ServiceKey service;
  final ServiceConnectionStatus status;
  final ServiceFailureReason? reason;
  final String? failureDetail;
  final String? serverVersion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final presentation = describeConnection(
      service,
      status: status,
      reason: reason,
    );
    final tone = statusToneColor(scheme, presentation.tone);
    final sentence = switch (status) {
      ServiceConnectionStatus.connected => '${service.title} answered.',
      ServiceConnectionStatus.notConfigured =>
        service.usesApiKey
            ? 'Enter the address and the ${service.credentialLabel.toLowerCase()}, then test.'
            : 'Enter the address, then test.',
      // The detail when the failure carried one, the reason-derived sentence
      // otherwise — the same rule `ServiceDiagnosis.messageFor` applies on the
      // settings screen, so the two surfaces cannot describe one test
      // differently.
      _ => failureDetail ?? connectionFailureMessage(service, reason),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sentence,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                // What the server said it is running. Amber when the version
                // itself is the problem: "answered" is true and still not the
                // whole answer on a release Cupola cannot drive.
                if (describeServerVersion(service, serverVersion)
                    case final note?) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    note.message,
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: note.isWarning
                          ? AppColors.warning
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                // The permission is the only failure in the vocabulary whose fix
                // is not in this form, so it is the only one that earns a button:
                // everything else is an address or a credential the user is
                // already looking at.
                if (reason == ServiceFailureReason.localNetworkBlocked) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () async {
                        final opened =
                            await LocalNetworkPermission.openSettings();
                        if (!opened && context.mounted) {
                          SnackBarHelper.info(
                            context,
                            LocalNetworkPermission.remedy,
                          );
                        }
                      },
                      icon: const Icon(Icons.settings_rounded, size: 18),
                      label: const Text('Open Settings'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The self-signed certificate moment, resolved inside the step.
///
/// A modal appearing on top of a failure the user has not read yet is an
/// ambush; on a home lab a server presenting its own certificate is normal,
/// so it gets a state rather than an interruption. [CertTrustContent] is the
/// same content [showCertTrustDialog] wraps in a modal for settings — the
/// evidence and words match wherever the user meets a certificate; only the
/// chrome around it (a card here, a dialog there) differs.
class _CertificateCard extends StatelessWidget {
  const _CertificateCard({
    required this.service,
    required this.origin,
    required this.probe,
    required this.onTrust,
    this.previousFingerprint,
    this.sharedWith = const [],
  });

  final ServiceKey service;

  /// The address this certificate was presented for, already resolved to
  /// [UrlUtils.certOrigin]'s canonical `https://host:port` form by the
  /// caller — the same string [SettingsModel.trustedCertificates] keys on.
  final String origin;
  final UntrustedCertificateProbe probe;
  final VoidCallback onTrust;
  final String? previousFingerprint;
  final List<ServiceKey> sharedWith;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rotated = probe.rotated;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: rotated
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(
          color: rotated ? scheme.error : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CertTrustContent(
            origin: origin,
            probe: probe,
            previousFingerprint: previousFingerprint,
            sharedWith: sharedWith,
          ),
          const SizedBox(height: AppSpacing.md),
          // Rotated gets no visually-affirmative default: an outlined button
          // is what the first-trust case already used, so the escalation is
          // carried by the card's own tint and border above, not by demoting
          // this control further.
          OutlinedButton(
            onPressed: onTrust,
            style: rotated
                ? OutlinedButton.styleFrom(foregroundColor: scheme.error)
                : null,
            child: Text(
              rotated
                  ? 'Trust this certificate anyway'
                  : 'Trust and test again',
            ),
          ),
        ],
      ),
    );
  }
}

class _PortChip extends StatelessWidget {
  const _PortChip({required this.port, required this.onTap});

  final int port;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: 'Use port $port',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: AppRadius.borderRadiusSm,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.14),
            borderRadius: AppRadius.borderRadiusSm,
          ),
          child: Text(
            ':$port',
            style: theme.textTheme.labelSmall!
                .weight(FontWeight.w600)
                .tabular
                .copyWith(
                  color: ServiceTheme.onTint(
                    scheme.primary,
                    surface: scheme.surface,
                    tintAlpha: 0.14,
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

/// Flags a pasted Plex JSON Web Token while it is still being typed.
///
/// A warning rather than an error: the token is well-formed and will work — for
/// seven days. After that it can only be renewed through plex.tv, which Cupola
/// never calls, so the user would be left with a 401 and no way to read it.
String? _plexTokenWarning(String value) => value.trim().startsWith('eyJ')
    ? 'That token expires in 7 days and cannot be renewed here. Paste a '
          'long-lived device token instead.'
    : null;
