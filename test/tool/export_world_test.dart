import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/world/world.dart';
import '../../tool/testlab/export_world.dart';

/// The exported world is the same world the tests and the boards name: one
/// source, no hand-copied second catalogue. A drift here is a seed that
/// quietly stops matching the app's fixtures.
void main() {
  final document = jsonDecode(worldJson()) as Map<String, dynamic>;

  test('the export is deterministic', () {
    expect(worldJson(), worldJson());
  });

  test('every catalogue title is in the export, with its ids', () {
    final titles = (document['titles'] as List).cast<Map<String, dynamic>>();
    expect(titles, hasLength(WorldTitles.catalogue.length));
    for (final title in WorldTitles.catalogue) {
      final entry = titles.firstWhere((item) => item['key'] == title.key);
      expect(entry['title'], title.title);
      expect(entry['year'], title.year);
      expect(entry['tmdbId'], title.tmdbId);
      expect(entry['isSeries'], title.isSeries);
      if (title.tvdbId case final tvdb?) {
        expect(entry['tvdbId'], tvdb);
      }
    }
    expect(titles.where((item) => item['isSeries'] == true), hasLength(12));
    expect(titles.where((item) => item['isSeries'] == false), hasLength(40));
  });

  test('the music and the books are the world catalogue', () {
    final artists = (document['artists'] as List).cast<Map<String, dynamic>>();
    final authors = (document['authors'] as List).cast<Map<String, dynamic>>();
    expect(artists, hasLength(WorldMusic.all.length));
    expect(authors, hasLength(WorldBooks.all.length));
    expect(artists.first['name'], 'Air');
    expect(authors.first['name'], 'Jane Austen');
    for (final artist in WorldMusic.all) {
      final entry = artists.firstWhere((item) => item['key'] == artist.key);
      expect(entry['name'], artist.name);
      expect(entry['albums'], hasLength(artist.albums.length));
    }
    for (final author in WorldBooks.all) {
      final entry = authors.firstWhere((item) => item['key'] == author.key);
      expect(entry['name'], author.name);
      expect(entry['books'], hasLength(author.books.length));
    }
  });

  test('every download is in the export, with its join', () {
    final downloads = (document['downloads'] as List)
        .cast<Map<String, dynamic>>();
    expect(downloads, hasLength(WorldDownloads.all.length));
    for (final download in WorldDownloads.all) {
      final entry = downloads.firstWhere((item) => item['id'] == download.id);
      expect(entry['release'], download.release);
      expect(entry['client'], download.client);
      expect(entry['state'], download.state.name);
      expect(entry['progress'], download.progress);
      if (download.title case final title?) {
        expect(entry['title'], title.key);
      }
    }
  });

  test('the people and the hosts are the world', () {
    expect((document['people'] as Map)['anna'], WorldPeople.anna);
    expect((document['hosts'] as Map)['radarr'], WorldHosts.radarr);
    expect((document['hosts'] as Map)['readarr'], WorldHosts.readarr);
  });
}
