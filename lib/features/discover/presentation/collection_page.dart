import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/domain/collection_shelf.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_title_row.dart';
import 'package:cupola/features/discover/presentation/widgets/collection_tally.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_not_set_up.dart';
import 'package:cupola/features/media/domain/media_facts.dart';
import 'package:cupola/features/media/presentation/media_decision_card.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A collection on TMDB, as Seerr knows it: its still, how much of it is on
/// the server, what waits for approval, then the movies in release order,
/// each with where it stands and what can be done for it from here.
class CollectionPage extends ConsumerStatefulWidget {
  const CollectionPage({super.key, required this.collectionId, this.heroTag});

  final int collectionId;
  final String? heroTag;

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  /// The still, once drawn: the room is lit from it.
  String? _drawn;

  void _stillDrawn(String url) {
    if (_drawn == url) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _drawn = url);
    });
  }

  void _readAgain() {
    ref.invalidate(collectionDetailProvider(widget.collectionId));
    final seerr = ref.read(activeInstanceProvider(ServiceKey.seerr))?.id;
    if (seerr != null) ref.invalidate(activeRequestsForProvider(seerr));
  }

  @override
  Widget build(BuildContext context) {
    if (!watchSeerrConfigured(ref)) return const SeerrDetailNotSetUpView();
    final id = widget.collectionId;
    final heroTag = widget.heroTag ?? 'collection_$id';
    final collectionAsync = ref.watch(collectionDetailProvider(id));
    final collection = collectionAsync.value;
    if (collection == null) {
      return ShelfPage.banner(
        name: '',
        summary: '',
        banner: null,
        slivers: [
          if (collectionAsync.error case final error?)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppErrorState(
                error: error,
                service: ServiceKey.seerr,
                onRetry: () => ref.invalidate(collectionDetailProvider(id)),
              ),
            )
          else
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: AppSpacing.xl),
                child: ShimmerList(itemCount: 4, itemHeight: 76),
              ),
            ),
        ],
      );
    }
    if (collection.isEmpty) {
      final namesSeerr = ref
          .watch(roleGateProvider(''))
          .namesService(ServiceKey.seerr);
      return ShelfPage.banner(
        name: '',
        summary: '',
        banner: null,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: AppEmptyState(
              icon: Icons.collections_bookmark_outlined,
              title: 'No collection here',
              message: namesSeerr
                  ? 'Seerr answered, but it has nothing filed under this '
                        'collection.'
                  : 'There is nothing filed under this collection.',
            ),
          ),
        ],
      );
    }

    final numbering = ref.watch(seerrNumberingProvider).value;
    final shelf = CollectionShelf.of(collection, numbering: numbering);
    final backdrop = ImageUtils.buildTmdbPosterUrl(
      collection.backdropPath,
      size: 'w1280',
    );
    final light = _drawn == null
        ? null
        : ref.watch(titleLightProvider(_drawn!)).value;
    final pending = _pendingOf(collection);
    final room = CupolaRoom.of(context);

    return ShelfPage.banner(
      name: collection.name,
      summary: shelf.summary,
      banner: backdrop.isEmpty ? null : (url: backdrop, headers: null),
      light: light,
      heroTag: heroTag,
      onArtDrawn: _stillDrawn,
      onRefresh: () async => _readAgain(),
      slivers: [
        if (shelf.parts.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: CollectionTally(shelf: shelf),
            ),
          ),
        for (final (index, request) in pending.indexed)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: MediaDecisionCard(
                pending: request,
                title: _titleOf(collection, request.request),
                leads: index == 0,
                light: light,
                onDecided: _readAgain,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: MediaHeading('In release order')),
        if (shelf.parts.isEmpty)
          SliverToBoxAdapter(
            child: Text(
              'TMDB lists no movies in this collection yet.',
              style: AppType.body.copyWith(color: room.inkSecondary),
            ),
          )
        else
          ShelfSliverGroup(
            itemCount: shelf.parts.length,
            itemBuilder: (context, index) {
              final part = shelf.parts[index];
              final media = part.media;
              final score = media.tmdbScore;
              return CatalogTitleRow(
                key: ValueKey(media.id),
                media: media,
                meta: [
                  if (part.year != null) '${part.year}',
                  if (score != null)
                    'TMDB$unitSpace${score.toStringAsFixed(1)}',
                ].join(dotSeparator),
                heroTag: 'collection_${id}_${media.id}',
                onChanged: _readAgain,
              );
            },
          ),
      ],
    );
  }

  /// The requests for the collection's movies that wait for approval, the
  /// oldest first, on the lens's Seerr: the operator's, where the account
  /// may see them.
  List<MediaPendingRequest> _pendingOf(CollectionDetail collection) {
    if (ref.watch(audienceProvider) != Audience.operator) return const [];
    final seerr = ref.watch(activeInstanceProvider(ServiceKey.seerr));
    if (seerr == null) return const [];
    final ids = {for (final part in collection.parts) part.id};
    final requests = ref.watch(activeRequestsForProvider(seerr.id)).value;
    return [
      for (final request in [
        ...?requests,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)))
        if (request.status == RequestStatus.pendingApproval &&
            request.type == 'movie' &&
            ids.contains(request.media?.tmdbId))
          (seerr: seerr, request: request),
    ];
  }

  static String _titleOf(CollectionDetail collection, SeerrRequest request) =>
      collection.parts
          .where((part) => part.id == request.media?.tmdbId)
          .firstOrNull
          ?.title ??
      request.media?.title ??
      '';
}
