import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class RequestsSection extends StatelessWidget {
  final List<SeerrRequest> requests;
  final void Function(int) onDeleteRequest;

  const RequestsSection({
    super.key,
    required this.requests,
    required this.onDeleteRequest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Requests',
          style: theme.textTheme.titleMedium?.weight(FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.md),
        if (requests.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Center(
              child: Text(
                'No requests for this media',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ...requests.map(
            (request) => _RequestCard(
              request: request,
              onDelete: () => onDeleteRequest(request.id),
            ),
          ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  final SeerrRequest request;
  final VoidCallback onDelete;

  const _RequestCard({required this.request, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    String formattedDate = '';

    try {
      final date = DateTime.parse(request.createdAt);
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      formattedDate = '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      formattedDate = request.createdAt;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      request.requestedBy?.displayName ?? 'Unknown',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    // A fact about the request, so blue. Amber would call the
                    // resolution a fault. Through the tone, walked against the
                    // card it sits on: the raw byte was painted as it came.
                    if (request.is4k)
                      _Badge(
                        text: '4K',
                        color: statusToneColor(
                          colorScheme,
                          StatusTone.info,
                          surface: colorScheme.surfaceContainer,
                        ),
                      ),
                    _StatusBadge(request: request),
                  ],
                ),
                if (request.seasons != null && request.seasons!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Seasons',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: request.seasons!.map((season) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.2),
                          borderRadius: AppRadius.borderRadiusXs,
                        ),
                        child: Text(
                          '${season.seasonNumber}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      formattedDate,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            // It deletes the *request*: the file, if there is one, stays in
            // the library. "Delete from library" named the one thing this
            // button never touches.
            tooltip: 'Delete request',
            onPressed: onDelete,
            // Neutral: red means unreachable and nothing else, and the
            // confirmation says what goes.
            icon: const Icon(Icons.delete_outline),
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.borderRadiusXs,
      ),
      child: Text(
        text,
        // The chip's fill is a caller-supplied colour — a quality profile
        // accent, a service accent — so the ink has to be measured against it
        // rather than asserted. Black was right for the ambers and wrong for
        // every dark fill that ever reached this widget.
        style: theme.textTheme.labelSmall
            ?.weight(FontWeight.w600)
            .copyWith(color: ServiceTheme.foregroundOn(color)),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final SeerrRequest request;

  const _StatusBadge({required this.request});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // The word from the same reading the tone comes from: the request's own
    // state, the media's only past approval.
    final displayStatus = request.lifecycleStatus;

    // The tone comes from the one resolver every other request row uses, so
    // this badge cannot disagree with Activity about the same request. That
    // resolver is where the arms are argued: a failed request is a fault Seerr
    // reported (amber); a declined one is a decision somebody made, and a
    // decision is not a fault, so it is neutral with the deleted ones. This
    // badge used to paint all three red, which on this canvas says Seerr did not
    // answer, when the badge exists precisely because it did.
    final color = statusToneFill(
      colorScheme,
      resolveRequestStatus(request).tone,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.borderRadiusXs,
      ),
      child: Text(
        displayStatus.label,
        style: theme.textTheme.labelSmall
            ?.weight(FontWeight.w600)
            .copyWith(color: ServiceTheme.foregroundOn(color)),
      ),
    );
  }
}

/// One copy of the title in the Media section: the server that holds it, as
/// the controls name it, and what Open can do about it.
class MediaCopyControls {
  const MediaCopyControls({
    required this.serverName,
    required this.open,
    required this.onOpen,
    required this.onRemove,
  });

  /// `Radarr`, `Radarr · 4K`, or Seerr's own name for a server Cupola has no
  /// connection to.
  final String serverName;
  final MediaCopyOpen open;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
}

/// How Open is gated for one copy.
enum MediaCopyOpen {
  /// The copy is on a connection Cupola has: Open goes straight to it.
  connection,

  /// Which server holds the copy is not known here (Seerr's servers were not
  /// read): Open is the jump into Cupola's own Radarr, gated on one being set
  /// up, as it always was.
  service,

  /// The copy is on a server Seerr knows and Cupola does not: Open is dimmed
  /// but tappable, and its toast says why and leads to the setup.
  knownOnlyToSeerr,
}

/// The title as Radarr or Sonarr holds it: a jump into Cupola's own, and a
/// removal Seerr performs on its own, for every copy Seerr's record names.
///
/// A title on disk in HD and in 4K is two copies on two servers, and each has
/// its own pair: "Remove from Radarr" used to remove the standard copy
/// whichever the person meant, and a title only in 4K had no section at all.
class MediaSection extends StatelessWidget {
  final bool isMovie;
  final bool isDeleting;
  final List<MediaCopyControls> copies;

  const MediaSection({
    super.key,
    required this.isMovie,
    required this.isDeleting,
    required this.copies,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Media',
          style: theme.textTheme.titleMedium?.weight(FontWeight.w600),
        ),
        for (final copy in copies) ...[
          const SizedBox(height: AppSpacing.md),
          _CopyControls(isMovie: isMovie, isDeleting: isDeleting, copy: copy),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          '* ${removalSentence(isMovie: isMovie)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// What *Remove from Radarr* does, said once for the note under it and for
  /// the confirmation that asks before it: Seerr does the removing, on its own
  /// Radarr, and the files go with it. [server] names the server when the
  /// copy's is known.
  static String removalSentence({required bool isMovie, String? server}) {
    final service = isMovie ? 'Radarr' : 'Sonarr';
    final noun = isMovie ? 'movie' : 'series';
    final from = server ?? 'its $service server';
    return 'Seerr removes this $noun from $from and deletes its files. This '
        'cannot be undone.';
  }
}

class _CopyControls extends StatelessWidget {
  const _CopyControls({
    required this.isMovie,
    required this.isDeleting,
    required this.copy,
  });

  final bool isMovie;
  final bool isDeleting;
  final MediaCopyControls copy;

  @override
  Widget build(BuildContext context) {
    final target = isMovie ? ServiceKey.radarr : ServiceKey.sonarr;
    final noun = isMovie ? 'movie' : 'series';
    final name = copy.serverName;

    Widget openButton(
      VoidCallback onPressed,
      Widget Function(Widget content) annotate,
    ) => OutlinedButton.icon(
      onPressed: onPressed,
      icon: annotate(const Icon(Icons.open_in_new)),
      label: annotate(Text('Open in $name')),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The jump is into Cupola's own Radarr, so it is a cross-service
        // cell: dimmed but tappable when that Radarr is not set up here, and
        // its toast opens the setup.
        SizedBox(
          width: double.infinity,
          child: switch (copy.open) {
            MediaCopyOpen.knownOnlyToSeerr => GatedAffordance.builder(
              enabled: false,
              hint: 'requires a connection to $name',
              onTap: copy.onOpen,
              onBlocked: () => SnackBarHelper.withAction(
                context,
                '$name is known only to Seerr. Set it up to open this $noun.',
                actionLabel: Lexicon.setUp(target.title),
                onAction: () => context.go(ServiceRoutes.setUp(target)),
              ),
              builder: (context, onPressed, annotate) =>
                  openButton(onPressed, annotate),
            ),
            MediaCopyOpen.connection ||
            MediaCopyOpen.service => CrossServiceAction.builder(
              target: target,
              blockedMessage:
                  '${Lexicon.setUp(target.title)} to open this $noun',
              onTap: copy.onOpen,
              builder: (context, onPressed, annotate) =>
                  openButton(onPressed, annotate),
            ),
          },
        ),
        const SizedBox(height: AppSpacing.md),
        // The removal is not. Seerr performs it, on the server that holds the
        // copy, and this pair is drawn only when Seerr says that server holds
        // the title. It used to be gated on a Radarr set up in Cupola, which
        // this write never touches, so a stack that knew its Radarr only
        // through Seerr got "Set up Radarr" for something Seerr could already
        // do.
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            // Null only while the removal is in flight.
            onPressed: isDeleting ? null : copy.onRemove,
            icon: isDeleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            label: Text('Remove from $name'),
          ),
        ),
      ],
    );
  }
}

class AdvancedSection extends StatelessWidget {
  final bool isMovie;
  final bool isDeleting;
  final VoidCallback? onClear;

  const AdvancedSection({
    super.key,
    required this.isMovie,
    required this.isDeleting,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Advanced',
          style: theme.textTheme.titleMedium?.weight(FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: !isDeleting ? onClear : null,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clear data'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '* This will irreversibly remove all data for this ${isMovie ? 'movie' : 'series'}, '
          'including any requests. If this item exists in your Jellyfin library, '
          'the media information will be recreated during the next scan.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
