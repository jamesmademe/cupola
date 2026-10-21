import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/discover/domain/seerr_invite.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_dialog.dart';
import 'package:cupola/features/settings/presentation/widgets/seerr_sign_in_flow.dart';
import 'package:cupola/features/settings/presentation/widgets/seerr_sign_in_steps.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// The way in for a household member: where their Seerr is, then their own
/// account on it.
///
/// Outside the shell, at `/welcome/sign-in`, opened by the Welcome's and the
/// Home at zero's "I have a Seerr account". No ring: the stack is the
/// operator's, and someone who asks for movies and series has none to look
/// at. The sign-in itself is [SeerrSignInFlow], drawn by [SeerrSignInSteps]
/// as the connection's form in Settings draws it.
///
/// Signed in, the connection is saved with the account, the way in is over,
/// and the app opens on the Home of whoever the account makes them.
///
/// An invite ([SeerrInvite]) fills it. A link opened by the system fills the
/// address and waits: a link is not signed, so the person checks the host and
/// taps Continue before anything is sent. A link pasted into the field is an
/// action of the person's own and is read at once, as before. An invite shown
/// in person comes from [pendingInviteProvider], where the receiving screen
/// left it: it carries what a gateway in front of Seerr asks for, so it is
/// never in the location, and the draft reaches the server through that
/// gateway at once.
class RequesterSignInScreen extends ConsumerStatefulWidget {
  const RequesterSignInScreen({
    super.key,
    this.invite = const {},
    this.certificateProber = probeUntrustedCertificate,
  });

  /// The query of the invite's link the screen was opened with, rewritten
  /// here by the router; empty when the door opened it.
  final Map<String, String> invite;

  final CertificateProber certificateProber;

  @override
  ConsumerState<RequesterSignInScreen> createState() =>
      _RequesterSignInScreenState();
}

class _RequesterSignInScreenState extends ConsumerState<RequesterSignInScreen> {
  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  String? _addressProblem;

  /// The connection being drawn up: one id for the whole visit, so a retry
  /// and the sign-in that follows save the same connection.
  late final String _id = _slot();

  /// The empty Seerr slot a first run already holds, else a new one. Saved
  /// under a new id beside an empty first slot, the account was a
  /// connection the audience counted and every Seerr screen skipped: they
  /// read the first, and said Seerr was not set up (15/10).
  ///
  /// Empty means no address and no account. A key may be there without an
  /// address: the iOS keychain outlives the app, so a reinstall finds the
  /// last install's key in a slot nothing else is left in. Signing in takes
  /// it out.
  String _slot() {
    final settings = ref.read(currentSettingsProvider);
    for (final instance in settings.instancesOf(ServiceKey.seerr)) {
      if (instance.url.isEmpty && instance.account == null) return instance.id;
    }
    return ServiceInstance.mintId(
      ServiceKey.seerr,
      settings.instances.map((i) => i.id),
    );
  }

  late final SeerrSignInFlow _flow = SeerrSignInFlow(
    ref: ref,
    connection: _draft,
    certificateProber: widget.certificateProber,
    invitedPin: (url) => _invite?.pinFor(url),
    inviteIsSealed: () => _invite != null && identical(_invite, _sealedInvite),
    consent:
        ({
          required origin,
          required probe,
          previousFingerprint,
          invitedFingerprint,
        }) async =>
            mounted &&
            await showCertTrustDialog(
              context,
              origin: origin,
              probe: probe,
              previousFingerprint: previousFingerprint,
              invitedFingerprint: invitedFingerprint,
            ),
  );

  bool _finishing = false;

  /// The address the problem was said of: it goes when the text changes,
  /// not when the field takes the cursor.
  String? _problemOf;

  /// The invite the address came from, while the address is still its
  /// own: changed by hand, it is an address like any other.
  SeerrInvite? _invite;

  /// The invite the sealed package shown in person handed over, if one did.
  ///
  /// [_invite] is trusted as sealed only while it is this very invite: a link
  /// pasted into the address later replaces [_invite] and is not signed, so
  /// its pin is a hint for the dialog, never a reason to skip it.
  SeerrInvite? _sealedInvite;

  static const _brokenInvite = "This invite isn't whole. Ask for a new one.";

  @override
  void initState() {
    super.initState();
    // Read now, let go of after the frame: a provider is not changed while
    // the tree builds.
    final held = widget.invite.isEmpty ? ref.read(pendingInviteProvider) : null;
    if (widget.invite.isNotEmpty || held != null) {
      final invite = held ?? SeerrInvite.fromQuery(widget.invite);
      if (invite == null) {
        _problemOf = '';
        _addressProblem = _brokenInvite;
      } else {
        _sealedInvite = held;
        _take(invite);
        // A link opened by the system waits for Continue: the person has not
        // seen the host yet, and a link anyone can compose must not make the
        // app dial it on its own. The sealed package shown in person is the
        // one arrival that is already a deliberate act, and it goes at once.
        if (held != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(pendingInviteProvider.notifier).take();
            _flow.readServer();
          });
        }
      }
    }
    _address.addListener(_onAddress);
  }

  void _onAddress() {
    final text = _address.text;
    if (SeerrInvite.mentionsInvite(text)) {
      final invite = SeerrInvite.tryParse(text);
      if (invite == null) {
        _problemOf = text;
        setState(() => _addressProblem = _brokenInvite);
        return;
      }
      // Out of the field's own change: the paste is still being applied.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _take(invite);
        _continue();
      });
      setState(() {});
      return;
    }
    if (_invite case final invite?
        when UrlUtils.normalizeBaseUrl(text) != invite.home) {
      _invite = null;
    }
    if (_addressProblem != null && text != _problemOf) {
      setState(() => _addressProblem = null);
    }
  }

  /// Takes [invite]: its address at home in the field, the rest held.
  void _take(SeerrInvite invite) {
    _invite = invite;
    _address.value = TextEditingValue(
      text: invite.home,
      selection: TextSelection.collapsed(offset: invite.home.length),
    );
  }

  @override
  void dispose() {
    _flow.dispose();
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  ServiceInstance _draft() =>
      _invite?.draft(_id) ??
      ServiceInstance(
        id: _id,
        service: ServiceKey.seerr,
        url: UrlUtils.normalizeBaseUrl(_address.text.trim()),
      );

  void _continue() {
    final typed = _address.text.trim();
    final problem = typed.isEmpty
        ? 'Add the address of your Seerr'
        : UrlUtils.validateServiceHost(typed);
    if (problem != null) {
      _problemOf = _address.text;
      setState(() => _addressProblem = problem);
      _addressFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _addressProblem = null);
    _flow.readServer();
  }

  /// Back to the address, with what was read of the server forgotten.
  void _checkAddress() {
    _flow.restart();
    _addressFocus.requestFocus();
  }

  void _useHttps() {
    _address.text = _address.text.trim().replaceFirst(
      RegExp('^http://', caseSensitive: false),
      'https://',
    );
    _flow.restart();
    _flow.readServer();
  }

  /// Every way in is off: the server's key is what is left, and that is the
  /// operator's way, Connect with Seerr proposed.
  void _useApiKey() => context.go(ServiceRoutes.welcomeConnect);

  void _back() {
    if (_flow.stage != SeerrSignInStage.start || _flow.facts != null) {
      _flow.restart();
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(ServiceRoutes.welcome);
    }
  }

  Future<void> _signedIn() async {
    if (_finishing) return;
    _finishing = true;
    HapticFeedback.mediumImpact();
    await markOnboardingComplete(ref);
    // Nothing is under the finger: the screen it is on goes away now.
    ref.read(shellAudienceProvider.notifier).take();
    if (mounted) context.go(ServiceRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      currentSettingsProvider.select(
        (s) => s.instanceById(_id)?.account?.isSignedIn ?? false,
      ),
      (previous, next) {
        if (next) _signedIn();
      },
    );
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                top: AppSpacing.xs,
              ),
              child: BackButton(onPressed: _back),
            ),
            Expanded(
              // A form, read from the top as Connect's is: centred, it sat
              // mid-screen with a hole above, and jumped when the keyboard
              // came up.
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    padding: onboardingPadding.copyWith(top: AppSpacing.xl),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: SeerrSignInSteps(
                      flow: _flow,
                      onUseApiKey: _useApiKey,
                      onCheckAddress: _checkAddress,
                      onUseHttps: _useHttps,
                      heading: theme.textTheme.headlineSmall!.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      start: _addressStep,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _addressStep(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Semantics(
        header: true,
        child: Text(
          'Where is your Seerr?',
          style: theme.textTheme.headlineSmall!.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      OnboardingField(
        key: const ValueKey('seerr address'),
        controller: _address,
        focusNode: _addressFocus,
        label: 'Seerr address',
        hint: 'nas.home.arpa:5055',
        help: 'Whoever runs your server can tell you, or send you an invite.',
        isUrl: true,
        problem: _addressProblem,
        action: TextInputAction.go,
        onSubmitted: (_) => _continue(),
      ),
      if (_invite != null && !identical(_invite, _sealedInvite)) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Check the address above before continuing. A link is not signed: '
          'continue only if you trust whoever sent it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.xl),
      SeerrSignInPrimary(label: 'Continue', onPressed: _continue),
    ];
  }
}
