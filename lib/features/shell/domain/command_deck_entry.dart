import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/shell_breadcrumb.dart';

/// What kind of thing an entry is, which decides how it is grouped and drawn.
enum CommandDeckKind {
  /// One *connection* — not one service. Radarr 4K and Radarr HD are two
  /// entries, for the same reason the phone's Portal gives each its own cell: a
  /// folded entry would reach the service while hiding every connection but the
  /// one the lens happens to point at.
  connection,

  /// A named screen: a section, a settings page, an area of a console.
  screen,

  /// Somewhere this window has actually been, this session.
  recent,
}

/// One row in the deck.
@immutable
class CommandDeckEntry {
  const CommandDeckEntry({
    required this.kind,
    required this.label,
    required this.location,
    this.service,
    this.instanceId,
    this.detail,
    this.icon,
  });

  final CommandDeckKind kind;

  /// What the row says. Already includes the connection label where there is
  /// one, because two rows reading `Radarr` would be a bug the user has to
  /// resolve by guessing.
  final String label;

  final String location;
  final ServiceKey? service;

  /// Set for a connection entry: opening it moves the lens as well as the route.
  final String? instanceId;

  /// The muted half of the row — a host, a breadcrumb, a hint.
  final String? detail;

  final IconData? icon;

  /// Everything this row can be matched against, lower-cased once.
  String get haystack =>
      '$label ${detail ?? ''} ${service?.title ?? ''}'.toLowerCase();
}

/// Where this window has been, most recent first, this session only.
///
/// Not persisted. A recent list that survives a restart is a history, and a
/// history is a thing you curate and delete — a promise the app is not making
/// here. Within a session it is simply the back of your own hand.
final recentLocationsProvider = StateProvider<List<String>>((ref) => const []);

/// Records a visit, keeping the list short and free of consecutive repeats.
void noteVisit(WidgetRef ref, String location) {
  final current = ref.read(recentLocationsProvider);
  if (current.isNotEmpty && current.first == location) return;
  ref.read(recentLocationsProvider.notifier).state = [
    location,
    ...current.where((l) => l != location),
  ].take(6).toList(growable: false);
}

/// Named screens the deck can reach by name, beyond the services themselves.
///
/// A hand-written list on purpose. Generating it from the router would offer
/// every route including the ones that need an id, and a command palette that
/// offers `/services/radarr/movie/:id` is offering a crash.
const List<({String label, String location, String detail})> _namedScreens = [
  (
    label: 'Connections',
    location: '/settings/services',
    detail: 'Settings · every service and its state',
  ),
  (
    label: 'Trusted certificates',
    location: '/settings/certificates',
    detail: 'Settings · pinned per host',
  ),
  (label: 'Appearance', location: '/settings/appearance', detail: 'Settings'),
  (label: 'Region', location: '/settings/region', detail: 'Settings'),
  (label: 'Hints', location: '/settings/hints', detail: 'Settings'),
  (
    label: 'Background search',
    location: '/settings/background-search',
    detail: 'Settings · release search',
  ),
];

/// Everything the deck can offer, in the order it offers it.
///
/// Built from the registry and the settings rather than from a search index:
/// the set is small enough that filtering it in one pass on every keystroke is
/// cheaper than maintaining an index, and it can never be stale.
final commandDeckEntriesProvider = Provider<List<CommandDeckEntry>>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  // Skipping the first: it is where the window is standing right now, and a
  // switcher that offers you the room you are in has spent a row saying nothing.
  final recents = ref.watch(recentLocationsProvider).skip(1);

  return [
    for (final tab in NavTab.values)
      CommandDeckEntry(
        kind: CommandDeckKind.screen,
        label: tab.label,
        location: tab.routePath,
        detail: 'Section',
        icon: tab.icon,
      ),
    for (final service in ServiceKey.values)
      ...settings.configuredInstancesOf(service).map((instance) {
        final label = instance.label.trim();
        return CommandDeckEntry(
          kind: CommandDeckKind.connection,
          label: label.isEmpty ? service.title : '${service.title} · $label',
          location: '${NavTab.services.routePath}/${service.routeParam}',
          service: service,
          instanceId: instance.id,
          detail: Uri.tryParse(instance.url)?.host,
          icon: service.icon,
        );
      }),
    for (final screen in _namedScreens)
      CommandDeckEntry(
        kind: CommandDeckKind.screen,
        label: screen.label,
        location: screen.location,
        detail: screen.detail,
      ),
    for (final location in recents)
      CommandDeckEntry(
        kind: CommandDeckKind.recent,
        // The trail, not the path: `/services/truenas/pools/tank` is a route,
        // and `TrueNAS › Pools` is a place somebody remembers being.
        label: ShellBreadcrumb.of(location).map((c) => c.label).join(' › '),
        location: location,
      ),
  ];
});
