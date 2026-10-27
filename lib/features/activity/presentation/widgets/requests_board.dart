import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/data/household_requests.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_download_row.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/everyone_request_row.dart';
import 'package:cupola/features/activity/presentation/widgets/needs_you_cards.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/request_ordering.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// One of the household's requests that waits on nobody here, with the
/// Seerr it lives on: its id is per server, and so is its delete.
typedef HouseholdRequest = ({
  MyRequest mine,
  String instanceId,
  String? connection,

  /// Whether its row names who asked: where the connection sees everyone's
  /// requests, never to the requester.
  bool namesWho,
});

/// The household's requests as Activity draws them: those that wait for the
/// operator, as decisions, the longest waiting first, then every other in the order of the requester's
/// page; how many there are by Seerr's own count, and which Seerr did not
/// answer.
@immutable
class HouseholdRequests {
  const HouseholdRequests({
    required this.waiting,
    required this.waitingRequests,
    required this.rest,
    required this.total,
    required this.floor,
    required this.whole,
    required this.failed,
    required this.pending,
  });

  /// The requests waiting for the operator's answer, the longest waiting
  /// first, as Needs you ranks them.
  final List<DashboardDecision> waiting;

  /// The requests behind [waiting], by their decision's id.
  final Map<String, SeerrRequest> waitingRequests;

  /// Every other request.
  final List<HouseholdRequest> rest;

  /// Seerr's count of every request, over the Seerrs that answered.
  final int total;

  /// [total] is only what arrived: a Seerr that gave no count and whose
  /// rows may be short, or one that did not answer or is still read. Drawn
  /// `48+`. A page that did not arrive leaves Seerr's own count true.
  final bool floor;

  /// Every Seerr answered with every row: a figure tallied over the rows (`1
  /// processing`) is then true of the household.
  final bool whole;

  /// The Seerrs that did not answer, with why.
  final List<SeerrRequestsRead> failed;

  /// No Seerr has answered or failed yet.
  final bool pending;

  bool get isEmpty => waiting.isEmpty && rest.isEmpty;

  /// The figure of the section under the waiting ones: `47 total`, Seerr's
  /// count less the requests waiting above, which the section does not list.
  /// Never fewer than the rows it lists. `47+ total` where the count is a
  /// floor.
  String get totalLabel {
    final less = total - waiting.length;
    final listed = less < rest.length ? rest.length : less;
    return '$listed${floor ? '+' : ''} total';
  }
}

/// Folds [reads] at [now]. [gateOf] says, for a connection, whether its
/// waiting requests are the operator's to answer and whether its rows name
/// who asked; [named] names each row's Seerr, for a list that holds two.
HouseholdRequests householdRequestsOf(
  List<SeerrRequestsRead> reads, {
  required DateTime now,
  required RoleGate Function(String instanceId) gateOf,
  required bool named,
}) {
  final waiting = <DashboardDecision>[];
  final waitingRequests = <String, SeerrRequest>{};
  final rest = <SeerrRequest>[];
  final home = Map<SeerrRequest, SeerrRequestsRead>.identity();
  final namesWho = <String, bool>{};
  final failed = <SeerrRequestsRead>[];
  var total = 0;
  var floor = false;
  var short = false;
  var stale = false;
  var answered = 0;
  for (final source in reads) {
    final list = source.read.value;
    if (list == null) {
      floor = true;
      if (source.read.hasError) {
        failed.add(source);
        answered++;
      }
      continue;
    }
    answered++;
    stale = stale || source.read.hasError;
    final gate = gateOf(source.instanceId);
    namesWho[source.instanceId] = gate.showsRequesterNames;
    final decides = gate.operatorAction(SeerrAbility.approve).isDrawn;
    final server = list is SeerrRequestList ? list.total : null;
    total += server ?? list.length;
    if (!holdsEveryRequest(list)) {
      short = true;
      if (server == null) floor = true;
    }
    final name = named ? source.name : null;
    for (final request in list) {
      if (decides && isAwaitingApproval(request)) {
        final decision = pendingRequestDecision(
          request,
          instanceId: source.instanceId,
          name: name,
          isLens: source.isLens,
          namesWho: gate.showsRequesterNames,
        );
        waiting.add(decision);
        waitingRequests[decision.id] = request;
      } else {
        rest.add(request);
        home[request] = source;
      }
    }
  }
  final ordered = myRequestsOf(rest, now: now, stale: stale).all;
  return HouseholdRequests(
    // As Needs you ranks them: the longest waiting first.
    waiting: rankDecisions(waiting),
    waitingRequests: waitingRequests,
    rest: [
      for (final mine in ordered)
        (
          mine: mine,
          instanceId: home[mine.request]!.instanceId,
          connection: switch (named ? home[mine.request]!.name : null) {
            final name? => serviceWithConnection(
              ServiceKey.seerr,
              name,
              joiner: ' ',
            ),
            null => null,
          },
          namesWho: namesWho[home[mine.request]!.instanceId] ?? false,
        ),
    ],
    total: total,
    floor: floor,
    whole: !floor && !short,
    failed: failed,
    pending: answered == 0 && reads.isNotEmpty,
  );
}

/// How many of the other requests the list draws at a time.
const requestsBoardPage = 30;

/// The household's requests, whole: those that wait for you with Approve and
/// Decline, then everyone's, newest movement first, each opening its title,
/// with Delete request on a long press. Activity's Requests view and Seerr's
/// Requests tab both draw it; the host scrolls and refreshes.
///
/// [only] chooses whose: null every Seerr, `''` the lens's, an id that
/// connection's (`?i=`).
class RequestsBoard extends ConsumerStatefulWidget {
  const RequestsBoard({super.key, this.only});

  final String? only;

  @override
  ConsumerState<RequestsBoard> createState() => _RequestsBoardState();
}

class _RequestsBoardState extends ConsumerState<RequestsBoard> {
  int _shown = requestsBoardPage;

  @override
  Widget build(BuildContext context) {
    final reads = ref.watch(householdRequestsProvider(widget.only));
    if (reads.isEmpty) {
      return NotConfiguredPlaceholder.forService(ServiceKey.seerr);
    }
    final now = ref.watch(arrivalsClockProvider)();
    final answered = ref.watch(answeredRequestsProvider);
    final requests = householdRequestsOf(
      reads,
      now: now,
      gateOf: (id) => ref.watch(roleGateOfProvider(id)),
      named: reads.length > 1,
    );
    if (requests.pending) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: AppSkeleton.listRows(count: 5),
      );
    }

    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final blue = statusToneColor(scheme, StatusTone.info, surface: room.slab);
    final ids = {for (final source in reads) source.instanceId};
    final decisions = [
      for (final decision in requests.waiting)
        if (!answered.containsKey(decision.id)) decision,
      for (final answer in answered.values)
        if (ids.contains(answer.decision?.instanceId)) ?answer.decision,
    ];
    final rows = requests.rest.take(_shown).toList(growable: false);
    final more = requests.rest.length - rows.length;
    // The one Seerr the address named, of several: said once, with the way
    // back to all of them.
    final namedOnly = widget.only?.isNotEmpty == true && reads.length == 1
        ? reads.single.name
        : null;

    Widget gutter(Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        0,
      ),
      child: child,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (namedOnly != null) gutter(_OnlyLine(name: namedOnly)),
        for (final source in requests.failed)
          gutter(
            BriefFailureLine.line(
              error: source.read.error!,
              service: ServiceKey.seerr,
              instanceId: source.instanceId,
              // The lens's entry is a passthrough of the plain provider,
              // which holds the error: both are dropped, or Retry reads the
              // same failure again.
              onRetry: () => invalidateSeerrRequestsOf(
                ref.container,
                source.isLens ? '' : source.instanceId,
              ),
            ),
          ),
        if (decisions.isNotEmpty)
          gutter(
            ActivitySlab(
              children: requestRowsOf(
                decisions,
                answered,
                blue,
                requestOf: requests.waitingRequests,
              ),
            ),
          ),
        if (requests.rest.isNotEmpty)
          ActivitySection(
            title: "Everyone's requests",
            meta: requests.totalLabel,
            children: [
              for (final (index, entry) in rows.indexed)
                EveryoneRequestRow(
                  key: ValueKey('${entry.instanceId}-${entry.mine.request.id}'),
                  mine: entry.mine,
                  now: now,
                  divided: index > 0,
                  connection: entry.connection,
                  namesWho: entry.namesWho,
                  actions: _actionsOf(entry),
                ),
              if (more > 0)
                ActivitySlabLink(
                  label:
                      'Show ${more < requestsBoardPage ? more : requestsBoardPage} more',
                  onTap: () => setState(() => _shown += requestsBoardPage),
                ),
            ],
          ),
        if (requests.isEmpty && requests.failed.isEmpty)
          const AppEmptyState(
            icon: Icons.person_add_alt_1_rounded,
            title: 'No requests yet',
            message:
                'Requests made in Seerr, by you or anyone you share it with, '
                'will appear here.',
          ),
      ],
    );
  }

  /// Delete request for the key and an account that manages requests;
  /// dimmed with the server's reason for an account of the operator's that
  /// may not; nothing where it is not part of the app.
  List<RowAction> _actionsOf(HouseholdRequest entry) {
    final request = entry.mine.request;
    final gate = ref.watch(roleGateProvider(entry.instanceId));
    final own =
        request.requestedBy?.id != null &&
        request.requestedBy?.id ==
            ref.watch(seerrAccountUserIdProvider(entry.instanceId));
    final verdict = gate.cancelAction(
      own: own,
      waitingForApproval: request.status == RequestStatus.pendingApproval,
    );
    if (!verdict.isDrawn) return const [];
    // A key, or an account that manages requests, deletes any request; any
    // other account only takes back its own, which it calls cancelling.
    final cancels =
        !(gate.grant?.mayCancelRequest(own: false, waitingForApproval: false) ??
            true);
    return [
      (
        label: cancels ? Lexicon.cancelRequest : 'Delete request',
        icon: cancels ? Icons.undo_rounded : Icons.delete_outline_rounded,
        onSelected: verdict.acts
            ? () => _delete(entry, cancels: cancels)
            : () => SnackBarHelper.info(context, verdict.reason!),
      ),
    ];
  }

  /// Deletes the request after a neutral confirmation, or cancels it for an
  /// account that only takes back its own: the same call, which Seerr
  /// refuses once the request no longer waits.
  Future<void> _delete(HouseholdRequest entry, {required bool cancels}) async {
    final title = entry.mine.title;
    final result = await showAppConfirmDialog(
      context: context,
      title: cancels ? '${Lexicon.cancelRequest}?' : 'Delete request?',
      message: cancels
          ? title
          : 'This removes the request for $title from Seerr.',
      icon: cancels ? Icons.undo_rounded : Icons.delete_outline_rounded,
      confirmLabel: cancels ? Lexicon.cancelRequest : 'Delete request',
      cancelLabel: cancels ? 'Keep it' : 'Cancel',
    );
    if (!result.confirmed || !mounted) return;
    try {
      await ref
          .read(seerrServiceForProvider(entry.instanceId))
          .deleteRequest(entry.mine.request.id);
      if (mounted) {
        SnackBarHelper.success(
          context,
          cancels
              ? 'Canceled the request for $title'
              : 'Deleted the request for $title',
        );
      }
    } on SeerrRequestConflict catch (conflict) {
      // Somebody got there first, from Seerr's own page: the list is stale.
      if (mounted) SnackBarHelper.error(context, '$conflict');
    } catch (error) {
      if (!mounted) return;
      if (seerrRefusalOf(error) == SeerrRefusal.noLongerCancellable) {
        SnackBarHelper.info(context, Lexicon.noLongerCancellable);
      } else {
        SnackBarHelper.error(
          context,
          '${cancels ? 'Could not cancel the request' : 'Could not delete the request'}. '
          '${writeFailureReason(ServiceKey.seerr, error)}',
          cause: error,
        );
        return;
      }
    }
    // The whole family: the lens's own id collapses onto the plain provider,
    // and dropping one and not the other leaves a stale copy behind.
    invalidateSeerrRequests(ref.container);
  }
}

/// `Seerr Friends only`, and the way back to every Seerr's requests.
class _OnlyLine extends StatelessWidget {
  const _OnlyLine({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            '${serviceWithConnection(ServiceKey.seerr, name, joiner: ' ')} only',
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
        ),
        TextButton(
          onPressed: () => context.go(ActivityTab.requests.location),
          child: const Text('Show every Seerr'),
        ),
      ],
    );
  }
}
