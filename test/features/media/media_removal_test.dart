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

  test('clearing from Seerr counts the requests it forgets, and says the '
      'scan finds what is on the server again', () {
    final cleared = seerrClearing(
      title: 'Sintel',
      name: 'Seerr',
      requests: 2,
      onServer: true,
    );
    expect(cleared.title, 'Clear Sintel from Seerr?');
    expect(
      cleared.message,
      'Seerr forgets it and its 2 requests. Nothing is removed from your '
      'server. Seerr finds it again at its next scan, as not requested.',
    );
    expect(cleared.confirm, 'Clear from Seerr');
    expect(
      seerrClearing(
        title: 'Spring',
        name: 'Seerr',
        requests: 0,
        onServer: false,
      ).message,
      'Seerr forgets what it knows of it. Nothing is removed from your server.',
    );
  });

  test('removing through Seerr says the files go with it', () {
    final removal = seerrArrRemoval(
      title: 'Sintel',
      server: 'Radarr 4K',
      seerr: 'Seerr',
    );
    expect(removal.title, 'Remove Sintel from Radarr 4K?');
    expect(
      removal.message,
      'Seerr asks Radarr 4K to remove it and delete its files. '
      'This cannot be undone.',
    );
  });
}
