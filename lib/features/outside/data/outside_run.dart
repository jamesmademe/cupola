/// The run: reads what the widgets draw and the notifications say, writes it
/// where the widgets read it, and says what is new.
///
/// One run for every place it starts from. The app runs it in its own
/// container as it leaves the screen, and some seconds after a start, so a
/// widget is as fresh as the last look at the app, which on iOS is the
/// common case; with nothing on the screen (T3.2's WorkManager and
/// BGAppRefresh), it runs in a container built from the same startup
/// (`readHeadlessStartup`). Either way it reads the same providers the
/// Home's modules read, through the same route, access and pins, so what a
/// widget says is what the Home would say.
library;

import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/network/network_registries.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/outside/data/outside_faces.dart';
import 'package:cupola/features/outside/data/outside_shelf.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/outside/domain/outside_snapshot.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/route_probe.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// How long a run waits for all its reads together. iOS gives a background
/// refresh about thirty seconds, and the writing comes after: a read that has
/// not answered by then is a read that did not answer, and its widget keeps
/// the frames it had. A container built for a run turns Riverpod's retries
/// off (`retry: (_, _) => null`): a read that failed is not worth waiting on
/// while it is tried again.
const outsideReadBudget = Duration(seconds: 20);

/// One read: whose it is, when, each widget's frames and each kind's
/// notices. For a widget, an empty list is a person with nothing to show
/// there (no calendar set up), and null a read that did not answer. For a
/// kind, null is a read that did not answer or was not asked (its switch is
/// off). [pictures] are the sources of the file names the frames carry.
typedef OutsideReading = ({
  Audience audience,
  DateTime takenAt,
  Map<OutsideWidget, List<OutsideFrame>?> frames,
  Map<OutsideNoticeKind, List<OutsideNotice>?> notices,
  Map<String, ImageSource> pictures,
});

/// Reads [container] at [now], for the notification kinds that are [enabled]:
/// a kind switched off is not read at all, so a person who wants no
/// notification costs their servers nothing for it. [probe] asks where each
/// connection is reached from first; the app on the screen already knows.
Future<OutsideReading> readOutside(
  ProviderContainer container, {
  required DateTime now,
  required Set<OutsideNoticeKind> enabled,
  bool probe = true,
  Duration budget = outsideReadBudget,
}) async {
  final kept = <ProviderSubscription<Object?>>[];
  // Measured, not dated: [now] is the clock the words are said against,
  // which a test fixes.
  final elapsed = Stopwatch()..start();
  Future<T?> settle<T>(ProviderListenable<Future<T>> future) async {
    final subscription = container.listen(future, (_, _) {});
    kept.add(subscription);
    final left = budget - elapsed.elapsed;
    if (left <= Duration.zero) return null;
    try {
      return await subscription.read().timeout(left);
    } catch (_) {
      return null;
    }
  }

  final pictures = <String, ImageSource>{};
  String? picture(ImageSource? source) {
    if (source == null || source.url.isEmpty) return null;
    final name = outsidePictureName(source.url);
    pictures[name] = source;
    return name;
  }

  try {
    kept.add(container.listen(networkRegistriesProvider, (_, _) {}));
    // Where each connection is reached from here: the phone may have left
    // home since the app last asked. The app on the screen keeps its own.
    if (probe) {
      await container
          .read(routeProbeProvider)
          .probeAll()
          .timeout(budget ~/ 4, onTimeout: () {});
    }

    final settings = container.read(currentSettingsProvider);
    final audience = container.read(shellAudienceProvider);
    final frames = <OutsideWidget, List<OutsideFrame>?>{};
    final notices = <OutsideNoticeKind, List<OutsideNotice>?>{};

    String? requestRoute(MyRequest mine) {
      final id = mine.request.media?.tmdbId;
      if (id == null) return null;
      return ServiceRoutes.media(
        mine.request.type == 'tv' ? MediaKey.tv(id) : MediaKey.movie(id),
        from: ServiceRoutes.home,
      );
    }

    List<OutsideNotice> arrivals(
      Iterable<({String instanceId, SeerrRequest request})> requests,
    ) {
      final byRequest = {
        for (final (:instanceId, :request) in requests) request: instanceId,
      };
      return readyToWatchNotices(
        myRequestsOf(byRequest.keys, now: now),
        idOf: (mine) => 'seerr-${byRequest[mine.request]}-${mine.request.id}',
        routeOf: requestRoute,
        pictureOf: (mine) => picture(_tmdb(mine.request.media?.posterPath)),
      );
    }

    final seerr = settings.isServiceConfigured(ServiceKey.seerr);
    switch (audience) {
      case Audience.requester:
        final requests = seerr ? await settle(requestsProvider.future) : null;
        final lens = container.read(activeInstanceProvider(ServiceKey.seerr));
        frames[OutsideWidget.requests] = !seerr
            ? const []
            : requests == null
            ? null
            : requestsFrames(requests, takenAt: now, pictures: picture);
        if (enabled.contains(OutsideNoticeKind.readyToWatch)) {
          notices[OutsideNoticeKind.readyToWatch] = requests == null
              ? null
              : arrivals([
                  for (final request in requests)
                    (instanceId: lens?.id ?? '', request: request),
                ]);
        }
      case Audience.operator:
        await Future.wait([
          () async {
            if (!container.read(hasLibraryCalendarProvider)) {
              frames[OutsideWidget.comingUp] = const [];
              return;
            }
            final calendar = await settle(libraryCalendarProvider.future);
            frames[OutsideWidget.comingUp] =
                calendar == null ||
                    (calendar.answered.isEmpty && calendar.silent.isNotEmpty)
                ? null
                : comingUpFrames(
                    calendar.events,
                    takenAt: now,
                    pictures: picture,
                  );
          }(),
          () async {
            if (!HomeModule.downloads.services.any(
              settings.isServiceConfigured,
            )) {
              frames[OutsideWidget.downloads] = const [];
              return;
            }
            final data = await settle(servicesInFlightProvider.future);
            frames[OutsideWidget.downloads] = data == null
                ? null
                : downloadsFrames(
                    data,
                    takenAt: now,
                    clientSetUp: downloadClients.any(
                      settings.isServiceConfigured,
                    ),
                    clientSilent: data.coverage.failedServices.any(
                      downloadClients.contains,
                    ),
                  );
          }(),
          if (enabled.contains(OutsideNoticeKind.needsYou))
            () async {
              final sources = await Future.wait([
                for (final source in DecisionSource.values)
                  settle(dashboardDecisionSourceProvider(source).future),
              ]);
              if (sources.every((read) => read == null)) return;
              final decisions = container.read(dashboardDecisionsProvider);
              notices[OutsideNoticeKind.needsYou] =
                  decisions.coverage.everySourceFailed
                  ? null
                  : needsYouNotices(decisions.decisions, now: now);
            }(),
          if (enabled.contains(OutsideNoticeKind.readyToWatch) && seerr)
            () async {
              final ids = container.read(
                serviceInstanceIdsProvider(ServiceKey.seerr),
              );
              final reads = await Future.wait([
                for (final id in ids) settle(requestsForProvider(id).future),
              ]);
              // Every Seerr or none: an arrival on a Seerr that did not
              // answer is not an arrival that went away.
              if (reads.any((read) => read == null)) return;
              notices[OutsideNoticeKind.readyToWatch] = arrivals([
                for (final (index, id) in ids.indexed)
                  for (final request in reads[index]!)
                    (instanceId: id, request: request),
              ]);
            }(),
        ]);
    }
    return (
      audience: audience,
      takenAt: now,
      frames: frames,
      notices: notices,
      pictures: pictures,
    );
  } finally {
    for (final subscription in kept) {
      subscription.close();
    }
  }
}

ImageSource? _tmdb(String? path) {
  final url = ImageUtils.buildTmdbPosterUrl(path, size: 'w342');
  return url.isEmpty ? null : (url: url, headers: null);
}

/// Fetches [source] the way the app's own posters are fetched: through the
/// cache the Home's pictures already filled, pinned where the server's
/// certificate is, with the connection's headers.
Future<List<int>?> fetchOutsidePicture(ImageSource source) async {
  final manager = pinnedImageCacheFor(source.url) ?? DefaultCacheManager();
  final file = await manager.getSingleFile(
    source.url,
    headers: source.headers ?? const {},
  );
  return file.readAsBytes();
}

/// Says notifications. Posting is the platform's (T3.3): the run hands it
/// what is new and the shelf the pictures are on.
abstract interface class OutsideSpeaker {
  Future<void> say(List<OutsideNotice> notices, OutsideShelf shelf);
}

/// Asks the widgets to draw the snapshot again (the native side's).
abstract interface class OutsideWidgets {
  Future<void> reload();
}

/// One run: [readOutside], then the shelf, the pictures, the notifications
/// and the widgets, in that order, so a widget never names a picture that is
/// not on disk yet.
class OutsideRun {
  OutsideRun({
    required this.shelf,
    this.fetch = fetchOutsidePicture,
    this.speaker,
    this.widgets,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final OutsideShelf shelf;
  final Future<List<int>?> Function(ImageSource source) fetch;
  final OutsideSpeaker? speaker;
  final OutsideWidgets? widgets;
  final DateTime Function() _clock;

  /// Runs over [container]. [speak] false is the app on the screen: what it
  /// shows is recorded as seen and nothing is said.
  Future<OutsideHeard> run(
    ProviderContainer container, {
    required bool speak,
    required Set<OutsideNoticeKind> enabled,
    bool probe = true,
    Duration budget = outsideReadBudget,
  }) async {
    final reading = await readOutside(
      container,
      now: _clock(),
      enabled: enabled,
      probe: probe,
      budget: budget,
    );
    final plan = await shelf.plan(
      OutsideSnapshot(
        takenAt: reading.takenAt,
        audience: reading.audience.name,
        frames: {
          for (final MapEntry(:key, :value) in reading.frames.entries)
            key: ?value,
        },
      ),
      unread: {
        for (final MapEntry(:key, :value) in reading.frames.entries)
          if (value == null) key,
      },
    );
    final heard = outsideNoticesOf(
      current: reading.notices,
      said: await shelf.readSaid(),
      enabled: enabled,
      now: reading.takenAt,
      speak: speak,
    );
    plan.pictures.addAll([for (final notice in heard.say) ?notice.picture]);
    await shelf.keepPictures(plan, reading.pictures, fetch);
    await shelf.write(plan);
    await shelf.writeSaid(heard.said);
    if (heard.say.isNotEmpty) await speaker?.say(heard.say, shelf);
    await widgets?.reload();
    return heard;
  }
}
