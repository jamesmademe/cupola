/// What an \*arr history record means to the Dashboard.
///
/// Two regions read the same page of history and ask it different questions:
/// *Recently added* asks what landed, and *Needs a decision* asks what did not.
/// Classifying the `eventType` once, here, is what keeps those two from
/// disagreeing about the same record, and keeps the vocabulary out of a widget,
/// where the answer would be a switch nobody can test without pumping a frame.
///
/// ## The fetch, and where it deviates from the brief
///
/// The settled policy is **one history read per arr**: the same read the old
/// "Finished today" band already owed, with the poster URL arriving inside the
/// records, so nothing extra is fetched when the page opens. That part stands.
///
/// The `eventType=downloadFolderImported` filter in the brief does **not**, and
/// this is the deviation to know about: \*arr's `/history` takes `eventType` as
/// an integer event code, the codes differ between Radarr and Sonarr (`2` is
/// `downloadFolderImported` on Radarr and `seriesFolderImported` on Sonarr), and
/// a string value is rejected outright by the controller's model binder. Sending
/// it would empty the region on every real server. Worse, the filter cannot
/// coexist with the other half of the brief: a *failed* import is a decision,
/// and a query that returns only successful imports can never produce one.
///
/// So the read is unfiltered, one page, and the classification happens here.
/// Same request count, same payload shape, both questions answered.
library;

/// What one history record did.
enum ArrImportOutcome {
  /// A file was imported into the library. This is the region's subject.
  imported,

  /// A grab or an import failed. A **fault**, which is amber, and a decision.
  failed,

  /// Everything else (grabbed, renamed, deleted, ignored). Not this region's
  /// business, and deliberately not counted in its eyebrow either.
  other,
}

/// The import events across the four arrs.
///
/// Each arr names the same act after its own unit, which is why this is a set
/// and not a string comparison: Radarr imports a download folder, Sonarr imports
/// a download folder *or* a series folder, Lidarr imports a track file, Readarr
/// a book file.
const Set<String> arrImportedEvents = {
  'downloadFolderImported',
  'seriesFolderImported',
  'trackFileImported',
  'bookFileImported',
};

/// The failure events.
///
/// `downloadIgnored` is deliberately absent: ignoring a download is a decision
/// the user already made, and the tone rule files a thing stopped on purpose
/// under neutral rather than under faults.
const Set<String> arrFailedEvents = {
  'downloadFailed',
  'importFailed',
  'downloadFolderImportFailed',
  'trackFileImportFailed',
};

ArrImportOutcome classifyHistoryEvent(String? eventType) {
  final event = eventType?.trim() ?? '';
  if (event.isEmpty) return ArrImportOutcome.other;
  if (arrImportedEvents.contains(event)) return ArrImportOutcome.imported;
  if (arrFailedEvents.contains(event)) return ArrImportOutcome.failed;
  // Anything unrecognised is other, never guessed at: a new event type invented
  // by a future \*arr must not silently become an import in a region whose whole
  // claim is "this is what landed".
  return ArrImportOutcome.other;
}

/// Parses an arr `added` or `date` field, which is an ISO 8601 string or
/// absent.
///
/// Returns null rather than throwing or defaulting to the epoch: a bad
/// timestamp must not sort an item to the top of a "newest first" list, and it
/// must not take the list down either.
DateTime? parseAddedTimestamp(String? added) {
  final raw = added?.trim();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
