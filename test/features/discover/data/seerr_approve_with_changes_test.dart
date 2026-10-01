import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/domain/seerr_request_update.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';

/// Records every write in the order it was sent, and can refuse the edit.
class _SequenceClient extends FakeApiClient {
  final List<String> writes = [];

  /// Thrown by the PUT, when set.
  Object? putFailure;

  /// The status the PUT answers with.
  int putStatus = 200;

  @override
  Future<Response<dynamic>> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    writes.add('PUT $path');
    lastPutData = data;
    final failure = putFailure;
    if (failure != null) throw failure;
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      statusCode: putStatus,
      data: const {'id': 7},
    );
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
  }) async {
    writes.add('POST $path');
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }
}

DioException _answered(int status, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
  ),
);

const _hd = SeerrArrServer(
  service: ServiceKey.radarr,
  id: 0,
  name: 'Radarr',
  isDefault: true,
);
const _spare = SeerrArrServer(
  service: ServiceKey.radarr,
  id: 2,
  name: 'Radarr spare',
);
const _uhd = SeerrArrServer(
  service: ServiceKey.radarr,
  id: 1,
  name: 'Radarr 4K',
  is4k: true,
  isDefault: true,
);

const _movie = SeerrRequest(
  id: 7,
  status: RequestStatus.pendingApproval,
  createdAt: '2026-09-30T10:00:00Z',
  type: 'movie',
  serverId: 0,
  profileId: 4,
  rootFolder: '/films',
  tags: [3],
);

const _series = SeerrRequest(
  id: 8,
  status: RequestStatus.pendingApproval,
  createdAt: '2026-09-30T10:00:00Z',
  type: 'tv',
  profileId: 4,
  languageProfileId: 1,
  seasons: [
    RequestSeason(seasonNumber: 1, status: '1'),
    RequestSeason(seasonNumber: 2, status: '1'),
  ],
);

void main() {
  late _SequenceClient client;
  late SeerrService service;

  setUp(() {
    client = _SequenceClient();
    service = SeerrService(client, numbering: SeerrNumbering.seerr);
  });

  group('approveRequestWithChanges', () {
    test('the edit lands first, then the approval', () async {
      await service.approveRequestWithChanges(
        _movie,
        server: _spare,
        profileId: 9,
        rootFolder: '/archive',
      );

      expect(client.writes, [
        'PUT /api/v1/request/7',
        'POST /api/v1/request/7/approve',
      ]);
      expect(client.lastPutData, {
        'mediaType': 'movie',
        'is4k': false,
        'serverId': 2,
        'profileId': 9,
        'rootFolder': '/archive',
        'tags': [3],
      });
    });

    test('an edit that fails approves nothing, and says why', () async {
      client.putFailure = _answered(500, '/api/v1/request/7');

      await expectLater(
        service.approveRequestWithChanges(_movie, profileId: 9),
        throwsA(isA<DioException>()),
      );
      expect(client.writes, ['PUT /api/v1/request/7']);
    });

    test('a request decided elsewhere meanwhile is the race, not approved', () {
      // Seerr edits only a request still waiting, and answers 409.
      client.putFailure = _answered(409, '/api/v1/request/7');

      expect(
        service.approveRequestWithChanges(_movie, profileId: 9),
        throwsA(isA<SeerrRequestConflict>()),
      );
    });

    test('an edit Seerr kept as it was (202) approves nothing', () async {
      client.putStatus = 202;

      await expectLater(
        service.approveRequestWithChanges(_movie, profileId: 9),
        throwsA(isA<SeerrRequestConflict>()),
      );
      expect(client.writes, ['PUT /api/v1/request/7']);
    });

    test('a change that asks for nothing new is only an approval', () async {
      await service.approveRequestWithChanges(
        _movie,
        server: _hd,
        profileId: 4,
        rootFolder: '/films',
      );

      expect(client.writes, ['POST /api/v1/request/7/approve']);
    });

    test('a server of the other copy is refused before anything is sent', () {
      expect(
        () => service.approveRequestWithChanges(_movie, server: _uhd),
        throwsArgumentError,
      );
      expect(client.writes, isEmpty);
    });

    test('a series goes back with its seasons and language profile', () async {
      await service.approveRequestWithChanges(
        _series,
        server: const SeerrArrServer(
          service: ServiceKey.sonarr,
          id: 1,
          name: 'Sonarr Anime',
        ),
      );

      expect(client.lastPutData, {
        'mediaType': 'tv',
        'is4k': false,
        'seasons': [1, 2],
        'serverId': 1,
        'profileId': 4,
        'languageProfileId': 1,
      });
      expect(client.writes.last, 'POST /api/v1/request/8/approve');
    });
  });

  group('seerrRequestUpdateBody', () {
    test('a series request with no seasons is refused: Seerr would throw', () {
      const bare = SeerrRequest(
        id: 9,
        status: RequestStatus.pendingApproval,
        createdAt: '2026-09-30T10:00:00Z',
        type: 'tv',
      );

      expect(
        () => seerrRequestUpdateBody(bare, profileId: 2),
        throwsArgumentError,
      );
    });

    test('a movie request never goes to a Sonarr', () {
      expect(
        () => seerrRequestUpdateBody(
          _movie,
          server: const SeerrArrServer(
            service: ServiceKey.sonarr,
            id: 0,
            name: 'Sonarr',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('a 4K request may move between 4K servers', () {
      const uhdRequest = SeerrRequest(
        id: 10,
        status: RequestStatus.pendingApproval,
        createdAt: '2026-09-30T10:00:00Z',
        type: 'movie',
        is4k: true,
      );

      expect(seerrRequestUpdateBody(uhdRequest, server: _uhd), {
        'mediaType': 'movie',
        'is4k': true,
        'serverId': 1,
      });
    });
  });
}
