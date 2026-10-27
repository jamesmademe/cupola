import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry, visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, AssetManifest;

import 'package:cupola/demo/world/profile_network.dart';
import 'package:cupola/demo/world/world.dart';

/// The demo's posters and backdrops: the Blender Studio's own pictures of its
/// open films (CC BY 4.0, studio.blender.org), cropped and kept as app
/// assets under `assets/demo/artwork/`, `<title slug>-poster.jpg` and
/// `<title slug>-backdrop.jpg`.
///
/// Each pair comes from the header picture of the film's project page,
/// `https://studio.blender.org/projects/<slug>/` (fetched 27 October 2026):
/// the backdrop is that picture at 1280 pixels wide, the poster a 2:3 crop
/// of it around its subject, 400 by 600.
///
/// The world names them the way TMDB names its pictures, at
/// `image.tmdb.org`, which every client of the app already reads (Seerr's
/// `posterPath`, an arr's `remoteUrl`); the network answers that host with
/// the asset. A title with no picture, or a world that never [preload]ed
/// them (a test's), names none and draws its initials.
abstract final class WorldArtwork {
  /// The host the pictures are named at.
  static const host = 'image.tmdb.org';

  /// Where they are, as a path from the package root and as the asset key
  /// prefix.
  static const directory = 'assets/demo/artwork/';

  /// The titles the Blender Studio pictures, by slug: every one has a poster
  /// and a backdrop.
  static const slugs = {
    'agent-327',
    'big-buck-bunny',
    'charge',
    'coffee-run',
    'cosmos-laundromat',
    'elephants-dream',
    'sintel',
    'spring',
    'sprite-fright',
    'tears-of-steel',
  };

  static final Map<String, Uint8List> _files = {};

  /// Reads every picture [bundle] carries into memory, for the demo.
  static Future<void> preload(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    for (final key in manifest.listAssets()) {
      if (key.startsWith(directory)) {
        final data = await bundle.load(key);
        _files[key.substring(directory.length)] = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      }
    }
  }

  /// Lets go of what [preload] read: the demo ends, and the app's own
  /// servers never answer at the pictures' host.
  static void forget() => _files.clear();

  /// The pictures [preload] read, by file name.
  @visibleForTesting
  static Iterable<String> get files => _files.keys;

  /// [t]'s poster as TMDB names it (`/sintel-poster.jpg`), or null.
  static String? posterPath(WorldTitle t) => _path(t, 'poster');

  /// [t]'s backdrop the same way, or null.
  static String? backdropPath(WorldTitle t) => _path(t, 'backdrop');

  static String? _path(WorldTitle t, String kind) {
    final file = '${t.slug}-$kind.jpg';
    return _files.containsKey(file) ? '/$file' : null;
  }

  /// An arr's `images` for [t]: its poster and fanart at TMDB's full size,
  /// or none.
  static List<Map<String, Object?>> arrImages(WorldTitle t) => [
    if (posterPath(t) case final poster?)
      {'coverType': 'poster', 'remoteUrl': 'https://$host/t/p/original$poster'},
    if (backdropPath(t) case final backdrop?)
      {
        'coverType': 'fanart',
        'remoteUrl': 'https://$host/t/p/original$backdrop',
      },
  ];

  /// Whether [uri] is one of the pictures' addresses, once they are read.
  static bool serves(Uri uri) => _files.isNotEmpty && uri.host == host;

  /// The picture `/t/p/<size>/<file>` names, whatever the size asked for.
  static NetworkReply answer(NetworkRequest request) {
    final bytes = _files[request.uri.pathSegments.lastOrNull];
    if (request.method != 'GET' || bytes == null) {
      return const NetworkReply(404, body: 'Not found');
    }
    return NetworkReply.bytes(bytes, contentType: 'image/jpeg');
  }

  /// Puts the pictures' licence in the app's licence page.
  static void registerLicense() {
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(
        ['Blender Studio films (demo artwork)'],
        'The demo home shows pictures of the open films of the Blender '
        'Studio: Agent 327, Big Buck Bunny, Charge, Coffee Run, Cosmos '
        'Laundromat, Elephants Dream, Sintel, Spring, Sprite Fright and '
        'Tears of Steel. (c) Blender Foundation, studio.blender.org, '
        'licensed under the Creative Commons Attribution 4.0 International '
        'licence (https://creativecommons.org/licenses/by/4.0/). Cropped '
        'and resized for the app.',
      );
    });
  }
}
