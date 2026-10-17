import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/reel_motion.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/reel_command_button.dart';
import 'package:cupola/core/widgets/reel_line.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/onboarding/data/known_candidates_provider.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_access_rules.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_content.dart';
import 'package:cupola/features/settings/presentation/widgets/connection_access_fields.dart';

// ── Connect ─────────────────────────────────────────────────────────────────

/// Which service Connect is setting up: hoisted out of the pager so it can
/// *roll* from one service to the next.
///
/// It sits beside the ring for the same reason the ring sits outside the
/// `PageView`: a `PageView` builds one child per page, so nothing in one page
/// can animate into its counterpart in the next. Held here it is one widget,
/// and choosing another service rolls `Set up Seerr` into `Set up Radarr`: one
/// word moving inside a sentence that holds still, on the same beat as the ring
/// rotating that service to noon.
///
/// The service's identity is the glyph tile beside the step, never the ink of
/// the words: a counter is a counter in every service's step.
class OnboardingWalkSubject extends StatelessWidget {
  const OnboardingWalkSubject({
    super.key,
    required this.service,
    this.step,
    this.onStartElsewhere,
  }) : _eyebrowOnly = false;

  /// The service and the step on one line, for the ring's compact register:
  /// see [OnboardingInstrument].
  ///
  /// While the keyboard is up the person is already answering the form, with a
  /// field labelled `Address` under the cursor; what they still need is which
  /// service they are answering for, which is exactly what this line says.
  const OnboardingWalkSubject.eyebrow({
    super.key,
    required this.service,
    this.step,
  }) : onStartElsewhere = null,
       _eyebrowOnly = true;

  final ServiceKey service;

  /// Where Connect sits in the way in (`Step 1 of 2`), or null when this
  /// service is the whole of it: only Seerr and Prowlarr lead somewhere.
  final String? step;

  /// Opens "Start with another service", or null to leave the link out.
  final VoidCallback? onStartElsewhere;

  final bool _eyebrowOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_eyebrowOnly) {
      final words = step == null
          ? 'Set up ${service.title}'
          : 'Set up ${service.title}\u00A0· ${step!.toLowerCase()}';
      return ReelLine(
        words,
        style: AppTheme.chrome(context, color: scheme.onSurfaceVariant),
        options: ReelMotion.word,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ServiceGlyph(service: service),
              if (step case final step?) ...[
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  child: Text(
                    step,
                    style: AppTheme.chrome(
                      context,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            header: true,
            child: ReelLine(
              'Set up ${service.title}',
              style: theme.textTheme.headlineSmall!.copyWith(
                color: scheme.onSurface,
              ),
              options: ReelMotion.word,
              fallbackMaxLines: null,
            ),
          ),
          // What the step wants, before it has been given anything to react
          // to. Dropped on the compact frame, where the two 308pt columns spend
          // their height on the form and the certificate instead.
          if (!AppBreakpoints.isCompactDesktop(context)) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              connectLead(service),
              style: theme.textTheme.bodyMedium!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (onStartElsewhere case final open?)
            OnboardingStartElsewhere(onPressed: open),
        ],
      ),
    );
  }
}

/// The way from Connect to the list of every other service.
///
/// Under the headline while the subject is on screen, and at the foot of the
/// form once the register folds the subject away: see
/// [OnboardingWalk.onStartElsewhere].
class OnboardingStartElsewhere extends StatelessWidget {
  const OnboardingStartElsewhere({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 44),
        visualDensity: VisualDensity.standard,
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.chevron_right_rounded, size: 18),
      label: const Text('Start with another service'),
    );
  }
}

/// What Connect says under "Set up X": why to start here, for the two
/// services that know the others, and what to type for every other one.
String connectLead(ServiceKey service) => switch (service) {
  ServiceKey.seerr =>
    'Seerr already knows your Radarr and Sonarr, keys included, so it is the '
        'quickest place to start.',
  ServiceKey.prowlarr =>
    "Prowlarr knows your arrs' addresses, so you only add their keys.",
  _ => walkInstruction(service),
};

/// What this step is asking for, in one line: the walk's subtitle.
///
/// Shared rather than inlined because the step says it twice in two registers:
/// under the headline as a standing instruction, and, when a test runs against
/// an empty form, as the reason nothing was sent.
String walkInstruction(ServiceKey service) => service.usesApiKey
    // The credential as the registry spells it: `API key` keeps the capitals
    // of its initialism, and `Plex token` its name.
    ? 'Enter the address and the ${service.credentialLabel}, '
          'then test.'
    : 'Enter the address, then test.';

/// The service's identity, now that the eyebrow's is neutral.
///
/// A tile rather than a bare icon: at 34pt the accent needs a ground to be read
/// as an accent, and the wash is what lets the glyph itself be an ink that
/// measures: seven of the seventeen accents fall under 3:1 on paper, so the
/// raw colour is never what gets stroked.
class _ServiceGlyph extends StatelessWidget {
  const _ServiceGlyph({required this.service});

  final ServiceKey service;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      // The eyebrow beside it already names the service for a screen reader;
      // this is the same fact drawn, so it is excluded rather than repeated.
      excludeSemantics: true,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: service.accent.withValues(alpha: 0.16),
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: service.accent.withValues(alpha: 0.5)),
        ),
        child: Icon(
          service.icon,
          size: 18,
          color: ServiceTheme.onTint(
            service.accent,
            surface: scheme.surface,
            tintAlpha: 0.16,
          ),
        ),
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
/// its own: the port chip and, on a secret, the reveal toggle. Both stay in the
/// traversal order for keyboard and screen-reader users; they are simply not
/// where the return key goes.
/// The step's address away: the connection form's second address, offered
/// behind `Add an address away` under the address at home, with its own
/// Access row and its own certificate.
class OnboardingAway {
  const OnboardingAway({
    required this.controller,
    required this.shown,
    required this.onShow,
    required this.accessController,
    required this.accessFormKey,
    this.showAccess = false,
    required this.onShowAccess,
    this.result,
    this.testedAccess,
    this.certificateProbe,
    required this.onTrustCertificate,
  });

  final TextEditingController controller;

  /// Whether the field is on screen: once its link was taken, or when the
  /// connection already has an address away.
  final bool shown;
  final VoidCallback onShow;

  /// Its Access row, under the field: shown once access is set or a
  /// gateway's remedy was taken ([onShowAccess]), as the one at home is.
  final ConnectionAccessController accessController;
  final GlobalKey<FormState> accessFormKey;
  final bool showAccess;
  final ValueChanged<AccessKind> onShowAccess;

  /// What it answered on the last test; null when it was not asked.
  final ServiceDiagnosis? result;

  /// The access that test sent there.
  final ConnectionAccess? testedAccess;

  /// A certificate it presented, waiting to be trusted.
  final UntrustedCertificateProbe? certificateProbe;
  final VoidCallback onTrustCertificate;
}

class OnboardingWalk extends StatefulWidget {
  const OnboardingWalk({
    super.key,
    required this.service,
    required this.urlController,
    required this.apiKeyController,
    required this.usernameController,
    required this.passwordController,
    required this.accessController,
    required this.accessFormKey,
    this.showAccess = false,
    this.testedAccess,
    required this.onShowAccess,
    this.sharedTokenFrom,
    this.onUseSharedToken,
    required this.status,
    this.homeStatus,
    required this.reason,
    this.gateway,
    required this.failureDetail,
    required this.serverVersion,
    required this.verifying,
    required this.certificateProbe,
    required this.trustedFingerprint,
    this.affectedServices = const [],
    required this.onTest,
    required this.onTrustCertificate,
    required this.onSuggestPort,
    required this.onAdvance,
    required this.onBack,
    this.onStartElsewhere,
    this.formScroll,
    required this.away,
  });

  final ServiceKey service;

  final TextEditingController urlController;
  final TextEditingController apiKeyController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;

  /// The step's Access row, the connection form's own: shown when
  /// [showAccess], which is once access is set, an address carried a
  /// password, or a gateway's remedy was taken ([onShowAccess]).
  final ConnectionAccessController accessController;
  final GlobalKey<FormState> accessFormKey;
  final bool showAccess;

  /// The access the last test sent, which decides how its outcome is said.
  final ConnectionAccess? testedAccess;

  /// Takes a gateway's remedy in the step: shows the Access row with the
  /// choice the gateway wants.
  final ValueChanged<AccessKind> onShowAccess;

  /// The service whose Cloudflare token passed this step's Access team
  /// earlier in the walk, when the step was stopped there with no token: the
  /// remedy is then that token ([onUseSharedToken]), not an empty row.
  final ServiceKey? sharedTokenFrom;
  final VoidCallback? onUseSharedToken;

  /// The step's verdict: connected when either address answered and the
  /// fields are still the ones tested. It turns the primary into the way on.
  final ServiceConnectionStatus? status;

  /// What the address at home itself answered, when the address away was
  /// asked too; null reads [status]. [reason], [gateway], [failureDetail] and
  /// [serverVersion] are the home's.
  final ServiceConnectionStatus? homeStatus;
  final ServiceFailureReason? reason;

  /// What answered in the service's place, when the test met a gateway: the
  /// state word names it.
  final AccessGatewayAnswer? gateway;

  /// The verbatim sentence the failure carried, when it carried one: see
  /// `ServiceDiagnosis.detail`. Null for almost every failure, where the
  /// reason-derived message is the better one.
  final String? failureDetail;

  /// The version the server named during its test, for services that say so.
  /// See `ServiceDiagnosis.serverVersion`. Printed in the outcome, because a
  /// TrueNAS below the supported floor answers this test and then leaves whole
  /// sections of its console empty.
  final String? serverVersion;
  final bool verifying;

  /// A certificate probe the last test ran into, waiting to be trusted.
  final UntrustedCertificateProbe? certificateProbe;
  final String? trustedFingerprint;

  /// Other services in this walk whose typed address shares this one's TLS
  /// origin: trusting or forgetting the certificate here covers them too.
  final List<ServiceKey> affectedServices;

  final Future<void> Function() onTest;
  final VoidCallback onTrustCertificate;
  final VoidCallback onSuggestPort;
  final VoidCallback onAdvance;
  final VoidCallback onBack;

  /// Opens the list of every other service, from the foot of the form, or
  /// null while [OnboardingWalkSubject] carries the link itself.
  ///
  /// The subject folds away when the instrument takes the short screen's
  /// register (an accessibility reading size, a keyboard), and the link goes
  /// with it: without this, another service would be out of reach exactly
  /// where the person has the least room to look for it.
  final VoidCallback? onStartElsewhere;

  /// The form's scroll, held by the screen so that every arrival at the step
  /// opens on its first field, whatever the visit before left it at.
  final ScrollController? formScroll;

  /// The address away, its field, its access and its answer.
  final OnboardingAway away;

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
  final _awayAddress = FocusNode(debugLabel: 'onboarding address away');

  /// What a press of Test found wrong with each address, said in the error
  /// tone under its field until its text changes: by the text, since the
  /// caret the press puts there notifies the controller too.
  String? _homeProblem;
  String? _awayProblem;
  String _homeProblemOf = '';
  String _awayProblemOf = '';

  /// Where the Access row sits, so a remedy can bring it into view.
  final _accessRow = GlobalKey();

  /// Where the address away's Access row sits, for the same reason.
  final _awayAccessRow = GlobalKey();

  /// Where a test's outcome sits. A test is answered under the fields, and on
  /// a phone the fields and the hero above them can leave it below the pinned
  /// actions: the verdict, and the remedy it offers, scroll into view when they
  /// arrive instead of waiting for the user to look for them.
  final _outcome = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.urlController.addListener(_clearHomeProblem);
    widget.away.controller.addListener(_clearAwayProblem);
  }

  void _clearHomeProblem() {
    if (_homeProblem == null) return;
    if (widget.urlController.text == _homeProblemOf) return;
    setState(() => _homeProblem = null);
  }

  void _clearAwayProblem() {
    if (_awayProblem == null) return;
    if (widget.away.controller.text == _awayProblemOf) return;
    setState(() => _awayProblem = null);
  }

  @override
  void didUpdateWidget(OnboardingWalk oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urlController != widget.urlController) {
      oldWidget.urlController.removeListener(_clearHomeProblem);
      widget.urlController.addListener(_clearHomeProblem);
    }
    if (oldWidget.away.controller != widget.away.controller) {
      oldWidget.away.controller.removeListener(_clearAwayProblem);
      widget.away.controller.addListener(_clearAwayProblem);
    }
    final arrived =
        widget.status != null &&
        !widget.verifying &&
        (oldWidget.verifying ||
            oldWidget.status != widget.status ||
            oldWidget.reason != widget.reason ||
            oldWidget.gateway != widget.gateway);
    if (!arrived) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final outcome = _outcome.currentContext;
      if (outcome == null || !outcome.mounted) return;
      final still = MediaQuery.maybeDisableAnimationsOf(outcome) ?? false;
      Scrollable.ensureVisible(
        outcome,
        duration: still ? Duration.zero : AppAnimation.standard,
        curve: AppAnimation.standardCurve,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  /// A gateway's remedy, answered here: the Access row, with the choice the
  /// gateway wants, scrolled into view under the outcome that asked for it.
  void _addAccess(AccessKind kind) {
    widget.onShowAccess(kind);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _accessRow.currentContext;
      if (row != null && row.mounted) Scrollable.ensureVisible(row);
    });
  }

  @override
  void dispose() {
    widget.urlController.removeListener(_clearHomeProblem);
    widget.away.controller.removeListener(_clearAwayProblem);
    _address.dispose();
    _credential.dispose();
    _password.dispose();
    _awayAddress.dispose();
    super.dispose();
  }

  /// `Add an address away`: the field, with the keyboard on it.
  void _showAway() {
    widget.away.onShow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _awayAddress.requestFocus();
      // Only as far as it takes, from below: the address at home stays in
      // view above it.
      final field = _awayAddress.context;
      if (field != null && field.mounted) {
        Scrollable.ensureVisible(
          field,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  /// What is wrong with [raw] as the address at home or ([away]) away, or
  /// null when it can be tested: the connection form's rules, so an address
  /// the step takes is one the form takes when it is reopened.
  String? _addressProblem(String raw, {required bool away}) {
    final service = widget.service;
    if (raw.trim().isEmpty) return away ? null : 'Add the address at home';
    final malformed = UrlUtils.validateServiceHost(raw, allowCredentials: true);
    if (malformed != null) return malformed;
    if (cleartextRefusal(service, raw, optional: away) case final refused?) {
      return refused;
    }
    if (away &&
        isSameAddress(
          UrlUtils.normalizeBaseUrl(UrlUtils.withoutCredentials(raw)),
          UrlUtils.normalizeBaseUrl(
            UrlUtils.withoutCredentials(widget.urlController.text),
          ),
        )) {
      return 'This is the address at home. Use the one you reach from '
          'outside, or leave this empty.';
    }
    return null;
  }

  /// Whether either address is refused for `http://` as it stands: the
  /// primary is drawn dim, and still pressed.
  bool get _refused =>
      cleartextRefusal(widget.service, widget.urlController.text) != null ||
      (widget.away.shown &&
          cleartextRefusal(
                widget.service,
                widget.away.controller.text,
                optional: true,
              ) !=
              null);

  /// Test, once both addresses can be sent; otherwise the first one that
  /// cannot comes into view with its words, the keyboard on it.
  Future<void> _test() async {
    final home = _addressProblem(widget.urlController.text, away: false);
    final away = widget.away.shown
        ? _addressProblem(widget.away.controller.text, away: true)
        : null;
    if (home != null || away != null) {
      setState(() {
        _homeProblem = home;
        _awayProblem = away;
        _homeProblemOf = widget.urlController.text;
        _awayProblemOf = widget.away.controller.text;
      });
      final focus = home != null ? _address : _awayAddress;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final field = focus.context;
        if (!mounted || field == null || !field.mounted) return;
        Scrollable.ensureVisible(field, alignment: 0.3);
        focus.requestFocus();
      });
      return;
    }
    await widget.onTest();
  }

  /// `Use https`: the same address over https, which the next test checks.
  static void _useHttpsIn(TextEditingController address) {
    address.text = address.text.trim().replaceFirst(
      RegExp('^http://', caseSensitive: false),
      'https://',
    );
  }

  /// Hands the keyboard to [next], keeping it up. Requesting focus rather than
  /// unfocusing first is what stops the keyboard closing and reopening between
  /// two fields, which on iOS costs two animations and a relayout of the beat.
  void _pass(FocusNode next) => next.requestFocus();

  /// The end of the form: the return key does what the primary button does:
  /// it runs the test. The keyboard goes with it (the test itself dismisses it), so
  /// the outcome and the pinned actions (Test, Skip, Back) come back into
  /// view instead of being answered behind the keys.
  ///
  /// Guarded on [OnboardingWalk.verifying] the same way the button is: a second
  /// return while a probe is in flight would start another one.
  void _submit() {
    if (widget.verifying) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    _test();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingBeat(
      besideRing: MainAxisAlignment.start,
      controller: widget.formScroll,
      // Folded away in the short screen's register, where the link to
      // another service comes down to the form instead.
      subjectAbove: widget.onStartElsewhere == null,
      actions: Column(
        // Beside the ring the footer keeps its own width, so Back lines up
        // under it at the column's edge rather than floating in the middle.
        crossAxisAlignment: onboardingSideBySide(context)
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          // No Skip: a service is saved only once it answers, and Back is the
          // other way out.
          OnboardingFooter(
            primary: ListenableBuilder(
              listenable: Listenable.merge([
                widget.urlController,
                widget.away.controller,
              ]),
              builder: (context, _) => _TestOrAdvance(
                status: widget.status,
                verifying: widget.verifying,
                dimmed: _refused,
                onTest: _test,
                onAdvance: widget.onAdvance,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Back keeps the row to itself until the keyboard is up, at which
          // point the dismiss control joins it rather than taking a third row:
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
            // No "Add another <Service>" here: the services this one knows
            // come next, in Found, and every other one is set up from
            // Connections once the way in is over.
            TextButton(onPressed: widget.onBack, child: const Text('Back')),
        ],
      ),
      children: _form(context),
    );
  }

  /// An Access row in the step's own fields, as its address and key are
  /// drawn: the label above, a filled well, the reveal toggle on a secret.
  Widget _accessFields(ConnectionAccessController controller) =>
      ConnectionAccessFields(
        controller: controller,
        onMoveToCredential: (value) {
          if (value.isNotEmpty) widget.apiKeyController.text = value;
        },
        fieldBuilder: (context, field) => OnboardingField(
          label: field.label,
          controller: field.controller,
          isSecret: field.secret,
          action: TextInputAction.next,
          validator: field.validator,
          trailing: field.onPaste == null
              ? null
              : _PasteButton(onPaste: field.onPaste!),
        ),
      );

  /// A gateway's remedy at the address away: its Access row, under its
  /// field, scrolled into view.
  void _addAwayAccess(AccessKind kind) {
    widget.away.onShowAccess(kind);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _awayAccessRow.currentContext;
      if (row != null && row.mounted) Scrollable.ensureVisible(row);
    });
  }

  /// `At home · nas.home.arpa:7878`: where an answer came from.
  String _addressLine({required bool away}) {
    final raw = away ? widget.away.controller.text : widget.urlController.text;
    final host =
        widget.service.extractHost(UrlUtils.normalizeBaseUrl(raw)) ??
        raw.trim();
    return '${away ? 'Away' : 'At home'}\u00A0· $host';
  }

  /// Whether an answer is an address that did not answer at all, which is
  /// said differently when the other address answered: from home, an
  /// address away often cannot be reached (a router that cannot reach its
  /// own public address), and the reverse.
  static bool _silent(
    ServiceConnectionStatus status,
    ServiceFailureReason? r,
  ) =>
      status == ServiceConnectionStatus.disconnected &&
      (r == ServiceFailureReason.unreachable ||
          r == ServiceFailureReason.timeout);

  /// The test's answer: one card for one address, as always; one for each
  /// when the address away was asked too, said together in red when
  /// neither answered.
  Widget _outcomes(ServiceConnectionStatus status) {
    final service = widget.service;
    final home = _Outcome(
      service: service,
      status: widget.homeStatus ?? status,
      reason: widget.reason,
      gateway: widget.gateway,
      failureDetail: widget.failureDetail,
      serverVersion: widget.serverVersion,
      testedAccess: widget.testedAccess,
      // Until the row is on screen, the remedy is the way to it.
      onAddAccess: widget.showAccess ? null : _addAccess,
      sharedTokenFrom: widget.sharedTokenFrom,
      onUseSharedToken: widget.onUseSharedToken,
      address: widget.away.result == null ? null : _addressLine(away: false),
    );
    final away = widget.away.result;
    if (away == null) return KeyedSubtree(key: _outcome, child: home);
    final homeSilent = _silent(widget.homeStatus ?? status, widget.reason);
    final awaySilent = _silent(away.status, away.reason);
    if (homeSilent && awaySilent) {
      return _OutcomeCard(
        key: _outcome,
        tone: StatusTone.error,
        sentence: failureHeadline(
          ServiceFailureReason.unreachableAtBoth,
          subject: service.title,
        ),
        lines: [_addressLine(away: false), _addressLine(away: true)],
      );
    }
    _OutcomeCard notChecked({required bool away}) => _OutcomeCard(
      tone: StatusTone.info,
      sentence: 'Not checked from here.',
      lines: [
        away
            ? "Cupola tries it when the home address doesn't answer."
            : 'Cupola tries it first, and uses it whenever it answers.',
        _addressLine(away: away),
      ],
    );
    return Column(
      key: _outcome,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        homeSilent ? notChecked(away: false) : home,
        const SizedBox(height: AppSpacing.sm),
        awaySilent
            ? notChecked(away: true)
            : _Outcome(
                service: service,
                status: away.status,
                reason: away.reason,
                gateway: away.gateway,
                failureDetail: away.isDisconnected
                    ? away.messageFor(service)
                    : away.detail,
                serverVersion: away.serverVersion,
                testedAccess: widget.away.testedAccess,
                onAddAccess: widget.away.showAccess ? null : _addAwayAccess,
                address: _addressLine(away: true),
              ),
      ],
    );
  }

  List<Widget> _form(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final service = widget.service;
    return [
      // Each field keyed: the address away comes and goes above the
      // credential, and an unkeyed field would take over the state of the
      // one that stood in its place, listening to the other's controller.
      OnboardingField(
        key: const ValueKey('address'),
        label: 'Address at home',
        controller: widget.urlController,
        isUrl: true,
        // `http://` across the internet first: refused, on every platform.
        // Then the service's own reason (TrueNAS refuses http:// outright).
        warningFor: (raw) =>
            cleartextRefusal(service, raw) ?? transportWarningFor(service, raw),
        problem: _homeProblem,
        focusNode: _address,
        action: TextInputAction.next,
        onSubmitted: (_) =>
            _pass(widget.away.shown ? _awayAddress : _credential),
        trailing: ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.urlController,
          // Only beside a host: with nothing typed there is no host to put
          // the port on, and a chip that does nothing is a broken promise.
          builder: (context, value, _) =>
              value.text.trim().isNotEmpty &&
                  UrlUtils.offersDefaultPort(
                    value.text,
                    port: service.defaultPort,
                  )
              ? _PortChip(
                  port: service.defaultPort,
                  onTap: widget.onSuggestPort,
                )
              : const SizedBox.shrink(),
        ),
      ),
      _UseHttps(controller: widget.urlController, service: service),
      // The field's help, and after it, under the address it adds to, the
      // link to an address away: on the help's line rather than a line of its
      // own, which pushed the key below the fold of a 6.3" phone. It wraps
      // under the help when the two do not fit side by side.
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          children: [
            Text(
              "${service.title}'s default port is ${service.defaultPort}.",
              style: theme.textTheme.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (!widget.away.shown)
              TextButton(
                onPressed: _showAway,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 44),
                  visualDensity: VisualDensity.standard,
                  // In ink: the one thing a first run may want here that the
                  // form does not show.
                  foregroundColor: scheme.onSurface,
                ),
                child: const Text('Add an address away'),
              ),
          ],
        ),
      ),
      if (widget.away.shown) ...[
        const SizedBox(height: AppSpacing.lg),
        OnboardingField(
          key: const ValueKey('address away'),
          label: 'Address away\u00A0· optional',
          controller: widget.away.controller,
          isUrl: true,
          hint: 'https://${service.routeParam}.example.com',
          warningFor: (raw) =>
              cleartextRefusal(service, raw, optional: true) ??
              transportWarningFor(service, raw),
          problem: _awayProblem,
          focusNode: _awayAddress,
          action: TextInputAction.next,
          onSubmitted: (_) => _pass(_credential),
          help:
              "Used when the home address doesn't answer. Leave it empty to "
              'reach ${service.title} only at home.',
        ),
        _UseHttps(
          controller: widget.away.controller,
          service: service,
          optional: true,
        ),
        if (widget.away.showAccess) ...[
          const SizedBox(height: AppSpacing.lg),
          Form(
            key: widget.away.accessFormKey,
            child: KeyedSubtree(
              key: _awayAccessRow,
              child: _accessFields(widget.away.accessController),
            ),
          ),
        ],
      ],
      if (service.usesApiKey) ...[
        SizedBox(height: widget.away.shown ? AppSpacing.lg : AppSpacing.xs),
        OnboardingField(
          key: const ValueKey('credential'),
          label: service.credentialLabel,
          controller: widget.apiKeyController,
          isSecret: true,
          focusNode: _credential,
          action: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          hint: 'Paste the ${service.credentialLabel}',
          // On the label row, not under the field. Under it, a Plex token
          // warning replaced the very breadcrumb that says where a better
          // token lives: the note slot is validation's, and this is not a
          // validation.
          breadcrumb: service.credentialPath == null
              ? null
              : '${service.title} → ${service.credentialPath}',
          warningFor: service == ServiceKey.plex ? _plexTokenWarning : null,
        ),
      ] else ...[
        SizedBox(height: widget.away.shown ? AppSpacing.lg : AppSpacing.xs),
        OnboardingField(
          key: const ValueKey('username'),
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
          key: const ValueKey('password'),
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
      if (widget.showAccess) ...[
        const SizedBox(height: AppSpacing.xl),
        Form(
          key: widget.accessFormKey,
          child: KeyedSubtree(
            key: _accessRow,
            child: _accessFields(widget.accessController),
          ),
        ),
      ],
      // Per-service facts worth saying at the moment they matter: registry
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
      if (widget.away.certificateProbe case final probe?) ...[
        const SizedBox(height: AppSpacing.xl),
        _CertificateCard(
          service: service,
          origin:
              UrlUtils.certOrigin(widget.away.controller.text) ??
              widget.away.controller.text.trim(),
          probe: probe,
          onTrust: widget.away.onTrustCertificate,
        ),
      ],
      if (widget.status case final status? when !widget.verifying) ...[
        const SizedBox(height: AppSpacing.xl),
        _outcomes(status),
      ],
      if (widget.trustedFingerprint != null &&
          widget.certificateProbe == null) ...[
        const SizedBox(height: AppSpacing.md),
        Text(
          widget.affectedServices.length > 1
              ? "You trusted this server's own certificate. It also covers "
                    '${widget.affectedServices.where((s) => s != service).map((s) => s.title).join(', ')}.'
              : "You trusted this server's own certificate.",
          style: theme.textTheme.bodySmall!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      if (widget.onStartElsewhere case final open?) ...[
        const SizedBox(height: AppSpacing.lg),
        OnboardingStartElsewhere(onPressed: open),
      ],
    ];
  }
}

/// One button that changes its job once the service has answered: there is no
/// reason to make someone press Test and then press Next.
///
/// It is a **single** [ReelCommandButton] across that change rather than two
/// widgets swapped by a conditional, and that is the whole point: the same
/// control rolls `Test connection` → `Testing…` → `Continue`, so the reward
/// for a service answering is the button itself turning into the way forward.
/// Swapping widgets would reset the label controller and replace the text
/// instead of rolling it.
///
/// The spinner this replaced is not missed. A test behind a reverse proxy can
/// take fifteen seconds; for all fifteen the old button said nothing at all:
/// the label had been swapped out for an 18pt ring. Here the label stays and
/// being in motion is what says busy.
class _TestOrAdvance extends StatelessWidget {
  const _TestOrAdvance({
    required this.status,
    required this.verifying,
    this.dimmed = false,
    required this.onTest,
    required this.onAdvance,
  });

  final ServiceConnectionStatus? status;
  final bool verifying;

  /// An address is refused as typed: the test cannot run, and the press
  /// brings the field into view.
  final bool dimmed;

  /// Once the service answers, the way on: to Found or to the close.
  static const _advance = 'Continue';
  final Future<void> Function() onTest;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final connected = status == ServiceConnectionStatus.connected;

    return ReelCommandButton(
      label: connected ? _advance : 'Test connection',
      // Absent on the advance arm: that press navigates, it does not wait, and a
      // waiting label would flash for one frame on the way out.
      busyLabel: connected ? null : 'Testing',
      // Not "Failed". The outcome card below already names the cause in a
      // sentence the user can act on; the button's job is to say what pressing
      // it again will do.
      failureLabel: connected ? null : 'Test again',
      // Both arms measured now, so the one transition this reservation exists
      // for: the answer moves a word and not the button's width.
      slotLabels: const ['Test connection', 'Test again', _advance],
      dimmed: dimmed && !connected,
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
    this.gateway,
    required this.failureDetail,
    required this.serverVersion,
    this.testedAccess,
    this.onAddAccess,
    this.sharedTokenFrom,
    this.onUseSharedToken,
    this.address,
  });

  final ServiceKey service;
  final ServiceConnectionStatus status;
  final ServiceFailureReason? reason;
  final AccessGatewayAnswer? gateway;
  final String? failureDetail;
  final String? serverVersion;

  /// The access the test sent: a Cloudflare service token's test says what
  /// Access did with it, in the connection form's words.
  final ConnectionAccess? testedAccess;

  /// Takes a gateway's remedy in the step, or null when there is none to
  /// offer (no gateway, or its Access row already on screen).
  final ValueChanged<AccessKind>? onAddAccess;

  /// A token another step passed this Access team with, offered as the
  /// remedy in place of an empty row: `Use Radarr's token`.
  final ServiceKey? sharedTokenFrom;
  final VoidCallback? onUseSharedToken;

  /// `At home · host`, closing the card, when the step asked two addresses.
  final String? address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final presentation = describeConnection(
      service,
      status: status,
      reason: reason,
      gateway: gateway,
    );
    final tone = statusToneColor(scheme, presentation.tone);
    final sentence = switch (status) {
      ServiceConnectionStatus.connected => '${service.title} answered.',
      // The instruction itself is the step's subtitle, standing above the
      // form before anything is pressed, so repeating it here would answer a
      // press with the sentence the user is already looking at. What the press
      // actually found is that there is nothing to send.
      ServiceConnectionStatus.notConfigured => 'Nothing to send yet.',
      // The detail when the failure carried one, the reason-derived sentence
      // otherwise: the same rule `ServiceDiagnosis.messageFor` applies on the
      // settings screen, so the two surfaces cannot describe one test
      // differently.
      _ =>
        failureDetail ??
            connectionFailureMessage(service, reason, gateway: gateway),
    };
    final tokenOutcome = testedAccess is CloudflareServiceToken
        ? cloudflareTokenTestOutcome(
            service,
            answered: status == ServiceConnectionStatus.connected,
            reason: reason,
            gateway: gateway,
          )
        : null;
    // A gateway in front of the service: its remedy, the same verb Home and
    // the connection form offer, opens the Access row right here.
    final sharedFrom = reason == ServiceFailureReason.accessGateway
        ? sharedTokenFrom
        : null;
    final remedy = sharedFrom != null && onUseSharedToken != null
        ? "Use ${sharedFrom.title}'s token"
        : reason == ServiceFailureReason.accessGateway && onAddAccess != null
        ? failureRemedy(
            ServiceFailureReason.accessGateway,
            credential: refusedCredentialOf(service),
            gateway: gateway,
          )
        : null;
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
                  tokenOutcome ?? sentence,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                if (remedy != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton(
                      // An amber fault's remedy is its one amber fill.
                      style: remedyFillStyle(context, compact: true),
                      onPressed: sharedFrom != null && onUseSharedToken != null
                          ? onUseSharedToken
                          : () => onAddAccess!(
                              accessKindForGateway(service, gateway),
                            ),
                      child: Text(remedy),
                    ),
                  ),
                ],
                // What the server said it is running. Amber when the version
                // itself is the problem: "answered" is true and still not the
                // whole answer on a release Cupola cannot drive.
                if (describeServerVersion(service, serverVersion)
                    case final note?) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    note.message,
                    style: theme.textTheme.bodySmall!.copyWith(
                      // Through the tone walk, and told which ground it lands
                      // on: the raw amber measures 1.39:1 on paper, and this
                      // sentence sits on the outcome card's own
                      // `surfaceContainer` rather than on the beat's surface.
                      color: note.isWarning
                          ? statusToneColor(
                              scheme,
                              StatusTone.warning,
                              surface: scheme.surfaceContainer,
                            )
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
                if (address case final address?) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    address,
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
    );
  }
}

/// An answer that is said in a sentence and its lines, with no remedy of
/// its own: `Not checked from here` beside an address that answered, and
/// the one red when neither did. Drawn as [_Outcome] is.
class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({
    super.key,
    required this.tone,
    required this.sentence,
    this.lines = const [],
  });

  final StatusTone tone;
  final String sentence;

  /// Under the sentence, one a line: what it means, then where.
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusToneColor(scheme, tone),
              ),
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
                for (final line in lines) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    line,
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
    );
  }
}

/// `Use https`, under an address refused for `http://` across the internet:
/// the one remedy, in the one amber fill, which puts the same address over
/// https for the next test to check. Nothing while the address is not
/// refused.
class _UseHttps extends StatelessWidget {
  const _UseHttps({
    required this.controller,
    required this.service,
    this.optional = false,
  });

  final TextEditingController controller;
  final ServiceKey service;

  /// The address away, which may also be left empty.
  final bool optional;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) =>
            cleartextRefusal(service, value.text, optional: optional) == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton(
                    onPressed: () =>
                        _OnboardingWalkState._useHttpsIn(controller),
                    style: remedyFillStyle(context, compact: true),
                    child: const Text('Use https'),
                  ),
                ),
              ),
      );
}

/// The self-signed certificate moment, resolved inside the step.
///
/// A modal appearing on top of a failure the user has not read yet is an
/// ambush; on a home lab a server presenting its own certificate is normal,
/// so it gets a state rather than an interruption. [CertTrustContent] is the
/// same content [showCertTrustDialog] wraps in a modal for settings: the
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
  /// caller, the same string [SettingsModel.trustedCertificates] keys on.
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
    // The card's own ground: the rotation's wash over the page, or the plain
    // container. Every red ink inside it, the border included, is measured
    // against this: the tone's fill byte for the wash, its walked colour for
    // anything drawn on it, never the scheme's raw `error`.
    final ground = rotated
        ? Color.alphaBlend(
            statusToneFill(scheme, StatusTone.error).withValues(alpha: 0.12),
            scheme.surfaceContainer,
          )
        : scheme.surfaceContainer;
    final alarm = statusToneColor(scheme, StatusTone.error, surface: ground);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: rotated ? alarm : scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CertTrustContent(
            origin: origin,
            probe: probe,
            previousFingerprint: previousFingerprint,
            sharedWith: sharedWith,
            surface: ground,
          ),
          const SizedBox(height: AppSpacing.md),
          // Rotated gets no visually-affirmative default: an outlined button
          // is what the first-trust case already used, so the escalation is
          // carried by the card's own tint and border above, not by demoting
          // this control further.
          OutlinedButton(
            onPressed: onTrust,
            style: rotated
                ? OutlinedButton.styleFrom(foregroundColor: alarm)
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

/// Paste, beside a secret of the step's Access row.
class _PasteButton extends StatelessWidget {
  const _PasteButton({required this.onPaste});

  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPaste,
    icon: Icon(
      Icons.content_paste_rounded,
      size: 18,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    // The reveal toggle's target, beside which it sits.
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    padding: EdgeInsets.zero,
    tooltip: 'Paste',
  );
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
      container: true,
      button: true,
      label: 'Use port $port',
      onTap: onTap,
      child: ExcludeSemantics(
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
      ),
    );
  }
}

/// Flags a pasted Plex JSON Web Token while it is still being typed.
///
/// A warning rather than an error: the token is well-formed and will work, for
/// seven days. After that it can only be renewed through plex.tv, which Cupola
/// never calls, so the user would be left with a 401 and no way to read it.
String? _plexTokenWarning(String value) => value.trim().startsWith('eyJ')
    ? 'That token expires in 7 days and cannot be renewed here. Paste a '
          'long-lived device token instead.'
    : null;
