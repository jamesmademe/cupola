import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/features/media/domain/quality_words.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/models/arr_media_file.dart';
import 'package:cupola/core/status/media_action.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_videos_button.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/stream/domain/stream_web_url.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_cast_list.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_collection_banner.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_lead.dart';
import 'package:cupola/features/media/domain/media_row_view.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/presentation/media_identity.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/media/presentation/media_manage_summaries.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The canonical Media page: one title, the same page from every entry
/// point.
///
/// Four layers, top to bottom: who the title is (artwork, title, scores), the
/// one action that leads, what every connection holds ("On your server"),
/// and the operator's sections, closed. [focus] is the connection the page
/// was opened from: its copy leads when it needs something.
class MediaPage extends ConsumerStatefulWidget {
  const MediaPage({super.key, required this.mediaKey, this.focus});

  final MediaKey mediaKey;
  final String? focus;

  @override
  ConsumerState<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends ConsumerState<MediaPage> {
  /// Where Manage scrolls to.
  final _manageKey = GlobalKey();

  /// The artwork the page has drawn: the title light is read from one of
  /// these only.
  final _drawn = <String>{};

  void _artDrawn(String url) {
    if (_drawn.contains(url)) return;
    // After the frame that drew it: a setState inside an image builder would
    // rebuild the tree that is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _drawn.add(url));
    });
  }

  MediaKey get mediaKey => widget.mediaKey;
  String? get focus => widget.focus;

  /// Plays [lead] in its server's own client, at the item.
  Future<void> _play(MediaLeadPlay lead, String serverName) async {
    final server = lead.server;
    final machineId = server.service == ServiceKey.plex
        ? ref
              .read(plexCapabilitiesForProvider(server.id))
              .value
              ?.machineIdentifier
        : null;
    final target = streamItemWebUrl(
      service: server.service,
      baseUrl: server.url,
      itemId: lead.item.id,
      plexMachineId: machineId,
    );
    final opened =
        target != null &&
        await launchUrl(target, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      SnackBarHelper.error(context, 'Could not open $serverName');
    }
  }

  /// The Seerr "More like this" is read through: the first one set up, while
  /// the title has a TMDB id.
  String? _recommender(SettingsModel settings) {
    if (mediaKey.tmdbId == null) return null;
    return settings
        .instancesOf(ServiceKey.seerr)
        .where((instance) => instance.isConfigured)
        .firstOrNull
        ?.id;
  }

  void _toManage() {
    final target = _manageKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(mediaRowsProvider(mediaKey));
    final audience = ref.watch(audienceProvider);
    final settings = ref.watch(currentSettingsProvider);
    final identity = MediaIdentity.of(rows);
    final lead = resolveMediaLead(rows, audience: audience, focus: focus);
    final views = [
      for (final row in rows)
        if (audience == Audience.operator ||
            row.service == ServiceKey.jellyfin ||
            row.service == ServiceKey.plex)
          ?mediaRowView(
            row,
            title: (connection) =>
                settings.connectionTitle(connection.id, connection.service),
            now: DateTime.now(),
          ),
    ];
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    // The one image that lights the room: the backdrop, else the poster. Until
    // it is read, and for artwork with too little chroma, the lamp.
    // It is read once the page has drawn that picture: it comes from the same
    // cache then, and a picture that never arrives leaves the lamp on.
    final lightSource = identity?.backdropUrl ?? identity?.posterUrl;
    final lit = _drawn.contains(lightSource) ? lightSource : null;
    final light = lit == null ? null : ref.watch(titleLightProvider(lit)).value;

    return Scaffold(
      backgroundColor: room.ground,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppGradients.ambientBackground(
            scheme,
            accent: light?.light,
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                top + AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              sliver: SliverList.list(
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _BackPlate(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _Hero(
                    onArtDrawn: _artDrawn,
                    identity: identity,
                    marks: mediaFormatMarks(rows),
                    light: light,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _Scores(
                    scores: mediaScoresOf(rows, identity),
                    showMetacritic: audience == Audience.operator,
                  ),
                  const SizedBox(height: AppSpacing.slabY),
                  _LeadBar(
                    lead: lead,
                    light: light,
                    onPlay: (lead) => _play(
                      lead,
                      settings.connectionTitle(
                        lead.server.id,
                        lead.server.service,
                      ),
                    ),
                    onTrailer: identity?.videos.isNotEmpty ?? false
                        ? () => DiscoverVideosButton.show(
                            context,
                            identity!.videos,
                          )
                        : null,
                    onManage: _toManage,
                    hasTrailer: identity?.videos.isNotEmpty ?? false,
                    showManage: audience == Audience.operator,
                    serverName: (lead) => settings.connectionTitle(
                      lead.server.id,
                      lead.server.service,
                    ),
                  ),
                  if (views.isNotEmpty) ...[
                    _Heading('On your server', trailing: _servicesCount(rows)),
                    _RowsCard(views: views),
                  ],
                  if (audience == Audience.operator) ..._manage(rows, settings),
                  if ((identity?.overview ?? '').isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.section),
                    Text(
                      identity!.overview,
                      style: AppType.body.copyWith(color: room.ink),
                    ),
                  ],
                  if ((identity?.creditsLine ?? '').isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      identity!.creditsLine,
                      style: AppType.meta.copyWith(color: room.inkSecondary),
                    ),
                  ],
                  if (identity?.cast.isNotEmpty ?? false) ...[
                    const _Heading('Cast'),
                    DiscoverCastList(
                      cast: identity!.cast,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                  if (identity?.collection case final collection?) ...[
                    const SizedBox(height: AppSpacing.section),
                    DiscoverCollectionBanner(collection: collection),
                  ],
                  if (_recommender(settings) case final seerr?) ...[
                    const SizedBox(height: AppSpacing.section),
                    DiscoverCarousel(
                      title: 'More like this',
                      sectionId: 'media-more-like-this',
                      forcedMediaType: mediaKey.isMovie ? 'movie' : 'tv',
                      items: ref.watch(
                        mediaRecommendationsProvider((
                          key: mediaKey,
                          connectionId: seerr,
                        )),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `4 services`: the services the rows speak for, each once.
  String _servicesCount(List<MediaRow> rows) {
    final services = {
      for (final row in rows)
        if (row is MediaConnectionRow) row.service,
    };
    return services.length == 1 ? '1 service' : '${services.length} services';
  }

  /// The operator's sections, closed: each says what it holds in one line
  /// ([mediaManageSummaries]).
  List<Widget> _manage(List<MediaRow> rows, SettingsModel settings) {
    final summaries = mediaManageSummaries(
      rows,
      title: (connection) =>
          settings.connectionTitle(connection.id, connection.service),
    );
    if (summaries == null) return const [];
    return [
      _Heading('Manage', key: _manageKey),
      _RowsCard(
        views: const [],
        children: [
          _ManageRow(
            title: 'Files & quality',
            summary: summaries.files,
            body: (context) => _Files(rows: rows, settings: settings),
          ),
          _ManageRow(
            title: 'History',
            summary: summaries.history,
            body: (context) => _History(rows: rows, settings: settings),
          ),
          if (summaries.subtitles case final subtitles?)
            _ManageRow(title: 'Subtitles', summary: subtitles),
          _ManageRow(title: 'Search releases', summary: summaries.search),
        ],
      ),
    ];
  }
}

/// The back control: a 44 plate at rest over the room.
class _BackPlate extends StatelessWidget {
  const _BackPlate();

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      child: PressableScale(
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          width: DesignTokens.sizeTouch,
          height: DesignTokens.sizeTouch,
          decoration: BoxDecoration(
            color: room.fillControl,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: room.edge),
          ),
          child: Icon(Icons.chevron_left_rounded, size: 26, color: room.ink),
        ),
      ),
    );
  }
}

/// Artwork, poster and title: the backdrop in a slab, the poster rising out
/// of its foot, the title beside the poster, then the meta line.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.identity,
    required this.marks,
    required this.onArtDrawn,
    this.light,
  });

  /// Told when the backdrop or the poster has been drawn.
  final ValueChanged<String> onArtDrawn;

  final MediaIdentity? identity;
  final List<String> marks;

  /// The title's light, or null for the lamp.
  final TitleLight? light;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final identity = this.identity;
    const backdropHeight = 214.0;
    const posterWidth = 88.0;
    const posterHeight = 132.0;
    const rise = 52.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                Container(
                  height: backdropHeight,
                  decoration: BoxDecoration(
                    color: room.raised,
                    borderRadius: BorderRadius.circular(AppRadius.slab),
                    boxShadow: AppElevation.hero(scheme, light: light?.light),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _Artwork(
                    url: identity?.backdropUrl,
                    onDrawn: onArtDrawn,
                  ),
                ),
                // The poster rises [rise] into the artwork: the rest of it
                // is the space below.
                const SizedBox(height: posterHeight - rise),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              top: backdropHeight - rise,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: posterWidth,
                    height: posterHeight,
                    decoration: BoxDecoration(
                      color: room.raised,
                      borderRadius: BorderRadius.circular(AppRadius.poster),
                      border: Border.all(color: room.edge),
                      boxShadow: AppElevation.poster(
                        scheme,
                        light: light?.light,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _Artwork(
                      url: identity?.posterUrl,
                      onDrawn: onArtDrawn,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.slabY),
                  Expanded(
                    child: Padding(
                      // Clear of the artwork: the title starts under it.
                      padding: const EdgeInsets.only(top: rise + AppSpacing.md),
                      child: Semantics(
                        header: true,
                        child: Text(
                          identity?.title ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.media.copyWith(color: room.ink),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              identity?.metaLine ?? '',
              style: AppType.label
                  .weight(FontWeight.w400)
                  .copyWith(color: room.inkSecondary),
            ),
            for (final mark in marks) _Mark(mark),
          ],
        ),
      ],
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: room.inkTertiary),
      ),
      child: Text(
        text,
        style: AppType.micro.copyWith(color: room.inkSecondary),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, this.onDrawn});

  final String? url;

  /// Told once the picture is drawn, with its address.
  final ValueChanged<String>? onDrawn;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) return const SizedBox.expand();
    return ArtworkDecodeBox(
      builder: (context, decode) => CachedNetworkImage(
        imageUrl: url,
        cacheManager: pinnedImageCacheFor(url),
        memCacheWidth: decode.width,
        memCacheHeight: decode.height,
        fit: BoxFit.cover,
        imageBuilder: (context, image) {
          onDrawn?.call(url);
          return Image(image: image, fit: BoxFit.cover);
        },
        placeholder: (context, url) =>
            const ShimmerPlaceholder(height: double.infinity),
        errorWidget: (context, url, error) => const SizedBox.expand(),
      ),
    );
  }
}

/// The four scores in one slab, each with its source; a source with no
/// figure reads `—`.
class _Scores extends StatelessWidget {
  const _Scores({required this.scores, required this.showMetacritic});

  final MediaScores scores;

  /// The requester never sees Metacritic: Seerr has none.
  final bool showMetacritic;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    String figure(num? value, {bool decimal = true}) => value == null
        ? '—'
        : decimal
        ? value.toStringAsFixed(1)
        : '$value';
    final cells = [
      ('TMDB', figure(scores.tmdb)),
      ('IMDb', figure(scores.imdb)),
      ('Rotten Tomatoes', figure(scores.rottenTomatoes, decimal: false)),
      if (showMetacritic)
        ('Metacritic', figure(scores.metacritic, decimal: false)),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (final (index, cell) in cells.indexed) ...[
              if (index > 0) VerticalDivider(width: 1, color: room.hair),
              Expanded(
                child: Semantics(
                  label: '${cell.$1}: ${cell.$2 == '—' ? 'no score' : cell.$2}',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.row),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          cell.$2,
                          style: AppType.figure.copyWith(color: room.ink),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          cell.$1,
                          style: AppType.micro
                              .weight(FontWeight.w400)
                              .copyWith(color: room.inkTertiary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The one action that leads, and the three beside it: Trailer, Watchlist,
/// Manage.
class _LeadBar extends StatelessWidget {
  const _LeadBar({
    required this.lead,
    required this.onPlay,
    required this.onTrailer,
    required this.onManage,
    this.light,
    required this.hasTrailer,
    required this.showManage,
    required this.serverName,
  });

  final MediaLead lead;

  /// The title's light: the lead takes its tinted fill. Null, the ink.
  final TitleLight? light;
  final void Function(MediaLeadPlay lead) onPlay;
  final VoidCallback? onTrailer;
  final VoidCallback onManage;
  final bool hasTrailer;
  final bool showManage;
  final String Function(MediaLeadPlay lead) serverName;

  @override
  Widget build(BuildContext context) {
    final label = switch (lead) {
      MediaLeadPlay(:final resume) =>
        '${resume ? 'Resume' : 'Play'} on ${serverName(lead as MediaLeadPlay)}',
      MediaLeadAdd(:final arr) => 'Add to ${arr.title}',
      MediaLeadRequest() => 'Request',
      MediaLeadCopy(:final status, :final connection) => resolveMediaAction(
        status,
        const MediaActionCapabilities(
          canSearch: true,
          canInteractiveSearch: true,
          canOpenQueue: true,
        ),
        serviceName: connection.service.title,
      ).label,
      MediaLeadTrailer() || MediaLeadNone() || MediaLeadWaiting() => null,
    };
    final trailerLeads = lead is MediaLeadTrailer;
    // Lit by the title: the tinted fill under its ink in the dark room, the
    // tinted primary under white in the day room. Unlit, the ink.
    final light = this.light;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final leadStyle = light == null
        ? AppTheme.primaryButtonStyle(context)
        : AppTheme.primaryButtonStyle(context).copyWith(
            backgroundColor: WidgetStatePropertyAll(
              dark ? light.actionFill : light.dayPrimary,
            ),
            foregroundColor: WidgetStatePropertyAll(
              dark ? light.actionInk : const Color(0xFFFFFFFF),
            ),
            iconColor: WidgetStatePropertyAll(
              dark ? light.actionInk : const Color(0xFFFFFFFF),
            ),
          );
    // Watchlist is wired with the account the Seerr connection acts as
    // (F-seerr-actas): until then it has no way to keep its promise.
    final secondaries = <(String, IconData, VoidCallback?)>[
      if (hasTrailer && !trailerLeads)
        ('Trailer', Icons.smart_display_outlined, onTrailer),
      ('Watchlist', Icons.bookmark_border_rounded, null),
      if (showManage) ('Manage', Icons.tune_rounded, onManage),
    ];
    final onLead = switch (lead) {
      final MediaLeadPlay play => () => onPlay(play),
      // Add, Request and a copy's own action open the operator's and the
      // requester's flows from the page: lots M5 and M6.
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lead is MediaLeadWaiting)
          const ShimmerPlaceholder(height: DesignTokens.sizeButtonL)
        else if (label != null && label.isNotEmpty)
          FilledButton(
            onPressed: onLead,
            style: leadStyle,
            child: Row(
              children: [
                Expanded(child: Text(label)),
                Icon(
                  lead is MediaLeadPlay
                      ? Icons.play_arrow_rounded
                      : Icons.arrow_forward_rounded,
                  size: 20,
                ),
              ],
            ),
          )
        else if (trailerLeads)
          FilledButton.icon(
            onPressed: onTrailer,
            style: leadStyle,
            icon: const Icon(Icons.smart_display_outlined, size: 20),
            label: const Text('Trailer'),
          ),
        const SizedBox(height: AppSpacing.row),
        Row(
          children: [
            for (final (index, (text, icon, onPressed))
                in secondaries.indexed) ...[
              if (index > 0) const SizedBox(width: AppSpacing.row),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon, size: 17),
                  label: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.section,
        bottom: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: AppType.section.copyWith(color: room.ink),
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
        ],
      ),
    );
  }
}

/// A group of rows on one slab, divided by hairlines.
class _RowsCard extends StatelessWidget {
  const _RowsCard({required this.views, this.children = const []});

  final List<MediaRowView> views;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final items = [for (final view in views) _ServerRow(view), ...children];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.slabY),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.group),
        border: Border.all(color: room.hair),
      ),
      child: Column(
        children: [
          for (final (index, item) in items.indexed) ...[
            if (index > 0) Divider(height: 1, color: room.hair),
            item,
          ],
        ],
      ),
    );
  }
}

/// One row of "On your server", in the shape its case takes
/// ([MediaRowShape]): the connection on the left, a fixed 92; what it holds;
/// on the right the state, or the row's one way forward.
class _ServerRow extends StatelessWidget {
  const _ServerRow(this.view);

  final MediaRowView view;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(scheme, view.tone, surface: room.ground);
    final waiting = view.state.isEmpty;
    final secondary = AppType.meta
        .weight(FontWeight.w400)
        .copyWith(color: room.inkTertiary);
    final stateStyle = AppType.meta
        .weight(FontWeight.w600)
        .copyWith(color: room.inkSecondary);

    Widget state() => ConstrainedBox(
      // The state takes its own width, up to a third of the row: the detail
      // gets the rest, and a long state wraps inside its own column.
      constraints: const BoxConstraints(maxWidth: 150),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: view.hollow ? null : tone,
              border: view.hollow
                  ? Border.all(color: room.inkSecondary, width: 1.5)
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Flexible(child: Text(view.state, style: stateStyle)),
        ],
      ),
    );

    final middle = switch (view.shape) {
      _ when waiting => const Align(
        alignment: Alignment.centerLeft,
        child: ShimmerPlaceholder(width: 120, height: 12),
      ),
      MediaRowShape.fact ||
      MediaRowShape.claim => Text(view.detail, style: secondary),
      MediaRowShape.notSetUp => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(view.state, style: stateStyle),
          if (view.detail.isNotEmpty) Text(view.detail, style: secondary),
        ],
      ),
      MediaRowShape.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(view.state, style: stateStyle.copyWith(color: tone)),
          if (view.detail.isNotEmpty) Text(view.detail, style: secondary),
        ],
      ),
    };

    final trailing = switch (view.shape) {
      _ when waiting => null,
      MediaRowShape.fact || MediaRowShape.claim => state(),
      MediaRowShape.notSetUp || MediaRowShape.failed => Text(
        view.action ?? '',
        style: AppType.label.copyWith(color: room.ink),
      ),
    };

    return Semantics(
      container: true,
      button: view.action != null,
      label: view.spoken,
      excludeSemantics: true,
      child: Opacity(
        opacity: view.dimmed ? 0.62 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            view.name,
                            style: AppType.row.copyWith(color: room.ink),
                          ),
                          if (view.via case final via?)
                            Text(
                              via,
                              style: AppType.caption.copyWith(
                                color: room.inkTertiary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.row),
                    Expanded(child: middle),
                    if (trailing != null) ...[
                      const SizedBox(width: AppSpacing.row),
                      trailing,
                    ],
                  ],
                ),
              ),
              if (view.shape == MediaRowShape.claim && view.action != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, size: 18, color: room.ink),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: Text(
                          view.action!,
                          style: AppType.label.copyWith(color: room.ink),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A closed operator section: its title and what it holds in one line.
/// A closed operator section: its title and what it holds in one line,
/// opening on [body] when there is one. Its content is built when it opens:
/// a section nobody opens reads nothing.
class _ManageRow extends StatefulWidget {
  const _ManageRow({required this.title, required this.summary, this.body});

  final String title;
  final String summary;
  final WidgetBuilder? body;

  @override
  State<_ManageRow> createState() => _ManageRowState();
}

class _ManageRowState extends State<_ManageRow> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final body = widget.body;
    final header = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: AppType.row.copyWith(color: room.ink),
                ),
                if (widget.summary.isNotEmpty)
                  Text(
                    widget.summary,
                    style: AppType.meta
                        .weight(FontWeight.w400)
                        .copyWith(color: room.inkTertiary),
                  ),
              ],
            ),
          ),
          if (body != null)
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: room.inkTertiary,
              ),
            ),
        ],
      ),
    );
    if (body == null) return header;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: header,
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.slabY),
            child: body(context),
          ),
      ],
    );
  }
}

/// Files & quality, open: every copy under its connection's name, its file
/// as the service records it, or the row a copy with nothing on disk keeps.
class _Files extends StatelessWidget {
  const _Files({required this.rows, required this.settings});

  final List<MediaRow> rows;
  final SettingsModel settings;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final copies = [
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaRadarrCopy(:final movie?))
            (connection: connection, file: movie.movieFile, folder: movie.path),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final copy in copies) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              [
                settings.connectionTitle(
                  copy.connection.id,
                  copy.connection.service,
                ),
                if (copy.file?.qualityName case final quality?
                    when quality.isNotEmpty)
                  qualityWords(quality),
                if (copy.file?.size case final size? when size > 0)
                  formatBytes(size),
              ].join(' · '),
              style: AppType.label.copyWith(color: room.inkSecondary),
            ),
          ),
          switch (copy.file) {
            ArrMediaFile(:final fileName?) => FileInfoSection.file(
              fileName: fileName,
              releasedAs: copy.file!.releasedAs,
              path: copy.folder,
            ),
            _ => const FileInfoSection.missing(),
          },
        ],
      ],
    );
  }
}

/// History, open: each Radarr copy's own events, newest first, read when the
/// section opens.
class _History extends ConsumerWidget {
  const _History({required this.rows, required this.settings});

  final List<MediaRow> rows;
  final SettingsModel settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final copies = [
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaRadarrCopy(:final movie?))
            (connection: connection, movieId: movie.id),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final copy in copies) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              settings.connectionTitle(
                copy.connection.id,
                copy.connection.service,
              ),
              style: AppType.label.copyWith(color: room.inkSecondary),
            ),
          ),
          switch (ref.watch(
            mediaRadarrHistoryProvider((
              connectionId: copy.connection.id,
              movieId: copy.movieId,
            )),
          )) {
            AsyncValue(:final value?) when value.isEmpty => Text(
              'Nothing in its history yet',
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
            AsyncValue(:final value?) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final record in value.take(8))
                  _HistoryLine(record: record, scheme: scheme),
              ],
            ),
            AsyncValue(:final error?) => InlineErrorRetry(
              message: 'Could not read the history',
              error: error,
              service: copy.connection.service,
              instanceId: copy.connection.id,
              onRetry: () => ref.invalidate(
                mediaRadarrHistoryProvider((
                  connectionId: copy.connection.id,
                  movieId: copy.movieId,
                )),
              ),
            ),
            _ => const ShimmerPlaceholder(height: 36),
          },
        ],
      ],
    );
  }
}

/// One event: its word in its tone, the release's quality, the day.
class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.record, required this.scheme});

  final Map<String, dynamic> record;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final event = '${record['eventType'] ?? ''}';
    final quality = mapOrNull(
      mapOrNull(record['quality'])?['quality'],
    )?['name'];
    final date = '${record['date'] ?? ''}';
    final words = [
      historyEventLabel(event),
      if (quality is String && quality.isNotEmpty) qualityWords(quality),
      if (date.isNotEmpty) formatShortDate(date),
    ];
    return Semantics(
      container: true,
      label: words.join('. '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusToneColor(
                  scheme,
                  historyEventTone(event),
                  surface: room.ground,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                words.join(' · '),
                style: AppType.meta
                    .weight(FontWeight.w400)
                    .copyWith(color: room.inkSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
