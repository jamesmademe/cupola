import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/media_child_list.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';

/// An author's books as the author's page shows them: every one by year,
/// and the ones Readarr is looking for.
class AuthorShelf {
  const AuthorShelf._({required this.books, required this.wanted});

  factory AuthorShelf.of(List<ReadarrBook> books, {required DateTime now}) {
    // By year, the oldest first; a book with no date after the dated ones.
    final sorted = [...books]
      ..sort((a, b) {
        final ya = a.year;
        final yb = b.year;
        if (ya == null || yb == null) {
          return (ya == null ? 1 : 0) - (yb == null ? 1 : 0);
        }
        return ya != yb ? ya.compareTo(yb) : a.title.compareTo(b.title);
      });
    return AuthorShelf._(
      books: sorted,
      wanted: [
        for (final book in sorted)
          if (book.monitored && !book.onDisk && !bookIsComing(book, now: now))
            book,
      ],
    );
  }

  /// Every book Readarr knows of the author's, by year.
  final List<ReadarrBook> books;

  /// Monitored, out, and not on disk: what a search would fetch.
  final List<ReadarrBook> wanted;

  int get onDisk => books.where((book) => book.onDisk).length;

  /// Under the author's name: `7 books · 6 on disk · 1 wanted`. A part with
  /// nothing to count is left out.
  String get summary {
    if (books.isEmpty) return 'No books yet';
    // A figure keeps its word on its line.
    return [
      '${books.length}$unitSpace${books.length == 1 ? 'book' : 'books'}',
      if (onDisk > 0) '$onDisk${unitSpace}on disk',
      if (wanted.isNotEmpty)
        '${wanted.length}$unitSpace${StateWord.wanted.inline}',
    ].join(' · ');
  }
}

/// Whether [book] is announced and not out yet, by its release date.
bool bookIsComing(ReadarrBook book, {required DateTime now}) {
  final date = DateTime.tryParse(book.releaseDate ?? '');
  return date != null && date.isAfter(now);
}

/// Where one book stands: the word, its tone, and whether it is the
/// backlog's ring rather than a dot.
typedef BookState = ({String word, StatusTone tone, bool hollow});

/// The state of [book], or null when it needs none (on disk, its year says
/// enough) or while the queue it depends on is still being read.
///
/// In the queue, the queue's word. Not out yet: `Not out yet`. Not on disk:
/// `Wanted` while monitored, over a queue read whole, else `Unknown`; and
/// `Unmonitored` when Readarr was told not to look.
BookState? bookState(
  ReadarrBook book, {
  required ArrQueueSnapshot queue,
  required DateTime now,
}) {
  final entry = queue.entryFor(book.id);
  if (entry != null) {
    final status = mediaStatusFromQueue(
      availability: book.onDisk
          ? MediaAvailability.available
          : MediaAvailability.missing,
      monitored: book.monitored,
      queueEntry: entry,
    );
    return (
      word: mediaStatusWord(status) ?? status.label,
      tone: status.tone,
      hollow: false,
    );
  }
  if (book.onDisk) return null;
  if (bookIsComing(book, now: now)) {
    return (
      word: StateWord.notOutYet.label,
      tone: StatusTone.neutral,
      hollow: true,
    );
  }
  if (!book.monitored) {
    return (word: 'Unmonitored', tone: StatusTone.neutral, hollow: true);
  }
  if (!queue.isWhole) {
    if (queue.isPending) return null;
    return (word: 'Unknown', tone: StatusTone.neutral, hollow: true);
  }
  return (word: StateWord.wanted.label, tone: StatusTone.neutral, hollow: true);
}
