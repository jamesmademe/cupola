import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One step in the window's breadcrumb.
///
/// Carries the location it points at so a crumb can be a *control*: on desktop
/// the window title is the breadcrumb, and a title you cannot click is a label
/// pretending to be navigation.
typedef Crumb = ({String label, String? location});

/// Turns a router location into the trail the window strip prints.
///
/// Derived from the path alone, never from `state.extra`, for the same reason
/// detail routes must resolve from path params: a deep link, a restored window
/// and a restart all arrive with nothing but the path, and a breadcrumb that
/// went blank in those cases would take the window's title with it.
///
/// The trail is deliberately shallow — section, service, area — and stops
/// there. Nobody navigates by the fourth crumb, and an item's own name is
/// already the largest thing on the page under it.
abstract final class ShellBreadcrumb {
  /// Segments that name a *thing* rather than a place, and are dropped.
  ///
  /// An id in a breadcrumb is noise at best and a leaked database key at worst;
  /// the page it identifies is showing that item's title in display type two
  /// rows below.
  static bool _isIdentifier(String segment) =>
      int.tryParse(segment) != null ||
      segment.length > 24 ||
      // tvdb/tmdb-style compound keys, and the base64-ish hashes qBittorrent
      // and Dockge use for their own rows.
      segment.contains('-') && int.tryParse(segment.split('-').last) != null;

  /// Words the app uses as path segments, in the app's own vocabulary.
  ///
  /// Anything missing falls back to a title-cased segment, which is right often
  /// enough (`storage`, `shares`, `virt`) that enumerating every route would be
  /// upkeep with no payoff.
  static const Map<String, String> _known = {
    'requests': 'Requests',
    'wanted': 'Wanted',
    'history': 'History',
    'queue': 'Queue',
    'blocklist': 'Blocklist',
    'indexers': 'Indexers',
    'tags': 'Tags',
    'stacks': 'Stacks',
    'pools': 'Pools',
    'datasets': 'Datasets',
    'shares': 'Shares',
    'apps': 'Apps',
    'virt': 'Virtualisation',
    'reporting': 'Reporting',
    'system': 'System',
    'services': 'Services',
    'credentials': 'Credentials',
    'diagnostics': 'Diagnostics',
    'data-protection': 'Data protection',
    'connections': 'Connections',
    'appearance': 'Appearance',
    'region': 'Region',
    'hints': 'Hints',
    'certificates': 'Trusted certificates',
    'background-search': 'Background search',
    'all': 'All',
    'import': 'Manual import',
    'locate': 'Locate',
    'review': 'Review',
    'progress': 'Progress',
  };

  /// What a title's page under a tab is (`/discover/media/movie/603`): its
  /// kind, never a place it is not. It was `Library` once, under Discover,
  /// for a title the library does not hold.
  static const Map<String, String> _mediaKinds = {
    'movie': 'Movie',
    'tv': 'Series',
    'person': 'Person',
    'collection': 'Collection',
  };

  static final Map<String, ServiceKey> _servicesByRouteParam = {
    for (final service in ServiceKey.values) service.routeParam: service,
  };

  /// The trail for [location], outermost first. Never empty on a known route.
  static List<Crumb> of(String location) {
    final segments = Uri.parse(
      location,
    ).pathSegments.where((s) => s.isNotEmpty).toList(growable: false);
    if (segments.isEmpty) return const [];

    final tab = NavTab.values.firstWhere(
      (t) => t.routePath == '/${segments.first}',
      orElse: () => NavTab.dashboard,
    );
    final crumbs = <Crumb>[(label: tab.label, location: tab.routePath)];
    if (segments.length == 1) return crumbs;

    var consumed = 1;
    final service = _servicesByRouteParam[segments[1]];
    if (service != null) {
      crumbs.add((
        label: service.title,
        location: '${tab.routePath}/${service.routeParam}',
      ));
      consumed = 2;
    }

    // A title's page under a tab says what it is.
    if (service == null && segments.elementAtOrNull(consumed) == 'media') {
      final kind = _mediaKinds[segments.elementAtOrNull(consumed + 1)];
      if (kind != null) crumbs.add((label: kind, location: null));
      return crumbs;
    }

    // At most one more, and only if it is a place. The remaining segments are
    // an item's own identity, which the page owns.
    for (final segment in segments.skip(consumed)) {
      if (_isIdentifier(segment)) continue;
      crumbs.add((label: _label(segment, service: service), location: null));
      break;
    }
    return crumbs;
  }

  /// The word for one path segment.
  ///
  /// Inside a service the third crumb *is* a tab, so it takes the tab's own
  /// label rather than a title-cased guess at the segment. The guess was not
  /// merely lucky — it was already wrong twice: nothing knew `vms` or `rss`,
  /// so the crumb printed `Vms` and `Rss` beside bars that say VMs and RSS.
  static String _label(String segment, {ServiceKey? service}) {
    if (service != null) {
      final tab = ServiceTab.fromSegment(segment);
      // Only a tab this service actually has: a deep link naming someone
      // else's tab is not a place on this service, and printing its label
      // would claim it is.
      if (tab != null && (tabsFor(service)?.contains(tab) ?? false)) {
        return tab.label;
      }
    }

    final known = _known[segment];
    if (known != null) return known;
    final spaced = segment.replaceAll('-', ' ').replaceAll('_', ' ');
    if (spaced.isEmpty) return spaced;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}
