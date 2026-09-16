import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A control the user can see, reach and press, that is not going to act.
///
/// Three states get drawn this way and they are the same cell:
///
///  * a jump into another service that is not configured — Radarr's *Open in
///    qBittorrent* with no qBittorrent saved;
///  * a write blocked by a credential that may only read;
///  * anything else where the affordance is real and the precondition is not.
///
/// ## Why it is not disabled, and not hidden
///
/// Both of the obvious answers were in the tree and both are wrong in the same
/// direction — they remove the control from the one user who most needs it
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
/// button role, the name, and a hint that says what it wants — *requires
/// qBittorrent*. Only the foreground drains to 38%, which is the one signal a
/// sighted user reads for free and a screen-reader user was previously charged
/// for. Pressing it is not a dead end either: it raises a toast whose single
/// action is the fix.
///
/// **Dimmed means not configured, never unreachable.** A service that is down
/// keeps full ink and gets a `FaultBand` instead — the two states need opposite
/// answers ("go set this up" against "this is what it said last") and one
/// visual language cannot carry both.
class GatedAffordance extends StatelessWidget {
  const GatedAffordance({
    super.key,
    required this.enabled,
    required this.label,
    required this.hint,
    required this.onTap,
    required this.onBlocked,
    required this.child,
  });

  /// Whether the precondition is met. When true this is an ordinary control.
  final bool enabled;

  /// The accessible name. Required even when [child] renders its own text: this
  /// widget publishes one node for the whole cell, so the child's text is
  /// excluded and there would otherwise be nothing to announce.
  final String label;

  /// What the control wants, in the user's terms — `requires qBittorrent`,
  /// `requires a read-write key`. Published in **both** states; a hint that
  /// disappears when it becomes relevant is not a hint.
  final String hint;

  /// What the control does when it can act.
  final VoidCallback onTap;

  /// What it does when it cannot. Raises the toast; never navigates silently.
  final VoidCallback onBlocked;

  final Widget child;

  /// The one dim in the app that means "precondition unmet".
  ///
  /// 38% is Material's own disabled opacity, kept on purpose: it is the level
  /// users already read as "not right now", and inventing a second one would
  /// only mean two things that look almost the same.
  static const double dimmedOpacity = 0.38;

  @override
  Widget build(BuildContext context) {
    final Widget body = enabled
        ? child
        : Opacity(
            opacity: dimmedOpacity,
            // The foreground only. The cell's own hit area, padding and any
            // surrounding plate stay at full strength, because the target is
            // not what is unavailable — the action is.
            child: child,
          );

    return PressableScale(
      // Always a real callback, so `PressableScale` publishes `button: true`,
      // `enabled: true` and the hint. That is the whole mechanism: the node
      // stays on the screen reader's path in both states and the hint carries
      // the difference. Handing it `null` here is the bug this widget exists to
      // stop — Material would render the disabled look and the semantics tree
      // would lose the control entirely.
      onTap: enabled ? onTap : onBlocked,
      semanticLabel: label,
      semanticHint: hint,
      // One node for the cell, not three fragments: the child's own text would
      // otherwise compete with [label] and the row would read twice.
      excludeChildSemantics: true,
      // No haptic on the blocked arm — a tap that does not act should not feel
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

/// [GatedAffordance] wired to "is the other service configured?".
///
/// The specimen is Radarr's *Open in qBittorrent*: the control reads the saved
/// connections, and when the target is missing it dims, gains the hint
/// `requires qBittorrent`, and answers a tap with a toast whose one action
/// lands on that service's own settings page.
///
/// The toast sentence is the caller's because only the caller knows what the
/// jump was *for* — "Connect qBittorrent to open this transfer" and "Connect
/// Seerr to see cast" are the same mechanism and different promises.
class CrossServiceAction extends ConsumerWidget {
  const CrossServiceAction({
    super.key,
    required this.target,
    required this.label,
    required this.blockedMessage,
    required this.onTap,
    required this.child,
    this.hint,
  });

  /// The service this control acts on. Not the service the page belongs to.
  final ServiceKey target;

  /// The accessible name, e.g. `Open in qBittorrent`.
  final String label;

  /// The toast, e.g. `Connect qBittorrent to open this transfer`.
  final String blockedMessage;

  /// What the control does when [target] is configured.
  final VoidCallback onTap;

  /// Overrides the default `requires <Service>` hint, for the rare control
  /// whose precondition needs more than a name.
  final String? hint;

  final Widget child;

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

    return GatedAffordance(
      enabled: configured,
      label: label,
      hint: hint ?? 'requires ${target.title}',
      onTap: onTap,
      onBlocked: () => SnackBarHelper.withAction(
        context,
        blockedMessage,
        actionLabel: 'Settings',
        // The action is the fix, and it is the *specific* fix: this service's
        // own settings page, where its setup note is printed, rather than the
        // settings root the user would then have to navigate.
        onAction: () => context.go(ServiceRoutes.settingsFor(target)),
      ),
      child: child,
    );
  }
}

/// [GatedAffordance] wired to a credential's scope.
///
/// The write half of cross-cutting C: the banner says what the key cannot do
/// once, at the top of the page, and every write below it dims to match rather
/// than disappearing. The readouts keep refreshing — a read-only key reads
/// perfectly well, and the page is still worth looking at.
class CapabilityGatedAction extends ConsumerWidget {
  const CapabilityGatedAction({
    super.key,
    required this.service,
    required this.connectionId,
    required this.label,
    required this.blockedMessage,
    required this.onTap,
    required this.child,
    this.hint = 'requires a read-write key',
  });

  /// Which service the blocked control belongs to. Used only to aim the
  /// toast's action at the page where the key is replaced.
  final ServiceKey service;

  /// Which saved connection's scope governs this control. Per connection, not
  /// per service: the same service can be read-write on one instance and
  /// read-only on another, so the *scope* cannot be looked up from [service].
  final String connectionId;

  final String label;

  /// The toast, e.g. `This Unraid key can read. Starting a container needs a
  /// key with write scope.`
  final String blockedMessage;

  final VoidCallback onTap;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(capabilityScopeForProvider(connectionId));

    return GatedAffordance(
      enabled: scope.canWrite,
      label: label,
      hint: hint,
      onTap: onTap,
      onBlocked: () => SnackBarHelper.withAction(
        context,
        blockedMessage,
        actionLabel: 'Update the key',
        onAction: () => context.go(ServiceRoutes.settingsFor(service)),
      ),
      child: child,
    );
  }
}
