/// What can be done for a title of Seerr's catalogue from outside its page:
/// ask for it, add it, open it in the arr that holds it, copy its link. The
/// row's plus (`CatalogTitleRow`) and the poster's menu (`CatalogPoster`)
/// both act through here, so the two never disagree.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/row_actions.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_download_row.dart'
    show openArrTitle;
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/request_bottom_sheet.dart';
import 'package:cupola/features/media/domain/operator_adds_via.dart';
import 'package:cupola/features/media/presentation/media_add_sheet.dart';
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

/// The arr a title of [mediaType] goes to.
ServiceKey catalogArrOf(String mediaType) =>
    mediaType == 'tv' ? ServiceKey.sonarr : ServiceKey.radarr;

/// TMDB's own page of the title.
String tmdbPageOf(MediaPreview media, {required String mediaType}) =>
    'https://www.themoviedb.org/${mediaType == 'tv' ? 'tv' : 'movie'}/'
    '${media.id}';

/// The request sheet a title's page opens, for [copies] of [media].
void requestCatalogTitle(
  BuildContext context,
  MediaPreview media, {
  required String mediaType,
  required SeerrRequestCopies copies,
  VoidCallback? onDone,
}) {
  final isMovie = mediaType != 'tv';
  AppBottomSheet.show<void>(
    context: context,
    title: 'Request ${media.title}',
    subtitle: [
      if (media.year.isNotEmpty) media.year,
      isMovie ? 'Movie' : 'Series',
    ].join(dotSeparator),
    // Closed as its sibling the add sheet is.
    showClose: true,
    builder: (_) => RequestBottomSheet(
      mediaId: media.id,
      mediaType: isMovie ? 'movie' : 'tv',
      copies: copies,
      title: media.title,
      onRequestComplete: () {
        if (!context.mounted) return;
        SnackBarHelper.success(context, 'Request submitted');
        onDone?.call();
      },
    ),
  );
}

/// The add sheet a title's page opens; then the library it went to is read
/// again, so whatever shows the title says where it is on the arr's word.
Future<void> addCatalogTitle(
  BuildContext context,
  WidgetRef ref,
  MediaPreview media, {
  required String mediaType,
  required List<ServiceInstance> connections,
  VoidCallback? onDone,
}) async {
  final settings = ref.read(currentSettingsProvider);
  String name(ServiceInstance c) => settings.connectionTitle(c.id, c.service);
  final arr = catalogArrOf(mediaType);
  final added = await showMediaAddSheet(
    context,
    arr: arr,
    connections: connections,
    name: name,
    title: media.title,
    tmdbId: media.id,
    year: media.year.isEmpty ? null : media.year,
  );
  if (added == null || !context.mounted) return;
  SnackBarHelper.success(context, 'Added to ${name(added)}');
  // The lens's library is the plain provider's: both, or a row would read
  // the copy from before the add.
  if (arr == ServiceKey.radarr) {
    ref
      ..invalidate(moviesProvider)
      ..invalidate(moviesForProvider(added.id));
  } else {
    ref
      ..invalidate(seriesProvider)
      ..invalidate(seriesForProvider(added.id));
  }
  onDone?.call();
}

/// How long the menu waits for a library it has not read yet. Read once a
/// session; past this the menu opens without what the library would say.
const _libraryWait = Duration(seconds: 4);

/// The poster's menu for [media], opened at [at]: Open; Request or Add to
/// the arr, by the rule the row's plus follows; Open in the arr that holds
/// it, for the operator; Copy TMDB link. A Request the account may not make
/// stays, and says why when chosen.
///
/// The arr's libraries are read when the menu opens, not by every poster:
/// a catalogue is hundreds of titles, and each library is read once a
/// session. When one does not answer in time, neither Add nor Open in is
/// offered, rather than an Add for a title the library may hold.
Future<void> showCatalogTitleMenu(
  BuildContext context,
  WidgetRef ref,
  MediaPreview media, {
  required String mediaType,
  required VoidCallback onOpen,
  Offset? at,
}) async {
  final actions = await catalogTitleActions(
    context,
    ref,
    media,
    mediaType: mediaType,
    onOpen: onOpen,
  );
  if (!context.mounted) return;
  await showRowActions(context, at, actions);
}

/// The actions [showCatalogTitleMenu] offers, in its order.
Future<List<RowAction>> catalogTitleActions(
  BuildContext context,
  WidgetRef ref,
  MediaPreview media, {
  required String mediaType,
  required VoidCallback onOpen,
}) async {
  final isMovie = mediaType != 'tv';
  final arr = catalogArrOf(mediaType);
  final settings = ref.read(currentSettingsProvider);
  final audience = ref.read(audienceProvider);
  final kind = isMovie ? SeerrMediaKind.movie : SeerrMediaKind.tv;
  // The standard copy: what a request from outside the page is for.
  final gate = seerrRequestGate(
    media.mediaInfo,
    isMovie: isMovie,
    numbering: ref.read(seerrNumberingProvider).value,
  );
  final open = gate.state == SeerrRequestState.open;
  final verdict = ref.read(roleGateProvider('')).requestAction(kind);
  String name(ServiceInstance c) => settings.connectionTitle(c.id, c.service);

  final connections = audience == Audience.operator
      ? settings.configuredInstancesOf(arr)
      : const <ServiceInstance>[];

  // Which connection holds the title, and under which of its ids.
  var answered = true;
  ({ServiceInstance connection, int id})? heldBy;
  for (final connection in connections) {
    try {
      final held = await _heldIn(ref, arr, connection.id, media.id);
      if (held != null) {
        heldBy = (connection: connection, id: held);
        break;
      }
    } on Object {
      answered = false;
    }
  }

  // Through Seerr when it has a server of this arr to send to.
  Future<bool?> sendsTo() async {
    try {
      return await ref
          .read(seerrSendsToProvider(arr).future)
          .timeout(_libraryWait);
    } on Object {
      return null;
    }
  }

  RowAction? request() => switch (verdict) {
    Live() => (
      label: 'Request',
      icon: Icons.add_rounded,
      onSelected: () => requestCatalogTitle(
        context,
        media,
        mediaType: mediaType,
        copies: gate.copies,
      ),
    ),
    Dimmed(:final reason) => (
      label: 'Request',
      icon: Icons.add_rounded,
      onSelected: () => SnackBarHelper.info(context, reason),
    ),
    _ => null,
  };

  RowAction? lead;
  if (open && heldBy == null) {
    if (audience == Audience.requester) {
      lead = request();
    } else if (connections.isNotEmpty) {
      if (answered) {
        final seerrChoice =
            settings.configuredInstancesOf(ServiceKey.seerr).isNotEmpty &&
            ref.read(operatorAddsViaProvider) == OperatorAddsVia.seerr;
        final viaSeerr =
            seerrChoice && verdict is Live && await sendsTo() == true;
        final where = connections.length == 1
            ? name(connections.single)
            : arr.title;
        lead = viaSeerr
            ? request()
            : (
                label: 'Add to $where',
                icon: Icons.add_rounded,
                onSelected: () => addCatalogTitle(
                  context,
                  ref,
                  media,
                  mediaType: mediaType,
                  connections: connections,
                ),
              );
      }
    } else if (await sendsTo() == true) {
      lead = request();
    }
  }

  final held = heldBy;
  return [
    (label: 'Open', icon: Icons.open_in_new_rounded, onSelected: onOpen),
    ?lead,
    if (held != null)
      (
        label: 'Open in ${name(held.connection)}',
        icon: Icons.explore_outlined,
        onSelected: () => openArrTitle(
          context,
          service: arr,
          mediaId: held.id,
          instanceId: held.connection.id,
        ),
      ),
    (
      label: 'Copy TMDB link',
      icon: Icons.content_copy_rounded,
      onSelected: () async {
        await Clipboard.setData(
          ClipboardData(text: tmdbPageOf(media, mediaType: mediaType)),
        );
        if (!context.mounted) return;
        SnackBarHelper.info(context, 'Link copied');
      },
    ),
  ];
}

/// The id [connection]'s library of [arr] holds TMDB's [tmdbId] under, or
/// null when it holds no such title. Throws when the library did not answer
/// in time.
Future<int?> _heldIn(
  WidgetRef ref,
  ServiceKey arr,
  String connection,
  int tmdbId,
) async {
  if (arr == ServiceKey.radarr) {
    final movies = await ref
        .read(moviesForProvider(connection).future)
        .timeout(_libraryWait);
    return movies.where((m) => m.tmdbId == tmdbId).firstOrNull?.id;
  }
  final series = await ref
      .read(seriesForProvider(connection).future)
      .timeout(_libraryWait);
  return series.where((s) => s.tmdbId == tmdbId).firstOrNull?.id;
}
