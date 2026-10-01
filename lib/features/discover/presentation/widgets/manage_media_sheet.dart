import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/discover_navigation_utils.dart';
import 'package:cupola/features/discover/presentation/manage_media_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/manage_media_sections.dart';

/// Bottom sheet for managing media requests and files via Seerr.
///
/// Shows:
/// - Requests section: list of requests with delete option
/// - Media section: Open in Radarr/Sonarr, Remove from service
/// - Advanced section: Clear all data
class ManageMediaSheet extends ConsumerWidget {
  final Map<String, dynamic> mediaInfo;
  final String mediaTitle;
  final String mediaType; // 'movie' or 'tv'
  final int tmdbId;
  final int? tvdbId;

  /// Provided by [AppBottomSheet.showScrollable]; null when the widget is used
  /// standalone (e.g. in tests), in which case the ListView uses its own.
  final ScrollController? scrollController;
  final VoidCallback onDataChanged;

  const ManageMediaSheet({
    super.key,
    required this.mediaInfo,
    required this.mediaTitle,
    required this.mediaType,
    required this.tmdbId,
    this.tvdbId,
    this.scrollController,
    required this.onDataChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (
      mediaInfo: mediaInfo,
      mediaType: mediaType,
      tmdbId: tmdbId,
      tvdbId: tvdbId,
    );
    final state = ref.watch(manageMediaProvider(args));
    final notifier = ref.read(manageMediaProvider(args).notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMovie = mediaType == 'movie';

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      // A record Seerr sent that could not be read: an answer, so the glyph
      // is amber, and the sentence stays in the sheet's own secondary ink.
      return Center(
        child: FaultNote.fault(
          message: state.error!,
          surface: colorScheme.surfaceContainer,
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        RequestsSection(
          requests: state.requests,
          onDeleteRequest: (requestId) {
            _deleteRequest(context, ref, args, requestId);
          },
        ),
        if (notifier.showMediaSection) ...[
          const SizedBox(height: AppSpacing.xl),
          MediaSection(
            isMovie: isMovie,
            isDeleting: state.isDeleting,
            onOpen: () => _openInService(context, ref),
            onRemove: () {
              _removeFromService(context, ref, args);
            },
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        AdvancedSection(
          isMovie: isMovie,
          isDeleting: state.isDeleting,
          onClear: () {
            _clearAllData(context, ref, args);
          },
        ),
        const SizedBox(height: AppSpacing.xxxl),
      ],
    );
  }

  Future<void> _deleteRequest(
    BuildContext context,
    WidgetRef ref,
    ManageMediaArgs args,
    int requestId,
  ) async {
    // The same question the Requests tab asks before the same write. This one
    // fired on the tap, one row above Remove and Clear data, which both ask.
    // Neutral, like every confirmation: red on this canvas is kept for what
    // did not answer.
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Delete request?',
      message: mediaTitle,
      icon: Icons.delete_outline_rounded,
      confirmLabel: 'Delete request',
    );
    if (!result.confirmed || !context.mounted) return;

    final notifier = ref.read(manageMediaProvider(args).notifier);
    final error = await notifier.deleteRequest(requestId);
    if (!context.mounted) {
      return;
    }

    if (error == null) {
      SnackBarHelper.success(context, 'Request deleted');
      onDataChanged();
      return;
    }

    SnackBarHelper.error(context, error);
  }

  Future<void> _removeFromService(
    BuildContext context,
    WidgetRef ref,
    ManageMediaArgs args,
  ) async {
    final notifier = ref.read(manageMediaProvider(args).notifier);
    if (notifier.seerrMediaId == null) {
      return;
    }

    final isMovie = mediaType == 'movie';
    final service = isMovie ? 'Radarr' : 'Sonarr';
    // Neutral: the verb says the whole of it — the files go too — and the
    // sentence says who does it and that it cannot be undone. Red means
    // unreachable and nothing else.
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Remove from $service?',
      message: MediaSection.removalSentence(isMovie: isMovie),
      confirmLabel: 'Remove and delete files',
    );

    if (!result.confirmed || !context.mounted) {
      return;
    }

    final error = await notifier.removeFromService();
    if (!context.mounted) {
      return;
    }

    if (error == null) {
      // Named: "removed from service" did not say which one.
      SnackBarHelper.success(
        context,
        '${isMovie ? 'Movie' : 'Series'} removed from $service',
      );
      Navigator.pop(context);
      onDataChanged();
      return;
    }

    SnackBarHelper.error(context, error);
  }

  Future<void> _clearAllData(
    BuildContext context,
    WidgetRef ref,
    ManageMediaArgs args,
  ) async {
    final notifier = ref.read(manageMediaProvider(args).notifier);
    if (notifier.seerrMediaId == null) {
      return;
    }

    final result = await showAppConfirmDialog(
      context: context,
      title: 'Clear data?',
      message:
          'This will irreversibly remove all data for this ${mediaType == 'movie' ? 'movie' : 'series'}, '
          'including any requests. If this item exists in your Jellyfin library, '
          'the media information will be recreated during the next scan.',
      confirmLabel: 'Clear data',
    );

    if (!result.confirmed || !context.mounted) {
      return;
    }

    final error = await notifier.clearAllData();
    if (!context.mounted) {
      return;
    }

    if (error == null) {
      SnackBarHelper.success(context, 'Data cleared');
      Navigator.pop(context);
      onDataChanged();
      return;
    }

    SnackBarHelper.error(context, error);
  }

  Future<void> _openInService(BuildContext context, WidgetRef ref) async {
    await openMediaInService(
      context: context,
      ref: ref,
      mediaType: mediaType,
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      dismissSheet: () => Navigator.pop(context),
      movieNotFoundMessage: 'Movie not found in Radarr',
      seriesNotFoundMessage: 'Series not found in Sonarr',
    );
  }
}
