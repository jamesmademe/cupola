import 'package:cupola/core/utils/byte_format.dart';

/// What removing one copy from its arr says: the question, the
/// sentence under it, what "Also delete" would take, and the confirm for
/// each choice. The confirm names the whole of what happens.
class MediaRemoval {
  const MediaRemoval._({
    required this.title,
    required this.message,
    required this.name,
    required this.files,
  });

  /// `Remove Big Buck Bunny from Radarr?`
  final String title;

  /// What follows, in one or two sentences: the arr stops looking for it;
  /// nothing of it is on the server yet, or which other copy stays.
  final String message;

  /// The connection the copy is removed from.
  final String name;

  /// What "Also delete" would take, `1.2 GB`; null when nothing of it is on
  /// disk, and there is nothing to delete.
  final String? files;

  /// `Also delete 1.2 GB of files`, when there are any.
  String? get filesLabel =>
      files == null ? null : 'Also delete $files of files';

  /// The confirm, as the two choices stand.
  String confirm({required bool deleteFiles, required bool exclude}) {
    final files = this.files;
    return switch ((deleteFiles && files != null, exclude)) {
      (true, true) => "Remove, delete $files, don't add again",
      (true, false) => 'Remove and delete $files',
      (false, true) => "Remove and don't add it again",
      (false, false) => 'Remove from $name',
    };
  }
}

/// The removal of [title]'s copy from the connection called [name], whose
/// files take [sizeOnDisk] bytes, while [keeping] (the other connections that
/// hold a copy) keep theirs. [monitored] is whether the arr is looking for it.
///
/// [works] is for a person rather than a title, an artist or an author: what
/// the arr looks for of theirs (`albums`), so it says `Lidarr stops looking
/// for their albums.` and never calls the person "it".
MediaRemoval mediaRemoval({
  required String title,
  required String name,
  required int sizeOnDisk,
  required bool monitored,
  List<String> keeping = const [],
  String? works,
}) {
  final stops = switch ((monitored, works)) {
    (true, null) => '$name stops looking for it.',
    (false, null) => '$name stops tracking it.',
    (true, final works?) => '$name stops looking for their $works.',
    (false, _) => '$name stops tracking them.',
  };
  final rest = switch (keeping) {
    [] when sizeOnDisk <= 0 =>
      works == null
          ? 'Nothing of it is on your server yet.'
          : 'None of their $works are on your server yet.',
    [] => null,
    [final other] => '$other keeps its copy.',
    _ =>
      '${keeping.take(keeping.length - 1).join(', ')} and '
          '${keeping.last} keep theirs.',
  };
  return MediaRemoval._(
    title: 'Remove $title from $name?',
    message: rest == null ? stops : '$stops $rest',
    name: name,
    files: sizeOnDisk > 0 ? formatBytes(sizeOnDisk) : null,
  );
}

/// What one Seerr's controls on a title say: a question, the sentence under
/// it, and the confirm, which names the whole of what happens.
typedef SeerrRemoval = ({String title, String message, String confirm});

/// Clearing [title] from the Seerr called [name] (Seerr's "Clear data"):
/// Seerr forgets its record and the [requests] made for it, and nothing
/// leaves an arr or the server. [onServer] is whether Seerr says some of it
/// is there: its next scan then finds it again, with no request.
SeerrRemoval seerrClearing({
  required String title,
  required String name,
  required int requests,
  required bool onServer,
}) => (
  title: 'Clear $title from $name?',
  message: [
    switch (requests) {
      0 => '$name forgets what it knows of it.',
      1 => '$name forgets it and its request.',
      _ => '$name forgets it and its $requests requests.',
    },
    'Nothing is removed from your server.',
    if (onServer) '$name finds it again at its next scan, as not requested.',
  ].join(' '),
  confirm: 'Clear from $name',
);

/// Removing [title]'s copy from [server], a server Cupola has no connection
/// to, through the Seerr called [seerr]: Seerr always deletes its files with
/// it, and never keeps the arr from adding it again.
SeerrRemoval seerrArrRemoval({
  required String title,
  required String server,
  required String seerr,
}) => (
  title: 'Remove $title from $server?',
  message:
      '$seerr asks $server to remove it and delete its files. '
      'This cannot be undone.',
  confirm: 'Remove and delete its files',
);
