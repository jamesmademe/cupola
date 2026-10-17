import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/media_child_list.dart';
import 'package:cupola/features/music/domain/lidarr_status.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';

/// An artist's albums as the artist's page sorts them: the ones announced,
/// the ones Lidarr is looking for, the ones on disk, and the ones it leaves
/// alone.
///
/// Every album lands in exactly one: one not out yet is [coming] whatever is
/// on disk; one out with a track or more on disk is [onDisk]; one out with
/// nothing on disk is [wanted] while it is monitored and [unmonitored]
/// otherwise.
class ArtistShelf {
  const ArtistShelf._({
    required this.coming,
    required this.wanted,
    required this.onDisk,
    required this.unmonitored,
  });

  factory ArtistShelf.of(List<LidarrAlbum> albums, {required DateTime now}) {
    final coming = <LidarrAlbum>[];
    final wanted = <LidarrAlbum>[];
    final onDisk = <LidarrAlbum>[];
    final unmonitored = <LidarrAlbum>[];
    for (final album in albums) {
      if (albumIsComing(album, now: now)) {
        coming.add(album);
      } else if (album.trackFileCount > 0) {
        onDisk.add(album);
      } else if (album.monitored) {
        wanted.add(album);
      } else {
        unmonitored.add(album);
      }
    }
    int newestFirst(LidarrAlbum a, LidarrAlbum b) =>
        _releaseOf(b).compareTo(_releaseOf(a));
    coming.sort((a, b) => _releaseOf(a).compareTo(_releaseOf(b)));
    wanted.sort(newestFirst);
    onDisk.sort(newestFirst);
    unmonitored.sort(newestFirst);
    return ArtistShelf._(
      coming: coming,
      wanted: wanted,
      onDisk: onDisk,
      unmonitored: unmonitored,
    );
  }

  /// Announced and not out yet, the soonest first.
  final List<LidarrAlbum> coming;

  /// Out, monitored, nothing on disk: what a search would fetch. Newest
  /// first, as every list here.
  final List<LidarrAlbum> wanted;

  /// Out, with a track or more on disk.
  final List<LidarrAlbum> onDisk;

  /// Out, nothing on disk, and Lidarr told not to look.
  final List<LidarrAlbum> unmonitored;

  /// Under the artist's name: `3 albums on disk · 1 wanted · 1 announced`.
  /// A part with nothing to count is left out; with nothing on disk the
  /// wanted lead (`4 albums wanted`).
  String get summary {
    // A figure keeps its word on its line: `1 announced` never breaks after
    // the 1.
    String count(int n, String words) => '$n$unitSpace$words';
    final parts = <String>[
      if (onDisk.isNotEmpty) '${_albums(onDisk.length)} on disk',
      if (wanted.isNotEmpty)
        onDisk.isEmpty
            ? '${_albums(wanted.length)} ${StateWord.wanted.inline}'
            : count(wanted.length, StateWord.wanted.inline),
      if (coming.isNotEmpty) count(coming.length, 'announced'),
    ];
    return parts.isEmpty ? 'No albums yet' : parts.join(dotSeparator);
  }

  /// The covers the page shows under the name, at most three: what is on
  /// disk first, newest first, then the rest.
  List<LidarrAlbum> get covers => [
    ...onDisk,
    ...wanted,
    ...coming,
    ...unmonitored,
  ].take(3).toList(growable: false);
}

/// Whether [album] is announced and not out yet, by its release date.
/// An album with no date Lidarr can read is out.
bool albumIsComing(LidarrAlbum album, {required DateTime now}) {
  final date = DateTime.tryParse(album.releaseDate ?? '');
  return date != null && date.isAfter(now);
}

DateTime _releaseOf(LidarrAlbum album) =>
    DateTime.tryParse(album.releaseDate ?? '') ?? DateTime(0);

String _albums(int count) =>
    '$count$unitSpace${count == 1 ? 'album' : 'albums'}';

/// `5 tracks`, or null when Lidarr does not say.
String? albumTrackCount(LidarrAlbum album) => album.trackCount <= 0
    ? null
    : '${album.trackCount} ${album.trackCount == 1 ? 'track' : 'tracks'}';

/// What a row says about [album] under its title: `2010 · 5 tracks ·
/// 21 min`.
List<String> albumFacts(LidarrAlbum album) => [
  if (album.year.isNotEmpty) album.year,
  ?albumTrackCount(album),
  if (album.duration > 0)
    formatTimeSpan(Duration(milliseconds: album.duration)),
];

/// The same facts as a screen reader hears them: `2010, 5 tracks,
/// 21 minutes`.
List<String> albumSpokenFacts(LidarrAlbum album) => [
  if (album.year.isNotEmpty) album.year,
  ?albumTrackCount(album),
  if (album.duration > 0) _spokenSpan(Duration(milliseconds: album.duration)),
];

String _spokenSpan(Duration span) {
  final hours = span.inHours;
  final minutes = span.inMinutes % 60;
  String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
  if (hours == 0) return unit(minutes, 'minute');
  return minutes == 0
      ? unit(hours, 'hour')
      : '${unit(hours, 'hour')} ${unit(minutes, 'minute')}';
}

/// Where one album stands, as its row's state line says it: the word, its
/// tone, and whether it is the backlog's ring rather than a dot.
typedef AlbumState = ({String word, StatusTone tone, bool hollow});

/// The state line of [album]'s row, or null while the queue it depends on is
/// still being read (`badgeOverQueue`).
///
/// In the queue, the queue's word (`Downloading 45%`, `Import failed`). Not
/// out yet: `Out Fri 2 Oct · not out yet`. Then by what is on disk: every
/// track is `Complete`, some are `4 of 5 tracks`, none is `Wanted` while
/// monitored and `Unmonitored` otherwise.
AlbumState? albumState(
  LidarrAlbum album, {
  required ArrQueueSnapshot queue,
  required DateTime now,
}) {
  final entry = queue.entryFor(album.id);
  if (entry != null) {
    final status = lidarrAlbumStatus(album, queueEntry: entry);
    return (
      word: mediaStatusWord(status) ?? status.label,
      tone: status.tone,
      hollow: false,
    );
  }
  if (albumIsComing(album, now: now)) {
    return (
      word:
          'Out ${formatShortDate(album.releaseDate!, now: now)}\u00A0· '
          '${StateWord.notOutYet.inline}',
      tone: StatusTone.neutral,
      hollow: true,
    );
  }
  final files = album.trackFileCount;
  final tracks = album.trackCount;
  if (files > 0 && files >= tracks) {
    return (word: 'Complete', tone: StatusTone.success, hollow: false);
  }
  if (files > 0) {
    return (
      word: lidarrAlbumSummary(album) ?? StateWord.missing.label,
      tone: StatusTone.neutral,
      hollow: true,
    );
  }
  if (!album.monitored) {
    return (word: 'Unmonitored', tone: StatusTone.neutral, hollow: true);
  }
  // Nothing on disk and nothing in a queue read whole: it may be downloading
  // right now, so the word waits for the queue, and says it does not know
  // once the queue has failed.
  if (!queue.isWhole) {
    if (queue.isPending) return null;
    return (word: 'Unknown', tone: StatusTone.neutral, hollow: true);
  }
  return (word: StateWord.wanted.label, tone: StatusTone.neutral, hollow: true);
}
