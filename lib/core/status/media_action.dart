import 'package:flutter/material.dart';

import 'package:cupola/core/status/media_status.dart';

/// What a promoted primary action *does*.
///
/// Deliberately a small closed set rather than a callback with a label: the
/// promotion below has to be a pure, testable function of a resolved status, and
/// a `kind` is what a test can assert on.
enum MediaActionKind {
  openQueue,
  search,
  interactiveSearch,
  manualImport,
  monitor,
  request,
  add,
  refresh,

  /// Nothing follows from this status. The band renders no button at all.
  none,
}

/// Which writes the host screen actually supplied a path for.
///
/// Built from the callbacks, never asserted: a library detail screen has no add
/// path, so it passes `canAdd: false` and an untracked title yields a *sentence*
/// instead of a full-width accent CTA whose only behaviour is an info snackbar
/// reading "Add Movie is not available yet from this view." An action is
/// withheld, never disabled — a disabled full-width control teaches nothing.
@immutable
class MediaActionCapabilities {
  final bool canSearch;
  final bool canInteractiveSearch;
  final bool canImport;
  final bool canMonitor;
  final bool canRequest;
  final bool canAdd;
  final bool canOpenQueue;

  const MediaActionCapabilities({
    this.canSearch = false,
    this.canInteractiveSearch = false,
    this.canImport = false,
    this.canMonitor = false,
    this.canRequest = false,
    this.canAdd = false,
    this.canOpenQueue = false,
  });
}

/// The one action a resolved status promotes, and why.
///
/// For [MediaActionKind.none] the [label] is empty and [icon] is not rendered;
/// only [consequence] is. The consequence lives here — beside the decision that
/// produced it — rather than being composed at the call site, so a state can
/// never ship a button without an explanation or an explanation that contradicts
/// its button.
@immutable
class MediaPrimaryAction {
  final MediaActionKind kind;
  final String label;
  final IconData icon;

  /// The sentence under the action: what is true right now, in the user's
  /// words. Never a raw exception, never a service enum name.
  final String consequence;

  const MediaPrimaryAction({
    required this.kind,
    required this.label,
    required this.icon,
    required this.consequence,
  });
}

/// Promotes exactly one action from an already-resolved [MediaStatusInfo].
///
/// Pure, and never called from anything but a `build` that already holds a
/// resolved status: this derives an *action*, not a status. Statuses arrive
/// fully resolved from the feature's `domain/` layer.
///
/// First match wins, and the order mirrors [MediaStatusInfo.label]'s own
/// precedence — pipeline beats unmonitored beats availability — so the promoted
/// verb and the status headline can never describe different situations.
///
/// Three of the outcomes are the point of the whole exercise:
///
/// * **`available` promotes nothing.** The loudest element on an available
///   monitored series used to read "Unmonitor", which is not what anyone opened
///   the page for. It is replaced with *nothing* rather than with another search
///   that can churn a library; "find a better release" stays reachable as
///   Interactive search beside it.
/// * **An action is withheld, never disabled.** [MediaActionKind.none] renders
///   no button, and the consequence carries the page instead.
/// * **Monitoring is not an action.** It is a persistent binary of the user's
///   copy, so it lives in the overflow — except at the one rung where *not*
///   monitoring is the reason nothing is happening.
///
/// **A button names its MECHANISM; the consequence sentence names the SITUATION.**
/// There are exactly two search mechanisms and therefore exactly two labels:
/// `Automatic search` for [MediaActionKind.search], which hands the decision to the
/// service, and `Interactive search` for [MediaActionKind.interactiveSearch],
/// which hands it to the user. Nothing else may name a search.
///
/// This replaced four names for the automatic search (`Find releases`,
/// `Find missing`, `Automatic search`) and three for the interactive one
/// (`Find an upgrade`, `Find another release`, `Interactive search`) — seven
/// labels for two behaviours. Worse, the state-shaped names pointed the wrong
/// way: `Find releases` reads as *show me the releases*, which is the
/// interactive behaviour, while the button it sat on performed the automatic
/// grab. On a rung where both mechanisms are on screen at once — a missing title
/// promotes the automatic one and shows the interactive one beside it — the user
/// could not tell which was which, and the label was the reason.
///
/// The per-state nuance those names carried is not lost, it moved to where state
/// belongs: `partial` says "Part of this is on disk; Radarr is hunting the rest.",
/// `upgradable` says "The file is below your quality cutoff, so Radarr keeps
/// looking." The button says how, the sentence says why.
MediaPrimaryAction resolveMediaAction(
  MediaStatusInfo status,
  MediaActionCapabilities caps, {
  required String serviceName,

  /// A whole clause for the `partial` rung, count first: `41 of 48 episodes are
  /// on disk.` A host supplies it because only the host knows the child noun.
  String? partialSummary,

  /// A **tail** for the `unavailable` rung, not a whole sentence: it completes
  /// `There's nothing to search for until …`, so pass `Jul 17, 2026` and never
  /// `Out on Jul 17, 2026.`. A tail keeps the stem inside the ladder's voice and
  /// puts the date last, where changing it cannot reflow the prose before it.
  String? consequenceOverride,
}) {
  final pipeline = status.pipeline;

  if (pipeline != null) {
    switch (pipeline) {
      case MediaPipeline.clientUnavailable:
        // Names the component that is down and the consequence the badge
        // withholds: the whole queue is frozen, not just this title. "The
        // download client" and never a brand name — the app does not know which
        // client is configured.
        return _queueOrNothing(
          caps,
          'Nothing moves until the download client answers.',
        );
      case MediaPipeline.failed:
        // The attributed frame REPLACES the fallback clause; it is never
        // appended after it, or the sentence claims two different things.
        final reported = _reports(serviceName, status.detail);
        return _findAnotherRelease(
          caps,
          "This release won't finish. ${reported ?? 'Another one might.'}",
        );
      case MediaPipeline.importBlocked:
        // The fact the badge withholds leads: the bytes arrived safely and the
        // blockage is at the import step. Deliberately no detail frame here —
        // on this rung the service's message is usually a path-length wall of
        // text, and the promoted verb has already done the sentence's job.
        final consequence =
            'The download is done; $serviceName needs a hand importing it.';
        if (caps.canImport) {
          return MediaPrimaryAction(
            kind: MediaActionKind.manualImport,
            label: 'Finish import',
            icon: Icons.download_for_offline_outlined,
            consequence: consequence,
          );
        }
        return _queueOrNothing(caps, consequence);
      case MediaPipeline.stalled:
        final percent = status.progressPercent;
        return _findAnotherRelease(
          caps,
          percent == null
              ? 'No bytes are moving on this transfer right now.'
              // The figure is the last thing in the sentence, so 5% -> 43% ->
              // 100% never reflows a word beside it.
              : 'No bytes are moving right now; it sits at $percent%.',
        );
      // These five shared one branch that printed `detail ?? pipeline.label`
      // plus an appended percentage — the badge's own word with a diagnostic
      // stapled to it, which is the worst restatement on the ladder. Each rung
      // now says what follows from itself instead.
      case MediaPipeline.queued:
        return _queueOrNothing(
          caps,
          _withWarning(
            status,
            serviceName,
            // Deliberately silent about *whose* turn: true of both a client
            // queue and a service-side release delay.
            "This title is waiting its turn; no bytes have moved yet.",
          ),
        );
      case MediaPipeline.downloading:
        final downloadedPercent = status.progressPercent;
        return _queueOrNothing(
          caps,
          _withWarning(
            status,
            serviceName,
            downloadedPercent == null
                ? 'The download client has it.'
                : 'The download client has it, $downloadedPercent% through.',
          ),
        );
      case MediaPipeline.importPending:
        return _queueOrNothing(
          caps,
          _withWarning(
            status,
            serviceName,
            'The download is done; $serviceName imports it on its next pass.',
          ),
        );
      case MediaPipeline.importing:
        return _queueOrNothing(
          caps,
          _withWarning(
            status,
            serviceName,
            '$serviceName is moving the files into your library.',
          ),
        );
      case MediaPipeline.paused:
        return _queueOrNothing(
          caps,
          _withWarning(
            status,
            serviceName,
            'Nothing moves until the download client resumes it.',
          ),
        );
    }
  }

  if (status.unmonitored && !status.isAvailable) {
    // The badge already says Unmonitored, so it carries the reason and the
    // sentence carries the consequence. The promoted Monitor verb carries the
    // fix; the sentence must not restate it.
    final consequence = "$serviceName isn't searching for this title.";
    if (caps.canMonitor) {
      return MediaPrimaryAction(
        kind: MediaActionKind.monitor,
        label: 'Monitor',
        icon: Icons.bookmark_add_outlined,
        consequence: consequence,
      );
    }
    return _nothing(consequence);
  }

  switch (status.availability) {
    case MediaAvailability.notTracked:
      // True of both the Seerr Request path and the *arr Add path, because
      // "tracking" is what both of them start.
      final consequence =
          'Nothing happens until $serviceName is tracking this title.';
      if (caps.canRequest) {
        return MediaPrimaryAction(
          kind: MediaActionKind.request,
          label: 'Request',
          icon: Icons.add_circle_outline_rounded,
          consequence: consequence,
        );
      }
      if (caps.canAdd) {
        return MediaPrimaryAction(
          kind: MediaActionKind.add,
          label: 'Add to $serviceName',
          icon: Icons.add_circle_outline_rounded,
          consequence: consequence,
        );
      }
      return _nothing(consequence);

    case MediaAvailability.missing:
      // Provable rather than hopeful: the unmonitored rung above is checked
      // first, so anything reaching here IS monitored, and therefore genuinely
      // in Wanted and in RSS. Naming the ongoing process instead of the absence
      // is the whole mechanism — it is what replaced "Expected on disk, nothing
      // there.", which had no actor and so read as a monitoring alert.
      final consequence = '$serviceName is hunting a release for this title.';
      if (caps.canSearch) {
        return MediaPrimaryAction(
          kind: MediaActionKind.search,
          label: 'Automatic search',
          icon: Icons.saved_search_rounded,
          consequence: consequence,
        );
      }
      return _nothing(consequence);

    case MediaAvailability.partial:
      final consequence =
          partialSummary ??
          'Part of this is on disk; $serviceName is hunting the rest.';
      if (caps.canSearch) {
        return MediaPrimaryAction(
          kind: MediaActionKind.search,
          label: 'Automatic search',
          icon: Icons.saved_search_rounded,
          consequence: consequence,
        );
      }
      return _nothing(consequence);

    case MediaAvailability.upgradable:
      // Names the reason the badge omits — the cutoff, which is the real
      // Radarr/Sonarr noun — and the consequence: the search is still live.
      final consequence =
          'The file is below your quality cutoff, so $serviceName keeps '
          'looking.';
      if (caps.canInteractiveSearch) {
        return MediaPrimaryAction(
          kind: MediaActionKind.interactiveSearch,
          label: 'Interactive search',
          icon: Icons.search_rounded,
          consequence: consequence,
        );
      }
      return _nothing(consequence);

    case MediaAvailability.available:
      // This sentence pays for the withheld primary: it tells the operator the
      // absence of a button is a *result*, not a gap. It is half the answer to
      // "the action row feels too empty" — the visible secondaries beside the
      // overflow are the other half.
      //
      // "everything it expects" and not "nothing is outstanding": the first
      // draft used the latter, which is bookish and ambiguous enough to be read
      // as "nothing is excellent". What this rung is actually about is the count
      // the page already shows — 89 of 89, 1 file — which is what the service
      // expected and got.
      return _nothing(
        "$serviceName has everything it expects, so it isn't searching.",
      );

    case MediaAvailability.unavailable:
      // The override is a tail substitution, so the stem stays inside the
      // ladder's voice and a date change never reflows the prose before it.
      return _nothing(
        "There's nothing to search for until ${consequenceOverride ?? "it's released"}.",
      );

    case MediaAvailability.deleted:
      return _nothing(
        'Nothing changes here until this title is back in $serviceName.',
      );

    case MediaAvailability.unknown:
      // On this rung the service's words ARE the only fact available, so the
      // frame stands alone. The bare label "Unknown" is never a sentence again.
      return _nothing(
        _reports(serviceName, status.detail) ??
            "$serviceName didn't report a state for this title.",
      );
  }
}

/// Normalises a service-supplied `detail` into an attributed sentence.
///
/// The service's words arrive after a colon, never inside our own grammar, so a
/// screen reader is handed a whole clause instead of the bare fragment the old
/// ladder passed through — `status.detail` *was* the entire sentence on two
/// rungs. Returns null when nothing legible survives, which is what lets a
/// caller fall back to its own clause instead of rendering a colon and nothing.
String? _reports(String serviceName, String? detail) {
  var text = detail?.trim() ?? '';
  const exceptionPrefix = 'Exception: ';
  if (text.startsWith(exceptionPrefix)) {
    text = text.substring(exceptionPrefix.length).trim();
  }
  if (text.isEmpty) return null;
  if (!text.endsWith('.') && !text.endsWith('!') && !text.endsWith('?')) {
    text = '$text.';
  }

  return '$serviceName reports: $text';
}

/// Appends the attributed detail as a second sentence on a warning-toned queue
/// rung.
///
/// Without it the badge turns warning-toned with nothing on the page saying why:
/// that reason rode in `detail`, which the five-way split of the queue branch
/// would otherwise drop on the floor.
String _withWarning(MediaStatusInfo status, String serviceName, String base) {
  if (!status.hasWarning) return base;
  final reported = _reports(serviceName, status.detail);

  return reported == null ? base : '$base $reported';
}

/// Every queue state routes to the queue — or, where the host gave no route
/// there, to a sentence.
///
/// The spec's ladder promotes `openQueue` unconditionally on these rungs; it is
/// guarded here for the same reason every other rung is. A full-width button
/// that cannot go anywhere is the dead end this whole ladder replaces.
MediaPrimaryAction _queueOrNothing(
  MediaActionCapabilities caps,
  String consequence,
) {
  if (!caps.canOpenQueue) return _nothing(consequence);
  return MediaPrimaryAction(
    kind: MediaActionKind.openQueue,
    label: 'Open queue',
    icon: Icons.monitor_heart_outlined,
    consequence: consequence,
  );
}

MediaPrimaryAction _findAnotherRelease(
  MediaActionCapabilities caps,
  String consequence,
) {
  if (!caps.canInteractiveSearch) return _nothing(consequence);
  return MediaPrimaryAction(
    kind: MediaActionKind.interactiveSearch,
    label: 'Interactive search',
    icon: Icons.search_rounded,
    consequence: consequence,
  );
}

MediaPrimaryAction _nothing(String consequence) => MediaPrimaryAction(
  kind: MediaActionKind.none,
  label: '',
  icon: Icons.check_circle_outline_rounded,
  consequence: consequence,
);
