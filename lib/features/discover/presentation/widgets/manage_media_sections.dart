import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
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
                style: TextStyle(color: colorScheme.onSurfaceVariant),
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
                    // resolution a fault.
                    if (request.is4k)
                      const _Badge(text: '4K', color: AppColors.info),
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
            tooltip: 'Delete from library',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            style: IconButton.styleFrom(
              backgroundColor: statusToneFill(
                colorScheme,
                StatusTone.error,
              ).withValues(alpha: 0.1),
              // The irreversible-action exception, walked against the wash
              // over the card it sits on.
              foregroundColor: statusToneColor(
                colorScheme,
                StatusTone.error,
                surface: colorScheme.surfaceContainer,
                tintAlpha: 0.1,
              ),
            ),
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
    final displayStatus = request.displayStatus;

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

class MediaSection extends StatelessWidget {
  final bool isMovie;
  final bool hasExternalService;
  final bool isDeleting;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  const MediaSection({
    super.key,
    required this.isMovie,
    required this.hasExternalService,
    required this.isDeleting,
    this.onOpen,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final serviceName = isMovie ? 'Radarr' : 'Sonarr';
    final target = isMovie ? ServiceKey.radarr : ServiceKey.sonarr;
    final noun = isMovie ? 'movie' : 'series';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Media',
          style: theme.textTheme.titleMedium?.weight(FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.md),
        // Both are jumps into the arr, so both are cross-service cells:
        // dimmed but tappable when that arr is not set up here, and their
        // toast opens its settings.
        SizedBox(
          width: double.infinity,
          child: CrossServiceAction.builder(
            target: target,
            blockedMessage: 'Connect $serviceName to open this $noun',
            onTap: onOpen ?? () {},
            builder: (context, onPressed, annotate) => OutlinedButton.icon(
              onPressed: hasExternalService ? onPressed : null,
              icon: annotate(const Icon(Icons.open_in_new)),
              label: annotate(Text('Open in $serviceName')),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: CrossServiceAction.builder(
            target: target,
            blockedMessage: 'Connect $serviceName to remove this $noun',
            onTap: onRemove ?? () {},
            builder: (context, onPressed, annotate) => ElevatedButton.icon(
              onPressed: hasExternalService && !isDeleting ? onPressed : null,
              icon: isDeleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : annotate(const Icon(Icons.delete_outline)),
              label: annotate(Text('Remove from $serviceName')),
              style: _destructiveFill(colorScheme),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '* This will irreversibly remove this ${isMovie ? 'movie' : 'series'} from $serviceName, including all files.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
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
            style: _destructiveFill(colorScheme),
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

/// The red fill of an irreversible action, with its label measured against the
/// fill rather than assumed: `onError` is white, which reads 3.5:1 on the light
/// theme's red.
ButtonStyle _destructiveFill(ColorScheme colorScheme) {
  final fill = statusToneFill(colorScheme, StatusTone.error);
  return ElevatedButton.styleFrom(
    backgroundColor: fill,
    foregroundColor: ServiceTheme.foregroundOn(fill),
  );
}
