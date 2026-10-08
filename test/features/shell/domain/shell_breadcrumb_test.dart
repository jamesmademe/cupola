import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/shell/domain/shell_breadcrumb.dart';

void main() {
  group('ShellBreadcrumb.of', () {
    List<String> labels(String location) =>
        ShellBreadcrumb.of(location).map((c) => c.label).toList();

    test('the crumb is the URL, three deep', () {
      expect(labels('/dashboard'), ['Dashboard']);
      expect(labels('/dashboard/radarr'), ['Dashboard', 'Radarr']);
      expect(labels('/dashboard/radarr/library'), [
        'Dashboard',
        'Radarr',
        'Library',
      ]);
    });

    test('a tab takes its own label, not a title-cased segment', () {
      // The defect this file exists for. Nothing knew `vms` or `rss`, so the
      // crumb title-cased the segment and printed `Vms` and `Rss` next to bars
      // that say VMs and RSS — two surfaces naming one place two ways, in the
      // same window, one above the other.
      expect(labels('/dashboard/unraid/vms').last, 'VMs');
      expect(labels('/dashboard/qbittorrent/rss').last, 'RSS');
      expect(labels('/dashboard/plex/on-deck').last, 'On deck');
      expect(labels('/dashboard/npm/proxy-hosts').last, 'Proxy hosts');
      expect(labels('/dashboard/npm/audit-log').last, 'Audit log');
    });

    test('a tab another service owns is not claimed by this one', () {
      // `rss` is a qBittorrent tab. Radarr has no such view, so a deep link
      // naming it is not a place on Radarr and the crumb must not say it is.
      expect(labels('/dashboard/radarr/rss').last, isNot('RSS'));
    });

    test("TrueNAS keeps the word Dashboard for its own console section", () {
      // The one place the app does not rename another product's furniture.
      expect(labels('/dashboard/truenas/dashboard'), [
        'Dashboard',
        'TrueNAS',
        'Dashboard',
      ]);
    });

    test('an item id is the page\'s to name, not the trail\'s', () {
      // The crumb stops at the last *place*. A record's own identity belongs to
      // the page, which knows what it is called; the trail would only have the
      // number.
      expect(labels('/dashboard/radarr/library/movie/1234'), [
        'Dashboard',
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
      expect(labels('/dashboard/media/movie/603'), ['Dashboard', 'Movie']);
    });

    test('an unknown location yields nothing rather than guessing', () {
      expect(ShellBreadcrumb.of(''), isEmpty);
      expect(ShellBreadcrumb.of('/'), isEmpty);
    });

    test('every crumb but the last points somewhere', () {
      final crumbs = ShellBreadcrumb.of('/dashboard/radarr/library');
      for (final crumb in crumbs.take(crumbs.length - 1)) {
        expect(crumb.location, isNotNull, reason: crumb.label);
      }
      // The leaf is where you already are.
      expect(crumbs.last.location, isNull);
    });
  });
}
