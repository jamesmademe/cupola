import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/shell/domain/shell_breadcrumb.dart';

void main() {
  group('ShellBreadcrumb.of', () {
    List<String> labels(String location) =>
        ShellBreadcrumb.of(location).map((c) => c.label).toList();

    test('the crumb is the URL, three deep', () {
      expect(labels('/stack'), ['Stack']);
      expect(labels('/stack/radarr'), ['Stack', 'Radarr']);
      expect(labels('/stack/radarr/library'), ['Stack', 'Radarr', 'Library']);
    });

    test('the first crumb is the tab the location hangs off', () {
      expect(labels('/home'), ['Home']);
      expect(labels('/discover'), ['Discover']);
      expect(labels('/activity'), ['Activity']);
      expect(labels('/requests'), ['Requests']);
      expect(labels('/home/media/movie/603'), ['Home', 'Movie']);
      expect(labels('/requests/media/tv/1396'), ['Requests', 'Series']);
      // A tab's crumb points back at the tab's own root.
      expect(ShellBreadcrumb.of('/home').single.location, '/home');
      expect(ShellBreadcrumb.of('/stack').single.location, '/stack');
    });

    test('a tab takes its own label, not a title-cased segment', () {
      // The defect this file exists for. Nothing knew `vms` or `rss`, so the
      // crumb title-cased the segment and printed `Vms` and `Rss` next to bars
      // that say VMs and RSS: two surfaces naming one place two ways, in the
      // same window, one above the other.
      expect(labels('/stack/unraid/vms').last, 'VMs');
      expect(labels('/stack/qbittorrent/rss').last, 'RSS');
      expect(labels('/stack/plex/on-deck').last, 'On deck');
      expect(labels('/stack/npm/proxy-hosts').last, 'Proxy hosts');
      expect(labels('/stack/npm/audit-log').last, 'Audit log');
    });

    test('a page of Settings takes the word its own bar says', () {
      expect(labels('/settings/another-device'), [
        'Settings',
        'Set up another device',
      ]);
      expect(labels('/settings/certificates').last, 'Trusted certificates');
    });

    test('a tab another service owns is not claimed by this one', () {
      // `rss` is a qBittorrent tab. Radarr has no such view, so a deep link
      // naming it is not a place on Radarr and the crumb must not say it is.
      expect(labels('/stack/radarr/rss').last, isNot('RSS'));
    });

    test("TrueNAS keeps the word Dashboard for its own console section", () {
      // The one place the app does not rename another product's furniture.
      expect(labels('/stack/truenas/dashboard'), [
        'Stack',
        'TrueNAS',
        'Dashboard',
      ]);
    });

    test('an item id is the page\'s to name, not the trail\'s', () {
      // The crumb stops at the last *place*. A record's own identity belongs to
      // the page, which knows what it is called; the trail would only have the
      // number.
      expect(labels('/stack/radarr/library/movie/1234'), [
        'Stack',
        'Radarr',
        'Library',
      ]);
    });

    test('a title\'s page under a tab says what it is, not Library', () {
      // A movie opened from Discover read `Discover › Library`, for a title
      // the library does not hold.
      expect(labels('/discover/media/movie/603'), ['Discover', 'Movie']);
      expect(labels('/discover/media/tv/1396'), ['Discover', 'Series']);
      expect(labels('/discover/media/person/287'), ['Discover', 'Person']);
      expect(labels('/discover/media/collection/2344'), [
        'Discover',
        'Collection',
      ]);
      expect(labels('/stack/media/movie/603'), ['Stack', 'Movie']);
    });

    test('an unknown location yields nothing rather than guessing', () {
      expect(ShellBreadcrumb.of(''), isEmpty);
      expect(ShellBreadcrumb.of('/'), isEmpty);
    });

    test('every crumb but the last points somewhere', () {
      final crumbs = ShellBreadcrumb.of('/stack/radarr/library');
      for (final crumb in crumbs.take(crumbs.length - 1)) {
        expect(crumb.location, isNotNull, reason: crumb.label);
      }
      // The leaf is where you already are.
      expect(crumbs.last.location, isNull);
    });
  });
}
