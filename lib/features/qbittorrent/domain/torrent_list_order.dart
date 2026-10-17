import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';

/// Which torrents the list shows, and in what order.
///
/// Both are applied on the phone, over the whole library the connection's
/// copy holds (`QbittorrentSync`), as qBittorrent's own WebUI does over the
/// same `sync/maindata` answer. They used to be the server's (`filter`, `sort`
/// and `reverse` on `/torrents/info`), which cost a request for every tab and
/// every change of order.

enum TorrentFilter { all, downloading, seeding, completed, paused, queued }

enum TorrentSort {
  name,
  size,
  progress,
  dlSpeed,
  upSpeed,
  eta,
  addedOn,
  state;

  String get label {
    switch (this) {
      case TorrentSort.name:
        return 'Name';
      case TorrentSort.size:
        return 'Size';
      case TorrentSort.progress:
        return 'Progress';
      case TorrentSort.dlSpeed:
        return '↓ Speed';
      case TorrentSort.upSpeed:
        return '↑ Speed';
      case TorrentSort.eta:
        return 'ETA';
      case TorrentSort.addedOn:
        return 'Added';
      case TorrentSort.state:
        return 'State';
    }
  }
}

/// Whether [torrent] belongs under [filter].
///
/// Downloading, Seeding and Completed are the WebUI's own rules, on the raw
/// state, so a tab holds what the same tab holds in qBittorrent: Downloading is
/// every `…DL` state (stopped and queued downloads included), Seeding the five
/// states that are uploading or about to, Completed every `…UP` state. Paused
/// and Queued read the model's census ([TorrentState]), which spans both
/// vocabularies of a stopped torrent (`pausedUP` before 5.1, `stoppedUP` from
/// it).
bool torrentMatches(Torrent torrent, TorrentFilter filter) {
  final state = torrent.state;
  return switch (filter) {
    TorrentFilter.all => true,
    TorrentFilter.downloading => state == 'downloading' || state.contains('DL'),
    TorrentFilter.seeding => _seeding.contains(state),
    TorrentFilter.completed => state == 'uploading' || state.contains('UP'),
    TorrentFilter.paused => torrent.parsedState.isPaused,
    TorrentFilter.queued => torrent.parsedState.isQueued,
  };
}

const _seeding = {
  'uploading',
  'forcedUP',
  'stalledUP',
  'queuedUP',
  'checkingUP',
};

/// [torrents] in [sort] order, largest or latest first when [reverse].
///
/// Ties keep a fixed order (by name, then hash), so rows with equal speeds do
/// not trade places on every tick.
List<Torrent> sortTorrents(
  Iterable<Torrent> torrents,
  TorrentSort sort, {
  required bool reverse,
}) {
  int byKey(Torrent a, Torrent b) => switch (sort) {
    TorrentSort.name => compareNatural(a.name, b.name),
    TorrentSort.size => a.size.compareTo(b.size),
    TorrentSort.progress => a.progress.compareTo(b.progress),
    TorrentSort.dlSpeed => a.dlSpeed.compareTo(b.dlSpeed),
    TorrentSort.upSpeed => a.upSpeed.compareTo(b.upSpeed),
    // qBittorrent's "never" is 8640000 s (100 days), so an unending ETA sorts
    // last ascending without a special case.
    TorrentSort.eta => a.eta.compareTo(b.eta),
    TorrentSort.addedOn => a.addedOn.compareTo(b.addedOn),
    TorrentSort.state => a.state.compareTo(b.state),
  };

  int tie(Torrent a, Torrent b) {
    final names = compareNatural(a.name, b.name);
    return names != 0 ? names : a.hash.compareTo(b.hash);
  }

  return torrents.toList()..sort((a, b) {
    final key = reverse ? byKey(b, a) : byKey(a, b);
    return key != 0 ? key : tie(a, b);
  });
}

/// Compares names as a person reads them: letters without regard to case, and
/// a run of digits by its value, so `Episode 9` comes before `Episode 10`.
int compareNatural(String a, String b) {
  final x = a.toLowerCase();
  final y = b.toLowerCase();
  var i = 0;
  var j = 0;
  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i);
    final cy = y.codeUnitAt(j);
    if (_isDigit(cx) && _isDigit(cy)) {
      final si = i;
      final sj = j;
      while (i < x.length && _isDigit(x.codeUnitAt(i))) {
        i++;
      }
      while (j < y.length && _isDigit(y.codeUnitAt(j))) {
        j++;
      }
      // Compared as text once leading zeros are gone, longer first: no run of
      // digits is too long for this, as it would be for an int.
      final dx = x.substring(si, i).replaceFirst(RegExp('^0+(?=.)'), '');
      final dy = y.substring(sj, j).replaceFirst(RegExp('^0+(?=.)'), '');
      if (dx.length != dy.length) return dx.length.compareTo(dy.length);
      final digits = dx.compareTo(dy);
      if (digits != 0) return digits;
      continue;
    }
    if (cx != cy) return cx.compareTo(cy);
    i++;
    j++;
  }
  return (x.length - i).compareTo(y.length - j);
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
