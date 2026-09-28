/// The Dashboard's third region: one list of everything waiting on a human.
///
/// ## Why one list and not six
///
/// The screen used to carry a Requests region — one kind, one service, its own
/// header, its own empty state — and nothing at all for the other five. So a
/// stalled torrent, a stopped stack and an expiring certificate had no place to
/// be *asked about*: each was a number on a card somewhere, and the user had to
/// know to go looking. A region per kind would have made six regions that are
/// empty most of the time, which is six headings to scroll past to learn that
/// nothing is wrong.
///
/// The question the region answers is "what needs me", and the answer does not
/// come sorted by which service happened to raise it. So it is one list, mixed
/// kinds, ranked by urgency:
///
///  * **faults before backlog.** A stalled download, a failing indexer, a
///    stopped stack, an expiring certificate and a failed import are things that
///    were meant to be working and are not. A pending request is somebody
///    politely waiting — it is *backlog*, the same category as 34 missing films,
///    and the tone rule files backlog under neutral. It still belongs in this
///    region (it needs a decision, which is the whole criterion) and it belongs
///    under the faults.
///  * **oldest first inside a kind.** Two stalled downloads are the same kind of
///    problem; the one that has been stuck since breakfast is the one to look at.
///    An undated item sorts last within its kind rather than to the top, for the
///    same reason `sortRecentlyAdded` does it: an item that cannot be placed
///    honestly loses to one that can.
///
/// Nothing in here fetches. The provider merges what the page has already
/// loaded — see `dashboardDecisionsProvider`.
library;

import 'package:cupola/features/settings/domain/service_key.dart';

/// What kind of thing is waiting.
///
/// Declaration order is the tiebreak between kinds of the same urgency, so it is
/// written worst-first: a transfer that stopped moving is more actionable than a
/// certificate with six days left on it.
enum DecisionKind {
  /// A download that has stopped moving. Action: open it in its client.
  stalledDownload,

  /// An \*arr history record whose import failed. Action: manual import.
  failedImport,

  /// An indexer Prowlarr has marked as failing. Action: test it.
  failingIndexer,

  /// A Dockge stack that is not running. Action: start it.
  stoppedStack,

  /// A certificate about to expire. Action: renew it.
  expiringCertificate,

  /// A Seerr request nobody has approved or declined. Action: both.
  ///
  /// Last, and deliberately: it is the only *backlog* kind in the region.
  pendingRequest,
}

extension DecisionKindRank on DecisionKind {
  /// Whether this kind is a fault — something that was working and stopped.
  ///
  /// The tone rule's first arm, stated once here rather than re-derived at every
  /// row: faults are amber, backlog is neutral, and red is left to a connection
  /// that did not answer.
  bool get isFault => this != DecisionKind.pendingRequest;
}

/// One thing waiting on a decision, already reduced to what the row paints.
///
/// Flat and service-agnostic on purpose. A union of six models would make the
/// row switch on a type to find a title; this way the merge happens once, in the
/// provider, and the row is one widget.
class DashboardDecision {
  const DashboardDecision({
    required this.kind,
    required this.id,
    required this.service,
    required this.title,
    required this.detail,
    required this.occurredAt,
    this.route,
    this.requiresService,
    this.posterUrl = '',
    this.actionId,
  });

  final DecisionKind kind;

  /// Unique within its kind — used for the row's key and for nothing else.
  final String id;

  /// Which service raised it. Owns the row's glyph and its accent.
  final ServiceKey service;

  /// The item, in the user's words: a film, a stack, an indexer, a hostname.
  final String title;

  /// The line under the title. Already `·`-joined for the eye; the row
  /// re-separates it for the ear.
  final String detail;

  /// When it started being a problem. Null when the source has no timestamp —
  /// Dockge does not date a stopped stack — which sorts it last inside its kind
  /// rather than pretending it just happened.
  final DateTime? occurredAt;

  /// Where the row body leads. The row body links to the item; the trailing
  /// control is the decision, and the two are never the same destination.
  final String? route;

  /// The service the *decision* acts on, when it is not [service].
  ///
  /// A stalled qBittorrent transfer surfaced by Radarr is the specimen: the row
  /// belongs to Radarr and the control opens qBittorrent. When this service is
  /// not configured the control is drawn dimmed but stays tappable, keeps its
  /// target and gains a hint — never `Semantics(enabled: false)`, which would
  /// take the fact off the screen reader's path along with the control.
  final ServiceKey? requiresService;

  /// The id the *action* needs, where the action is a call rather than a jump:
  /// the Seerr request to approve, the Prowlarr indexer to test, the library
  /// item a manual import is for. Null when the kind's control only navigates.
  ///
  /// Separate from [id], which is a string scoped by kind and exists to key a
  /// widget. Folding the two would mean parsing an integer back out of
  /// `seerr-1423` at the one call site that must not get it wrong.
  final int? actionId;

  /// Artwork, when the source has some. Empty is normal: a stack and an indexer
  /// have no poster, and the row draws its service glyph instead.
  final String posterUrl;

  bool get isFault => kind.isFault;
}

/// Faults before backlog, oldest first inside a kind.
///
/// Stable by construction: the sort is decorated with the source index, because
/// `List.sort` is not stable and several undated stopped stacks would otherwise
/// come back in a different order on each build — which reads on screen as rows
/// shuffling for no reason.
List<DashboardDecision> rankDecisions(
  List<DashboardDecision> decisions, {
  int? cap,
}) {
  final decorated =
      List.generate(
        decisions.length,
        (index) => (index: index, decision: decisions[index]),
        growable: false,
      )..sort((a, b) {
        final byKind = a.decision.kind.index.compareTo(b.decision.kind.index);
        if (byKind != 0) return byKind;

        final atA = a.decision.occurredAt;
        final atB = b.decision.occurredAt;
        if (atA != null && atB != null) {
          final byAge = atA.compareTo(atB);
          if (byAge != 0) return byAge;
        } else if (atA == null && atB != null) {
          return 1;
        } else if (atA != null && atB == null) {
          return -1;
        }

        return a.index.compareTo(b.index);
      });

  final ranked = decorated
      .map((entry) => entry.decision)
      .toList(growable: false);
  if (cap == null || cap >= ranked.length) return ranked;
  return ranked.take(cap < 0 ? 0 : cap).toList(growable: false);
}

/// How many rows the region shows, by size class.
///
/// Three numbers rather than a formula: the cap is a judgment about how much
/// triage fits above the stack, not a function of pixels. Pure — it takes the
/// two facts a breakpoint would give it rather than a `BuildContext`, so the
/// rule is testable without pumping a widget.
int decisionCapFor({required bool desktopShell, required bool compact}) {
  if (!desktopShell) return 3;
  return compact ? 2 : 4;
}

/// The region's eyebrow: how many are waiting, and of what.
///
/// Names the kinds present rather than a fixed list, so a stack with nothing but
/// requests does not advertise stalls and certificates it does not have.
String decisionsEyebrow(List<DashboardDecision> decisions) {
  if (decisions.isEmpty) return '';
  final noun = decisions.length == 1 ? 'item' : 'items';
  final kinds = <String>[];
  for (final decision in decisions) {
    final word = _kindNoun(decision.kind);
    if (!kinds.contains(word)) kinds.add(word);
  }
  return '${decisions.length} $noun · ${kinds.join(', ')}';
}

String _kindNoun(DecisionKind kind) => switch (kind) {
  DecisionKind.stalledDownload => 'stalls',
  DecisionKind.failedImport => 'imports',
  DecisionKind.failingIndexer => 'faults',
  DecisionKind.stoppedStack => 'stacks',
  DecisionKind.expiringCertificate => 'certs',
  DecisionKind.pendingRequest => 'requests',
};

/// What the trailing control on a row is called.
///
/// One table rather than a string per call site: the verb is the decision, and a
/// row whose button says something different from what the screen reader
/// announces is the defect this file exists to make impossible.
String decisionActionLabel(DecisionKind kind, {ServiceKey? target}) =>
    switch (kind) {
      DecisionKind.stalledDownload => 'Open in ${target?.title ?? 'client'}',
      DecisionKind.failedImport => 'Fix',
      DecisionKind.failingIndexer => 'Test',
      DecisionKind.stoppedStack => 'Start',
      // NPM's client has no renew call — `Renew` opens the screen that owns
      // renewal rather than pretending to fire one. The row's own words say how
      // long there is left, so the control is a destination and reads as one.
      DecisionKind.expiringCertificate => 'Renew',
      // Two controls, not one — see the row.
      DecisionKind.pendingRequest => 'Approve',
    };

/// The toast a decision control opens when its target service is not set up.
///
/// The control stays in the tree, stays tappable and keeps its 44pt target
/// (`CrossServiceAction`, whose default hint is `requires <Service>`); this is
/// what it says instead of working.
String decisionUnavailableToast(DecisionKind kind, ServiceKey required) {
  final what = switch (kind) {
    DecisionKind.stalledDownload => 'open this transfer',
    DecisionKind.failedImport => 'fix this import',
    DecisionKind.failingIndexer => 'test this indexer',
    DecisionKind.stoppedStack => 'start this stack',
    DecisionKind.expiringCertificate => 'renew this certificate',
    DecisionKind.pendingRequest => 'answer this request',
  };
  return 'Connect ${required.title} to $what.';
}
