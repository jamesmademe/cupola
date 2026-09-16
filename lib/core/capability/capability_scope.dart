/// What one saved credential is allowed to do, remembered per connection.
///
/// Four services in the roster hand out a single credential that can carry
/// several different scopes, and none of them tells you which until a write
/// fails: an Unraid or TrueNAS API key created without write scope, a Jellyfin
/// account whose policy is not `IsAdministrator`, an NPM login with a view-only
/// role. The app's behaviour today is to draw every write control live, let the
/// user press it, and report the 403 as if something had broken. Nothing broke.
/// The key is doing exactly what it was issued to do.
///
/// So each of the four owes the same three steps, and this is the first:
///
///  1. probe the credential **once on connect** and cache the answer here;
///  2. draw a [CapabilityBanner] naming what this credential cannot do — blue,
///     because a read-only key is a configuration fact and not a fault;
///  3. render every write **dimmed but tappable**, never hidden and never
///     `Semantics(enabled: false)`, so a screen reader still reaches it and
///     hears why.
///
/// ## Why it is keyed by connection and not by service
///
/// The same service can be read-write on one instance and read-only on
/// another — a TrueNAS with a full key at home and a friend's box behind a
/// read-only token are both "TrueNAS". Keying the cache on [ServiceKey] would
/// let one connection's answer govern the other, which is worse than not
/// probing at all: it would dim controls that work and enable controls that
/// cannot. The key is the connection id, which is stable by construction.
///
/// The probes themselves are not here. Each belongs to its own client — the
/// endpoint, the field and the failure shape are service knowledge — and this
/// layer only remembers what they found.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The three answers, and the one rule that makes them safe.
enum CapabilityScope {
  /// The probe answered, and the credential may write.
  readWrite,

  /// The credential may only read — **or** the probe itself failed.
  ///
  /// Those two collapse into one state deliberately. A probe that errors, times
  /// out or returns something unparseable has told us nothing, and the only
  /// safe reading of "nothing" is the restrictive one: falling back to
  /// read-write would mean drawing live controls on an unverified credential
  /// and discovering the truth from a 403 in the middle of a destructive
  /// action. A false read-only costs the user one banner and a trip to
  /// Settings; a false read-write costs them a stopped container that never
  /// stopped.
  readOnly,

  /// No probe has answered yet.
  ///
  /// Distinct from [readOnly] because it is a *timing* state, not a verdict.
  /// The probe runs on connect and lands in well under a second; dimming every
  /// write on the page for that window, and un-dimming them a frame later,
  /// would make a healthy connection look broken on every cold open. So
  /// [canWrite] is true here and the banner stays hidden — the window is the
  /// one moment where a 403 is a cheaper answer than a flicker, and the 403
  /// path writes [readOnly] back into the cache the first time it happens.
  unknown;

  /// Whether a write control is drawn live.
  ///
  /// `unknown` counts as writable; see its own doc for why that is not the
  /// "optimistic writes" the rule forbids. The forbidden case is a probe that
  /// *failed* being read as permission, and a failed probe records [readOnly].
  bool get canWrite => this != CapabilityScope.readOnly;

  /// Whether the banner has something to say.
  bool get isRestricted => this == CapabilityScope.readOnly;
}

/// The cache: connection id → what that credential may do.
///
/// A plain in-memory notifier rather than something persisted. A scope is a
/// fact about a key that the user can change from outside the app at any
/// moment — issuing a new token is the whole point of the banner's action — and
/// a persisted "read-only" would survive the fix and keep the controls dimmed
/// after the user had already corrected it. Re-probing on connect costs one
/// request.
final capabilityScopeProvider =
    NotifierProvider<CapabilityScopeNotifier, Map<String, CapabilityScope>>(
      CapabilityScopeNotifier.new,
    );

/// What a specific connection may do, defaulting to [CapabilityScope.unknown]
/// until its probe answers.
final capabilityScopeForProvider = Provider.family<CapabilityScope, String>((
  ref,
  connectionId,
) {
  return ref.watch(capabilityScopeProvider)[connectionId] ??
      CapabilityScope.unknown;
});

class CapabilityScopeNotifier extends Notifier<Map<String, CapabilityScope>> {
  @override
  Map<String, CapabilityScope> build() => const {};

  /// Records what a probe found for [connectionId].
  ///
  /// Idempotent: re-probing a connection that has not changed writes the same
  /// value and must not rebuild every write control on the page for it.
  void record(String connectionId, CapabilityScope scope) {
    if (state[connectionId] == scope) return;
    state = {...state, connectionId: scope};
  }

  /// The second signal, and the one that needs no endpoint.
  ///
  /// A 403 on any write is the service itself answering the question the probe
  /// asked, so every action runner reports one here. It is the reason a service
  /// with no probe to call — or one whose probe was wrong — still ends up with
  /// the right banner after the first refusal, instead of letting the user
  /// press the same dead control all afternoon.
  void markReadOnly(String connectionId) =>
      record(connectionId, CapabilityScope.readOnly);

  /// Forgets a connection, so the next connect re-probes it.
  ///
  /// Called when the credential changes: the whole point of "Update the key" is
  /// that the old verdict is now wrong.
  void forget(String connectionId) {
    if (!state.containsKey(connectionId)) return;
    final next = Map<String, CapabilityScope>.from(state)..remove(connectionId);
    state = next;
  }
}
