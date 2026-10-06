import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/api/arr_detail_actions_mixin.dart';
import 'package:cupola/core/api/quality_profile_mixin.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/domain/media_removal.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/domain/author_shelf.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/author_page_providers.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// An author on one Readarr: who they are, their books by year, the ones
/// Readarr is looking for, and what it does for them.
///
/// Readarr is no longer maintained and its metadata host no longer answers,
/// so the page says so once, under the name: what is in the library, and a
/// search for a wanted book, still work; finding new books may not.
class AuthorPage extends ConsumerStatefulWidget {
  const AuthorPage({
    super.key,
    required this.authorId,
    this.instanceId,
    this.initialAuthor,
    this.heroTag,
  });

  final int authorId;

  /// The connection this page belongs to, from the route's `?i=`; null
  /// falls through to the lens. Every read and every write on the page goes
  /// to it.
  final String? instanceId;

  /// The library's record, standing in while the page reads its own.
  final ReadarrAuthor? initialAuthor;

  /// The tag of the tile the page was opened from.
  final String? heroTag;

  @override
  ConsumerState<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends ConsumerState<AuthorPage>
    with QualityProfileMixin<AuthorPage>, ArrDetailActionsMixin<AuthorPage> {
  /// The pictures the page has drawn: the room's light is read from one of
  /// these only.
  final _drawn = <String>{};

  /// The books a search was just asked for, until Readarr takes it.
  final _searching = <int>{};

  /// What Monitored was just set to, standing until the author is read
  /// again: [_setOn] is the record it was set over.
  bool? _monitoredSet;
  ReadarrAuthor? _setOn;

  String _instanceId = '';

  ReadarrService get _readarr => _instanceId.isEmpty
      ? ref.read(readarrServiceProvider)
      : ref.read(readarrServiceForProvider(_instanceId));

  ReadarrRecordRef get _record =>
      (instanceId: _instanceId, id: widget.authorId);

  void _artDrawn(String url) {
    if (_drawn.contains(url)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _drawn.add(url));
    });
  }

  void _readAgain() {
    ref.invalidate(readarrAuthorProvider(_record));
    ref.invalidate(readarrAuthorBooksProvider(_record));
    ref.invalidate(readarrQueueSnapshotForProvider(_instanceId));
  }

  @override
  Widget build(BuildContext context) {
    _instanceId = effectiveInstanceId(
      ref,
      ServiceKey.readarr,
      widget.instanceId,
    );
    final connection = ref.watch(
      currentSettingsProvider.select((s) => s.instanceById(_instanceId)),
    );
    if (connection == null || !connection.isConfigured) {
      return Scaffold(
        backgroundColor: CupolaRoom.of(context).ground,
        body: NotConfiguredPlaceholder.forService(ServiceKey.readarr),
      );
    }
    final name = ref.watch(
      currentSettingsProvider.select(
        (s) => s.connectionTitle(_instanceId, ServiceKey.readarr),
      ),
    );
    final authorAsync = ref.watch(readarrAuthorProvider(_record));
    final author = authorAsync.value ?? widget.initialAuthor;
    if (author == null) {
      return ShelfPage(
        name: '',
        summary: '',
        heroTag: widget.heroTag,
        slivers: [
          if (authorAsync.error case final error?)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppErrorState(
                error: error,
                service: ServiceKey.readarr,
                instanceId: _instanceId,
                onRetry: _readAgain,
              ),
            )
          else
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: AppSpacing.xl),
                child: ShimmerPlaceholder(height: 320),
              ),
            ),
        ],
      );
    }
    if (!identical(author, _setOn)) _monitoredSet = null;
    ensureQualityProfiles(
      profileId: author.qualityProfileId,
      fetchProfiles: () => _readarr.getQualityProfiles(),
      record: author,
    );

    final now = DateTime.now();
    final booksAsync = ref.watch(readarrAuthorBooksProvider(_record));
    final books = booksAsync.value;
    final shelf = books == null ? null : AuthorShelf.of(books, now: now);
    final queue = ref.watch(readarrQueueSnapshotForProvider(_instanceId));
    final snapshot = queue.value ?? ArrQueueSnapshot.unknown;
    ShelfArt? artOf(List<dynamic> images, List<String> types) {
      final source = ImageUtils.extractPosterUrl(
        images,
        baseUrl: connection.url,
        apiKey: connection.credential,
        coverTypes: types,
      );
      return source.url.isEmpty
          ? null
          : (url: source.url, headers: source.headers);
    }

    final photo = artOf(author.images, ['poster']);
    ShelfArt? coverOf(ReadarrBook book) => artOf(book.images, ['cover']);
    final lightSource = [
      for (final book in shelf?.books ?? const <ReadarrBook>[])
        ?coverOf(book)?.url,
      ?photo?.url,
    ].where(_drawn.contains).firstOrNull;
    final light = lightSource == null
        ? null
        : ref.watch(titleLightProvider(lightSource)).value;
    final room = CupolaRoom.of(context);
    final profile = currentProfileName;

    return ShelfPage(
      name: author.authorName,
      summary: shelf?.summary ?? '',
      photo: photo,
      light: light,
      heroTag: widget.heroTag,
      moreLabel: 'More actions for ${author.authorName}',
      onMore: () => _more(author, name: name, shelf: shelf),
      onRefresh: () async => _readAgain(),
      slivers: [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: AppSpacing.xl),
            child: _RetiredNote(),
          ),
        ),
        ...switch (booksAsync) {
          AsyncValue(:final error?) when books == null => [
            const SliverToBoxAdapter(child: MediaHeading('Books')),
            SliverToBoxAdapter(
              child: AppErrorState.compact(
                error: error,
                service: ServiceKey.readarr,
                instanceId: _instanceId,
                onRetry: () =>
                    ref.invalidate(readarrAuthorBooksProvider(_record)),
              ),
            ),
          ],
          _ when shelf == null => [
            const SliverToBoxAdapter(child: MediaHeading('Books')),
            const SliverToBoxAdapter(child: ShimmerPlaceholder(height: 240)),
          ],
          _ when shelf.books.isEmpty => [
            const SliverToBoxAdapter(child: MediaHeading('Books')),
            SliverToBoxAdapter(
              child: Text(
                '$name holds no books by this author.',
                style: AppType.body.copyWith(color: room.inkSecondary),
              ),
            ),
          ],
          _ => [
            const SliverToBoxAdapter(
              child: MediaHeading('Books', trailing: 'by year'),
            ),
            _BookGrid(
              books: shelf.books,
              author: author.authorName,
              coverOf: coverOf,
              stateOf: (book) => bookState(book, queue: snapshot, now: now),
              light: light,
              onDrawn: _artDrawn,
            ),
            if (shelf.wanted.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: MediaHeading(
                  StateWord.wanted.label,
                  trailing: '${shelf.wanted.length}',
                ),
              ),
              ShelfSliverGroup(
                itemCount: shelf.wanted.length,
                itemBuilder: (context, index) {
                  final book = shelf.wanted[index];
                  final state = bookState(book, queue: snapshot, now: now);
                  final detail = [
                    if (book.year case final year?) '$year',
                    if (profile != null && profile.isNotEmpty)
                      'quality profile $profile',
                  ].join(' · ');
                  final words = switch (state) {
                    (word: final word, tone: _, hollow: true)
                        when word == StateWord.wanted.label =>
                      '$word · no file yet',
                    final state? => state.word,
                    null => null,
                  };
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ShelfWorkRow(
                        cover: ShelfCover(
                          art: coverOf(book),
                          size: const Size(48, 72),
                          radius: AppRadius.thumb,
                          light: light,
                          dashed: true,
                          fallback: _BookPlate(
                            title: book.title,
                            author: _surname(author.authorName),
                            small: true,
                          ),
                        ),
                        title: book.title,
                        state: state == null
                            ? null
                            : (
                                word: words!,
                                tone: state.tone,
                                hollow: state.hollow,
                              ),
                        detail: detail,
                        spoken: [book.title, ?words, detail].join(', '),
                      ),
                      FilledButton.icon(
                        onPressed: _searching.contains(book.id)
                            ? null
                            : () => _searchBook(book, name: name),
                        icon: const Icon(Icons.search_rounded, size: 18),
                        label: const Text('Search for this book'),
                      ),
                      const SizedBox(height: AppSpacing.slabY),
                    ],
                  );
                },
              ),
            ],
          ],
        },
        const SliverToBoxAdapter(child: MediaHeading('Details')),
        SliverToBoxAdapter(
          child: MediaGroup(
            children: [
              MediaSwitchRow(
                label: 'Monitored',
                detail: '$name looks for missing books by this author',
                value: _monitoredSet ?? author.monitored,
                onChanged: isUpdatingMonitoredState
                    ? null
                    : (on) => _setMonitored(author, on, name: name),
              ),
              if (qualityProfiles.isNotEmpty)
                MediaValueRow(
                  label: 'Quality profile',
                  value: Text(
                    profile ?? '',
                    textAlign: TextAlign.end,
                    style: AppType.meta.copyWith(color: room.inkSecondary),
                  ),
                  onTap: qualityProfiles.length > 1
                      ? () => _pickProfile(author, name: name)
                      : null,
                ),
              if (author.path case final path? when path.isNotEmpty)
                ShelfFolderRow(path: path),
            ],
          ),
        ),
        if (author.titleSlug case final slug? when slug.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: ShelfOpenIn(
                name: name,
                onTap: () => _openInReadarr(connection, slug, name: name),
              ),
            ),
          ),
      ],
    );
  }

  static String _surname(String name) => name.trim().split(RegExp(r'\s+')).last;

  Future<void> _setMonitored(
    ReadarrAuthor author,
    bool on, {
    required String name,
  }) async {
    var written = false;
    await setMonitored(
      context: context,
      serviceName: name,
      subject: 'author',
      monitored: on,
      write: () async {
        await _readarr.updateAuthorMonitored(author.id, on);
        written = true;
      },
      invalidate: [readarrAuthorProvider(_record), readarrAuthorsProvider],
    );
    if (written && mounted) {
      setState(() {
        _setOn = ref.read(readarrAuthorProvider(_record)).value ?? author;
        _monitoredSet = on;
      });
    }
  }

  Future<void> _pickProfile(
    ReadarrAuthor author, {
    required String name,
  }) async {
    final picked = await showMediaValueSheet<int>(
      context,
      title: 'Quality profile',
      value: currentProfileId,
      currentLabel: currentProfileName ?? '',
      options: qualityProfileOptions(qualityProfiles),
    );
    if (picked == null || !mounted) return;
    await changeProfile(
      profileId: picked.value,
      mediaTitle: author.authorName,
      serviceName: name,
      consequence: 'upgrades across every monitored book',
      write: () => _readarr.updateAuthorProfile(author.id, picked.value),
      invalidate: [readarrAuthorProvider(_record), readarrAuthorsProvider],
    );
  }

  Future<void> _searchBook(ReadarrBook book, {required String name}) async {
    HapticFeedback.selectionClick();
    setState(() => _searching.add(book.id));
    try {
      await _readarr.searchBooks([book.id]);
      if (!mounted) return;
      SnackBarHelper.success(context, '$name is searching for ${book.title}');
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        'Could not start a search for ${book.title}.',
        detail: error,
      );
    } finally {
      if (mounted) setState(() => _searching.remove(book.id));
    }
  }

  void _more(
    ReadarrAuthor author, {
    required String name,
    required AuthorShelf? shelf,
  }) {
    showMediaDetailActions(
      context,
      accent: ServiceKey.readarr.accent,
      title: author.authorName,
      actions: [
        if (shelf != null && shelf.wanted.isNotEmpty)
          MediaOverflowAction(
            label: 'Search for every wanted book',
            icon: Icons.manage_search_rounded,
            onInvoke: () => triggerSearch(
              context: context,
              serviceName: name,
              successMessage: '$name is searching for every monitored book',
              search: () => _readarr.searchAuthor(author.id),
            ),
          ),
        MediaOverflowAction.destructive(
          label: 'Remove from $name',
          icon: Icons.delete_outline_rounded,
          onInvoke: () => _remove(author, name: name),
        ),
      ],
    );
  }

  /// Removes the author from this Readarr, after the question removing asks.
  Future<void> _remove(ReadarrAuthor author, {required String name}) async {
    final removal = mediaRemoval(
      title: author.authorName,
      name: name,
      sizeOnDisk: author.sizeOnDisk,
      monitored: author.monitored,
      works: 'books',
    );
    final result = await showAppConfirmDialog(
      context: context,
      title: removal.title,
      message: removal.message,
      icon: Icons.delete_outline_rounded,
      cancelLabel: 'Keep them',
      confirmLabel: removal.confirm(deleteFiles: false, exclude: false),
      confirmLabelFor: (checked) => removal.confirm(
        deleteFiles: checked('files'),
        exclude: checked('exclude'),
      ),
      options: [
        if (removal.filesLabel case final label?)
          AppConfirmOption(
            key: 'files',
            label: label,
            subtitle: 'Their folder on your server. This cannot be undone.',
          ),
        AppConfirmOption(
          key: 'exclude',
          label: "Don't add them again",
          subtitle: "Keeps $name's import lists from bringing them back",
        ),
      ],
    );
    if (!result.confirmed || !mounted) return;
    try {
      await _readarr.deleteAuthor(
        author.id,
        deleteFiles: result.option('files'),
        addImportListExclusion: result.option('exclude'),
      );
      if (!mounted) return;
      SnackBarHelper.success(context, 'Removed from $name');
      ref.invalidate(readarrAuthorsProvider);
      ref.invalidate(readarrKpiLibraryProvider);
      context.pop();
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        'Could not remove ${author.authorName} from $name',
        detail: error,
      );
    }
  }

  Future<void> _openInReadarr(
    ServiceInstance connection,
    String slug, {
    required String name,
  }) async {
    final target = Uri.tryParse(
      UrlUtils.buildUrl(connection.url, '/author/$slug'),
    );
    final opened =
        target != null &&
        await launchUrl(target, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      SnackBarHelper.error(context, 'Could not open $name');
    }
  }
}

/// Readarr's state, said once: it is no longer maintained, and what still
/// works. Blue: a fact, nothing is wrong with this server.
class _RetiredNote extends StatelessWidget {
  const _RetiredNote();

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final info = statusToneColor(
      Theme.of(context).colorScheme,
      StatusTone.info,
      surface: room.fillQuiet,
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.slabY),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: room.hair),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline_rounded, size: 18, color: info),
          ),
          const SizedBox(width: AppSpacing.row),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Readarr is no longer maintained;',
                    style: AppType.label
                        .weight(FontWeight.w600)
                        .copyWith(color: info),
                  ),
                  const TextSpan(
                    text:
                        ' finding new books may not work. Your books, and '
                        'searching for a wanted one, still work.',
                  ),
                ],
              ),
              style: AppType.label
                  .weight(FontWeight.w400)
                  .copyWith(color: room.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The books by year, three to a row (two at a large reading size): each
/// cover, and under it where it stands and the year.
class _BookGrid extends StatelessWidget {
  const _BookGrid({
    required this.books,
    required this.author,
    required this.coverOf,
    required this.stateOf,
    required this.light,
    required this.onDrawn,
  });

  final List<ReadarrBook> books;
  final String author;
  final ShelfArt? Function(ReadarrBook book) coverOf;
  final BookState? Function(ReadarrBook book) stateOf;
  final TitleLight? light;
  final ValueChanged<String> onDrawn;

  static const double _gap = AppSpacing.row;

  @override
  Widget build(BuildContext context) {
    final columns = mediaStacked(context) ? 2 : 3;
    final rows = (books.length / columns).ceil();
    // Rows of covers rather than a grid of fixed cells: a caption that wraps
    // at a large reading size makes its row taller instead of overflowing.
    return SliverList.separated(
      itemCount: rows,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.lg),
      itemBuilder: (context, row) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var column = 0; column < columns; column++) ...[
            if (column > 0) const SizedBox(width: _gap),
            Expanded(
              child: row * columns + column < books.length
                  ? _tile(context, books[row * columns + column])
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, ReadarrBook book) {
    final room = CupolaRoom.of(context);
    final state = stateOf(book);
    final year = book.year;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: [book.title, ?year?.toString(), ?state?.word].join(', '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) => ShelfCover(
              art: coverOf(book),
              size: Size(box.maxWidth, box.maxWidth * 1.5),
              radius: AppRadius.chip,
              light: light,
              onDrawn: onDrawn,
              dashed: !book.onDisk,
              fallback: _BookPlate(title: book.title, author: author),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          // At a large reading size the cover's lettering stays its size, so
          // the title is written under it too, at the reader's.
          if (mediaStacked(context)) ...[
            Text(
              book.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.label
                  .weight(FontWeight.w600)
                  .copyWith(color: room.ink),
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (state != null)
                MediaStateWord(
                  state.word,
                  tone: state.tone,
                  hollow: state.hollow,
                ),
              if (year != null)
                Text(
                  '$year',
                  style: AppType.meta.copyWith(color: room.inkTertiary),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A book without a cover: its title on the plate, a hairline, its author;
/// dark in both rooms.
class _BookPlate extends StatelessWidget {
  const _BookPlate({
    required this.title,
    required this.author,
    this.small = false,
  });

  final String title;
  final String author;
  final bool small;

  @override
  Widget build(BuildContext context) {
    // Artwork is not palette: the plate, dark in both rooms, in its own inks.
    // Its lettering is a picture of a cover, at the cover's own size: grown
    // with the reading size it broke into letters, and the title beside or
    // under it is what is read.
    return MediaQuery.withNoTextScaling(child: _plate());
  }

  Widget _plate() {
    return ColoredBox(
      color: AppColors.plateSurface,
      child: Padding(
        padding: EdgeInsets.all(small ? AppSpacing.xs : AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: small ? 3 : 6,
                overflow: TextOverflow.ellipsis,
                style:
                    (small
                            ? AppType.micro
                            : AppType.label.weight(FontWeight.w600))
                        .copyWith(color: AppColors.plateInk),
              ),
            ),
            Divider(
              height: small ? 6 : AppSpacing.md,
              color: AppColors.plateOutline,
            ),
            Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.micro.copyWith(color: AppColors.plateDimInk),
            ),
          ],
        ),
      ),
    );
  }
}
