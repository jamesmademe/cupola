/// Activity's four views, each at its own address.
library;

import 'package:cupola/core/utils/service_routes.dart';

/// What Activity shows: one choice, never a filter over another.
///
/// The address says the view, as the bar's tabs do, so a link, a
/// notification and the back gesture land on the same one, and returning
/// to the tab finds it where it was left.
enum ActivityTab {
  /// Needs you, the requests, who is watching, the downloads, what waits and
  /// what finished today.
  all('All', ServiceRoutes.activity),

  /// What is downloading, the searches still running, and what waits its
  /// turn.
  downloads('Downloads', ServiceRoutes.activityDownloads),

  /// The household's requests: the ones waiting for an answer, then all.
  requests('Requests', ServiceRoutes.activityRequests),

  /// The last seven days, by day: what was imported and what failed.
  history('History', ServiceRoutes.activityHistory);

  const ActivityTab(this.label, this.location);

  /// The word on the tab.
  final String label;

  /// Where the view lives.
  final String location;
}
