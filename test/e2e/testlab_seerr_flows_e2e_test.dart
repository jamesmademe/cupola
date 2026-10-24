@Tags(['e2e'])
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/discover/data/seerr_auth_service.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_quota.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/domain/seerr_request_update.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Seerr flows of the catalogue against the lab's main Seerr, with the
/// people the world seeds: Anna and Luca are household accounts, the operator
/// is the API key.
///
/// Through Cupola's own clients only. [SeerrAuthService] signs Anna in,
/// `seerrClientFor` carries her session and the CSRF token, and [SeerrService]
/// makes every read and write the screens make:
///
/// * G-15 a movie request, waiting for approval;
/// * G-16 a series request with its seasons;
/// * G-17 a 4K request refused for the permission Anna lacks;
/// * G-18 the approval with changes: the request is updated with a real
///   profile and folder of the lab's Radarr, then approved, and Radarr holds
///   the movie with them. This is L7's acceptance;
/// * G-19 a decline;
/// * G-20 Anna withdrawing her own pending request, and the refusal once the
///   request is decided;
/// * G-21 an issue resolved;
/// * G-22 the users list and an account's quota;
/// * G-23 the watchlist, put on and taken off.
///
/// The world is `test/e2e/testlab/seerr_world.py`, which is idempotent and
/// writes `.ai/scratch/zz_testlab/state/seerr-world.json` (both under
/// `CUPOLA_TESTLAB_STATE_DIR`). Its format is the contract the tests read:
/// the two members with their permissions and quotas, the Jellyfin account
/// Seerr imported, seven requests, one per state, and one open issue. The
/// seeded requests and the issue are read and never moved; `tearDownAll`
/// reads them back and fails if any test did.
///
/// The flows that ask for a title take the three the world leaves free
/// (`titles` in the state): a movie to ask for, a series with a season to ask
/// of it, and a movie the approval sends to Radarr. A free title is one with
/// no Seerr media row and no request, and the two movies are also absent from
/// Radarr: the seed picks them at every run, so a run that stopped halfway
/// still leaves free ones behind.
///
/// Every test claims its title first: the claim refuses to start over a
/// request or a media row somebody left behind, and its teardown removes only
/// what the test created (the request, Radarr's movie when it was absent
/// before, the import exclusion Radarr added, Seerr's media row).
void main() {
  late _World world;
  var seeded = false;

  setUpAll(() async {
    world = await _World.load();
    seeded = true;
  });

  // Every test cleans up after itself; this reads the world back and holds
  // that none of the seeded requests was moved and the seeded issue is still
  // open. A test that touched a fixture fails here even if it passed.
  tearDownAll(() async {
    if (!seeded) return;
    final client = seerrClientFor(
      ServiceInstance(
        id: ServiceInstance.primaryIdFor(ServiceKey.seerr),
        service: ServiceKey.seerr,
        url: world.seerrUrl,
        credential: world.apiKey,
      ),
    );
    try {
      final operator = SeerrService(client);
      for (final fixture in world.fixtures) {
        final request = await operator.getRequest(fixture.id);
        expect(
          request.status,
          RequestStatus.fromCode(fixture.status),
          reason: 'the seeded ${fixture.key} request is as the world left it',
        );
        expect(request.media?.tmdbId, fixture.tmdbId);
      }
      if (world.issueId > 0) {
        final issues = await operator.getIssuesResult();
        expect(
          issues.items.any(
            (issue) => issue.id == world.issueId && issue.isOpen,
          ),
          isTrue,
          reason: 'the seeded issue is still open',
        );
      }
    } finally {
      client.close();
    }
  });

  group('a household member asks', () {
    test('G-15 a movie request waits for the operator', () async {
      final operator = _operator(world);
      final anna = await _signIn(world, world.anna);
      final movie = world.movieToAsk;
      await _Claim.take(operator, tmdbId: movie.tmdbId, series: false);

      await anna.service.createRequest(
        mediaType: 'movie',
        mediaId: movie.tmdbId,
      );

      final mine = await _singleRequest(anna.service, movie.tmdbId);
      expect(mine.type, 'movie');
      expect(mine.is4k, isFalse);
      expect(mine.requestedBy?.id, anna.account.userId);
      expect(mine.mediaAvailability, SeerrMediaAvailability.pending);
      expect(
        mine.status,
        _autoApproves(anna)
            ? RequestStatus.approved
            : RequestStatus.pendingApproval,
        reason: 'an account without AUTO_APPROVE leaves the request waiting',
      );

      // The operator reads the same row, with its title hydrated.
      final seen = (await operator.getRequests())
          .where((request) => request.id == mine.id)
          .single;
      expect(seen.media?.tmdbId, movie.tmdbId);
      expect(seen.media?.title, isNotEmpty);
      expect(seen.requestedBy?.id, anna.account.userId);
    });

    test('G-16 a series request carries the seasons asked for', () async {
      final operator = _operator(world);
      final anna = await _signIn(world, world.anna);
      final series = world.seriesToAsk;
      await _Claim.take(operator, tmdbId: series.tmdbId, series: true);

      await anna.service.createRequest(
        mediaType: 'tv',
        mediaId: series.tmdbId,
        seasons: [series.season],
      );

      final mine = await _singleRequest(anna.service, series.tmdbId);
      expect(mine.type, 'tv');
      expect(mine.seasons?.map((season) => season.seasonNumber), [
        series.season,
      ], reason: 'Seerr holds the season asked for, and only it');
      expect(
        mine.status,
        _autoApproves(anna, kind: SeerrMediaKind.tv)
            ? RequestStatus.approved
            : RequestStatus.pendingApproval,
      );
    });

    test('G-17 a 4K request is refused for the permission', () async {
      final operator = _operator(world);
      final anna = await _signIn(world, world.anna);
      final movie = world.movieToAsk;
      await _Claim.take(operator, tmdbId: movie.tmdbId, series: false);

      final grant = SeerrGrant.account(permissions: anna.account.permissions);
      expect(
        grant.may(SeerrAbility.request4k, kind: SeerrMediaKind.movie),
        isFalse,
        reason: 'the world gives Anna no 4K permission',
      );

      final refused = await _caught(
        () => anna.service.createRequest(
          mediaType: 'movie',
          mediaId: movie.tmdbId,
          is4k: true,
        ),
      );
      expect(seerrRefusalOf(refused), SeerrRefusal.requestNotAllowed);
      expect(
        await _requestsFor(operator, movie.tmdbId),
        isEmpty,
        reason: 'the refused 4K request never reaches Seerr',
      );

      // The standard copy is still hers to ask for: the refusal was the 4K
      // permission, not the title.
      await anna.service.createRequest(
        mediaType: 'movie',
        mediaId: movie.tmdbId,
      );
      final mine = await _singleRequest(anna.service, movie.tmdbId);
      expect(mine.is4k, isFalse);
    });
  });

  group('the operator decides', () {
    test('G-18 approving with changes writes profile and folder to '
        'Radarr', () async {
      final operator = _operator(world);
      final anna = await _signIn(world, world.anna);
      final movie = world.movieToApprove;
      await _Claim.take(
        operator,
        tmdbId: movie.tmdbId,
        series: false,
        absentFromRadarr: true,
      );

      await anna.service.createRequest(
        mediaType: 'movie',
        mediaId: movie.tmdbId,
      );
      final pending = await _singleRequest(anna.service, movie.tmdbId);
      expect(pending.status, RequestStatus.pendingApproval);

      // What the approve sheet reads: Seerr's Radarr servers, then the
      // profiles and folders of the default one.
      final servers = await operator.getArrServers(ServiceKey.radarr);
      final server = servers.firstWhere(
        (candidate) => candidate.isDefault && !candidate.is4k,
      );
      final listed = await operator.getRadarrProfiles(server.id);
      final profiles = (listed['profiles'] as List).cast<Map>();
      final folders = (listed['rootFolders'] as List).cast<Map>();
      expect(profiles, isNotEmpty);
      expect(folders, isNotEmpty);
      // A profile of its own, not the server's default: what the approval
      // changed has to be visible in Radarr.
      final profile = profiles.firstWhere(
        (candidate) =>
            candidate['id'] != server.activeProfileId &&
            '${candidate['name']}'.contains('1080'),
        orElse: () => profiles.firstWhere(
          (candidate) => candidate['id'] != server.activeProfileId,
          orElse: () => profiles.first,
        ),
      );
      // The lab's Radarr has one root folder, and it is the server's own: the
      // sheet offers what the server lists, so this is the real folder it
      // offers. The profile is the choice that differs from the default, and
      // both have to show in Radarr below.
      final folder = folders
          .firstWhere(
            (candidate) => candidate['path'] != server.activeDirectory,
            orElse: () => folders.first,
          )['path']
          .toString();

      // `updateRequest` then `approveRequest`: the sheet's order.
      await operator.updateRequest(
        pending.id,
        seerrRequestUpdateBody(
          pending,
          server: server,
          profileId: profile['id'] as int,
          rootFolder: folder,
        ),
      );
      final edited = await operator.getRequest(pending.id);
      expect(edited.status, RequestStatus.pendingApproval);
      expect(edited.profileId, profile['id']);
      expect(edited.rootFolder, folder);
      expect(edited.serverId, server.id);

      await operator.approveRequest(pending.id);

      final inRadarr = await _waitForRadarrMovie(
        movie.tmdbId,
        profileId: profile['id'] as int,
        folder: folder,
      );
      expect(inRadarr['tmdbId'], movie.tmdbId);
      expect(inRadarr['qualityProfileId'], profile['id']);
      expect(inRadarr['rootFolderPath'], folder);
      expect('${inRadarr['path']}', startsWith(folder));
    });

    test('G-19 a declined request leaves the title alone', () async {
      final operator = _operator(world);
      final anna = await _signIn(world, world.anna);
      final movie = world.movieToAsk;
      await _Claim.take(operator, tmdbId: movie.tmdbId, series: false);

      await anna.service.createRequest(
        mediaType: 'movie',
        mediaId: movie.tmdbId,
      );
      final pending = await _singleRequest(anna.service, movie.tmdbId);

      await operator.declineRequest(pending.id);

      final declined = await operator.getRequest(pending.id);
      expect(declined.status, RequestStatus.declined);
      expect(declined.lifecycleStatus.label, 'Declined');
      // Anna reads her own answer, and the title was not sent anywhere.
      final hers = (await anna.service.getRequests())
          .where((request) => request.id == pending.id)
          .single;
      expect(hers.status, RequestStatus.declined);
      expect(await _radarrMovie(movie.tmdbId), isNull);
    });
  });

  group('the requester takes it back', () {
    test('G-20 Anna cancels her pending request, and not a decided '
        'one', () async {
      final operator = _operator(world);
      final anna = await _signIn(world, world.anna);
      final movie = world.movieToAsk;
      await _Claim.take(operator, tmdbId: movie.tmdbId, series: false);

      // Still waiting: hers to cancel.
      await anna.service.createRequest(
        mediaType: 'movie',
        mediaId: movie.tmdbId,
      );
      final pending = await _singleRequest(anna.service, movie.tmdbId);
      await anna.service.deleteRequest(pending.id);
      expect(await _requestsFor(operator, movie.tmdbId), isEmpty);
      expect(
        (await anna.service.getRequests()).where(
          (request) => request.id == pending.id,
        ),
        isEmpty,
      );

      // Decided: Seerr answers the owner's cancel with its own 401, whatever
      // the decision was, which the app reads as "it can't be canceled here",
      // never as an ended session. Declined rather than approved so the test
      // does not send a movie to Radarr just to be refused a cancel.
      await anna.service.createRequest(
        mediaType: 'movie',
        mediaId: movie.tmdbId,
      );
      final decided = await _singleRequest(anna.service, movie.tmdbId);
      await operator.declineRequest(decided.id);
      final refused = await _caught(
        () => anna.service.deleteRequest(decided.id),
      );
      expect(seerrRefusalOf(refused), SeerrRefusal.noLongerCancellable);
      expect(await _requestsFor(operator, movie.tmdbId), hasLength(1));
    });
  });

  group('the stack', () {
    test('G-21 an issue is resolved', () async {
      final client = _operatorClient(world);
      final operator = SeerrService(client);
      final anna = await _signIn(world, world.anna);
      final movie = world.movieToAsk;
      await _Claim.take(operator, tmdbId: movie.tmdbId, series: false);

      // An issue hangs off a media row: Anna's request makes one. The app only
      // resolves issues (`resolveIssue`); opening one is Seerr's own route, so
      // the operator's client opens it here with Anna as its author, and the
      // issues screen reads it as hers.
      await anna.service.createRequest(
        mediaType: 'movie',
        mediaId: movie.tmdbId,
      );
      final details = await operator.getMovie(movie.tmdbId);
      final media = (details['mediaInfo'] as Map).cast<String, dynamic>();
      final created = await client.post(
        '/api/v1/issue',
        data: {
          'issueType': 1,
          'message': 'No sound after the opening.',
          'mediaId': media['id'],
          'userId': anna.account.userId,
        },
      );
      expect(created.statusCode, 201);
      final issueId = (created.data as Map)['id'] as int;

      final open = await operator.getIssuesResult();
      final issue = open.items.where((row) => row.id == issueId).single;
      expect(issue.isOpen, isTrue);
      expect(issue.commentCount, 1);
      expect(issue.createdBy?.id, anna.account.userId);
      expect(issue.media?.tmdbId, movie.tmdbId);

      await operator.resolveIssue(issueId);

      expect(
        (await operator.getIssuesResult()).items.where(
          (row) => row.id == issueId,
        ),
        isEmpty,
        reason: 'the open list no longer holds it',
      );
      final resolved = (await operator.getIssuesResult(
        filter: SeerrIssueFilter.resolved,
      )).items.where((row) => row.id == issueId).single;
      expect(resolved.isResolved, isTrue);
      expect(resolved.modifiedBy?.id, 1, reason: 'the key is the admin');
    });

    test('G-22 the users and a quota are read, not written', () async {
      final operator = _operator(world);

      final users = await operator.getUsersResult();
      expect(users.isPartial, isFalse, reason: 'one page answers the lab');
      expect(users.items, hasLength(users.total));

      SeerrUser named(_Member member) => users.items.firstWhere(
        (user) => user.id == member.userId,
        orElse: () => fail('the users list does not hold ${member.key}'),
      );
      final anna = named(world.anna);
      final luca = named(world.luca);
      expect(anna.displayName, isNotEmpty);
      expect(luca.displayName, isNotEmpty);
      expect(anna.email, world.anna.email);
      expect(anna.permissions, world.anna.permissions);
      expect(luca.permissions, world.luca.permissions);
      // The Jellyfin user Seerr imported is in the same list, and is neither
      // of the two.
      expect(
        users.items.map((user) => user.id),
        contains(world.jellyfinUserId),
      );

      final quota = await operator.getQuota(world.anna.userId);
      _expectQuota(quota.movie, world.anna.movieQuota, 'movie');
      _expectQuota(quota.tv, world.anna.tvQuota, 'series');
      // Luca's own quota, so the test reads two answers and not one twice.
      final lucaQuota = await operator.getQuota(world.luca.userId);
      _expectQuota(lucaQuota.movie, world.luca.movieQuota, 'movie');
      _expectQuota(lucaQuota.tv, world.luca.tvQuota, 'series');
      // The account reads its own quota too, the way the request sheet does.
      final hers = await _signIn(world, world.anna);
      final own = await hers.service.getQuota(anna.id);
      expect(own.movie, quota.movie);
      expect(own.tv, quota.tv);
    });

    test('G-23 the watchlist is put on and taken off', () async {
      final operator = _operator(world);
      final anna = await _signIn(world, world.anna);
      final movie = world.movieToAsk;
      await _Claim.take(operator, tmdbId: movie.tmdbId, series: false);

      Future<Map<String, dynamic>> hers() =>
          anna.service.getMovie(movie.tmdbId);
      expect((await hers())['onUserWatchlist'], isFalse);

      await anna.service.addToWatchlist(
        tmdbId: movie.tmdbId,
        mediaType: 'movie',
        title: movie.title,
      );
      expect(
        (await hers())['onUserWatchlist'],
        isTrue,
        reason: 'the title page reads onUserWatchlist as the account',
      );
      // Nobody else's watchlist: the operator's own answer is separate.
      expect(
        (await operator.getMovie(movie.tmdbId))['onUserWatchlist'],
        isFalse,
      );

      await anna.service.removeFromWatchlist(
        tmdbId: movie.tmdbId,
        mediaType: 'movie',
      );
      expect((await hers())['onUserWatchlist'], isFalse);
    });
  });
}

/// Anna signs in and her service answers as her.
typedef _SignedIn = ({SeerrAccountSignIn account, SeerrService service});

Future<_SignedIn> _signIn(_World world, _Member member) async {
  final pending = ServiceInstance(
    id: 'seerr-world-${member.key}',
    service: ServiceKey.seerr,
    url: world.seerrUrl,
    account: const SeerrAccountSignIn(kind: SeerrAccountKind.local),
  );
  final auth = SeerrAuthService.forConnection(pending);
  addTearDown(auth.close);
  final facts = await auth.readServer();
  final account = await auth.signInWithEmail(
    facts,
    email: member.email,
    password: member.password,
  );
  expect(
    account.permissions,
    member.permissions,
    reason: 'the world gave ${member.key} these permissions',
  );
  final client = seerrClientFor(
    ServiceInstance(
      id: pending.id,
      service: ServiceKey.seerr,
      url: world.seerrUrl,
      account: account,
    ),
  );
  addTearDown(client.close);
  return (account: account, service: SeerrService(client));
}

/// The operator's client: the lab Seerr's API key, user 1.
ApiClient _operatorClient(_World world) {
  final client = seerrClientFor(
    ServiceInstance(
      id: ServiceInstance.primaryIdFor(ServiceKey.seerr),
      service: ServiceKey.seerr,
      url: world.seerrUrl,
      credential: world.apiKey,
    ),
  );
  addTearDown(client.close);
  return client;
}

SeerrService _operator(_World world) => SeerrService(_operatorClient(world));

bool _autoApproves(
  _SignedIn who, {
  SeerrMediaKind kind = SeerrMediaKind.movie,
}) => SeerrGrant.account(
  permissions: who.account.permissions,
).may(SeerrAbility.autoApproved, kind: kind);

Future<List<SeerrRequest>> _requestsFor(
  SeerrService operator,
  int tmdbId,
) async {
  return [
    for (final request in await operator.getRequests())
      if (request.media?.tmdbId == tmdbId) request,
  ];
}

Future<SeerrRequest> _singleRequest(SeerrService service, int tmdbId) async {
  return (await service.getRequests())
      .where((request) => request.media?.tmdbId == tmdbId)
      .single;
}

/// The one title a test works on, and how to leave the lab as the world had
/// it: the request, Radarr's movie only when the test's request added it (and
/// the import exclusion Radarr added with it), Seerr's media row.
class _Claim {
  _Claim._(this._operator, this.tmdbId, this._series, this._heldInRadarr);

  /// Refuses to start over somebody else's data: the title must have no
  /// request and no Seerr media row.
  static Future<_Claim> take(
    SeerrService operator, {
    required int tmdbId,
    required bool series,
    bool absentFromRadarr = false,
  }) async {
    final kind = series ? 'series' : 'movie';
    expect(
      await _requestsFor(operator, tmdbId),
      isEmpty,
      reason: 'the $kind $tmdbId is free of requests',
    );
    final details = series
        ? await operator.getTv(tmdbId)
        : await operator.getMovie(tmdbId);
    expect(
      details['mediaInfo'],
      isNull,
      reason: 'the $kind $tmdbId has no Seerr media row',
    );
    Map<String, dynamic>? held = series ? null : await _radarrMovie(tmdbId);
    if (absentFromRadarr) {
      // Radarr must not hold it: the approval test needs the add to be the
      // test's. A movie or an exclusion here is a run that stopped before its
      // teardown, and it goes the same way.
      await _forgetRadarrMovie(tmdbId);
      held = null;
    }
    final claim = _Claim._(operator, tmdbId, series, held);
    addTearDown(claim.release);
    return claim;
  }

  final SeerrService _operator;
  final int tmdbId;
  final bool _series;

  /// Radarr's movie for the title before the test: null when the test's own
  /// request is what puts it there.
  final Map<String, dynamic>? _heldInRadarr;

  Future<void> release() async {
    for (final request in await _operator.getRequests()) {
      if (request.media?.tmdbId == tmdbId) {
        await _operator.deleteRequest(request.id);
      }
    }
    if (!_series && _heldInRadarr == null) {
      await _forgetRadarrMovie(tmdbId);
    }
    final details = _series
        ? await _operator.getTv(tmdbId)
        : await _operator.getMovie(tmdbId);
    final media = details['mediaInfo'];
    if (media is Map) {
      await _operator.deleteMedia(media['id'] as int);
    }
  }
}

/// What `GET /api/v1/user/{id}/quota` answers for a world quota: the window
/// and the limit the seed gave, and the server's own arithmetic over the
/// requests it counts. [quota]'s `used` is what the seed counted at its own
/// run, a floor: a request another test left behind is not this test's to
/// explain, and still has to be counted.
void _expectQuota(SeerrQuotaStatus status, _Quota? quota, String kind) {
  if (quota == null) {
    expect(status.limit, isNull, reason: 'no $kind limit');
    expect(status.restricted, isFalse);
    return;
  }
  expect(status.limit, quota.limit, reason: 'the $kind limit');
  expect(status.days, quota.days, reason: 'the $kind window');
  expect(
    status.used,
    greaterThanOrEqualTo(quota.used),
    reason: 'the $kind requests used, the world\'s own among them',
  );
  expect(status.used, lessThanOrEqualTo(quota.limit));
  expect(
    status.remaining,
    quota.limit - status.used,
    reason: 'the $kind requests left, from the limit and the used count',
  );
  expect(
    status.restricted,
    status.used >= quota.limit,
    reason: 'the server\'s own verdict on the $kind limit',
  );
}
// ── Radarr, as the verification of what Seerr sent ──────────────────────────

/// The lab Radarr's key: the seed sets it, and the arr tests use the same one.
const String _radarrKey = 'test-key';
const String _radarrUrl = 'http://127.0.0.1:7878/api/v3';

Future<Map<String, dynamic>?> _radarrMovie(int tmdbId) async {
  final (:status, :body) = await _rawJson(
    'GET',
    '$_radarrUrl/movie?tmdbId=$tmdbId',
    headers: {'X-Api-Key': _radarrKey},
  );
  expect(status, 200, reason: 'Radarr reading tmdbId $tmdbId: $body');
  final rows = (body as List).cast<Map>();
  return rows.isEmpty ? null : rows.first.cast<String, dynamic>();
}

/// Polls Radarr until it holds the movie with the profile and folder the
/// approval named.
Future<Map<String, dynamic>> _waitForRadarrMovie(
  int tmdbId, {
  required int profileId,
  required String folder,
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  Map<String, dynamic>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await _radarrMovie(tmdbId);
    if (last != null &&
        last['qualityProfileId'] == profileId &&
        last['rootFolderPath'] == folder) {
      return last;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail(
    'Radarr did not hold tmdbId $tmdbId with profile $profileId and folder '
    '$folder within 3 minutes: $last',
  );
}

/// Takes the movie out of Radarr with its files, and the import exclusion
/// Radarr added for it, leaving exclusions that were there before alone.
Future<void> _forgetRadarrMovie(int tmdbId) async {
  final movie = await _radarrMovie(tmdbId);
  if (movie != null) {
    final (:status, :body) = await _rawJson(
      'DELETE',
      '$_radarrUrl/movie/${movie['id']}?deleteFiles=true&addImportExclusion=true',
      headers: {'X-Api-Key': _radarrKey},
    );
    expect(status, anyOf(200, 202), reason: 'Radarr removing $tmdbId: $body');
  }
  final (:status, :body) = await _rawJson(
    'GET',
    '$_radarrUrl/exclusions',
    headers: {'X-Api-Key': _radarrKey},
  );
  expect(status, 200, reason: 'Radarr listing its exclusions: $body');
  for (final row in (body as List).cast<Map>()) {
    if (row['tmdbId'] != tmdbId) continue;
    final (status: dropped, body: answer) = await _rawJson(
      'DELETE',
      '$_radarrUrl/exclusions/${row['id']}',
      headers: {'X-Api-Key': _radarrKey},
    );
    expect(
      dropped,
      anyOf(200, 202, 204),
      reason: 'Radarr dropping the exclusion for $tmdbId: $answer',
    );
  }
}

// ── Requests outside the app's clients ──────────────────────────────────────

/// One request outside the app: Radarr has no Cupola client here, and the
/// test proves what Seerr sent by asking the arr itself.
Future<({int status, Object? body})> _rawJson(
  String method,
  String url, {
  Map<String, String> headers = const {},
  Object? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse(url));
    headers.forEach(request.headers.set);
    request.headers.set('Accept', 'application/json');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = text;
    }
    return (status: response.statusCode, body: decoded);
  } finally {
    client.close(force: true);
  }
}

Future<Object> _caught(Future<Object?> Function() action) async {
  try {
    await action();
  } catch (error) {
    return error;
  }
  fail('expected a refusal, and the request went through');
}

// ── The world ───────────────────────────────────────────────────────────────

/// A person the world seeds: their account, their quota, what they may do.
class _Member {
  const _Member({
    required this.key,
    required this.userId,
    required this.email,
    required this.password,
    required this.permissions,
    this.movieQuota,
    this.tvQuota,
  });

  final String key;
  final int userId;
  final String email;
  final String password;

  /// Seerr's permission bits, as the seed gave them.
  final int permissions;
  final _Quota? movieQuota;
  final _Quota? tvQuota;
}

/// One kind's request limit, as the seed declares it and Seerr answers it.
class _Quota {
  const _Quota({required this.limit, this.days, this.used = 0});

  final int limit;
  final int? days;

  /// How many the seed counted over the world's own requests: a floor for
  /// what the server answers.
  final int used;
}

/// A fixture of the world: a request the seed keeps in one state for the
/// screens to read, which no test of this file may move.
class _WorldFixture {
  const _WorldFixture({
    required this.key,
    required this.id,
    required this.status,
    required this.tmdbId,
  });

  final String key;
  final int id;
  final int status;
  final int tmdbId;
}

/// A title the world leaves free, with the season to ask for when it is a
/// series.
class _Title {
  const _Title({required this.tmdbId, required this.title, this.season = 1});

  final int tmdbId;
  final String title;
  final int season;
}

/// The state `test/e2e/testlab/seerr_world.py` seeds: the two members, the
/// imported Jellyfin account, the requests and the issue the world holds, and
/// the three titles it leaves free.
class _World {
  _World._({
    required this.seerrUrl,
    required this.apiKey,
    required this.anna,
    required this.luca,
    required this.jellyfinUserId,
    required this.fixtures,
    required this.issueId,
    required this.movieToAsk,
    required this.seriesToAsk,
    required this.movieToApprove,
  });

  /// Runs the seed, which is idempotent, and reads what it wrote.
  static Future<_World> load() async {
    final stateDir =
        Platform.environment['CUPOLA_TESTLAB_STATE_DIR'] ??
        '.ai/scratch/zz_testlab/state';
    final seed = File('test/e2e/testlab/seerr_world.py');
    if (seed.existsSync()) {
      final applied = await Process.run('python3', [
        seed.path,
        '--state-dir',
        stateDir,
      ]);
      expect(
        applied.exitCode,
        0,
        reason:
            'seeding the Seerr world failed: '
            '${applied.stdout}\n${applied.stderr}',
      );
    }
    final state = File('$stateDir/seerr-world.json');
    if (!state.existsSync()) {
      fail(
        'No Seerr world at ${state.path}: run '
        'test/e2e/testlab/seerr_world.py --state-dir $stateDir.',
      );
    }
    final json = (jsonDecode(state.readAsStringSync()) as Map)
        .cast<String, dynamic>();
    final seerr = (json['seerr'] as Map).cast<String, dynamic>();
    final people = (json['people'] as Map).cast<String, dynamic>();
    final titles = (json['titles'] as Map).cast<String, dynamic>();
    final jellyfin = (json['jellyfin'] as Map).cast<String, dynamic>();
    final issues = (json['issues'] as List).cast<Map>();
    final key = (seerr['apiKey'] as String?) ?? '';
    if (key.isEmpty) {
      fail('The Seerr world holds no operator key: seed it again.');
    }
    return _World._(
      seerrUrl: (seerr['url'] as String?) ?? 'http://127.0.0.1:5055',
      apiKey: key,
      anna: _member(people['anna'], 'anna'),
      luca: _member(people['luca'], 'luca'),
      jellyfinUserId: (jellyfin['seerrUserId'] as num).toInt(),
      fixtures: [
        for (final entry in (json['requests'] as Map).entries)
          _fixture(entry.key as String, entry.value as Map),
      ],
      issueId: issues.isEmpty ? 0 : (issues.first['id'] as num).toInt(),
      movieToAsk: _title(titles['ask'] as Map),
      seriesToAsk: _title(titles['series'] as Map),
      movieToApprove: _title(titles['approve'] as Map),
    );
  }

  final String seerrUrl;
  final String apiKey;
  final _Member anna;
  final _Member luca;

  /// The Jellyfin account Seerr imported, which is not Anna nor Luca.
  final int jellyfinUserId;

  /// The seven requests the seed holds, one per state: the tests read them,
  /// and never move them.
  final List<_WorldFixture> fixtures;

  /// The open issue the seed keeps, with its comments.
  final int issueId;

  /// A movie with no Seerr media row and no request, and absent from Radarr:
  /// the flow asks for it and, once done, leaves it as it found it.
  final _Title movieToAsk;

  /// A series with no Seerr media row and no request, and the season to ask.
  final _Title seriesToAsk;

  /// A movie with no Seerr media row and no request, and absent from Radarr:
  /// the approval test is what puts it in Radarr.
  final _Title movieToApprove;

  static _Member _member(Object? source, String key) {
    final person = (source as Map).cast<String, dynamic>();
    return _Member(
      key: key,
      userId: (person['id'] as num).toInt(),
      email: person['email'] as String,
      password: person['password'] as String,
      permissions: (person['permissions'] as num).toInt(),
      movieQuota: _quota(person['quota'], 'movie'),
      tvQuota: _quota(person['quota'], 'tv'),
    );
  }

  static _Quota? _quota(Object? source, String kind) {
    final quota = source is Map ? source[kind] : null;
    if (quota is! Map) return null;
    final limit = quota['limit'];
    if (limit is! num || limit <= 0) return null;
    return _Quota(
      limit: limit.toInt(),
      days: (quota['days'] as num?)?.toInt(),
      used: (quota['used'] as num?)?.toInt() ?? 0,
    );
  }

  static _WorldFixture _fixture(String key, Map row) => _WorldFixture(
    key: key,
    id: (row['id'] as num).toInt(),
    status: (row['status'] as num).toInt(),
    tmdbId: (row['tmdbId'] as num).toInt(),
  );

  static _Title _title(Map row) => _Title(
    tmdbId: (row['tmdbId'] as num).toInt(),
    title: (row['title'] as String?) ?? '',
    season: (row['season'] as num?)?.toInt() ?? 1,
  );
}
