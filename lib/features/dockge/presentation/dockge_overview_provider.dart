/// What the Dockge Overview reads, and the pure functions that fold it.
///
/// Everything on this page comes from **one** push the service home is already
/// paying for: Dockge's `stackList` through [dockgeStackListProvider], plus
/// the `agentList` the app-bar lens already watches through
/// [dockgeAgentsProvider]. Nothing here fetches on its own, so opening Overview
/// costs no round trip the Stacks tab was not already making.
///
/// Every folding rule lives in a top-level pure function, so each boundary is
/// unit-testable without a container and without a socket.
///
/// ## There is no window rule on this page, and that is a finding
///
/// Every other Overview in the app has one: "next 7 days", "today", "idle 42
/// min", and each takes an explicit `now` so its boundary can be tested
/// without a clock. Dockge's has none to take: `stackList` carries a name, an
/// integer status, tags, a compose filename and an endpoint, and **not one
/// timestamp**. The board's `bazarr · 3 h ago` and `exit code 137 · out of
/// memory` have no source in this protocol; per-container evidence would need
/// `serviceStatusList`, one socket round trip *per stack*, and even that
/// answers a docker status string, not a structured exit code.
///
/// So the rows say what happened and stop. A window the server cannot
/// sustain is a window that lies, and an invented "3 h ago" beside a stack that
/// went down yesterday is worse than no clause at all.
///
/// ## Every figure here is per **agent**, never per deployment
///
/// Dockge's multi-agent model is a hub, and [DockgeClient.selectAgent] clears
/// the cached stacks whenever the lens moves: the client holds the stack list
/// of exactly one instance at a time. So a census folded here counts the stacks
/// on the *selected* agent, and a header printing it as a bare `12 stacks` on a
/// two-agent install would state a subset as a total: the same defect as
/// counting inside a paged response. [dockgeStackCensus] is honest because the
/// section that draws it names the agent whenever there is more than one; see
/// `dockge_overview_screen.dart`.
///
/// Within that agent the figure **is** a total: `stackList` is a full push of
/// every stack Dockge knows, not a page, so counting it is legitimate.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/features/dockge/domain/models/dockge_agent.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// Rows in the Stacks preview.
const int dockgeStackPreviewLimit = 5;

// There is no cap on the Agents section, and that is deliberate. See
// [dockgeAgentRows]. It is the only region on this page with no "see the rest"
// link, so anything a cap hid would be reported nowhere at all.

/// How many stack names an aggregate row spells out before it counts the rest.
///
/// Three, because the row is one line of evidence and not a list. The Stacks
/// tab is the list.
const int dockgeAggregateNamesLimit = 3;

// ─── The census ─────────────────────────────────────────────────────────────

/// How the selected agent's stacks are distributed across Dockge's states.
///
/// Folded once, for the Stacks header and its empty state.
@immutable
class DockgeStackCensus {
  const DockgeStackCensus({
    required this.total,
    required this.running,
    required this.stopped,
    required this.inactive,
    required this.unknown,
  });

  /// Every stack on the selected agent. A total within that agent, never
  /// across the deployment. See the library doc.
  final int total;

  final int running;

  /// Dockge's `EXITED`, read as **stopped**. Dockge does not say whether the
  /// stack was brought down on purpose or crashed, so it is a plain count of
  /// backlog and never a fault.
  final int stopped;

  /// `CREATED_FILE` and `CREATED_STACK` folded together, because Dockge itself
  /// prints one word for the pair ([DockgeStackStatus.label] is `Inactive` for
  /// both) and the difference, a compose file on disk versus a project
  /// directory, is not a difference the user acts on.
  final int inactive;

  /// `UNKNOWN`: Dockge answered and declined to say. Kept apart from
  /// [inactive] on purpose: "not started" is a fact and "we do not know" is
  /// not, and folding the second into the first would print the fact.
  final int unknown;

  // There is deliberately no `notRunning` roll-up here, and no fault count.
  //
  // A roll-up of `stopped + inactive + unknown` would fold the backlog into one
  // figure: a tidy server with one stopped stack and eight never-started
  // templates printed "9" over rows that are eight-ninths neutral, the
  // five-arm rule broken in the figure after the rows had got it right. Every
  // state here is backlog, so no header states a figure for it: each group
  // states its own size inside its own neutral row.
}

/// Counts the states. Total-safe: `stackList` is a full push, not a page.
DockgeStackCensus dockgeStackCensus(List<DockgeStack> stacks) {
  var running = 0;
  var stopped = 0;
  var inactive = 0;
  var unknown = 0;
  for (final stack in stacks) {
    switch (stack.status) {
      case DockgeStackStatus.running:
        running++;
      case DockgeStackStatus.exited:
        stopped++;
      case DockgeStackStatus.createdFile || DockgeStackStatus.createdStack:
        inactive++;
      case DockgeStackStatus.unknown:
        unknown++;
    }
  }
  return DockgeStackCensus(
    total: stacks.length,
    running: running,
    stopped: stopped,
    inactive: inactive,
    unknown: unknown,
  );
}

// ─── Not running ────────────────────────────────────────────────────────────

/// One row under the running stacks: a state the others are in, how many,
/// and the evidence.
///
/// The tone is carried rather than derived from a kind enum, because the one
/// authority on what a Dockge state *means* is already written:
/// [DockgeStackStatus.tone], whose own doc explains why a stopped stack is
/// neutral. A second table here would be a second place to get it wrong.
@immutable
class DockgeIdleGroup {
  const DockgeIdleGroup({
    required this.tone,
    required this.icon,
    required this.headline,
    required this.detail,
  });

  final StatusTone tone;
  final IconData icon;

  /// The state and how many stacks it covers: `3 stacks are stopped`. Every
  /// row here is an aggregate, so the headline is the whole claim.
  final String headline;

  /// Whatever the push carried about it: tags, or the names behind an
  /// aggregate. Often empty, and that emptiness is the truth: see the library
  /// doc on why there is no timestamp and no exit code to print here.
  final String detail;

  /// The row as one sentence, with the layout's `·` turned back into commas:
  /// `·` is decoration, and a screen reader either names it or drops it
  /// depending on the user's punctuation setting.
  String get spoken =>
      joinSpokenParts([spokenFromDotted(headline), spokenFromDotted(detail)]);
}

/// Everything on the selected agent that is not running, one row per state,
/// drawn under the running stacks.
///
/// Every state here is **backlog**, and none is a fault, which is why the page
/// has no Needs attention section: Dockge reports nothing that could fill it.
///
///  * a stopped stack (Dockge's `EXITED`) is a stack somebody brought down, or
///    one that crashed, and Dockge cannot tell which. Its stack list carries no
///    exit code and no date, so the row says what Dockge says and no more;
///  * an inactive stack was never started, or was brought down. Nothing failed;
///  * an unknown stack is aggregated rather than flagged, because Dockge did
///    not say what it is.
///
/// Each state is one aggregate row that states its own count and spells out up
/// to [dockgeAggregateNamesLimit] names. An aggregate already *is* its count, so
/// nothing is capped and nothing is left for a header to report. Painting
/// stopped amber was the defect this replaces: it promised a fault Dockge does
/// not know about, and it put a deliberate `compose down` in the same colour as
/// a crash.
List<DockgeIdleGroup> dockgeIdleGroups(List<DockgeStack> stacks) {
  final stopped = <String>[];
  final inactive = <String>[];
  final unknown = <String>[];

  for (final stack in stacks) {
    switch (stack.status) {
      case DockgeStackStatus.exited:
        stopped.add(stack.name);
      case DockgeStackStatus.createdFile || DockgeStackStatus.createdStack:
        inactive.add(stack.name);
      case DockgeStackStatus.unknown:
        unknown.add(stack.name);
      case DockgeStackStatus.running:
        break;
    }
  }

  stopped.sort(_caseInsensitive);
  inactive.sort(_caseInsensitive);
  unknown.sort(_caseInsensitive);

  return List.unmodifiable([
    if (stopped.isNotEmpty)
      DockgeIdleGroup(
        tone: StatusTone.neutral,
        icon: Icons.stop_circle_outlined,
        headline: stopped.length == 1
            ? '1 stack is stopped'
            : '${stopped.length} stacks are stopped',
        // Dockge's own reading of the state, and the honest limit of it: it
        // does not say whether the stop was intended.
        detail: joinDisplayParts([
          _namesLabel(stopped),
          'Dockge does not say why',
        ]),
      ),
    if (inactive.isNotEmpty)
      DockgeIdleGroup(
        tone: StatusTone.neutral,
        icon: Icons.pause_circle_outline_rounded,
        headline: inactive.length == 1
            ? '1 stack is inactive'
            : '${inactive.length} stacks are inactive',
        // Names the mechanism rather than an instruction: both readings are
        // deliberate acts, which is precisely why this row is not a fault.
        detail: joinDisplayParts([
          _namesLabel(inactive),
          'brought down, or never started',
        ]),
      ),
    if (unknown.isNotEmpty)
      DockgeIdleGroup(
        tone: StatusTone.neutral,
        icon: Icons.help_outline_rounded,
        headline: unknown.length == 1
            ? '1 stack reports no state'
            : '${unknown.length} stacks report no state',
        detail: joinDisplayParts([_namesLabel(unknown), 'Dockge did not say']),
      ),
  ]);
}

// ─── Stacks ─────────────────────────────────────────────────────────────────

/// One row of the Stacks preview.
@immutable
class DockgeStackRow {
  const DockgeStackRow({
    required this.name,
    required this.tone,
    required this.detail,
  });

  final String name;
  final StatusTone tone;

  /// The state word and whatever tags the stack carries. The state is spelled
  /// out rather than left to the dot beside it: colour is not information, and
  /// a screen reader hears nothing at all from a coloured circle.
  final String detail;

  String get spoken => joinSpokenParts([name, spokenFromDotted(detail)]);
}

/// What is up right now, by name.
///
/// **Only the running stacks**: the others are summed by state in
/// [dockgeIdleGroups], under them. A preview draws five rows out of a list
/// that can hold fifty, so a stopped stack listed by name among the running
/// could be pushed off the bottom; its group row cannot, and it names the
/// stacks it counts.
List<DockgeStackRow> dockgeRunningRows(
  List<DockgeStack> stacks, {
  int limit = dockgeStackPreviewLimit,
}) {
  final running =
      stacks.where((stack) => stack.status.isActive).toList(growable: false)
        ..sort(_byName);

  return List.unmodifiable(
    running
        .take(limit)
        .map(
          (stack) => DockgeStackRow(
            name: stack.name,
            tone: stack.status.tone,
            detail: joinDisplayParts([
              stack.status.label.toLowerCase(),
              _stackQualifiers(stack),
            ]),
          ),
        ),
  );
}

// ─── Agents ─────────────────────────────────────────────────────────────────

/// One instance reachable through this login.
@immutable
class DockgeAgentRow {
  const DockgeAgentRow({
    required this.name,
    required this.detail,
    required this.tone,
    required this.isSelected,
  });

  final String name;

  /// Where it is, what Dockge calls its connection, and whether the figures
  /// above came off it.
  final String detail;

  final StatusTone tone;

  /// The agent the lens is on: the one every other figure on this page was
  /// folded from.
  ///
  /// Read by the row, which rings its dot. The `showing its stacks` clause in
  /// [detail] is the same fact for a screen reader; the ring is what makes the
  /// list scannable as a list of instances rather than a readout of them.
  final bool isSelected;

  String get spoken => joinSpokenParts([name, spokenFromDotted(detail)]);
}

/// The instances, hub first, the order [DockgeClient.latestAgents] already
/// guarantees, and **every one of them**.
///
/// Uncapped, unlike the two stack regions, because the Agents section has no
/// tab to send the remainder to: the picker is the app-bar lens, so a capped
/// list would drop agents six and up off the page entirely while its header
/// stated the sample's own length as the deployment's total. A login's agent
/// list is a handful of registered instances, not a feed, so drawing all of it
/// costs nothing, and the header can then count what is in front of the user.
///
/// The selected one says so, and that clause is load-bearing rather than
/// decorative: it is the sentence that explains why the census above counts
/// what it counts on an install with more than one agent.
///
/// An offline agent is the **one red** in this feature, and the model's own doc
/// says why: red means a connection that did not answer, and that is exactly
/// what an offline agent is. `connecting` is informational: it has not failed
/// yet, which is [StatusTone.info]; neither reading is invented here, both
/// come from [DockgeAgent.tone].
List<DockgeAgentRow> dockgeAgentRows(
  List<DockgeAgent> agents, {
  required String selectedEndpoint,
}) {
  return List.unmodifiable(
    agents.map((agent) {
      final selected = agent.endpoint == selectedEndpoint;
      return DockgeAgentRow(
        name: agent.name,
        tone: agent.tone,
        detail: joinDisplayParts([
          // The hub has no `host:port` of its own: it is the address the user
          // typed into Settings, so it names itself by what it is.
          agent.isLocal ? 'this connection' : agent.endpoint,
          agent.status.toLowerCase(),
          if (selected) 'showing its stacks',
        ]),
        isSelected: selected,
      );
    }),
  );
}

// ─── Providers ──────────────────────────────────────────────────────────────

/// All three carry `retry: noProviderRetry`, and the reasoning is the framework's
/// default, not the sources'.
///
/// Omitting `retry:` is not "no retry": `ProviderContainer.defaultRetry` re-runs
/// a build that throws ten times, 200ms to a 6.4s ceiling, some forty seconds in
/// all. See `lib/core/providers/provider_retry.dart`. Each of these folds is a
/// `FutureProvider` whose whole body is `await ref.watch(<stream>.future)`, so a
/// stream sitting on an `AsyncError` makes the fold *throw*, and the default
/// policy then re-reads that same held error ten times, synchronously, with no
/// round trip in between that could change the answer. Two providers deep,
/// that is twenty pointless rebuilds and a pending timer any widget test
/// reaching this page inherits.
///
/// The sources do carry the recovery, and it is not a backoff: a live socket
/// reconnects on its own, and the section's Retry invalidates
/// [dockgeStackListProvider] itself rather than the fold: invalidating a fold
/// only re-reads the error the stream is still holding, and the stream, being
/// watched by the other fold, is never disposed and so never re-subscribes
/// on its own. See `dockge_overview_screen.dart`.
///
/// The screen still checks `isServiceConfigured` before any of this is watched,
/// because *that* condition no waiting changes.

/// The census, folded once for the Stacks header.
final dockgeOverviewCensusProvider =
    FutureProvider.autoDispose<DockgeStackCensus>((ref) async {
      return dockgeStackCensus(await ref.watch(dockgeStackListProvider.future));
    }, retry: noProviderRetry);

/// What the Stacks section draws: the running stacks by name, then the rest
/// summed by state.
typedef DockgeStacksPreview = ({
  List<DockgeStackRow> running,
  List<DockgeIdleGroup> idle,
});

/// The running stacks, then the others by state.
final dockgeOverviewStacksProvider =
    FutureProvider.autoDispose<DockgeStacksPreview>((ref) async {
      final stacks = await ref.watch(dockgeStackListProvider.future);
      return (
        running: dockgeRunningRows(stacks),
        idle: dockgeIdleGroups(stacks),
      );
    }, retry: noProviderRetry);

/// The instances, with the selected one marked.
final dockgeOverviewAgentsProvider =
    FutureProvider.autoDispose<List<DockgeAgentRow>>((ref) async {
      final agents = await ref.watch(dockgeAgentsProvider.future);
      return dockgeAgentRows(
        agents,
        selectedEndpoint: ref.watch(dockgeSelectedAgentProvider),
      );
    }, retry: noProviderRetry);

// ─── Shared folding ─────────────────────────────────────────────────────────

int _byName(DockgeStack a, DockgeStack b) => _caseInsensitive(a.name, b.name);

int _caseInsensitive(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());

/// What the push carries *about* a stack beyond its state.
///
/// Tags only. `isManagedByDockge` is deliberately not printed: the model parses
/// it as `json['isManagedByDockge'] == true`, so a push that simply omits the
/// key yields `false` for every row, and a clause reading "not managed by
/// Dockge" under all twelve stacks would be a fabrication on an install where
/// the field is absent. A claim that defaults to the accusing side is a claim
/// this page will not make.
String _stackQualifiers(DockgeStack stack) =>
    stack.tags.where((tag) => tag.trim().isNotEmpty).join(', ');

/// `media, immich, npm`, and `media, immich, npm and 2 more` past the limit.
///
/// "and", not another `·`: a dotted list that simply stops reads as truncated,
/// and the count is the half that cannot be dropped.
String _namesLabel(
  List<String> names, {
  int limit = dockgeAggregateNamesLimit,
}) {
  if (names.length <= limit) return names.join(', ');
  final hidden = names.length - limit;
  return '${names.take(limit).join(', ')} and $hidden more';
}
