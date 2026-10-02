import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/discover/presentation/discover_detail_extras_provider.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/discover_navigation_utils.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_videos_button.dart';
import 'package:cupola/features/discover/presentation/widgets/manage_media_sheet.dart';
import 'package:cupola/features/discover/presentation/widgets/request_bottom_sheet.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Action buttons for the discover detail screen header.
///
/// One expanded request action plus at most two captioned icon actions: the
/// trailers, when Seerr sent any, and either Manage or the jump into Radarr
/// or Sonarr. Never six.
///
/// This is the Discover page's region-1 deck, so the same rule
/// [LibraryDetailActions] carries applies: **never pad this widget.** The detail
/// spine already wraps `deck` in the resolved gutter and the gap above it. When
/// this widget carried its own `symmetric(horizontal: lg, vertical: md)` the
/// Discover action row sat 32pt in and 12pt lower than every other page's deck —
/// the two insets compounded rather than replacing one another.
class DiscoverActionButtons extends ConsumerWidget {
  final int mediaId;
  final String mediaType;
  final bool hasManageableMedia;

  /// What this stack's own Radarr (or Sonarr) said about the title: it holds
  /// it, it does not, or null when Cupola could not say — that service is not
  /// set up here, the lookup is still out, or it failed.
  final bool? isInService;

  /// Whether Seerr would take a request now, and why not when it would not.
  /// Read from Seerr's record alone ([seerrRequestGate]).
  final SeerrRequestGate requestGate;
  final int? tvdbId;
  final Map<String, dynamic>? mediaInfo;
  final String title;
  final double? voteAverage;

  /// Related videos for the Trailers button.
  final List<RelatedVideo> videos;

  const DiscoverActionButtons({
    super.key,
    required this.mediaId,
    required this.mediaType,
    required this.hasManageableMedia,
    required this.isInService,
    required this.requestGate,
    required this.tvdbId,
    required this.mediaInfo,
    required this.title,
    required this.voteAverage,
    required this.videos,
  });

  String get _normalizedMediaType => mediaType == 'movie' ? 'movie' : 'tv';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMovie = _normalizedMediaType == 'movie';
    final arr = isMovie ? ServiceKey.radarr : ServiceKey.sonarr;
    final serviceName = arr.title;
    // The page reads the lens's Seerr, so its gate is the lens's: a
    // requester reads no service name and no operator's control here, and an
    // account that may not do something says so on the control.
    final gate = ref.watch(roleGateProvider(''));
    final namesSeerr = gate.namesService(ServiceKey.seerr);
    final namesArr = gate.namesService(arr);
    // The page's one primary is the ink button, the same on every page: a
    // request is not Seerr-coloured, it is the thing this page is for.
    final room = CupolaRoom.of(context);

    // "Requested" is the wrong word for a title that is already on disk, and a
    // disabled button with no explanation is a dead end. So the label states the
    // actual state and a single line underneath says why nothing is offered.
    //
    // Seerr's own state, and nothing else. Any media row used to read as
    // "Requested · Radarr is already tracking this.", which disabled Request
    // for a series with seasons still to ask for, for a title whose files
    // were deleted, and on a stack whose Radarr is known only through Seerr.
    final String requestLabel;
    final IconData requestIcon;
    final String? disabledReason;
    switch (requestGate.state) {
      case SeerrRequestState.available:
        requestLabel = 'Available';
        requestIcon = Icons.check_circle_outline_rounded;
        disabledReason = 'Already in your library, nothing to request.';
      case SeerrRequestState.waitingForApproval:
        requestLabel = 'Requested';
        requestIcon = Icons.check_circle_outline_rounded;
        disabledReason = namesSeerr
            ? 'Waiting for approval in Seerr.'
            : Lexicon.requestWaiting;
      case SeerrRequestState.onItsWay:
        requestLabel = 'Requested';
        requestIcon = Icons.check_circle_outline_rounded;
        disabledReason = namesArr
            ? '$serviceName is already tracking this.'
            : Lexicon.onItsWay;
      case SeerrRequestState.failed:
        // Seerr takes no second request while this one stands, and the row
        // that can remove it is under Manage.
        requestLabel = 'Request failed';
        requestIcon = Icons.error_outline_rounded;
        disabledReason = namesSeerr && namesArr
            ? 'Seerr could not send the last request to $serviceName.'
            : Lexicon.lastRequestFailed;
      case SeerrRequestState.blocklisted:
        // The operator's own choice, made in Seerr: neutral, and nothing to
        // fix from here. Seerr refuses any request for it.
        requestLabel = StateWord.blocklisted.label;
        requestIcon = Icons.block_rounded;
        disabledReason = namesSeerr
            ? 'Blocklisted in Seerr, which takes no request for it.'
            : Lexicon.blockedByOwner;
      case SeerrRequestState.open:
        requestLabel = 'Request';
        requestIcon = Icons.add_circle_outline_rounded;
        disabledReason = null;
    }
    // A series partly held already: which seasons a request would add, since
    // the request asks for every season Seerr does not have yet.
    final missing = requestGate.missingSeasons;
    // Open for the 4K copy alone: the standard one is on disk or asked for
    // already, so a request now asks for 4K, and the sheet offers only the
    // 4K servers. Said, since the badge above may read "Available".
    final only4k = requestGate.copies == SeerrRequestCopies.uhd;
    final requestNote = missing.isEmpty
        ? (only4k ? 'Only the 4K copy can be requested.' : null)
        : '${missing.length == 1 ? 'Season' : 'Seasons'} '
              '${Lexicon.names(missing.map((season) => '$season'))} '
              '${missing.length == 1 ? 'is' : 'are'} not requested '
              '${only4k ? 'in 4K ' : ''}yet.';
    final canRequest = disabledReason == null;
    // Open, Seerr would take a request: whether this account may ask for
    // this kind at all. One that may not keeps Request, dimmed, and says why
    // under it and on a tap.
    final requestVerdict = canRequest
        ? gate.requestAction(isMovie ? SeerrMediaKind.movie : SeerrMediaKind.tv)
        : const Live();
    final note = disabledReason ?? requestVerdict.reason ?? requestNote;
    final openAction = namesArr ? _openAction(context, ref) : null;
    // Manage is the operator's: absent from the requester's app, dimmed for
    // an account of the operator's that may not manage media.
    final manage = gate.operatorAction(SeerrAbility.manageMedia);

    Widget requestButton(
      VoidCallback? onPressed,
      Widget Function(Widget content) annotate,
    ) => FilledButton.icon(
      onPressed: onPressed,
      // The glyph drains with the label; the hint rides on the label alone,
      // so it is heard once.
      icon: Opacity(
        opacity: requestVerdict.acts ? 1 : GatedAffordance.dimmedOpacity,
        child: Icon(requestIcon, size: ActionStateGlyph.glyphSize),
      ),
      // Clamped at 1.6x for the reason the stacking section header is: an
      // unclamped single word too wide for its line gets broken mid-word,
      // which is how this button came to read "Requeste / d" at an
      // accessibility reading size.
      label: annotate(
        MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
          child: Text(requestLabel, maxLines: 2, textAlign: TextAlign.center),
        ),
      ),
      style: HeaderActionRow.expandedButtonStyle(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        // "Available" and "Requested" are states read, not dead controls, so
        // the label stays legible: the secondary ink on the room's strong
        // fill, not Material's 38% grey.
        disabledBackgroundColor: room.fillStrong,
        disabledForegroundColor: colorScheme.onSurfaceVariant,
      ),
    );

    return Row(
      // Tops align, so the two captions hang below their own buttons instead
      // of pushing them up out of line with the request action.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!canRequest)
                requestButton(null, (content) => content)
              else
                RoleGatedAction.builder(
                  verdict: requestVerdict,
                  onTap: () => _showRequestSheet(context, ref),
                  builder: (context, onPressed, annotate) =>
                      requestButton(onPressed, annotate),
                ),
              if (note != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  note,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Only when Seerr sent something to play. With none it was drawn with
        // `onPressed: null`: a control a screen reader skips and a sighted
        // user presses for nothing, for a promise the page cannot keep.
        if (videos.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          HeaderActionButton(
            icon: Icons.play_circle_outline_rounded,
            label: 'Trailers',
            semanticLabel: 'Trailers and teasers',
            onPressed: () => DiscoverVideosButton.show(context, videos),
          ),
        ],
        if (hasManageableMedia && manage.isDrawn) ...[
          const SizedBox(width: AppSpacing.sm),
          RoleGatedAction.builder(
            verdict: manage,
            onTap: () => _showManageSheet(context, ref),
            builder: (context, onPressed, annotate) => HeaderActionButton(
              icon: Icons.settings_outlined,
              label: 'Manage',
              semanticLabel: 'Manage ${isMovie ? 'movie' : 'series'}',
              onPressed: onPressed,
              annotate: annotate,
            ),
          ),
        ] else if (openAction != null) ...[
          const SizedBox(width: AppSpacing.sm),
          openAction,
        ],
      ],
    );
  }

  /// The jump into the Radarr or Sonarr that holds this title, or null when
  /// there is nothing to jump to.
  ///
  /// A cross-service control: dimmed but tappable when that service is not set
  /// up here, hinted `requires Radarr`, and its toast's one action is that
  /// service's setup. It used to be reached only once the library check had
  /// answered yes, which needs the service set up, so the dimmed arm never
  /// drew; a stack without Radarr got a bare disabled button, which a screen
  /// reader skips.
  ///
  /// Not drawn when the service answered that it does not hold the title, or
  /// for a series Seerr sent without a TVDB id: the jump could only report
  /// that it found nothing, and a promise the page cannot keep is better left
  /// out than drawn as a control that fails. While the check is still out, or
  /// when it failed, the jump stays and asks for itself.
  Widget? _openAction(BuildContext context, WidgetRef ref) {
    final isMovie = _normalizedMediaType == 'movie';
    if (isInService == false) return null;
    if (!isMovie && tvdbId == null) return null;

    final serviceName = isMovie ? 'Radarr' : 'Sonarr';
    return CrossServiceAction.builder(
      target: isMovie ? ServiceKey.radarr : ServiceKey.sonarr,
      blockedMessage:
          '${Lexicon.setUp(serviceName)} to open this '
          '${isMovie ? 'movie' : 'series'}',
      onTap: () => _openInService(context, ref),
      builder: (context, onPressed, annotate) => HeaderActionButton(
        icon: Icons.open_in_new_rounded,
        label: 'Open',
        semanticLabel: 'Open in $serviceName',
        onPressed: onPressed,
        annotate: annotate,
      ),
    );
  }

  void _showRequestSheet(BuildContext context, WidgetRef ref) {
    AppBottomSheet.show(
      context: context,
      title: _normalizedMediaType == 'tv' ? 'Request series' : 'Request movie',
      icon: Icons.download_rounded,
      accent: ServiceKey.seerr.accent,
      builder: (sheetContext) => RequestBottomSheet(
        mediaId: mediaId,
        mediaType: _normalizedMediaType,
        copies: requestGate.copies,
        title: title,
        onRequestComplete: () {
          if (!context.mounted) {
            return;
          }

          // Through the helper, not a bare ScaffoldMessenger: the app's one
          // celebratory moment should not be default Material chrome with no
          // live region.
          SnackBarHelper.success(context, 'Request submitted');
          _invalidateDetailProviders(ref);
        },
      ),
    );
  }

  void _showManageSheet(BuildContext context, WidgetRef ref) {
    final currentMediaInfo = mediaInfo;
    if (currentMediaInfo == null) {
      return;
    }

    AppBottomSheet.showScrollable(
      context: context,
      title: 'Manage',
      subtitle: title,
      icon: Icons.settings_outlined,
      accent: ServiceKey.seerr.accent,
      builder: (sheetContext, scrollController) => ManageMediaSheet(
        mediaInfo: currentMediaInfo,
        mediaTitle: title,
        mediaType: _normalizedMediaType,
        tmdbId: mediaId,
        tvdbId: tvdbId,
        scrollController: scrollController,
        onDataChanged: () => _invalidateDetailProviders(ref),
      ),
    );
  }

  Future<void> _openInService(BuildContext context, WidgetRef ref) async {
    await openMediaInService(
      context: context,
      ref: ref,
      mediaType: _normalizedMediaType,
      tmdbId: mediaId,
      tvdbId: tvdbId,
    );
  }

  void _invalidateDetailProviders(WidgetRef ref) {
    ref.invalidate(
      discoverDetailProvider((id: mediaId, type: _normalizedMediaType)),
    );
    ref.invalidate(
      discoverDetailExtrasProvider((
        mediaId: mediaId,
        mediaType: _normalizedMediaType,
        tvdbId: tvdbId,
        voteAverage: voteAverage,
      )),
    );
  }
}
