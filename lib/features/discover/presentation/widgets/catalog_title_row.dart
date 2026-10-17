import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/request_bottom_sheet.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/media/domain/operator_adds_via.dart';
import 'package:cupola/features/media/presentation/media_add_sheet.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/settings/data/operator_adds_via_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Whether the lens's Seerr has a Radarr or a Sonarr ([arr]) to send a
/// request to, from the list the request sheet reads. Throws when Seerr did
/// not answer.
final seerrSendsToProvider = FutureProvider.autoDispose
    .family<bool, ServiceKey>((ref, arr) async {
      final service = ref.watch(seerrServiceProvider);
      final servers = arr == ServiceKey.sonarr
          ? await service.getSonarrServers()
          : await service.getRadarrServers();
      return servers.isNotEmpty;
    }, retry: noProviderRetry);

/// The TMDB ids one connection of [arr] holds, from its library: the read
/// the library pages make, once a session.
final _heldTmdbIdsProvider = Provider.autoDispose
    .family<AsyncValue<Set<int>>, (ServiceKey, String)>((ref, arg) {
      final (arr, connection) = arg;
      return arr == ServiceKey.radarr
          ? ref
                .watch(moviesForProvider(connection))
                .whenData((movies) => {for (final m in movies) m.tmdbId})
          : ref
                .watch(seriesForProvider(connection))
                .whenData((series) => {for (final s in series) s.tmdbId});
    });

/// A title Seerr lists on a person's or a collection's page: its row, where
/// it stands, and what can be done for it from here.
///
/// Where it stands is Seerr's word; with none, the arr library that holds
/// it. At its end, for the operator: the plus to the title's arr when it is
/// set up, every connection of it has answered and none holds the title;
/// without that arr, Request when Seerr has one to send it to; and with
/// neither, the plus dimmed, naming the arr to set up. The requester is
/// offered Request, as far as the account may. Nothing is offered for a
/// title that is there, on its way or asked for.
class CatalogTitleRow extends ConsumerWidget {
  const CatalogTitleRow({
    super.key,
    required this.media,
    required this.meta,
    required this.heroTag,
    required this.onChanged,
  });

  final MediaPreview media;

  /// `2012 · Movie · TMDB 6.6`.
  final String meta;

  /// Unique on the page: the same title can sit in two of its sections.
  final String heroTag;

  /// After a request or an add: the page reads its record again.
  final VoidCallback onChanged;

  bool get _isMovie => media.mediaType != 'tv';

  ServiceKey get _arr => _isMovie ? ServiceKey.radarr : ServiceKey.sonarr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final audience = ref.watch(audienceProvider);
    final numbering = ref.watch(seerrNumberingProvider).value;
    final kind = _isMovie ? SeerrMediaKind.movie : SeerrMediaKind.tv;
    final poster = ImageUtils.buildTmdbPosterUrl(media.posterPath);
    // The standard copy: what a request from a row is for.
    final gate = seerrRequestGate(
      media.mediaInfo,
      isMovie: _isMovie,
      numbering: numbering,
    );
    final open = gate.state == SeerrRequestState.open;

    final connections = audience == Audience.operator
        ? settings.configuredInstancesOf(_arr)
        : const <ServiceInstance>[];
    String name(ServiceInstance c) => settings.connectionTitle(c.id, c.service);
    final libraries = [
      for (final connection in connections)
        (
          connection: connection,
          ids: ref.watch(_heldTmdbIdsProvider((_arr, connection.id))),
        ),
    ];
    final heldBy = libraries
        .where((l) => l.ids.value?.contains(media.id) ?? false)
        .map((l) => l.connection)
        .firstOrNull;

    final seerr = seerrCatalogStatus(
      media.mediaInfo,
      numbering: numbering,
      audience: audience,
    );
    final status = seerr != null
        ? (label: seerr.label, tone: seerr.tone)
        : heldBy != null
        ? (label: 'In ${name(heldBy)}', tone: StatusTone.neutral)
        : null;

    SearchRowAction request() => SearchRowRequest(
      label: 'Request ${media.title}',
      verdict: ref.watch(roleGateProvider('')).requestAction(kind),
      onTap: () => _request(context, gate.copies),
    );
    final SearchRowAction? action;
    if (!open || heldBy != null) {
      action = null;
    } else if (audience == Audience.requester) {
      action = request();
    } else if (connections.isNotEmpty) {
      final where = connections.length == 1
          ? name(connections.single)
          : _arr.title;
      final answered = libraries.every((l) => l.ids.hasValue);
      // Through Seerr, the plus requests the title when Seerr has a server of
      // this arr to send it to and this account may ask; otherwise it adds to
      // the arr. Read only where a Seerr is set up, as the lead reads it. While
      // Seerr is still asked, the plus waits rather than flipping from Add to
      // Request once the answer comes.
      final seerrChoice =
          settings.configuredInstancesOf(ServiceKey.seerr).isNotEmpty &&
          ref.watch(operatorAddsViaProvider) == OperatorAddsVia.seerr;
      final sendsTo = seerrChoice
          ? ref.watch(seerrSendsToProvider(_arr))
          : null;
      final mayAsk =
          ref.watch(roleGateProvider('')).requestAction(kind) is Live;
      action = !answered || (sendsTo?.isLoading ?? false)
          ? null
          : sendsTo?.value == true && mayAsk
          ? request()
          : SearchRowAdd(
              label: 'Add ${media.title} to $where',
              onTap: () => _add(context, ref, connections, name),
            );
    } else {
      action = switch (ref.watch(seerrSendsToProvider(_arr))) {
        AsyncData(value: true) => request(),
        AsyncData() || AsyncError() => SearchRowSetUp(
          label: 'Add ${media.title}',
          service: _arr,
          blockedMessage: '${Lexicon.isNotSetUp(_arr.title)}.',
        ),
        _ => null,
      };
    }

    return SearchRow.title(
      title: media.title,
      meta: meta,
      status: status,
      poster: poster,
      heroTag: heroTag,
      onTap: () => context.openSeerrTitle(
        mediaType: media.mediaType,
        id: media.id,
        heroTag: poster.isEmpty ? null : heroTag,
        posterUrl: poster.isEmpty ? null : poster,
      ),
      action: action,
      selected: context.paneShows(
        media.mediaType == 'tv'
            ? MediaKey.tv(media.id)
            : MediaKey.movie(media.id),
      ),
    );
  }

  /// The request sheet a title's page opens.
  void _request(BuildContext context, SeerrRequestCopies copies) {
    AppBottomSheet.show<void>(
      context: context,
      title: 'Request ${media.title}',
      subtitle: [
        if (media.year.isNotEmpty) media.year,
        _isMovie ? 'Movie' : 'Series',
      ].join(dotSeparator),
      // Closed as its sibling the add sheet is.
      showClose: true,
      builder: (_) => RequestBottomSheet(
        mediaId: media.id,
        mediaType: _isMovie ? 'movie' : 'tv',
        copies: copies,
        title: media.title,
        onRequestComplete: () {
          if (!context.mounted) return;
          SnackBarHelper.success(context, 'Request submitted');
          onChanged();
        },
      ),
    );
  }

  /// The add sheet a title's page opens; then the library it went to is
  /// read again, so the row says where it is on the arr's word.
  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    List<ServiceInstance> connections,
    String Function(ServiceInstance) name,
  ) async {
    final added = await showMediaAddSheet(
      context,
      arr: _arr,
      connections: connections,
      name: name,
      title: media.title,
      tmdbId: media.id,
      year: media.year.isEmpty ? null : media.year,
    );
    if (added == null || !context.mounted) return;
    SnackBarHelper.success(context, 'Added to ${name(added)}');
    // The lens's library is the plain provider's: both, or the row would
    // read the copy from before the add.
    if (_isMovie) {
      ref
        ..invalidate(moviesProvider)
        ..invalidate(moviesForProvider(added.id));
    } else {
      ref
        ..invalidate(seriesProvider)
        ..invalidate(seriesForProvider(added.id));
    }
    onChanged();
  }
}
