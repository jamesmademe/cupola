/// The modules the Home is made of, declared once.
///
/// One registry, like `serviceTabs`: every module says whose Home it is on,
/// where it stands by default, whether it starts on, whether the person may
/// hide it, and which services feed it. The Home draws from it, Edit Home lists
/// it, and the saved layout (`HomeLayout`) is read against it, so a module
/// added here reaches a Home that was arranged before it existed at its own
/// default place.
///
/// The enum's names are what a saved layout stores: renaming one drops it from
/// every layout written before, and it comes back at its default place.
library;

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Where a module stands on its Home.
enum HomePlacement {
  /// Before every other module, whatever the layout says: Needs you.
  first,

  /// In the person's order.
  ordered,

  /// After every other module: Set up next, which speaks of the Home itself.
  last,
}

/// One module of a Home, in its default order.
///
/// The declaration order is the default order of each person's Home: the
/// operator's modules first, then the requester's. A person reorders and hides
/// their own; nothing else is added.
enum HomeModule {
  /// The fault in the lead, how many more, the way in.
  needsYou(
    audience: Audience.operator,
    label: 'Needs you',
    line: 'Always first, and only there when something is wrong',
    placement: HomePlacement.first,
  ),

  /// What the libraries imported, newest first.
  arrived(
    audience: Audience.operator,
    label: 'Arrived',
    line: 'What your libraries imported, newest first',
    services: [ServiceKey.radarr, ServiceKey.sonarr, ServiceKey.lidarr],
  ),

  /// What is moving now.
  downloads(
    audience: Audience.operator,
    label: 'Downloads',
    line: 'What is moving now, from every queue',
    services: [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
      ServiceKey.readarr,
      ServiceKey.qbittorrent,
      ServiceKey.transmission,
      ServiceKey.sabnzbd,
      ServiceKey.nzbget,
    ],
  ),

  /// The requests that wait for an answer.
  requests(
    audience: Audience.operator,
    label: 'Requests',
    line: 'Requests waiting for your approval',
    services: [ServiceKey.seerr],
  ),

  /// Who is watching what, and on which screen.
  nowPlaying(
    audience: Audience.operator,
    label: 'Now playing',
    line: 'Who is watching, and on which screen',
    services: [ServiceKey.jellyfin, ServiceKey.plex],
  ),

  /// The services that would add to this Home.
  setUpNext(
    audience: Audience.operator,
    label: 'Set up next',
    line: 'The services that would add to this page',
    placement: HomePlacement.last,
  ),

  /// Seerr's shelf of the week, with her state on every poster.
  trending(
    audience: Audience.requester,
    label: 'Trending this week',
    line: 'What people are watching this week',
    services: [ServiceKey.seerr],
  ),

  /// What comes out soon.
  comingSoon(
    audience: Audience.requester,
    label: 'Coming soon',
    line: 'Movies and series on their way',
    services: [ServiceKey.seerr],
  );

  const HomeModule({
    required this.audience,
    required this.label,
    required this.line,
    this.placement = HomePlacement.ordered,
    this.services = const [],
  });

  /// Whose Home it is on.
  final Audience audience;

  /// Its name: the module's heading, and its row in Edit Home.
  final String label;

  /// What it shows, in one line under its name in Edit Home.
  final String line;

  /// Where it stands.
  final HomePlacement placement;

  /// Whether a Home starts with it on. Every module does today; the ones a
  /// person adds by choice (the lights of the stack, the storage) will not.
  bool get defaultOn => true;

  /// The services that feed it. Empty when it reads the whole stack.
  final List<ServiceKey> services;

  /// Whether Edit Home may switch it off. Needs you may not: it is there only
  /// when something is wrong, and then it is the point of the page.
  bool get hideable => placement != HomePlacement.first;

  /// Whether Edit Home may move it. The two that stand at an end stay there.
  bool get movable => placement == HomePlacement.ordered;

  /// Every module of [audience]'s Home, in its default order.
  static List<HomeModule> of(Audience audience) => [
    for (final module in values)
      if (module.audience == audience) module,
  ];

  /// The modules [audience] orders, in their default order.
  static List<HomeModule> orderedOf(Audience audience) => [
    for (final module in of(audience))
      if (module.movable) module,
  ];

  /// The module this [name] stored, or null for a name no module has.
  static HomeModule? byName(String name) {
    for (final module in values) {
      if (module.name == name) return module;
    }
    return null;
  }
}
