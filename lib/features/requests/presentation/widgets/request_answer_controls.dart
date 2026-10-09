/// The control for a Seerr request's answer: Approve in ink and Decline
/// outlined, wherever a request that waits is listed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';

/// What a declined request's row says.
const String declinedLine = 'Declined';

enum _Look { row, card, compact }

/// Approve and Decline for one request that waits, the same wherever it is
/// listed: the Home's Requests module, the Activity feed, a requests list,
/// the Seerr overview and Requests tab, and a title's page.
///
/// Both answers go through [ActivityActions], the app's one Seerr write
/// path, so every place asks the same question (the approval says where the
/// request goes), tells a request somebody answered meanwhile from a fault,
/// and reads the lists again. What the control adds is how it looks while
/// that happens:
///
/// - **busy**: while one answer is in flight the tapped button shows a ring
///   in its own place and the other waits, dimmed; a second tap does nothing
///   ([requestAnswersInFlightProvider]). The ring says the phase to a screen
///   reader, `Checking where it goes`, `Approving`, `Declining`.
/// - **answered**: once an answer went through, the pair gives way to what
///   happened, `Approved · sent to Radarr` or `Declined`, through
///   [answeredRequestsProvider]. A refused or cancelled answer leaves the
///   pair as it was.
/// - **gated**: by the gate of the Seerr the request lives on
///   ([instanceId]): absent from the requester's app, and dimmed, saying
///   why when pressed, on an account that may not approve there. Never
///   `Semantics(enabled: false)`.
///
/// Each button says its verb and is named by its title (`Approve Charge`),
/// as a tooltip and to a screen reader, because a page of them is a page of
/// identical words otherwise. Neither takes a tone: a request is somebody
/// waiting politely, and declining one is not a fault.
///
/// The caller draws the control only for a request that waits, judged by
/// the request's **own** status (`isAwaitingApproval`), never by
/// `displayStatus`: that one reads Available as soon as the media exists
/// anywhere.
class RequestAnswerControls extends ConsumerWidget {
  /// The pair side by side, one width each, under the words of a row: the
  /// Home's, and the one of every list.
  const RequestAnswerControls.row({
    super.key,
    required this.instanceId,
    required this.requestId,
    required this.title,
    this.request,
    this.decision,
  }) : _look = _Look.row,
       approveStyle = null,
       onDone = null;

  /// The pair one under the other, the width of the card they close: a
  /// title's page. Approve takes a glyph, and [approveStyle] when the page
  /// lets it lead; [onDone] reads the page again once the answer is over.
  const RequestAnswerControls.card({
    super.key,
    required this.instanceId,
    required this.requestId,
    required this.title,
    this.request,
    this.approveStyle,
    this.onDone,
  }) : _look = _Look.card,
       decision = null;

  /// The pair as two small plates in a dense row, a 28pt plate in a 44pt
  /// target: the desktop's Activity table.
  const RequestAnswerControls.compact({
    super.key,
    required this.instanceId,
    required this.requestId,
    required this.title,
    this.request,
  }) : _look = _Look.compact,
       decision = null,
       approveStyle = null,
       onDone = null;

  /// The Seerr the request lives on, empty for the lens's own. A request id
  /// is per server: the answer goes to this connection and no other.
  final String instanceId;

  /// The request's id on that Seerr.
  final int requestId;

  /// What the buttons' names and the questions call the request.
  final String title;

  /// The record, when the caller holds it: the approval reads where the
  /// request goes from it instead of asking Seerr for it first.
  final SeerrRequest? request;

  /// The Home's row for the request, which its module keeps drawing as the
  /// answered row once Seerr's list no longer holds the request.
  final DashboardDecision? decision;

  /// How Approve is filled, when it is not the ink: a page where something
  /// else leads.
  final ButtonStyle? approveStyle;

  /// Called once an answer is over, however it ended: sent, refused or
  /// cancelled.
  final VoidCallback? onDone;

  final _Look _look;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decide = ref
        .watch(roleGateProvider(instanceId))
        .operatorAction(SeerrAbility.approve);
    if (!decide.isDrawn) return const SizedBox.shrink();

    final outcome = ref.watch(
      answeredRequestsProvider.select(
        (answered) => answered[seerrRequestKey(instanceId, requestId)]?.outcome,
      ),
    );
    if (outcome != null) return _Outcome(text: outcome, look: _look);

    final phase = ref.watch(
      requestAnswersInFlightProvider.select(
        (inFlight) => inFlight[(instanceId: instanceId, requestId: requestId)],
      ),
    );
    final approve = _button(
      context,
      ref,
      approve: true,
      decide: decide,
      phase: phase,
    );
    final decline = _button(
      context,
      ref,
      approve: false,
      decide: decide,
      phase: phase,
    );

    return switch (_look) {
      _Look.row => Row(
        children: [
          Expanded(child: approve),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: decline),
        ],
      ),
      _Look.card => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          approve,
          const SizedBox(height: AppSpacing.sm),
          decline,
        ],
      ),
      _Look.compact => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          approve,
          const SizedBox(width: AppSpacing.sm),
          decline,
        ],
      ),
    };
  }

  Widget _button(
    BuildContext context,
    WidgetRef ref, {
    required bool approve,
    required GateVerdict decide,
    required RequestAnswerPhase? phase,
  }) {
    final verb = approve ? 'Approve' : 'Decline';
    // The button says its verb; a screen reader and a long press hear the
    // title with it.
    final named = '$verb $title';
    final busy = phase != null && phase.isApproval == approve ? phase : null;
    final waits = phase != null && busy == null;
    final ringSize = switch (_look) {
      _Look.row => 18.0,
      _Look.card => 20.0,
      _Look.compact => 14.0,
    };
    // The glyph a button wears at rest, if any: only a title's page has one.
    final Widget? glyph = _look == _Look.card && approve
        ? Icon(Icons.check_rounded, size: ringSize)
        : null;
    final Widget? lead = busy != null
        ? _AnswerRing(phase: busy, size: ringSize)
        : glyph;

    return RoleGatedAction.builder(
      verdict: decide,
      onTap: () => approve ? _approve(context, ref) : _decline(context, ref),
      builder: (context, onPressed, annotate) {
        final label = Text(
          verb,
          semanticsLabel: named,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        final content = lead == null
            ? label
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  lead,
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(child: label),
                ],
              );
        final annotated = annotate(content);
        // The other of the pair while an answer is on its way: quiet, and a
        // tap on it starts nothing (`ActivityActions` holds that).
        final child = waits
            ? Opacity(opacity: GatedAffordance.dimmedOpacity, child: annotated)
            : annotated;
        final style = _look == _Look.compact
            ? _compactStyle(context)
            : (approve ? approveStyle : null);
        return Tooltip(
          message: named,
          excludeFromSemantics: true,
          child: approve
              ? FilledButton(onPressed: onPressed, style: style, child: child)
              : OutlinedButton(
                  onPressed: onPressed,
                  style: style,
                  child: child,
                ),
        );
      },
    );
  }

  /// A 28pt plate: [MaterialTapTargetSize.padded] keeps the 44pt target
  /// round it, and the density is pinned because the desktop's compact one
  /// would take 8pt off the minimum.
  static ButtonStyle _compactStyle(BuildContext context) => ButtonStyle(
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
    minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    ),
    textStyle: WidgetStatePropertyAll(
      AppTheme.chrome(context, size: 11, weight: FontWeight.w600),
    ),
  );

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    // Held before the wait: the control goes once Seerr's list is read
    // again, and its answer stays in its place.
    final answered = ref.read(answeredRequestsProvider.notifier);
    final outcome = await ActivityActions.approveRequest(
      context,
      ref,
      instanceId: instanceId,
      requestId: requestId,
      title: title,
      request: request,
    );
    if (outcome != null) {
      answered.answer(
        instanceId: instanceId,
        requestId: requestId,
        outcome: outcome,
        decision: decision,
      );
    }
    onDone?.call();
  }

  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    final answered = ref.read(answeredRequestsProvider.notifier);
    final declined = await ActivityActions.declineRequest(
      context,
      ref,
      instanceId: instanceId,
      requestId: requestId,
      title: title,
    );
    if (declined) {
      answered.answer(
        instanceId: instanceId,
        requestId: requestId,
        outcome: declinedLine,
        decision: decision,
      );
    }
    onDone?.call();
  }
}

/// A button's glyph while its answer is in flight: a ring in the same ink
/// and at the glyph's size, so the control keeps its target and its place.
///
/// The phase is the button's value, annotated here, inside the button,
/// because a `Semantics` wrapped around a button lands on a node the screen
/// reader never focuses.
class _AnswerRing extends StatelessWidget {
  const _AnswerRing({required this.phase, required this.size});

  final RequestAnswerPhase phase;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    value: phase.spoken,
    child: SizedBox.square(
      dimension: size,
      child: Padding(
        padding: EdgeInsets.all(size / 8),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: IconTheme.of(context).color,
        ),
      ),
    ),
  );
}

/// What an answered request says in place of its pair.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.text, required this.look});

  final String text;
  final _Look look;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final style = look == _Look.compact
        ? AppTheme.chrome(
            context,
            size: 11,
            color: CupolaThemeColors.of(context).dimText,
          )
        : AppType.meta.copyWith(color: room.inkSecondary);
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
