import 'dart:math' as math;

import 'package:cupola/demo/world/arr_life.dart';
import 'package:cupola/demo/world/profile_network.dart';
import 'package:cupola/demo/world/world.dart';

/// The world once it lives: what the demo's visitor does changes what the
/// servers answer next, and time moves the downloads on.
///
/// Off by default. A test's network answers from its profile, as written,
/// whatever it sends; the demo turns life on (`ProfileNetwork.live`) and the
/// world then keeps what it is told and catches up with its clock before
/// every answer ([catchUp]).
///
/// Only what the world can keep honestly is kept: the downloads (their
/// progress, a pause, a removal, a new grab) here, and what each service
/// adds beside it (an arr's library, Seerr's requests) through the hooks it
/// registers.
class WorldLife {
  WorldLife(this._network)
    : _downloads = [..._network.profile.downloads],
      _stepped = _network.currentTime {
    arrs = ArrLife(this, _network);
  }

  /// The arrs' libraries, as the world keeps them.
  late final ArrLife arrs;

  final ProfileNetwork _network;
  List<WorldDownload> _downloads;
  DateTime _stepped;

  /// What a download moved at before it was paused, by id.
  final Map<String, int> _cruise = {};

  /// Usenet queues paused or resumed in the demo, by connection id; a queue
  /// not named here is as the profile has it.
  final Map<String, bool> _queuePaused = {};

  /// Told of each download as it finishes, with its row as it was: the arr
  /// whose queue carried it imports it from there.
  final List<void Function(WorldDownload finished, DateTime at)> _onFinished =
      [];

  /// The speed a usenet job starts at when the one before it ends and it
  /// left the queue with none of its own.
  static const usenetSpeed = 18 * 1024 * 1024;

  /// The same for a torrent.
  static const torrentSpeed = 6 * 1024 * 1024;

  /// Every download, as the clients and the arrs' queues see it now.
  List<WorldDownload> get downloads => List.unmodifiable(_downloads);

  /// The usenet clients whose whole queue is paused.
  Set<String> get pausedQueues => {
    for (final id in _network.profile.pausedQueues)
      if (_queuePaused[id] ?? true) id,
    for (final MapEntry(key: id, value: paused) in _queuePaused.entries)
      if (paused) id,
  };

  /// Registers [listener] for every download that finishes.
  void onFinished(
    void Function(WorldDownload finished, DateTime at) listener,
  ) => _onFinished.add(listener);

  // === Time ================================================================

  /// Brings the world to the network's clock: every download that moves
  /// takes its share of the time since the last answer, one that finishes
  /// is handed to whoever imports it, and a queue that emptied starts its
  /// next job.
  void catchUp() {
    final now = _network.currentTime;
    final elapsed = now.difference(_stepped);
    if (elapsed <= Duration.zero) return;
    _stepped = now;
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final paused = pausedQueues;
    final finished = <WorldDownload>[];
    final next = <WorldDownload>[];
    for (final d in _downloads) {
      if (d.state != DownloadState.downloading ||
          d.speed <= 0 ||
          _queueOf(d, paused)) {
        next.add(d);
        continue;
      }
      final progress = math.min(1.0, d.progress + d.speed * seconds / d.size);
      if (progress < 1) {
        final moved = d.copyWith(progress: progress);
        next.add(
          moved.copyWith(eta: Duration(seconds: moved.sizeLeft ~/ d.speed)),
        );
        continue;
      }
      finished.add(d);
      // A torrent stays with its client and seeds; a usenet job leaves the
      // queue for the client's history.
      if (_isTorrent(d)) {
        next.add(
          d.copyWith(
            state: DownloadState.seeding,
            progress: 1,
            speed: 0,
            clearEta: true,
          ),
        );
      }
    }
    _downloads = _startQueued(next, paused);
    for (final d in finished) {
      for (final listener in _onFinished) {
        listener(d, now);
      }
    }
  }

  /// Each client with nothing downloading starts the first job it holds
  /// queued.
  List<WorldDownload> _startQueued(
    List<WorldDownload> downloads,
    Set<String> paused,
  ) {
    final busy = {
      for (final d in downloads)
        if (d.state == DownloadState.downloading) d.client,
    };
    final started = <String>{};
    return [
      for (final d in downloads)
        if (d.state == DownloadState.queued &&
            !busy.contains(d.client) &&
            !_queueOf(d, paused) &&
            started.add(d.client))
          d.copyWith(state: DownloadState.downloading, speed: _speedOf(d))
        else
          d,
    ];
  }

  // === What the visitor does ===============================================

  /// The download [id] (a hash in any case, an `nzo_id`), or null.
  WorldDownload? byId(String id) {
    final wanted = id.toLowerCase();
    return _downloads.where((d) => d.id.toLowerCase() == wanted).firstOrNull;
  }

  /// Pauses download [id]: a job still coming stops where it is, a finished
  /// torrent stops seeding.
  void pause(String id) => _edit(id, (d) {
    if (d.state == DownloadState.downloading) _cruise[d.id] = d.speed;
    return switch (d.state) {
      DownloadState.downloading ||
      DownloadState.queued ||
      DownloadState.stuck => d.copyWith(
        state: DownloadState.paused,
        speed: 0,
        clearEta: true,
      ),
      DownloadState.seeding => d.copyWith(state: DownloadState.stopped),
      _ => d,
    };
  });

  /// Resumes download [id] where it stopped.
  void resume(String id) => _edit(id, (d) {
    return switch (d.state) {
      DownloadState.paused || DownloadState.heldByClient => d.copyWith(
        state: DownloadState.downloading,
        speed: _speedOf(d),
      ),
      DownloadState.stopped => d.copyWith(state: DownloadState.seeding),
      _ => d,
    };
  });

  /// Takes download [id] away from its client and its arr's queue.
  void remove(String id) {
    final wanted = id.toLowerCase();
    _downloads = [
      for (final d in _downloads)
        if (d.id.toLowerCase() != wanted) d,
    ];
  }

  /// Download [id] is done with: imported by its arr, it leaves the queue.
  /// A torrent stays with its client, seeding; a usenet job leaves for the
  /// client's history.
  void settle(String id) {
    final wanted = id.toLowerCase();
    _downloads = [
      for (final d in _downloads)
        if (d.id.toLowerCase() != wanted)
          d
        else if (_isTorrent(d))
          d.copyWith(
            state: DownloadState.seeding,
            progress: 1,
            speed: 0,
            clearEta: true,
          ),
    ];
  }

  /// The arr lets go of download [id] and the client keeps it: a queue row
  /// removed without removing it from the client.
  void leaveArr(String id) => _edit(id, (d) => d.copyWith(clearArr: true));

  /// Adds [download], a grab. It starts at once, whatever its client is
  /// busy with: a torrent client fetches side by side, and the demo's pace
  /// (a title asked for arrives in a minute or two) is worth more than a
  /// usenet queue's order.
  void add(WorldDownload download) => _downloads = [..._downloads, download];

  /// Dockge [serverId]'s stacks and their status (3 running, 4 exited, 1
  /// inactive), from [seed] the first time they are asked for.
  Map<String, int> stacks(String serverId, Map<String, int> seed) =>
      _stacks.putIfAbsent(serverId, () => {...seed});

  final Map<String, Map<String, int>> _stacks = {};

  /// Pauses or resumes the whole queue of usenet client [connectionId].
  void setQueuePaused(String connectionId, {required bool paused}) =>
      _queuePaused[connectionId] = paused;

  void _edit(String id, WorldDownload Function(WorldDownload) change) {
    final wanted = id.toLowerCase();
    _downloads = [
      for (final d in _downloads) d.id.toLowerCase() == wanted ? change(d) : d,
    ];
  }

  int _speedOf(WorldDownload d) {
    final known = _cruise.remove(d.id) ?? d.speed;
    if (known > 0) return known;
    return _isTorrent(d) ? torrentSpeed : usenetSpeed;
  }

  /// Whether [d] sits in a usenet queue somebody paused. The world's usenet
  /// clients are one connection each, named after the client.
  bool _queueOf(WorldDownload d, Set<String> paused) =>
      !_isTorrent(d) &&
      _network.profile.connections.any(
        (c) => c.service.name == d.client && paused.contains(c.id),
      );

  static bool _isTorrent(WorldDownload d) =>
      d.client == 'qbittorrent' || d.client == 'transmission';
}
