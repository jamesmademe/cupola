import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/notice_line.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/domain/pair_link.dart';
import 'package:cupola/features/pairing/domain/pair_plan.dart';
import 'package:cupola/features/pairing/presentation/pair_scan_screen.dart';
import 'package:cupola/features/pairing/presentation/pair_words.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/seerr_sign_in_steps.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// Copying everything from another device: where its code comes from, what
/// arrived, and the one button that adds it.
///
/// Outside the shell, at `/welcome/pair`, framed as the sign-in with an
/// account is: opened by the Welcome's and the Home at zero's *Copy from
/// another device*, by Settings' row of the same name, and by the other
/// device's code scanned with the camera (the system camera opens
/// `cupola://pair`, which the router takes off the location and holds for
/// [pairReceiveProvider]; on a phone *Scan code* reads it here,
/// [PairScanScreen]). A link pasted into the field starts the same fetch.
///
/// **The key never stays in the field**: a link, whole or not, is taken out of
/// it the moment it is read, and the screen says only what the link is for.
/// Nothing is written until *Add*, and what is written only ever adds: a
/// connection the device already has is left as it is ([PairPlan]).
///
/// **An invite shown in person** arrives here too (its link says so): the
/// screen reads *Your invite* while it fetches, and hands over to the sign-in,
/// already filled ([pendingInviteProvider]), or to the Seerr this device
/// already has at the invite's addresses, filled where it lacked something.
class PairReceiveScreen extends ConsumerStatefulWidget {
  const PairReceiveScreen({super.key});

  @override
  ConsumerState<PairReceiveScreen> createState() => _PairReceiveScreenState();
}

class _PairReceiveScreenState extends ConsumerState<PairReceiveScreen> {
  final _link = TextEditingController();
  final _linkFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _link.addListener(_onLink);
  }

  @override
  void dispose() {
    _link.dispose();
    _linkFocus.dispose();
    super.dispose();
  }

  /// A link in the field, alone or inside a message: fetched, and gone from
  /// the field. Something that names a pairing link and does not read says so.
  void _onLink() {
    final text = _link.text;
    final link = PairLink.tryParse(text);
    final notifier = ref.read(pairReceiveProvider.notifier);
    if (link != null) {
      _emptyAfterThePaste();
      notifier.receive(link);
    } else if (PairLink.mentionsPair(text)) {
      _emptyAfterThePaste();
      notifier.notWhole();
    }
  }

  /// Out of the field's own change: the paste is still being applied.
  void _emptyAfterThePaste() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _link.clear();
      });

  void _back() {
    final state = ref.read(pairReceiveProvider);
    // An invite came from a code someone else showed: there is no step of
    // this screen's to go back to.
    if (state is PairReceiveFailed && state.invite) {
      _leave();
      return;
    }
    if (state is! PairReceiveWaiting && state is! PairReceiveAdding) {
      ref.read(pairReceiveProvider.notifier).reset();
      return;
    }
    _leave();
  }

  /// Back where the visit came from: the screen under this one, else the
  /// Welcome on a first run and the Home otherwise.
  void _leave() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final settings = ref.read(currentSettingsProvider);
    final welcome = showsWelcome(
      onboardingCompleted: ref.read(onboardingCompletedProvider),
      settings: settings,
    );
    context.go(welcome ? ServiceRoutes.welcome : ServiceRoutes.home);
  }

  void _goHome() => context.go(ServiceRoutes.home);

  Future<void> _scan() async {
    _linkFocus.unfocus();
    final link = await PairScanScreen.open(context);
    if (link == null || !mounted) return;
    ref.read(pairReceiveProvider.notifier).receive(link);
  }

  /// Where an invite that arrived goes on: the sign-in, filled, or the Seerr
  /// already here (the account's page, or the connection's form when it
  /// signs in with the key), as an invite's link does.
  void _goOn(PairReceiveInvited invited) {
    final here = invited.here;
    if (here == null) {
      context.go(ServiceRoutes.welcomeSignIn);
      return;
    }
    if (invited.updated) {
      SnackBarHelper.success(context, 'Updated from the invite');
    }
    context.go(
      here.account != null
          ? ServiceRoutes.settingsAccountFor(instanceId: here.id)
          : ServiceRoutes.settingsForConnection(ServiceKey.seerr, here.id),
    );
  }

  /// Whether the screen is opening an invite rather than copying a device.
  static bool _invite(PairReceiveState state) => switch (state) {
    PairReceiveFetching(:final invite) => invite,
    PairReceiveFailed(:final invite) => invite,
    PairReceiveInvited() => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    ref.listen<PairReceiveState>(pairReceiveProvider, (_, next) {
      if (next is PairReceiveAdded) {
        // The way in is over and nothing is under the finger: the shell is
        // drawn for whoever the connections make this device's person.
        HapticFeedback.mediumImpact();
        ref.read(shellAudienceProvider.notifier).take();
        _goHome();
      } else if (next is PairReceiveInvited) {
        _goOn(next);
      }
    });
    final state = ref.watch(pairReceiveProvider);
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
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    padding: onboardingPadding.copyWith(top: AppSpacing.xl),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            _invite(state)
                                ? 'Your invite'
                                : 'Copy from another device',
                            style: theme.textTheme.headlineSmall!.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ..._body(context, state),
                      ],
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

  List<Widget> _body(BuildContext context, PairReceiveState state) =>
      switch (state) {
        PairReceiveWaiting() => _waiting(context),
        PairReceiveFetching(:final invite) => [
          SeerrSignInBusy(
            invite ? 'Opening the invite' : 'Fetching from the other device',
          ),
        ],
        // The listener goes on: this frame draws the wait it ends.
        PairReceiveInvited() => const [SeerrSignInBusy('Opening the invite')],
        PairReceiveFailed() => _failed(context, state),
        PairReceivePreview(:final plan) => _preview(context, plan),
        PairReceiveAdding(:final plan) => _preview(context, plan, adding: true),
        // The listener leaves for the Home: this frame draws what was there.
        PairReceiveAdded(:final plan) => _preview(context, plan, adding: true),
      };

  /// Whether this device has no camera to point at a code: a computer, where
  /// the link is copied and pasted.
  static bool get _pastesTheLink => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };

  List<Widget> _waiting(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text(
        _pastesTheLink
            ? 'On the device that has Cupola set up, open Settings › Set up '
                  'another device, copy its link and paste it here.'
            : 'On the device that has Cupola set up, open Settings › Set up '
                  'another device, then scan its code.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: AppSpacing.xl),
      if (!_pastesTheLink) ...[
        FilledButton.icon(
          key: const ValueKey('pair scan'),
          onPressed: _scan,
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.standard,
            minimumSize: const Size(64, 44),
          ),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan code'),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
      OnboardingField(
        key: const ValueKey('pair link'),
        controller: _link,
        focusNode: _linkFocus,
        label: 'Link from the other device',
        action: TextInputAction.done,
      ),
    ];
  }

  List<Widget> _failed(BuildContext context, PairReceiveFailed state) {
    final notice = state.invite
        ? state.failure.inviteNotice
        : state.failure.notice;
    final notifier = ref.read(pairReceiveProvider.notifier);
    // What arrived and could not be written: an amber fault whose remedy is
    // Retry, so Retry takes the fill (Start again would throw the code away).
    final retryFills =
        state.retryHelps && state.failure == PairReceiveFailure.notSaved;
    return [
      NoticeLine(
        tone: notice.tone,
        title: notice.headline,
        sentence: notice.sentence,
        actions: [
          if (state.retryHelps)
            noticeAction(
              context,
              Lexicon.retry,
              notifier.retry,
              fill: retryFills ? notice.tone : null,
            ),
          // An invite's remedy is a new code from the person who showed it:
          // nothing here starts again.
          if (!state.invite)
            noticeAction(
              context,
              'Start again',
              notifier.reset,
              fill: notice.fillsStartAgain ? notice.tone : null,
            ),
        ],
      ),
    ];
  }

  List<Widget> _preview(
    BuildContext context,
    PairPlan plan, {
    bool adding = false,
  }) {
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall!.copyWith(
      color: CupolaThemeColors.of(context).dimText,
    );
    final notifier = ref.read(pairReceiveProvider.notifier);
    final counts = pairPlanCounts(plan);
    final notes = pairPlanNotes(plan);
    return [
      Semantics(
        header: true,
        child: Text(
          'From ${plan.from.phrase}',
          style: theme.textTheme.titleMedium!.weight(FontWeight.w600),
        ),
      ),
      if (counts.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(counts, style: dim),
      ],
      if (plan.toAdd.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        SettingsGroupCard(
          children: [for (final c in plan.toAdd) _ConnectionRow(c)],
        ),
      ],
      // A pin is a trust decision, so the origins it applies to are named
      // rather than counted: the person can see that this copy also trusts a
      // certificate, and exactly where.
      if (plan.certificates.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        SettingsGroupCard(
          children: [
            for (final origin in plan.certificates.keys)
              _CertificateRow(origin),
          ],
        ),
      ],
      for (final note in notes) ...[
        const SizedBox(height: AppSpacing.md),
        _Note(note),
      ],
      const SizedBox(height: AppSpacing.xl),
      if (plan.addsAnything) ...[
        if (adding)
          SeerrSignInBusy(pairAddLabel(plan))
        else
          SeerrSignInPrimary(
            label: pairAddLabel(plan),
            onPressed: notifier.add,
          ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: adding ? null : notifier.reset,
          style: retryInkStyle(Theme.of(context).colorScheme),
          child: const Text('Start again'),
        ),
      ] else ...[
        Text(
          plan.alreadyHere.isEmpty
              ? 'Nothing to add from ${plan.from.phrase}.'
              : 'Everything from ${plan.from.phrase} is already here.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        SeerrSignInPrimary(label: 'Done', onPressed: _goHome),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: notifier.reset,
          style: retryInkStyle(Theme.of(context).colorScheme),
          child: const Text('Start again'),
        ),
      ],
    ];
  }
}

/// One origin whose certificate the copy would trust.
class _CertificateRow extends StatelessWidget {
  const _CertificateRow(this.origin);

  final String origin;

  @override
  Widget build(BuildContext context) {
    final shown = origin.startsWith('https://')
        ? origin.substring('https://'.length)
        : origin;
    return SettingsCard.grouped(
      leading: const Icon(Icons.verified_user_outlined),
      title: 'Trusted certificate',
      subtitle: shown,
      semanticLabel: 'Trusted certificate for $shown',
    );
  }
}

/// One connection that arrives: its mark, its title (the label when it has
/// one), and where it is, dim. Read as one sentence.
class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow(this.connection);

  final ServiceInstance connection;

  @override
  Widget build(BuildContext context) {
    final address = connection.url;
    final host = UrlUtils.hostInProse(
      connection.service.extractHost(address) ?? address,
    );
    final title = serviceWithConnection(connection.service, connection.label);
    return SettingsCard.grouped(
      leading: Icon(connection.service.icon),
      title: title,
      subtitle: host,
      semanticLabel: '$title at $host',
    );
  }
}

/// A fact about what arrives, said once under the connections: neutral, since
/// none of them is a fault.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = CupolaThemeColors.of(context).dimText;
    return Semantics(
      container: true,
      label: text,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.info_outline_rounded, size: 16, color: dim),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(color: dim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
