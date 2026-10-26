/// Everything the dashboard folds from every connection, in six libraries:
///
/// - `services_probe.dart`: health and version of each connection;
/// - `services_queue_snapshots.dart`: each \*arr's queue by title;
/// - `services_history.dart`: what arrived and what failed;
/// - `services_queue.dart`: the download queue, joined across the \*arr and
///   their clients;
/// - `services_decisions.dart`: what needs the person;
/// - `services_signals.dart`: the signal pair per service.
///
/// A barrel of `export`s, not `part`s: `part` keeps the privates but does not
/// modularise the imports, and what the libraries share (`MergeConnection`,
/// `watchMergeConnections`) is public in its own file and left out here with
/// `hide`, so the 79 importers see the same API as before.
library;

import 'package:cupola/features/discover/presentation/discover_provider.dart';

export 'services_decisions.dart';
export 'services_history.dart';
export 'services_probe.dart' hide MergeConnection, watchMergeConnections;
export 'services_queue.dart';
export 'services_queue_snapshots.dart';
export 'services_signals.dart';

final servicesRequestsProvider = requestsProvider;
