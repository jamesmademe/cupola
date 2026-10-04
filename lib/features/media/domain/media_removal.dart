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
MediaRemoval mediaRemoval({
  required String title,
  required String name,
  required int sizeOnDisk,
  required bool monitored,
  List<String> keeping = const [],
}) {
  final stops = monitored
      ? '$name stops looking for it.'
      : '$name stops tracking it.';
  final rest = switch (keeping) {
    [] when sizeOnDisk <= 0 => 'Nothing of it is on your server yet.',
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
