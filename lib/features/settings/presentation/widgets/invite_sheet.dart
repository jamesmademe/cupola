import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/a11y_announce.dart';
import 'package:cupola/core/utils/sheet_utils.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/qr_code_view.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_invite.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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

/// What the person who runs a Seerr hands out: the invite as a QR to scan and
/// a link to send, what it cannot do said under it, and nothing secret in
/// either (`SeerrInvite`).
///
/// The invite is made once the server has told its name, since the name is part
/// of it: until then a placeholder holds the QR's place at its exact size, so
/// the sheet does not move, and the code never changes under a camera. A server
/// that does not answer leaves the name out and the invite is made without it.
class InviteSheet extends ConsumerStatefulWidget {
  const InviteSheet({super.key, required this.connectionId});

  /// The saved Seerr connection the invite is for.
  final String connectionId;

  /// The QR tile's side.
  static const qrSide = 232.0;

  /// How long the button says *Link copied* before it offers the copy again.
  static const copiedFor = Duration(seconds: 2);

  @override
  ConsumerState<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<InviteSheet> {
  Timer? _copiedTimer;
  bool _copied = false;
  bool _closing = false;

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

    final facts = ref.watch(seerrServerFactsProvider(widget.connectionId));
    final loading = !facts.hasValue && !facts.hasError;
    final title = facts.hasValue ? facts.requireValue.applicationTitle : null;
    final invite = SeerrInvite.of(connection, settings, title: title);
    final limits = inviteLimitsOf(connection);

    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall!.copyWith(
      color: CupolaThemeColors.of(context).dimText,
    );
    final host = UrlUtils.hostInProse(
      ServiceKey.seerr.extractHost(invite.home) ?? invite.home,
    );
    final named = invite.title == null ? host : '${invite.title} · $host';

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
          Text(
            'They scan this with their phone\'s camera and sign in to Seerr '
            'with their own account.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: loading
                ? Semantics(
                    label: 'Preparing the invite',
                    child: ShimmerPlaceholder.card(
                      width: InviteSheet.qrSide,
                      height: InviteSheet.qrSide,
                    ),
                  )
                : QrCodeView(
                    data: invite.toLink(),
                    size: InviteSheet.qrSide,
                    semanticLabel: 'QR code of the invite',
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(named, textAlign: TextAlign.center, style: dim),
          for (final (index, limit) in limits.indexed) ...[
            SizedBox(height: index == 0 ? AppSpacing.sm : AppSpacing.xs),
            Text(
              _limitSentence(limit),
              textAlign: TextAlign.center,
              style: dim,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            // Not before the invite is made: a link copied now would lack the
            // name the QR is about to carry.
            onPressed: loading ? null : () => _copy(invite),
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
        ],
      ),
    );
  }

  /// What [limit] means for the person the invite is sent to, as the sheet
  /// says it: neutral, since none of them is a fault.
  static String _limitSentence(SeerrInviteLimit limit) => switch (limit) {
    SeerrInviteLimit.homeBehindGateway =>
      'The address at home asks for a token, and an invite never carries one.',
    SeerrInviteLimit.homeOnly =>
      'It works at home: Seerr has no address away from home.',
    SeerrInviteLimit.awayBehindGateway =>
      'It works at home: the address away asks for a token, and an invite '
          'never carries one.',
  };
}
