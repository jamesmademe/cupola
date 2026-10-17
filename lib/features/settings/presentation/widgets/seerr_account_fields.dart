import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/discover/presentation/seerr_sign_in_notice.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_dialog.dart';
import 'package:cupola/features/settings/presentation/widgets/seerr_sign_in_flow.dart';
import 'package:cupola/features/settings/presentation/widgets/seerr_sign_in_steps.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// How a Seerr connection signs in: the instance's API key, or an account of
/// one's own.
enum SeerrSignInWith {
  apiKey('API key'),
  account('An account');

  const SeerrSignInWith(this.label);

  final String label;
}

/// The account half of a Seerr connection's form: signing in, signed in, and
/// signed out.
///
/// The minimal way in, inside the connection's own settings. The sign-in
/// itself is [SeerrSignInFlow], drawn by [SeerrSignInSteps], as the first
/// run's sign-in draws it; this adds what only a saved connection has: who is
/// signed in, signing out, signing in again.
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

class _SeerrAccountFieldsState extends ConsumerState<SeerrAccountFields> {
  late final SeerrSignInFlow _flow = SeerrSignInFlow(
    ref: ref,
    connection: () => widget.connection(),
    certificateProber: widget.certificateProber,
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

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  ServiceInstance get _connection => widget.connection();

  /// What the server calls itself: from the methods read, else from what
  /// the saved account's server said, else Seerr.
  String get _title => _flow.facts?.title ?? _savedTitle ?? 'Seerr';

  String? _savedTitle;

  Future<void> _signOut(SeerrAccountSignIn account) => confirmSeerrSignOut(
    context,
    ref,
    connectionId: _connection.id,
    account: account,
    title: _title,
  );

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.instanceById(_connection.id)?.account,
      ),
    );
    // Only for a saved account: a key's form has no title to name.
    if (account != null) {
      _savedTitle = ref
          .watch(seerrServerFactsProvider(_connection.id))
          .whenOrNull(data: (facts) => facts.title);
    }
    return SeerrSignInSteps(
      flow: _flow,
      onUseApiKey: widget.onUseApiKey,
      onCheckAddress: widget.onCheckAddress,
      onUseHttps: widget.onUseHttps,
      start: (context) => _start(context, account),
    );
  }

  List<Widget> _start(BuildContext context, SeerrAccountSignIn? account) {
    final notice = _flow.notice;
    if (account != null && account.isSignedIn) {
      return [_signedInBlock(context, account)];
    }
    if (account != null) {
      return [
        if (notice == null) ...[
          SeerrSignInNoticeLine(notice: _signedOutNotice, actions: const []),
          const SizedBox(height: AppSpacing.md),
        ],
        SeerrSignInPrimary(
          label: Lexicon.signInAgain,
          onPressed: () => _flow.readServer(again: account),
        ),
      ];
    }
    return [
      if (notice == null ||
          notice.kind != SeerrSignInNoticeKind.turnedOff &&
              notice.kind != SeerrSignInNoticeKind.notSetUp)
        SeerrSignInPrimary(label: 'Continue', onPressed: _flow.readServer),
    ];
  }

  SeerrSignInNotice get _signedOutNotice =>
      ref.read(shellAudienceProvider) == Audience.requester
      ? SeerrSignInNotice.youWereSignedOut
      : SeerrSignInNotice.signedOut(_title);

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
                  '$title\u00A0· ${_flow.host}',
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
}

/// Asks before signing [account] out of the Seerr called [title], then signs
/// it out. The form's button and the requester's account page both end here.
Future<void> confirmSeerrSignOut(
  BuildContext context,
  WidgetRef ref, {
  required String connectionId,
  required SeerrAccountSignIn account,
  required String title,
}) async {
  final result = await showAppConfirmDialog(
    context: context,
    icon: Icons.logout_rounded,
    title: 'Sign out of $title?',
    message: account.kind == SeerrAccountKind.plex
        ? "You'll sign in with Plex again."
        : "You'll need your password to sign in again.",
    confirmLabel: Lexicon.signOut,
  );
  if (!result.confirmed || !context.mounted) return;
  await ref.read(seerrAccountsProvider).signOut(connectionId);
}
