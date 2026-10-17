import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/a11y_announce.dart';
import 'package:cupola/core/utils/sheet_utils.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/notice_line.dart';
import 'package:cupola/core/widgets/qr_code_view.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_invite.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/pairing/presentation/pair_code.dart';
import 'package:cupola/features/pairing/presentation/pair_words.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/seerr_sign_in_steps.dart';

/// Opens the operator's invite for the Seerr connection [connectionId]: a QR
/// and a link a household member opens Cupola with, to sign in with an
/// account of their own.
Future<void> showInviteSheet(
  BuildContext context, {
  required String connectionId,
}) => SheetUtils.showCupolaModalSheet<void>(
  context: context,
  // The panel is the sheet's own (`AppBottomSheet`).
  backgroundColor: Colors.transparent,
  builder: (_) => InviteSheet(connectionId: connectionId),
);

/// What the person who runs a Seerr hands out, in one of two ways.
///
/// **A link**, as a QR to scan and a link to send ([SeerrInvite]): nothing
/// secret in either, and what it cannot do said under it. Made at once from
/// the saved connection: it carries no name, so nothing holds the code back.
/// The line under the code names the server once the server has answered
/// (`<name> · <host>`) and is the host alone before that, or when it never
/// does; the code and the link do not change.
///
/// **In person**, when an address of the server asks for a token a link
/// never carries ([invitesInPerson]): a code that works once, for two
/// minutes, on the same Wi-Fi, which hands over Seerr with what its
/// addresses ask for and never the key ([PairPackage.invite]). The sheet
/// opens on it whenever it applies, the link one tap away (*Send a link
/// instead*), and closes the code when it turns to the link or goes.
class InviteSheet extends ConsumerStatefulWidget {
  const InviteSheet({super.key, required this.connectionId});

  /// The saved Seerr connection the invite is for.
  final String connectionId;

  /// The QR tile's side.
  static const qrSide = PairCodeSlot.side;

  /// How long the button says *Link copied* before it offers the copy again.
  static const copiedFor = Duration(seconds: 2);

  @override
  ConsumerState<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<InviteSheet> {
  Timer? _copiedTimer;
  bool _copied = false;
  bool _closing = false;

  /// The person's choice of the link over the code shown in person; the code
  /// until they make it.
  bool _byLink = false;

  /// Whether the code shown in person was asked for since the sheet last
  /// turned to it.
  bool _codeAsked = false;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(SeerrInvite invite) async {
    await Clipboard.setData(ClipboardData(text: invite.toLink()));
    if (!mounted) return;
    setState(() => _copied = true);
    // The label changes under a focused button, which a screen reader does not
    // read by itself.
    announce(context, 'Link copied');
    _copiedTimer?.cancel();
    _copiedTimer = Timer(InviteSheet.copiedFor, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _makeCode() => ref
      .read(inviteOfferProvider.notifier)
      .start(
        from: PairDevice.of(
          defaultTargetPlatform,
          tablet: MediaQuery.sizeOf(context).shortestSide >= 600,
        ),
        inviteTo: widget.connectionId,
      );

  /// Turns the sheet to the link, or back to the code. Leaving the code
  /// stops watching it, and the code closes with its provider.
  void _turn({required bool byLink}) {
    setState(() {
      _byLink = byLink;
      _codeAsked = false;
    });
    announce(
      context,
      byLink ? 'The invite is a link' : 'The invite is a code to scan here',
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final connection = settings.instanceById(widget.connectionId);
    if (connection == null) {
      // Removed while the sheet was open: nothing is left to invite to.
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const SizedBox.shrink();
    }

    final invite = SeerrInvite.of(connection, settings);
    // Only the line under the code: the invite never waits for it.
    final title = ref
        .watch(seerrServerFactsProvider(widget.connectionId))
        .value
        ?.applicationTitle;
    final host = UrlUtils.hostInProse(
      ServiceKey.seerr.extractHost(invite.home) ?? invite.home,
    );
    final named = title == null ? host : '$title\u00A0· $host';
    final inPerson = invitesInPerson(connection);

    final theme = Theme.of(context);
    return AppBottomSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Invite someone',
              style: theme.textTheme.titleLarge!.weight(FontWeight.w600),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (inPerson && !_byLink)
            ..._inPerson(context, connection, named)
          else
            ..._byLinkBody(context, connection, invite, named, inPerson),
        ],
      ),
    );
  }

  List<Widget> _inPerson(
    BuildContext context,
    ServiceInstance connection,
    String named,
  ) {
    final offer = ref.watch(inviteOfferProvider);
    if (!_codeAsked) {
      _codeAsked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _makeCode();
      });
    }
    final theme = Theme.of(context);
    final dim = _dim(context);
    final colorScheme = theme.colorScheme;
    final limits = inviteLimitsOf(connection);
    return [
      Text(
        'On your Wi-Fi, they scan this with their phone\'s camera and sign in '
        'to Seerr with their own account.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: AppSpacing.xl),
      ...switch (offer) {
        PairOfferPreparing() => [
          const PairCodeSlot(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
        PairOfferOpen(:final link) => [
          Center(
            child: QrCodeView(
              data: link.toLink(),
              size: InviteSheet.qrSide,
              semanticLabel: 'QR code of the invite',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(named, textAlign: TextAlign.center, style: dim),
          const SizedBox(height: AppSpacing.xs),
          PairCountdown(
            closesAt: link.closesAt,
            now: ref.read(pairNetworkProvider).now,
            style: dim,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(_carries(limits), textAlign: TextAlign.center, style: dim),
          if (defaultTargetPlatform == TargetPlatform.macOS) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'If your Mac asks, allow Cupola to accept incoming connections.',
              textAlign: TextAlign.center,
              style: dim,
            ),
          ],
        ],
        PairOfferSent() => [
          PairCodeSlot(
            child: Icon(
              Icons.check_rounded,
              size: 72,
              color: statusToneColor(
                colorScheme,
                StatusTone.success,
                surface: colorScheme.surfaceContainer,
              ),
            ),
          ),
          PairCodeOutcome(
            title: 'They have the invite',
            why:
                'They sign in to Seerr on their phone now. The code is '
                'closed.',
            primary: SeerrSignInPrimary(
              label: 'Done',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
        PairOfferClosed(:final how) => [
          PairCodeSlot(
            child: Icon(
              Icons.qr_code_2_rounded,
              size: 72,
              color: statusToneColor(
                colorScheme,
                StatusTone.neutral,
                surface: colorScheme.surfaceContainer,
              ),
            ),
          ),
          PairCodeOutcome(
            title: 'The code closed',
            why: pairClosedBecause(how),
            primary: SeerrSignInPrimary(
              label: 'Make a new code',
              onPressed: _makeCode,
            ),
          ),
        ],
        PairOfferNoNetwork() => [
          NoticeLine(
            tone: StatusTone.info,
            title: 'Join your Wi-Fi to invite in person',
            sentence: 'Their phone fetches the invite over your home network.',
            actions: [noticeAction(context, Lexicon.retry, _makeCode)],
          ),
        ],
        PairOfferFailed() => [
          NoticeLine(
            tone: StatusTone.warning,
            title: 'Cupola could not open the code',
            sentence: 'Wait a moment, then make a new code.',
            actions: [
              noticeAction(
                context,
                'Make a new code',
                _makeCode,
                fill: StatusTone.warning,
              ),
            ],
          ),
        ],
      },
      if (offer is! PairOfferSent) ...[
        const SizedBox(height: AppSpacing.xl),
        _ink(context, 'Send a link instead', () => _turn(byLink: true)),
        Text(_linkFallsShort(limits), textAlign: TextAlign.center, style: dim),
      ],
    ];
  }

  List<Widget> _byLinkBody(
    BuildContext context,
    ServiceInstance connection,
    SeerrInvite invite,
    String named,
    bool inPerson,
  ) {
    final theme = Theme.of(context);
    final dim = _dim(context);
    final limits = inviteLimitsOf(connection);
    return [
      Text(
        'They scan this with their phone\'s camera and sign in to Seerr '
        'with their own account.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: AppSpacing.xl),
      Center(
        child: QrCodeView(
          data: invite.toLink(),
          size: InviteSheet.qrSide,
          semanticLabel: 'QR code of the invite',
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(named, textAlign: TextAlign.center, style: dim),
      for (final (index, limit) in limits.indexed) ...[
        SizedBox(height: index == 0 ? AppSpacing.sm : AppSpacing.xs),
        Text(_limitSentence(limit), textAlign: TextAlign.center, style: dim),
      ],
      const SizedBox(height: AppSpacing.xl),
      FilledButton.icon(
        onPressed: () => _copy(invite),
        icon: Icon(
          _copied ? Icons.check_rounded : Icons.link_rounded,
          size: 18,
        ),
        label: Text(_copied ? 'Link copied' : 'Copy link'),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        'Sent as a message, they paste it where Cupola asks where their '
        'Seerr is.',
        textAlign: TextAlign.center,
        style: dim,
      ),
      if (inPerson) ...[
        const SizedBox(height: AppSpacing.lg),
        _ink(context, 'Invite in person instead', () => _turn(byLink: false)),
      ],
    ];
  }

  static TextStyle _dim(BuildContext context) => Theme.of(
    context,
  ).textTheme.bodySmall!.copyWith(color: CupolaThemeColors.of(context).dimText);

  static Widget _ink(
    BuildContext context,
    String label,
    VoidCallback onPressed,
  ) => Center(
    child: TextButton(
      onPressed: onPressed,
      style: retryInkStyle(Theme.of(context).colorScheme),
      child: Text(label),
    ),
  );

  /// What the code shown in person carries that the link does not, and
  /// what it never carries.
  static String _carries(List<SeerrInviteLimit> limits) {
    final home = limits.contains(SeerrInviteLimit.homeBehindGateway);
    final away = limits.contains(SeerrInviteLimit.awayBehindGateway);
    final what = home && away
        ? 'the tokens both addresses ask for'
        : home
        ? 'the token the address at home asks for'
        : 'the token the address away asks for';
    return "It brings $what. Seerr's key stays here.";
  }

  /// Why the link does less, said under *Send a link instead*.
  static String _linkFallsShort(List<SeerrInviteLimit> limits) =>
      limits.contains(SeerrInviteLimit.homeBehindGateway)
      ? 'A link never carries a token: they would be asked for it.'
      : 'A link works only at home: it never carries a token.';

  /// What [limit] means for the person the invite is sent to, as the sheet
  /// says it: neutral, since none of them is a fault.
  static String _limitSentence(SeerrInviteLimit limit) => switch (limit) {
    SeerrInviteLimit.homeBehindGateway =>
      'The address at home asks for a token, and a link never carries one.',
    SeerrInviteLimit.homeOnly =>
      'It works at home: Seerr has no address away from home.',
    SeerrInviteLimit.awayBehindGateway =>
      'It works at home: the address away asks for a token, and a link '
          'never carries one.',
  };
}
