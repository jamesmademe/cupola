import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/features/activity/presentation/global_activity_screen.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/release_search/data/release_search_notifications.dart';
import 'package:cupola/features/release_search/data/release_search_transport.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/presentation/release_search_headroom_provider.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_sheet.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The platform reach is resolved for. Null means "ask the host", which is what
/// production always wants.
///
/// It exists to be overridden: `flutter_test` runs on the desktop, so without
/// this the mobile branch — the only one that ever chooses the native transport,
/// and therefore the only one where the choice is a security decision — could
/// not be exercised from a test at all. See [backgroundSearchSupported] for why
/// the host is read through `dart:io` rather than `defaultTargetPlatform`.
final releaseSearchPlatformProvider = Provider<TargetPlatform?>((ref) => null);

/// How far a search against one **connection** can travel — see
/// [ReleaseSearchReach].
///
/// Both facts reach asks about — the saved URL's scheme and whether that origin
/// is trusted only inside Cupola (ADR-6) — are read straight from settings
/// rather than through `serviceDiagnosisProvider`: reach must stay correct even
/// for an instance that has never been tested this session.
///
/// **Keyed by connection, not by service, and that is a security fix rather
/// than tidying.** It used to read `settings.urlFor(service)` — the FIRST
/// instance — while the request itself was built and sent by the lens-aware
/// service. So the scheme and the pin were read off one server and the API key
/// was sent to another. With the first Radarr on https and the second on plain
/// `http://`, reach answered `beyondTheApp` for the cleartext one and handed
/// the search to the native background task, whose redirect following cannot be
/// stopped — which is precisely the case this reach exists to refuse. The
/// mirror image was merely broken rather than dangerous: a self-signed second
/// instance looked untrusted-but-fine because the first one carried no pin, and
/// every search against it failed on a certificate the app had been told to
/// trust.
final releaseSearchReachProvider = Provider.autoDispose
    .family<ReleaseSearchReach, ReleaseSearchTarget>((ref, target) {
      final settings = ref.watch(currentSettingsProvider);
      return _reachOf(ref, target.service, _urlOf(settings, target), settings);
    });

/// The reach of the connection [service] is currently being READ through.
///
/// The sibling of [releaseSearchReachProvider], for the surfaces that describe
/// a service rather than run a job: the headroom card explains what the path
/// the user is looking at imposes, and it has no target to ask about. Kept
/// apart rather than folded in, because the two answer genuinely different
/// questions the moment a job outlives the lens that started it — which is the
/// whole reason the job side is keyed on a target.
final releaseSearchLensReachProvider =
    Provider.family<ReleaseSearchReach, ServiceKey>((ref, service) {
      final instance = ref.watch(activeInstanceProvider(service));
      final settings = ref.watch(currentSettingsProvider);
      return _reachOf(
        ref,
        service,
        instance?.url ?? settings.urlFor(service),
        settings,
      );
    });

ReleaseSearchReach _reachOf(
  Ref ref,
  ServiceKey service,
  String baseUrl,
  SettingsModel settings,
) {
  return reachFor(
    service,
    baseUrl: baseUrl,
    certTrustedInApp: settings.pinForUrl(baseUrl) != null,
    backgroundEnabled: ref.watch(
      releaseSearchSettingsProvider.select((s) => s.backgroundEnabled),
    ),
    platform: ref.watch(releaseSearchPlatformProvider),
  );
}

/// The transport for a search against [service].
///
/// iOS and Android get the native background task when nothing about
/// [service]'s origin stops it, which is what lets a search outlive
/// suspension. Every other case falls back to the foreground path, which stays
/// on `ApiClient`'s redirect guard and, when the origin is pinned, on the same
/// pinned adapter the real client uses:
///
/// * desktop, which does not suspend apps and so has nothing to survive;
/// * background search switched off, which is the user declining to have the
///   request written to system storage at all;
/// * a certificate trusted only inside Cupola, which the native task cannot
///   see at all;
/// * a cleartext `http://` origin, where the native task's unstoppable redirect
///   following would let anyone on the path collect the API key — the one case
///   here that is a security boundary rather than a capability gap.
///
/// `autoDispose`, unlike almost everything else here: the key is a
/// [ReleaseSearchTarget] with value equality, so without it every episode ever
/// searched would leave a permanent entry listening to `currentSettingsProvider`
/// — a listener list that only grows for the life of the app.
///
/// **This is where the opt-in is enforced, and it is the only place it needs to
/// be.** Nothing else in the app constructs a `DataTask`, so a reach that is
/// not [ReleaseSearchReach.beyondTheApp] cannot enqueue one — which is why the
/// switch is a reach and not an `if` scattered over the call sites.
final releaseSearchTransportProvider = Provider.autoDispose
    .family<ReleaseSearchTransport, ReleaseSearchTarget>((ref, target) {
      final reach = ref.watch(releaseSearchReachProvider(target));
      if (reach == ReleaseSearchReach.beyondTheApp) {
        return const BackgroundReleaseSearchTransport();
      }

      final settings = ref.watch(currentSettingsProvider);
      final pin = settings.pinForUrl(_urlOf(settings, target));
      return ForegroundReleaseSearchTransport((
        url, {
        headers,
        receiveTimeout,
        cancelToken,
      }) async {
        // Note what actually carries the guarantee: [releaseSearchRunnerProvider]
        // routes every non-backgrounding transport through `_searchViaService`,
        // so a cleartext instance's search runs on the arr service's own
        // `ApiClient` and it is *that* client's redirect guard which refuses to
        // replay the API key off-origin. This closure is the transport's own
        // `run`, reached only from a test today — it mirrors the same three
        // lines so the seam cannot become the hole if a caller ever does use it.
        // `SameOriginRedirectInterceptor` needs both options set to see the 3xx.
        final dio = Dio(
          BaseOptions(
            followRedirects: false,
            validateStatus: allowRedirectStatus,
          ),
        );
        dio.interceptors.add(SameOriginRedirectInterceptor(dio));
        final adapter = pinnedHttpClientAdapterFor(
          url.toString(),
          pinnedFingerprint: pin,
        );
        if (adapter != null) dio.httpClientAdapter = adapter;
        try {
          return await dio.getUri<dynamic>(
            url,
            options: Options(headers: headers, receiveTimeout: receiveTimeout),
            cancelToken: cancelToken,
          );
        } finally {
          // Built per request, so it has to be closed per request: a pinned
          // origin gives this `Dio` its own `HttpClient`, and one leaked per
          // search is a socket pool the app never reclaims.
          dio.close();
        }
      });
    });

/// The address of the connection [target] belongs to.
///
/// Falls back to the service's first instance only for an unstamped target,
/// which is the shape a test can still build by hand. Everything the app itself
/// produces has been through `showReleaseSearch` and carries an id.
String _urlOf(SettingsModel settings, ReleaseSearchTarget target) {
  if (target.instanceId.isEmpty) return settings.urlFor(target.service);
  return settings.instanceById(target.instanceId)?.url ?? '';
}

/// Posts the "your search finished" notices, and gives their "Tap to pick one"
/// somewhere to land.
///
/// The notice promises a picker, so a tap has to reach one: the job id travels
/// in the payload, is handed to [pendingReleaseSearchJobProvider], and the
/// Searching list opens that job's sheet on arrival. When the job is gone — the
/// app was killed rather than suspended, so nothing survived in memory — the
/// route still lands on Activity, which is the honest fallback rather than a
/// sheet for a job that no longer exists.
final releaseSearchNotificationsProvider = Provider(
  (ref) => ReleaseSearchNotifications(null, (payload) {
    if (payload != null &&
        ref.read(releaseSearchJobsProvider.notifier).jobById(payload) != null) {
      ref.read(pendingReleaseSearchJobProvider.notifier).request(payload);
    }
    // Both halves are needed, and the second is the one a device pass found
    // missing: routing to /activity alone lands on whichever bucket the user
    // last used, so the Searching list is never built and nothing consumes the
    // request above.
    selectActivitySearching(ref);
    ref.read(routerProvider).go('/activity');
  }),
);

/// Whether the OS is currently letting Cupola post notifications.
///
/// Kept as a provider rather than local state so the answer is asked once and
/// read wherever it matters. Re-read by invalidating it — after the user
/// touches the toggle, and whenever the app comes back from the background,
/// since system settings are exactly where they may have just been.
final notificationPermissionProvider = FutureProvider<bool?>(
  (ref) => ref.read(releaseSearchNotificationsProvider).permissionGranted(),
);

/// The reach resolver handed to the job manager.
///
/// Resolved from the container rather than from the launching page's `ref` on
/// purpose: the manager keeps this callback for the whole session, a job
/// usually outlives the page that started it, and a `WidgetRef` throws on any
/// use once its widget unmounts — which used to leave a failing job stuck on
/// "running" forever, since the classifier could no longer even run.
final releaseSearchReachResolverProvider = Provider<ReleaseSearchReachResolver>(
  (ref) =>
      (target) => ref.read(releaseSearchReachProvider(target)),
);

/// Everything that happens when a search finishes, resolved from the container
/// for the same reason as [releaseSearchReachResolverProvider]: this callback
/// is what posts the notification and restarts the queue, and it fires
/// precisely when the launching page tends to be gone.
final releaseSearchOnFinishedProvider =
    Provider<void Function(ReleaseSearchJob)>(
      (ref) =>
          (job) => _onSearchFinished(ref, job),
    );

/// Performs a release search for any supported target.
///
/// One place resolves the service, so the job manager never learns about Sonarr,
/// Radarr or Lidarr and a test can drive it with a plain function.
final releaseSearchRunnerProvider = Provider<ReleaseSearchRunner>((ref) {
  return (target, cancelToken) async {
    final transport = ref.read(releaseSearchTransportProvider(target));

    // The foreground path goes through the arr service rather than round-tripping
    // through a URL: it keeps `ApiClient`'s redirect guard, and it keeps every
    // existing test able to stub a service the way it always could.
    if (!transport.survivesBackgrounding) {
      return _searchViaService(ref, target, cancelToken);
    }

    final request = _describeRequest(ref, target);
    return transport.run(
      url: request.url,
      headers: request.headers,
      timeout: ref.read(releaseSearchSettingsProvider).timeout,
      cancelToken: cancelToken,
    );
  };
});

/// The three services, resolved for the connection the target belongs to.
///
/// A stamped target names its own server, so a job queued behind another one
/// runs where it was started even if the lens has moved on in the meantime —
/// which, with jobs that outlive the page, is a thing that happens rather than
/// a thing that could. An unstamped target falls through to the lens, which is
/// the old behaviour and what a hand-built test target still gets.
RadarrService _radarrFor(Ref ref, ReleaseSearchTarget target) =>
    target.instanceId.isEmpty
    ? ref.read(radarrServiceProvider)
    : ref.read(radarrServiceForProvider(target.instanceId));

SonarrService _sonarrFor(Ref ref, ReleaseSearchTarget target) =>
    target.instanceId.isEmpty
    ? ref.read(sonarrServiceProvider)
    : ref.read(sonarrServiceForProvider(target.instanceId));

LidarrService _lidarrFor(Ref ref, ReleaseSearchTarget target) =>
    target.instanceId.isEmpty
    ? ref.read(lidarrServiceProvider)
    : ref.read(lidarrServiceForProvider(target.instanceId));

/// Runs the search through the service that owns the endpoint.
///
/// Carries the user's own ceiling with it: the services default to the
/// feature's constant, and without this a timeout raised to ten minutes in
/// Settings would still be cut at five on every foreground search — and then
/// misread as a lost connection, because the classifier is told the ceiling
/// the user set, not the one that actually fired.
Future<List<dynamic>> _searchViaService(
  Ref ref,
  ReleaseSearchTarget target,
  CancelToken cancelToken,
) {
  final timeout = ref.read(releaseSearchSettingsProvider).timeout;
  switch (target.service) {
    case ServiceKey.sonarr:
      final service = _sonarrFor(ref, target);
      return target.scope == ReleaseSearchScope.episode
          ? service.getReleases(
              episodeId: target.id,
              cancelToken: cancelToken,
              receiveTimeout: timeout,
            )
          : service.getReleases(
              seriesId: target.id,
              seasonNumber: target.seasonNumber ?? 1,
              cancelToken: cancelToken,
              receiveTimeout: timeout,
            );
    case ServiceKey.radarr:
      return _radarrFor(ref, target).getReleases(
        target.id,
        cancelToken: cancelToken,
        receiveTimeout: timeout,
      );
    case ServiceKey.lidarr:
      final service = _lidarrFor(ref, target);
      return target.scope == ReleaseSearchScope.album
          ? service.getReleases(
              albumId: target.id,
              cancelToken: cancelToken,
              receiveTimeout: timeout,
            )
          : service.getReleases(
              artistId: target.id,
              cancelToken: cancelToken,
              receiveTimeout: timeout,
            );
    default:
      throw UnsupportedError(
        '${target.service.name} has no interactive release search',
      );
  }
}

/// Describes the search as a URL and headers.
///
/// One place resolves the service, so neither the job manager nor the transport
/// learns about Sonarr, Radarr or Lidarr.
({Uri url, Map<String, String> headers}) _describeRequest(
  Ref ref,
  ReleaseSearchTarget target,
) {
  switch (target.service) {
    case ServiceKey.sonarr:
      final service = _sonarrFor(ref, target);
      return service.releaseSearchRequest(
        target.scope == ReleaseSearchScope.episode
            ? {'episodeId': target.id}
            : {'seriesId': target.id, 'seasonNumber': target.seasonNumber ?? 1},
      );
    case ServiceKey.radarr:
      return _radarrFor(
        ref,
        target,
      ).releaseSearchRequest({'movieId': target.id});
    case ServiceKey.lidarr:
      final service = _lidarrFor(ref, target);
      return service.releaseSearchRequest(
        target.scope == ReleaseSearchScope.album
            ? {'albumId': target.id}
            : {'artistId': target.id},
      );
    default:
      throw UnsupportedError(
        '${target.service.name} has no interactive release search',
      );
  }
}

/// Grabs a release on the service that found it.
/// Grabs a release on the connection that found it.
///
/// Takes the whole target rather than its [ServiceKey], because the service is
/// not enough to say *where*: the grab used to resolve through the lens at the
/// moment of the TAP, so a release found on the seedbox Radarr and tapped after
/// the lens moved home was pushed to the wrong server — with a guid that server
/// had never heard of.
final releaseGrabberProvider =
    Provider<Future<void> Function(ReleaseSearchTarget, String, int)>((ref) {
      return (target, guid, indexerId) async {
        switch (target.service) {
          case ServiceKey.sonarr:
            await _sonarrFor(
              ref,
              target,
            ).grabRelease(guid: guid, indexerId: indexerId);
          case ServiceKey.radarr:
            await _radarrFor(
              ref,
              target,
            ).grabRelease(guid: guid, indexerId: indexerId);
          case ServiceKey.lidarr:
            await _lidarrFor(
              ref,
              target,
            ).grabRelease(guid: guid, indexerId: indexerId);
          default:
            throw UnsupportedError(
              '${target.service.name} cannot grab releases',
            );
        }
      };
    });

/// The one way into interactive release search.
///
/// Every entry point in the app goes through here — the series, season, episode,
/// movie, artist and album actions, and the Wanted dispatcher — because the rules
/// that protect the user's indexers only hold if they cannot be bypassed:
///
/// * an in-flight search for this target, or one that **covers** it, is adopted
///   rather than duplicated — and the sheet says so, because adopting silently
///   would be work the user cannot see;
/// * a finished search whose releases are still grabbable is offered back
///   instead of spending another pass on the indexers.
Future<void> showReleaseSearch(
  BuildContext context,
  WidgetRef ref,
  ReleaseSearchTarget target,
) async {
  HapticFeedback.selectionClick();
  // Stamped here and nowhere else. Every screen in the app builds its target
  // and hands it over, so this is the one place that has to ask which Radarr
  // the user is looking at — and it has to ask BEFORE adoption and the results
  // cache are consulted, since the connection is now part of what makes two
  // targets the same target.
  //
  // Only when the caller left it blank: a detail page opened for a connection
  // other than the lens already knows which server it belongs to, and stamping
  // over that would send its search somewhere else.
  if (target.instanceId.isEmpty) {
    target = target.stampedWith(
      ref.read(activeInstanceProvider(target.service))?.id ?? '',
    );
  }
  final notifier = ref.read(releaseSearchJobsProvider.notifier);
  final settings = ref.read(releaseSearchSettingsProvider);
  // Every callback below comes from the container, never from this widget's
  // `ref`: they run when jobs finish, and jobs outlive pages.
  notifier.configure(
    runner: ref.read(releaseSearchRunnerProvider),
    reachFor: ref.read(releaseSearchReachResolverProvider),
    concurrency: settings.concurrency,
    timeout: settings.timeout,
    onFinished: ref.read(releaseSearchOnFinishedProvider),
  );

  final adopted = notifier.activeJobCovering(target);
  final fresh = adopted == null ? notifier.freshResultsFor(target) : null;
  final job = adopted ?? fresh ?? notifier.start(target);

  await ReleaseSearchSheet.show(
    context: context,
    ref: ref,
    jobId: job.id,
    target: target,
    // Both disclosures exist for the same reason: the user asked for a search
    // and is about to be shown something that is not one.
    adoptedFrom: adopted != null && adopted.target != target
        ? adopted.target.label
        : null,
    reusedResults: fresh != null,
  );
}

/// Everything that happens when a search finishes, in one place.
void _onSearchFinished(Ref ref, ReleaseSearchJob job) {
  _recordHeadroom(ref, job);

  final notice = noticeFor(
    job,
    appInForeground: ref.read(appInForegroundProvider),
    notificationsEnabled: ref
        .read(releaseSearchSettingsProvider)
        .notifyOnFinish,
    connection: job.target.connectionIn(ref.read(currentSettingsProvider)),
  );
  if (notice == null) return;
  ref.read(releaseSearchNotificationsProvider).show(notice, jobId: job.id);
}

/// Feeds a finished search into what the headroom card knows.
///
/// Only a **cut-off** teaches anything about the ceiling: a lost connection or a
/// server error says nothing about how long the path allows, and folding those in
/// would report a limit that does not exist.
void _recordHeadroom(Ref ref, ReleaseSearchJob job) {
  final notifier = ref.read(searchHeadroomProvider.notifier);
  final service = job.target.service;
  if (job.status == ReleaseSearchJobStatus.completed) {
    notifier.recordSuccess(service, job.elapsed);
    return;
  }
  final kind = job.failure?.kind;
  final isCutoff =
      kind == ReleaseSearchFailureKind.gatewayTimeout ||
      kind == ReleaseSearchFailureKind.cloudflareCap ||
      kind == ReleaseSearchFailureKind.clientTimeout;
  if (isCutoff) notifier.recordCutoff(service, job.elapsed);
}

/// Builds the target for a Sonarr season or whole-series action.
///
/// Sonarr's `/release` has no series-wide form, so the "whole series" button
/// searches season 1 — that is upstream behaviour, not a shortcut here.
ReleaseSearchTarget sonarrSeasonTarget({
  required int seriesId,
  required int? seasonNumber,
  required String label,
}) => ReleaseSearchTarget.season(
  seriesId: seriesId,
  seasonNumber: seasonNumber ?? 1,
  label: label,
);
