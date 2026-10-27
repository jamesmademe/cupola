/// Exports World A as `world.json` for the testlab seed.
///
/// `lib/demo/world/world.dart` is the one source: the unit tests,
/// the design boards and the testlab all name the same titles, people, artists,
/// books and downloads. This script only serialises it, in a stable order, so
/// the seed never carries a hand-copied second world.
///
/// ```sh
/// dart run tool/testlab/export_world.dart
/// dart run tool/testlab/export_world.dart --check
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:cupola/demo/world/world.dart';

const String defaultOutputPath = '.ai/scratch/zz_testlab/world.json';

String worldJson() {
  final document = <String, Object?>{
    'version': 1,
    'hosts': {
      'radarr': WorldHosts.radarr,
      'radarr4k': WorldHosts.radarr4k,
      'sonarr': WorldHosts.sonarr,
      'sonarrAnime': WorldHosts.sonarrAnime,
      'lidarr': WorldHosts.lidarr,
      'prowlarr': WorldHosts.prowlarr,
      'bazarr': WorldHosts.bazarr,
      'qbittorrent': WorldHosts.qbittorrent,
      'sabnzbd': WorldHosts.sabnzbd,
      'seerr': WorldHosts.seerr,
      'jellyfin': WorldHosts.jellyfin,
      'plex': WorldHosts.plex,
      'truenas': WorldHosts.truenas,
      'dockge': WorldHosts.dockge,
      'unraid': WorldHosts.unraid,
      'readarr': WorldHosts.readarr,
      'nzbget': WorldHosts.nzbget,
      'npm': WorldHosts.npm,
    },
    'people': {
      'operator': WorldPeople.operatorName,
      'anna': WorldPeople.anna,
      'luca': WorldPeople.luca,
      'friend': WorldPeople.friend,
    },
    'titles': [for (final title in _sortedTitles) _title(title)],
    'artists': [
      for (final artist in _sortedArtists)
        {
          'key': artist.key,
          'name': artist.name,
          'foreignArtistId': artist.foreignArtistId,
          'albums': [
            for (final album in artist.albums)
              {
                'title': album.title,
                'year': album.year,
                'foreignAlbumId': album.foreignAlbumId,
                'tracks': album.tracks,
              },
          ],
        },
    ],
    'authors': [
      for (final author in _sortedAuthors)
        {
          'key': author.key,
          'name': author.name,
          'foreignAuthorId': author.foreignAuthorId,
          'books': [
            for (final book in author.books)
              {
                'title': book.title,
                'year': book.year,
                'foreignBookId': book.foreignBookId,
              },
          ],
        },
    ],
    'downloads': [for (final download in _sortedDownloads) _download(download)],
  };
  return '${const JsonEncoder.withIndent('  ').convert(document)}\n';
}

List<WorldTitle> get _sortedTitles =>
    [...WorldTitles.catalogue]..sort((a, b) => a.key.compareTo(b.key));

List<WorldArtist> get _sortedArtists =>
    [...WorldMusic.all]..sort((a, b) => a.key.compareTo(b.key));

List<WorldAuthor> get _sortedAuthors =>
    [...WorldBooks.all]..sort((a, b) => a.key.compareTo(b.key));

List<WorldDownload> get _sortedDownloads =>
    [...WorldDownloads.all]..sort((a, b) => a.id.compareTo(b.id));

Map<String, Object?> _title(WorldTitle title) {
  final map = <String, Object?>{
    'key': title.key,
    'title': title.title,
    'year': title.year,
    'tmdbId': title.tmdbId,
    'isSeries': title.isSeries,
  };
  if (title.imdbId != null) map['imdbId'] = title.imdbId;
  if (title.tvdbId != null) map['tvdbId'] = title.tvdbId;
  return map;
}

Map<String, Object?> _download(WorldDownload download) {
  final map = <String, Object?>{
    'id': download.id,
    'release': download.release,
    'client': download.client,
    'state': download.state.name,
    'progress': download.progress,
    'size': download.size,
    'speed': download.speed,
    'onlyWithClient': download.onlyWithClient,
  };
  if (download.arr != null) map['arr'] = download.arr;
  if (download.title != null) map['title'] = download.title!.key;
  if (download.season != null) map['season'] = download.season;
  if (download.episode != null) map['episode'] = download.episode;
  if (download.eta != null) map['etaSeconds'] = download.eta!.inSeconds;
  if (download.peers != null) map['peers'] = download.peers;
  return map;
}

void main(List<String> arguments) {
  final check = arguments.contains('--check');
  final output = _outputPath(arguments);
  final json = worldJson();
  if (check) {
    final file = File(output);
    if (!file.existsSync() || file.readAsStringSync() != json) {
      stderr.writeln('$output is stale; run tool/testlab/export_world.dart');
      exitCode = 1;
    }
    return;
  }
  final file = File(output);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(json);
  stdout.writeln('wrote $output');
}

String _outputPath(List<String> arguments) {
  final index = arguments.indexOf('--output');
  if (index >= 0 && index + 1 < arguments.length) {
    return arguments[index + 1];
  }
  return defaultOutputPath;
}
