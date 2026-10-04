import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/media/domain/media_removal.dart';

void main() {
  test('nothing on disk: it says so, and there is nothing to delete', () {
    final removal = mediaRemoval(
      title: 'Big Buck Bunny',
      name: 'Radarr',
      sizeOnDisk: 0,
      monitored: true,
    );
    expect(removal.title, 'Remove Big Buck Bunny from Radarr?');
    expect(
      removal.message,
      'Radarr stops looking for it. Nothing of it is on your server yet.',
    );
    expect(removal.filesLabel, isNull);
    // Nothing to delete, so ticking it could not change the confirm.
    expect(
      removal.confirm(deleteFiles: true, exclude: false),
      'Remove from Radarr',
    );
    expect(
      removal.confirm(deleteFiles: false, exclude: true),
      "Remove and don't add it again",
    );
  });

  test('a file on disk: the confirm names what goes with it', () {
    final removal = mediaRemoval(
      title: 'Tears of Steel',
      name: 'Radarr 4K',
      sizeOnDisk: 1200000000,
      monitored: false,
    );
    expect(removal.message, 'Radarr 4K stops tracking it.');
    expect(
      removal.filesLabel,
      matches(RegExp(r'^Also delete 1\.1.GB of files$')),
    );
    expect(
      removal.confirm(deleteFiles: true, exclude: false),
      matches(RegExp(r'^Remove and delete 1\.1.GB$')),
    );
    expect(
      removal.confirm(deleteFiles: true, exclude: true),
      matches(RegExp(r"^Remove, delete 1\.1.GB, don't add again$")),
    );
    expect(
      removal.confirm(deleteFiles: false, exclude: false),
      'Remove from Radarr 4K',
    );
  });

  test('says which copy stays', () {
    expect(
      mediaRemoval(
        title: 'Sintel',
        name: 'Radarr',
        sizeOnDisk: 0,
        monitored: true,
        keeping: ['Radarr 4K'],
      ).message,
      'Radarr stops looking for it. Radarr 4K keeps its copy.',
    );
    expect(
      mediaRemoval(
        title: 'Sintel',
        name: 'Radarr',
        sizeOnDisk: 1,
        monitored: true,
        keeping: ['Radarr 4K', 'Radarr Kids', 'Radarr Anime'],
      ).message,
      'Radarr stops looking for it. Radarr 4K, Radarr Kids and Radarr Anime '
      'keep theirs.',
    );
  });
}
