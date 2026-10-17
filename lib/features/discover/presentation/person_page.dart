import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/domain/models/person_detail.dart';
import 'package:cupola/features/discover/domain/person_shelf.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_title_row.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_not_set_up.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A person on TMDB, as Seerr knows them: their work by trade, the one they
/// are known for first, each title with where it stands on the server and
/// what can be done for it from here.
///
/// Under the name, how much of the leading trade is on the server: exact,
/// because TMDB's credits come whole. Then the trades, a long one showing
/// its newest titles until asked for the rest; then who they are, and where
/// the credits come from.
class PersonPage extends ConsumerStatefulWidget {
  const PersonPage({
    super.key,
    required this.personId,
    this.heroTag,
    this.initialProfileUrl,
  });

  final int personId;
  final String? heroTag;

  /// The face the page was opened from, standing in while it reads its own,
  /// so the flight lands on a picture already in the cache.
  final String? initialProfileUrl;

  /// The titles a trade shows before Show all.
  static const int firstShown = 10;

  @override
  ConsumerState<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends ConsumerState<PersonPage> {
  /// The trades opened in full.
  final _open = <String>{};

  /// The photo, once drawn: the room is lit from it.
  String? _drawn;

  void _photoDrawn(String url) {
    if (_drawn == url) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _drawn = url);
    });
  }

  void _readAgain() {
    ref.invalidate(personDetailProvider(widget.personId));
    ref.invalidate(personCreditsProvider(widget.personId));
  }

  @override
  Widget build(BuildContext context) {
    if (!watchSeerrConfigured(ref)) return const SeerrDetailNotSetUpView();
    final id = widget.personId;
    final personAsync = ref.watch(personDetailProvider(id));
    final initial = (widget.initialProfileUrl ?? '').isEmpty
        ? null
        : (url: widget.initialProfileUrl!, headers: null);
    final heroTag = widget.heroTag ?? 'person_$id';

    final person = personAsync.value;
    if (person == null) {
      return ShelfPage(
        name: '',
        summary: '',
        photo: initial,
        heroTag: heroTag,
        slivers: [
          if (personAsync.error case final error?)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppErrorState(
                error: error,
                service: ServiceKey.seerr,
                onRetry: () => ref.invalidate(personDetailProvider(id)),
              ),
            )
          else
            const SliverToBoxAdapter(child: _Waiting()),
        ],
      );
    }
    if (person.isEmpty) {
      final namesSeerr = ref
          .watch(roleGateProvider(''))
          .namesService(ServiceKey.seerr);
      return ShelfPage(
        name: '',
        summary: '',
        heroTag: heroTag,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: AppEmptyState(
              icon: Icons.person_off_rounded,
              title: 'No details for this person',
              message: namesSeerr
                  ? 'Seerr answered, but it has no record of them.'
                  : 'There is nothing on record for them.',
            ),
          ),
        ],
      );
    }

    final profile = ImageUtils.buildTmdbPosterUrl(
      person.profilePath,
      size: 'w185',
    );
    final photo = profile.isNotEmpty ? (url: profile, headers: null) : initial;
    final light = _drawn == null
        ? null
        : ref.watch(titleLightProvider(_drawn!)).value;
    final numbering = ref.watch(seerrNumberingProvider).value;
    final creditsAsync = ref.watch(personCreditsProvider(id));
    final credits = creditsAsync.value;
    final shelf = credits == null
        ? null
        : PersonShelf.of(credits, knownFor: person.knownForDepartment);
    final lead = shelf?.lead;
    final held = lead?.onServer(numbering: numbering);

    return ShelfPage(
      name: person.name,
      role: PersonShelf.roleFor(person.knownForDepartment),
      summary: lead == null
          ? ''
          : '$held of ${lead.works.length} on your server',
      tally: lead == null ? null : (held: held!, of: lead.works.length),
      photo: photo,
      light: light,
      heroTag: heroTag,
      onArtDrawn: _photoDrawn,
      onRefresh: () async => _readAgain(),
      slivers: [
        ...switch (creditsAsync) {
          AsyncValue(:final error?) when credits == null => [
            const SliverToBoxAdapter(child: MediaHeading('Work')),
            SliverToBoxAdapter(
              child: AppErrorState.compact(
                error: error,
                service: ServiceKey.seerr,
                onRetry: () => ref.invalidate(personCreditsProvider(id)),
              ),
            ),
          ],
          _ when shelf == null => [const SliverToBoxAdapter(child: _Waiting())],
          _ when shelf.isEmpty => [
            const SliverToBoxAdapter(child: MediaHeading('Work')),
            SliverToBoxAdapter(
              child: Text(
                'TMDB lists no work for them yet.',
                style: AppType.body.copyWith(
                  color: CupolaRoom.of(context).inkSecondary,
                ),
              ),
            ),
          ],
          _ => [for (final trade in shelf.trades) ..._trade(trade)],
        },
        ..._about(person),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: Text(
              'Credits from TMDB.',
              style: AppType.caption.copyWith(
                color: CupolaRoom.of(context).inkTertiary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// A trade's heading over its titles; a long one shows its newest until
  /// Show all.
  List<Widget> _trade(PersonTrade trade) {
    final works = trade.works;
    final open = _open.contains(trade.title);
    final shown = open
        ? works.length
        : math.min(works.length, PersonPage.firstShown);
    final more = works.length - shown;
    return [
      SliverToBoxAdapter(
        child: MediaHeading(trade.title, trailing: '${works.length}'),
      ),
      ShelfSliverGroup(
        itemCount: shown + (more > 0 ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == shown) {
            return MediaLinkRow(
              label: 'Show all ${works.length}',
              detail: '$more more',
              onTap: () => setState(() => _open.add(trade.title)),
            );
          }
          final work = works[index];
          final media = work.media;
          final score = media.tmdbScore;
          return CatalogTitleRow(
            key: ValueKey((trade.title, media.mediaType, media.id)),
            media: media,
            meta: [
              if (work.year != null) '${work.year}',
              media.mediaType == 'tv' ? 'Series' : 'Movie',
              if (score != null) 'TMDB$unitSpace${score.toStringAsFixed(1)}',
            ].join(dotSeparator),
            heroTag:
                'person_${widget.personId}_${trade.title}_'
                '${media.mediaType}_${media.id}',
            onChanged: () =>
                ref.invalidate(personCreditsProvider(widget.personId)),
          );
        },
      ),
    ];
  }

  /// Who they are: the biography, under the dates and the place.
  List<Widget> _about(PersonDetail person) {
    final born = [
      if ((person.birthday ?? '').isNotEmpty)
        'Born ${formatMediumDate(person.birthday!)}',
      if ((person.placeOfBirth ?? '').isNotEmpty) person.placeOfBirth!,
    ].join(dotSeparator);
    final died = (person.deathday ?? '').isEmpty
        ? ''
        : 'Died ${formatMediumDate(person.deathday!)}';
    final biography = person.biography?.trim() ?? '';
    if (born.isEmpty && died.isEmpty && biography.isEmpty) return const [];
    final room = CupolaRoom.of(context);
    return [
      const SliverToBoxAdapter(child: MediaHeading('About')),
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in [born, died])
              if (line.isNotEmpty)
                Text(
                  line,
                  style: AppType.meta.copyWith(color: room.inkSecondary),
                ),
            if (biography.isNotEmpty) ...[
              if (born.isNotEmpty || died.isNotEmpty)
                const SizedBox(height: AppSpacing.sm),
              MediaProseSection(text: biography, maxLines: 5),
            ],
          ],
        ),
      ),
    ];
  }
}

/// The page's rows while Seerr is asked.
class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: AppSpacing.xl),
    child: ShimmerList(itemCount: 4, itemHeight: 76),
  );
}
