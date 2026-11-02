import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/data/download_writes.dart';
import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _mib = 1024 * 1024;

const _torrent = WorldDownload(
  id: 'b2c3d4e5f60718293a4b5c6d7e8f90123456789a',
  release: 'Torrent.Job.2024.1080p',
  client: 'transmission',
  state: DownloadState.downloading,
  progress: 0.3,
  size: 800 * _mib,
);

const _usenet = WorldDownload(
  id: 'SABnzbd_nzo_4kq2',
  release: 'Usenet.Job.2024.1080p',
  client: 'sabnzbd',
  state: DownloadState.downloading,
  progress: 0.3,
  size: 800 * _mib,
);

/// An \*arr sent this one, so its queue row names it by the `drone` id and
/// never by the NZBID that NZBGet edits it with.
const _drone = WorldDownload(
  id: 'f00dcafe0123',
  release: 'Drone.Job.2024.1080p',
  client: 'nzbget',
  arr: 'sonarr',
  state: DownloadState.downloading,
  progress: 0.3,
  size: 800 * _mib,
);

/// Every client but qBittorrent (held by `qbittorrent_service_test`), one
/// download each, through the app's own clients against the world.
void main() {
  Future<(ProfileHarness, WidgetRef)> pump(WidgetTester tester) async {
    final harness = await ProfileHarness.start(
      Profiles.p1
          .withConnection(WorldConnections.transmission)
          .withConnection(WorldConnections.nzbget)
          .withDownloads(const [_torrent, _usenet, _drone]),
    );
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return (harness, captured);
  }

  /// Runs one write to its end and gives back what it threw, if anything.
  Future<Object?> write(
    WidgetTester tester,
    ProfileHarness harness,
    WidgetRef ref,
    DownloadClientHandle download, {
    required bool stopped,
  }) async {
    Object? failure;
    var done = false;
    Future<void> run() async {
      try {
        await setDownloadStopped(ref, download, stopped: stopped);
      } catch (error) {
        failure = error;
      }
      done = true;
    }

    unawaited(run());
    await harness.settle(tester);
    expect(done, isTrue, reason: 'the write never settled');
    return failure;
  }

  List<NetworkRequest> writesTo(ProfileHarness harness, String id) => harness
      .network
      .requestsTo(id)
      .where((request) => request.method == 'POST')
      .toList();

  testWidgets('Transmission stops and starts the torrent by its hash', (
    tester,
  ) async {
    final (harness, ref) = await pump(tester);
    final handle = (
      client: ServiceKey.transmission,
      instanceId: WorldIds.transmission,
      id: _torrent.id,
    );

    expect(await write(tester, harness, ref, handle, stopped: true), isNull);
    expect(await write(tester, harness, ref, handle, stopped: false), isNull);

    // A request without the session id is the 409 handshake, which the
    // client replays once it holds one: not a second write.
    final calls = [
      for (final request in writesTo(harness, WorldIds.transmission))
        if (request.headers.containsKey('x-transmission-session-id'))
          if (request.json case {
            'method': String method,
            'arguments': Map args,
          } when method.startsWith('torrent-st'))
            '$method ${args['ids']}',
    ];
    expect(calls, [
      'torrent-stop [${_torrent.id}]',
      'torrent-start [${_torrent.id}]',
    ]);
    await harness.unmount(tester);
  });

  testWidgets('SABnzbd pauses and resumes the one job, never the queue', (
    tester,
  ) async {
    final (harness, ref) = await pump(tester);
    final handle = (
      client: ServiceKey.sabnzbd,
      instanceId: WorldIds.sabnzbd,
      id: _usenet.id,
    );

    expect(await write(tester, harness, ref, handle, stopped: true), isNull);
    expect(await write(tester, harness, ref, handle, stopped: false), isNull);

    final jobs = [
      for (final request in harness.network.requestsTo(WorldIds.sabnzbd))
        if (request.query['mode'] == 'queue' &&
            request.query['value'] == _usenet.id)
          request.query['name'],
    ];
    expect(jobs, ['pause', 'resume']);
    final queueWide = harness.network
        .requestsTo(WorldIds.sabnzbd)
        .where(
          (request) =>
              const {'pause', 'resume'}.contains(request.query['mode']),
        );
    expect(queueWide, isEmpty);
    await harness.unmount(tester);
  });

  testWidgets('NZBGet finds the job its drone id names and edits it by NZBID', (
    tester,
  ) async {
    final (harness, ref) = await pump(tester);
    final handle = (
      client: ServiceKey.nzbget,
      instanceId: 'nzbget',
      id: _drone.id,
    );

    expect(await write(tester, harness, ref, handle, stopped: true), isNull);
    expect(await write(tester, harness, ref, handle, stopped: false), isNull);

    final edits = [
      for (final request in writesTo(harness, 'nzbget'))
        if (request.json case {'method': 'editqueue', 'params': List params})
          '${params[0]} ${params[3]}',
    ];
    // The world numbers its groups by their place in `listgroups`.
    expect(edits, ['GroupPause [1]', 'GroupResume [1]']);
    await harness.unmount(tester);
  });

  testWidgets('NZBGet no longer listing the job is a failure, and nothing '
      'is edited', (tester) async {
    final (harness, ref) = await pump(tester);
    final handle = (
      client: ServiceKey.nzbget,
      instanceId: 'nzbget',
      id: 'gone0000',
    );

    final failure = await write(tester, harness, ref, handle, stopped: true);

    expect(failure, isA<StateError>());
    final edits = writesTo(
      harness,
      'nzbget',
    ).where((request) => (request.json as Map)['method'] == 'editqueue');
    expect(edits, isEmpty);
    await harness.unmount(tester);
  });

  testWidgets('a service that moves no bytes is refused before any write', (
    tester,
  ) async {
    final (harness, ref) = await pump(tester);
    final before = harness.network.requests.length;

    final failure = await write(tester, harness, ref, (
      client: ServiceKey.radarr,
      instanceId: WorldIds.radarr,
      id: 'x',
    ), stopped: true);

    expect(failure, isA<ArgumentError>());
    expect(harness.network.requests.length, before);
    await harness.unmount(tester);
  });
}
