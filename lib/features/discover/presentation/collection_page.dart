import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/domain/collection_shelf.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_title_row.dart';
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
              child: _Tally(shelf: shelf),
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
              final score = media.voteAverage;
              return CatalogTitleRow(
                key: ValueKey(media.id),
                media: media,
                meta: [
                  if (part.year != null) '${part.year}',
                  if (score != null && score > 0)
                    'TMDB$unitSpace${score.toStringAsFixed(1)}',
                ].join(' · '),
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

/// How much of the collection is on the server: the headline, the strip of
/// its movies with where each stands, and the count of each kind.
class _Tally extends StatelessWidget {
  const _Tally({required this.shelf});

  final CollectionShelf shelf;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final total = shelf.parts.length;
    final held = shelf.count(CollectionPartStand.onServer);
    final onTheWay = shelf.count(CollectionPartStand.onTheWay);
    final waiting = shelf.count(CollectionPartStand.waiting);
    final headline = held == total && total > 1
        ? 'All $total on your server'
        : '$held of $total on your server';
    Color tone(StatusTone t) =>
        statusToneColor(scheme, t, surface: room.fillQuiet);
    final coming = [
      if (onTheWay > 0) ('$onTheWay on the way', tone(StatusTone.info), false),
      if (waiting > 0)
        (
          '$waiting ${StateWord.waitingForApproval.label.toLowerCase()}',
          tone(StatusTone.info),
          true,
        ),
    ];
    final legend = [
      if (held > 0) ('$held on your server', tone(StatusTone.success), false),
      ...coming,
    ];
    return Semantics(
      container: true,
      label: [headline, for (final (words, _, _) in coming) words].join(', '),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: room.fillQuiet,
          borderRadius: BorderRadius.circular(AppRadius.door),
          border: Border.all(color: room.hair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(headline, style: AppType.section.copyWith(color: room.ink)),
            const SizedBox(height: AppSpacing.md),
            _Strip(shelf: shelf),
            if (legend.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final (words, color, hollow) in legend)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hollow ? null : color,
                            border: hollow
                                ? Border.all(color: color, width: 1.2)
                                : null,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          words,
                          style: AppType.label
                              .weight(FontWeight.w400)
                              .copyWith(color: room.inkSecondary),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The collection's movies side by side, each over a bar in the tone of
/// where it stands: filled on the server or on its way, a ring of a bar
/// while it waits for approval, the hairline where it is neither. Past
/// [_postersUpTo] movies the covers would be too small to read and the bars
/// stand alone.
class _Strip extends StatelessWidget {
  const _Strip({required this.shelf});

  final CollectionShelf shelf;

  static const int _postersUpTo = 10;
  static const double _gap = AppSpacing.s;
  static const double _bar = 3;
  static const double _maxPoster = 44;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final parts = shelf.parts;
    final posters = parts.length <= _postersUpTo;
    return LayoutBuilder(
      builder: (context, box) {
        final fit = (box.maxWidth - _gap * (parts.length - 1)) / parts.length;
        final width = posters ? math.min(fit, _maxPoster) : fit;
        return Row(
          children: [
            for (final (index, part) in parts.indexed) ...[
              if (index > 0) const SizedBox(width: _gap),
              SizedBox(
                width: width,
                child: Column(
                  children: [
                    if (posters) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.thumb),
                        child: SizedBox(
                          width: width,
                          height: width * 1.5,
                          child: ShelfArtwork(
                            art: switch (ImageUtils.buildTmdbPosterUrl(
                              part.media.posterPath,
                              size: 'w92',
                            )) {
                              '' => null,
                              final url => (url: url, headers: null),
                            },
                            box: Size(width, width * 1.5),
                            fallback: ColoredBox(color: room.raised),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    _barOf(part.stand, room: room, scheme: scheme),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _barOf(
    CollectionPartStand stand, {
    required CupolaRoom room,
    required ColorScheme scheme,
  }) {
    Color tone(StatusTone t) =>
        statusToneColor(scheme, t, surface: room.fillQuiet);
    final (color, hollow) = switch (stand) {
      CollectionPartStand.onServer => (tone(StatusTone.success), false),
      CollectionPartStand.onTheWay => (tone(StatusTone.info), false),
      CollectionPartStand.waiting => (tone(StatusTone.info), true),
      CollectionPartStand.missing => (room.hair, false),
    };
    return Container(
      height: _bar,
      decoration: BoxDecoration(
        color: hollow ? null : color,
        borderRadius: BorderRadius.circular(_bar),
        border: hollow ? Border.all(color: color, width: 1) : null,
      ),
    );
  }
}
