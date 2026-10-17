import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/capability_copy.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A control the user can see, reach and press, that is not going to act.
///
/// Three states get drawn this way and they are the same cell:
///
///  * a jump into another service that is not configured: Radarr's *Open in
///    qBittorrent* with no qBittorrent saved;
///  * a write blocked by a credential that may only read;
///  * anything else where the affordance is real and the precondition is not.
///
/// ## Why it is not disabled, and not hidden
///
/// Both of the obvious answers were in the tree and both are wrong in the same
/// direction; they remove the control from the one user who most needs it
/// explained.
///
/// `onPressed: null` makes Material publish `Semantics(enabled: false)`, and a
/// disabled node is **skipped** by VoiceOver and TalkBack: a screen-reader user
/// swipes straight past a feature that a sighted user can see greyed out and
/// reason about. Hiding it is worse still. `SizedBox.shrink()` teaches that the
/// feature does not exist, so the user never goes looking for the setting that
/// would turn it on, and the app's own capability becomes a secret.
///
/// So the cell keeps everything except the action: the full 44pt target, the
/// button role, the name, and a hint that says what it wants: *requires
/// qBittorrent*. Only the foreground drains to 38%, which is the one signal a
/// sighted user reads for free and a screen-reader user was previously charged
/// for. Pressing it is not a dead end either: it raises a toast whose single
/// action is the fix.
///
/// **Dimmed means not configured, never unreachable.** A service that is down
/// keeps full ink and gets a `FaultBand` instead; the two states need opposite
/// answers ("go set this up" against "this is what it said last") and one
/// visual language cannot carry both.
///
/// ## The two shapes
///
/// The default constructor draws the whole cell itself, around a
/// **non-interactive** child (a glyph, a caption) through [PressableScale].
/// [GatedAffordance.builder] is for a control that is already a button (a
/// `TextButton`, a FAB, an `OutlinedButton`): it hands the builder the
/// gated `onPressed` and an `annotate` function, and the builder's own button
/// keeps its role, name and target. Wrapping a Material button in the default
/// shape would nest a button inside a button, which a screen reader reads as
/// two stops for one control.
class GatedAffordance extends StatelessWidget {
  const GatedAffordance({
    super.key,
    required this.enabled,
    required String this.label,
    required this.hint,
    required this.onTap,
    required this.onBlocked,
    required Widget this.child,
  }) : builder = null;

  /// For a control that is already a button.
  ///
  /// [builder] receives the gated `onPressed`, never null, so the button is
  /// never `Semantics(enabled: false)`, and `annotate`, which wraps the
  /// button's **own content** in the dim and the hint. The annotation has to go
  /// inside: `ButtonStyleButton` publishes a `container: true` node, so a
  /// `Semantics(hint:)` wrapped around the button lands on a second,
  /// non-actionable node the screen reader never focuses.
  ///
  /// A caller keeps any *other* reason to pass `null` to its button: a save
  /// with nothing to save, but the precondition this widget gates is never
  /// expressed that way.
  const GatedAffordance.builder({
    super.key,
    required this.enabled,
    required this.hint,
    required this.onTap,
    required this.onBlocked,
    required GatedAffordanceBuilder this.builder,
  }) : label = null,
       child = null;

  /// Whether the precondition is met. When true this is an ordinary control.
  final bool enabled;

  /// The accessible name, for the default shape. Required there even when
  /// [child] renders its own text: that shape publishes one node for the whole
  /// cell, so the child's text is excluded and there would otherwise be nothing
  /// to announce. The builder shape's button names itself.
  final String? label;

  /// What the control wants, in the user's terms: `requires qBittorrent`,
  /// `requires an admin account`. Null publishes no hint.
  ///
  /// A cross-service jump publishes its hint in **both** states: *requires
  /// qBittorrent* is true of the jump whether or not qBittorrent is set up, and
  /// a hint that disappears when it becomes relevant is not a hint. A
  /// capability gate publishes one only while blocked, because on a credential
  /// that may write there is no requirement left to explain and every write on
  /// a page saying "requires write access" would be noise read on every stop.
  final String? hint;

  /// What the control does when it can act.
  final VoidCallback onTap;

  /// What it does when it cannot. Raises the toast; never navigates silently.
  final VoidCallback onBlocked;

  final Widget? child;

  /// The builder shape's content. See [GatedAffordance.builder].
  final GatedAffordanceBuilder? builder;

  /// The one dim in the app that means "precondition unmet".
  ///
  /// 38% is Material's own disabled opacity, kept on purpose: it is the level
  /// users already read as "not right now", and inventing a second one would
  /// only mean two things that look almost the same.
  static const double dimmedOpacity = 0.38;

  /// The dim and the hint, applied to a control's own foreground.
  static Widget annotateFor({
    required bool enabled,
    required String? hint,
    required Widget child,
  }) {
    final Widget body = enabled
        ? child
        : Opacity(opacity: dimmedOpacity, child: child);
    return hint == null ? body : Semantics(hint: hint, child: body);
  }

  @override
  Widget build(BuildContext context) {
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        enabled ? onTap : onBlocked,
        (content) => annotateFor(enabled: enabled, hint: hint, child: content),
      );
    }

    final Widget body = enabled
        ? child!
        : Opacity(
            opacity: dimmedOpacity,
            // The foreground only. The cell's own hit area, padding and any
            // surrounding plate stay at full strength, because the target is
            // not what is unavailable: the action is.
            child: child,
          );

    return PressableScale(
      // Always a real callback, so `PressableScale` publishes `button: true`,
      // `enabled: true` and the hint. That is the whole mechanism: the node
      // stays on the screen reader's path in both states and the hint carries
      // the difference. Handing it `null` here is the bug this widget exists to
      // stop: Material would render the disabled look and the semantics tree
      // would lose the control entirely.
      onTap: enabled ? onTap : onBlocked,
      semanticLabel: label,
      semanticHint: hint,
      // One node for the cell, not three fragments: the child's own text would
      // otherwise compete with [label] and the row would read twice.
      excludeChildSemantics: true,
      // No haptic on the blocked arm: a tap that does not act should not feel
      // like one that did.
      haptic: enabled,
      child: ConstrainedBox(
        // The target never shrinks with the affordance. A dimmed control that
        // is also hard to hit is a control the user concludes is broken. The
        // box wraps the *dim*, so the padding around a drained glyph stays part
        // of the 44pt square.
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Center(widthFactor: 1, heightFactor: 1, child: body),
      ),
    );
  }
}

/// Builds a gated control from its gated `onPressed` and an `annotate`
/// function that dims and hints the control's own content.
typedef GatedAffordanceBuilder =
    Widget Function(
      BuildContext context,
      VoidCallback onPressed,
      Widget Function(Widget content) annotate,
    );

/// [GatedAffordance] wired to "is the other service configured?".
///
/// The specimen is Radarr's *Open in qBittorrent*: the control reads the saved
/// connections, and when the target is missing it dims, gains the hint
/// `requires qBittorrent`, and answers a tap with a toast whose one action
/// lands on that service's own settings page.
///
/// The toast sentence is the caller's because only the caller knows what the
/// jump was *for*: "Connect qBittorrent to open this transfer" and "Connect
/// Seerr to see cast" are the same mechanism and different promises.
class CrossServiceAction extends ConsumerWidget {
  const CrossServiceAction({
    super.key,
    required this.target,
    required String this.label,
    required this.blockedMessage,
    required this.onTap,
    required Widget this.child,
    this.hint,
  }) : builder = null;

  /// For a jump that is already a button; see [GatedAffordance.builder].
  const CrossServiceAction.builder({
    super.key,
    required this.target,
    required this.blockedMessage,
    required this.onTap,
    required GatedAffordanceBuilder this.builder,
    this.hint,
  }) : label = null,
       child = null;

  /// The service this control acts on. Not the service the page belongs to.
  final ServiceKey target;

  /// The accessible name, e.g. `Open in qBittorrent`. The builder shape's
  /// button names itself.
  final String? label;

  /// The toast, e.g. `Set up qBittorrent to open this transfer.`: a full
  /// sentence, so it ends with a full stop.
  final String blockedMessage;

  /// What the control does when [target] is configured.
  final VoidCallback onTap;

  /// Overrides the default `requires <Service>` hint, for the rare control
  /// whose precondition needs more than a name.
  final String? hint;

  final Widget? child;
  final GatedAffordanceBuilder? builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `isServiceConfigured`, not the health check. BONUS 3 is explicit that not
    // configured is not the same as not answering: a qBittorrent that is saved
    // and currently down keeps this control live, because the jump is still the
    // right thing to offer and the destination will say for itself that it did
    // not answer.
    final configured = ref.watch(
      currentSettingsProvider.select((s) => s.isServiceConfigured(target)),
    );
    final resolvedHint = hint ?? 'requires ${target.title}';
    void blocked() => SnackBarHelper.withAction(
      context,
      blockedMessage,
      // The action is the fix, named as every other way in names it, and it
      // is the *specific* fix: this service's own setup form, where its setup
      // note is printed: the one place every `Set up X` goes.
      actionLabel: Lexicon.setUp(target.title),
      onAction: () => context.push(ServiceRoutes.setUp(target)),
    );

    final builder = this.builder;
    if (builder != null) {
      return GatedAffordance.builder(
        enabled: configured,
        hint: resolvedHint,
        onTap: onTap,
        onBlocked: blocked,
        builder: builder,
      );
    }
    return GatedAffordance(
      enabled: configured,
      label: label!,
      hint: resolvedHint,
      onTap: onTap,
      onBlocked: blocked,
      child: child!,
    );
  }
}

/// What a capability gate resolved to for one control.
class _CapabilityGate {
  const _CapabilityGate({
    required this.enabled,
    required this.hint,
    required this.onBlocked,
  });

  final bool enabled;
  final String? hint;
  final VoidCallback onBlocked;
}

/// Resolves a control's gate from its connection's grant.
///
/// The hint and the toast follow *why* the control is blocked. When the
/// service answered (or refused a write), the caller's sentences name the
/// missing permission and the toast's one action is the fix: that
/// connection's settings form, labelled with the service's own verb. When
/// Cupola could not ask, the credential may well be fine: the hint and toast
/// say so, and the action re-asks instead of sending the user to replace a
/// key that may work.
_CapabilityGate _resolveCapabilityGate(
  BuildContext context,
  WidgetRef ref, {
  required ServiceKey service,
  required String connectionId,
  required String? resource,
  required String hint,
  required String blockedMessage,
}) {
  final grant = ref.watch(capabilityGrantForProvider(connectionId));
  final enabled = grant.scopeFor(resource).canWrite;
  final unanswered = grant.basis == CapabilityBasis.unanswered;
  return _CapabilityGate(
    enabled: enabled,
    hint: enabled
        ? null
        : unanswered
        ? CapabilityCopy.unansweredHint(service)
        : hint,
    onBlocked: () => _showCapabilityBlocked(
      context,
      ref,
      service: service,
      connectionId: connectionId,
      message: blockedMessage,
      unanswered: unanswered,
    ),
  );
}

void _showCapabilityBlocked(
  BuildContext context,
  WidgetRef ref, {
  required ServiceKey service,
  required String connectionId,
  required String message,
  required bool unanswered,
}) {
  if (unanswered) {
    SnackBarHelper.withAction(
      context,
      CapabilityCopy.unansweredToast(service),
      actionLabel: 'Check again',
      onAction: () => recheckCapability(ref, connectionId),
    );
    return;
  }
  SnackBarHelper.withAction(
    context,
    message,
    actionLabel: service.capabilityFixLabel,
    onAction: () => context.push(
      ServiceRoutes.settingsForConnection(service, connectionId),
    ),
  );
}

/// Whether a write on [resource] of [connectionId] may go ahead, and when it
/// may not, the answer the user gets instead of the action.
///
/// For the writes that cannot be wrapped in a gated widget: a `PopupMenuItem`
/// (whose label is a [CapabilityGatedMenuLabel]) and a save inside an editor.
/// Returns false **after** raising the same toast a dimmed control raises, so
/// the call site reads `if (!capabilityWriteAllowed(...)) return;`.
bool capabilityWriteAllowed(
  BuildContext context,
  WidgetRef ref, {
  required ServiceKey service,
  required String connectionId,
  String? resource,
  required String blockedMessage,
}) {
  final grant = ref.read(capabilityGrantForProvider(connectionId));
  if (grant.scopeFor(resource).canWrite) return true;
  _showCapabilityBlocked(
    context,
    ref,
    service: service,
    connectionId: connectionId,
    message: blockedMessage,
    unanswered: grant.basis == CapabilityBasis.unanswered,
  );
  return false;
}

enum _GateShape { cell, icon, builder, toggle }

/// [GatedAffordance] wired to a credential's scope.
///
/// The write half of cross-cutting C: the banner says what the credential
/// cannot do once, at the top of the page, and every write below it dims to
/// match rather than disappearing. The readouts keep refreshing: a read-only
/// key reads perfectly well, and the page is still worth looking at.
///
/// One constructor per shape of control, because each hosts its hint and its
/// dim differently and a flag could not say which:
///
///  * the default: a bare glyph or caption cell, drawn by [GatedAffordance];
///  * [CapabilityGatedAction.icon]: every `IconButton` write;
///  * [CapabilityGatedAction.builder]: a `TextButton`, `FilledButton`,
///    `OutlinedButton` or FAB the caller builds;
///  * [CapabilityGatedAction.toggle]: every `Switch` write.
///
/// A menu item is the fifth shape and is not a widget of this class: see
/// [CapabilityGatedMenuLabel] and [capabilityWriteAllowed].
///
/// A flow (a sheet that collects a form, a typed confirmation) is gated at the
/// tap that **opens** it, never after the form is filled.
class CapabilityGatedAction extends ConsumerWidget {
  const CapabilityGatedAction({
    super.key,
    required this.service,
    required this.connectionId,
    required String this.label,
    required this.blockedMessage,
    required this.onTap,
    required Widget this.child,
    this.hint = 'requires a read-write key',
    this.resource,
  }) : _shape = _GateShape.cell,
       icon = null,
       tooltip = null,
       color = null,
       builder = null,
       value = null,
       onChanged = null;

  /// An `IconButton` write. The button is built here so its `onPressed` is
  /// never null; [tooltip] stays its accessible name (and what
  /// `find.byTooltip` finds), the dim and the hint go on [icon] inside the
  /// button, and it keeps Material's 48pt target.
  const CapabilityGatedAction.icon({
    super.key,
    required this.service,
    required this.connectionId,
    required Widget this.icon,
    required String this.tooltip,
    required this.blockedMessage,
    required this.onTap,
    this.hint = 'requires a read-write key',
    this.resource,
    this.color,
  }) : _shape = _GateShape.icon,
       label = null,
       child = null,
       builder = null,
       value = null,
       onChanged = null;

  /// A button the caller builds; see [GatedAffordance.builder].
  const CapabilityGatedAction.builder({
    super.key,
    required this.service,
    required this.connectionId,
    required this.blockedMessage,
    required this.onTap,
    required GatedAffordanceBuilder this.builder,
    this.hint = 'requires a read-write key',
    this.resource,
  }) : _shape = _GateShape.builder,
       label = null,
       child = null,
       icon = null,
       tooltip = null,
       color = null,
       value = null,
       onChanged = null;

  /// A `Switch` write.
  ///
  /// [value] is controlled by the caller, so a blocked tap does not flip it:
  /// the switch answers with the toast and stays where the server says it is.
  /// The hint is merged onto the toggle's own node, which a `Semantics(hint:)`
  /// placed around a `Switch` would miss.
  const CapabilityGatedAction.toggle({
    super.key,
    required this.service,
    required this.connectionId,
    required bool this.value,
    required ValueChanged<bool> this.onChanged,
    required this.blockedMessage,
    this.hint = 'requires a read-write key',
    this.resource,
  }) : _shape = _GateShape.toggle,
       label = null,
       child = null,
       icon = null,
       tooltip = null,
       color = null,
       builder = null,
       onTap = _noop;

  static void _noop() {}

  final _GateShape _shape;

  /// Which service the blocked control belongs to. Aims the toast's action at
  /// the page where that credential is replaced, and names its verb.
  final ServiceKey service;

  /// Which saved connection's scope governs this control. Per connection, not
  /// per service: the same service can be read-write on one instance and
  /// read-only on another, so the *scope* cannot be looked up from [service].
  final String connectionId;

  /// For services that scope per resource, which resource this writes
  /// (`vms`, `proxy_hosts`, a TrueNAS area). Null asks about the connection
  /// as a whole.
  final String? resource;

  /// The accessible name of the default cell.
  final String? label;

  /// The toast, e.g. `This Unraid key can't start or stop VMs.`
  final String blockedMessage;

  final VoidCallback onTap;

  /// The `requires …` fragment, published while the control is blocked.
  final String hint;

  final Widget? child;

  /// The glyph of the [CapabilityGatedAction.icon] shape.
  final Widget? icon;

  /// The name of the [CapabilityGatedAction.icon] shape.
  final String? tooltip;

  /// The glyph colour of the [CapabilityGatedAction.icon] shape.
  final Color? color;

  final GatedAffordanceBuilder? builder;

  /// The state of the [CapabilityGatedAction.toggle] shape.
  final bool? value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = _resolveCapabilityGate(
      context,
      ref,
      service: service,
      connectionId: connectionId,
      resource: resource,
      hint: hint,
      blockedMessage: blockedMessage,
    );

    switch (_shape) {
      case _GateShape.cell:
        return GatedAffordance(
          enabled: gate.enabled,
          label: label!,
          hint: gate.hint,
          onTap: onTap,
          onBlocked: gate.onBlocked,
          child: child!,
        );
      case _GateShape.builder:
        return GatedAffordance.builder(
          enabled: gate.enabled,
          hint: gate.hint,
          onTap: onTap,
          onBlocked: gate.onBlocked,
          builder: builder!,
        );
      case _GateShape.icon:
        return IconButton(
          tooltip: tooltip,
          color: color,
          onPressed: gate.enabled ? onTap : gate.onBlocked,
          icon: GatedAffordance.annotateFor(
            enabled: gate.enabled,
            hint: gate.hint,
            child: icon!,
          ),
        );
      case _GateShape.toggle:
        final toggle = Switch(
          value: value!,
          onChanged: gate.enabled ? onChanged : (_) => gate.onBlocked(),
        );
        return MergeSemantics(
          child: Semantics(
            hint: gate.hint,
            child: gate.enabled
                ? toggle
                : Opacity(
                    opacity: GatedAffordance.dimmedOpacity,
                    child: toggle,
                  ),
          ),
        );
    }
  }
}

/// The label of a `PopupMenuItem` write, dimmed and hinted when the write is
/// blocked.
///
/// The item itself stays `enabled: true`: a disabled menu item is skipped by
/// screen readers, the same failure as a disabled button, and its
/// `onSelected` asks [capabilityWriteAllowed] before acting. The hint lands on
/// the item's own node because `PopupMenuItem` merges its content.
class CapabilityGatedMenuLabel extends ConsumerWidget {
  const CapabilityGatedMenuLabel({
    super.key,
    required this.connectionId,
    required this.text,
    required this.hint,
    required this.service,
    this.resource,
    this.style,
  });

  final ServiceKey service;
  final String connectionId;
  final String? resource;
  final String text;

  /// The `requires …` fragment, published while the write is blocked.
  final String hint;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grant = ref.watch(capabilityGrantForProvider(connectionId));
    final enabled = grant.scopeFor(resource).canWrite;
    return GatedAffordance.annotateFor(
      enabled: enabled,
      hint: enabled
          ? null
          : grant.basis == CapabilityBasis.unanswered
          ? CapabilityCopy.unansweredHint(service)
          : hint,
      child: Text(text, style: style),
    );
  }
}

/// [GatedAffordance] wired to a Seerr connection's role gate: one control as
/// the gate's [verdict] for it says.
///
/// [Live] is an ordinary control. [Dimmed] keeps the control, its target and
/// its name, drains its content, hints [Dimmed.reason] and answers a tap with
/// that sentence: *Your account on Seerr can't approve requests.*, *You can't
/// ask for series on this server.* The fix lives on the server, with whoever
/// runs it, so the toast offers no action. [Absent] draws nothing: the control
/// is not part of this person's app, which is the one case a gate may leave a
/// control out.
///
/// The verdict is the caller's to read (`roleGateProvider` for the Seerr the
/// surface shows), so the control itself reads no provider.
class RoleGatedAction extends StatelessWidget {
  /// A control that is already a button; see [GatedAffordance.builder].
  const RoleGatedAction.builder({
    super.key,
    required this.verdict,
    required this.onTap,
    required this.builder,
  });

  /// What the gate said about this control.
  final GateVerdict verdict;

  /// What the control does when it can act.
  final VoidCallback onTap;

  final GatedAffordanceBuilder builder;

  @override
  Widget build(BuildContext context) {
    final verdict = this.verdict;
    if (verdict is Absent) return const SizedBox.shrink();
    final reason = verdict.reason;
    return GatedAffordance.builder(
      enabled: verdict.acts,
      hint: reason,
      onTap: onTap,
      onBlocked: () {
        if (reason != null) SnackBarHelper.info(context, reason);
      },
      builder: builder,
    );
  }
}
