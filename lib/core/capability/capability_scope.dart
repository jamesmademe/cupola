/// What one saved credential is allowed to do, remembered per connection.
///
/// Three services in the roster hand out a single credential that can carry
/// several different scopes, and none of them tells you which until a write
/// fails: an Unraid API key created without write permissions, a TrueNAS key
/// whose user holds only read roles, an NPM login with a view-only role. The
/// app's behaviour used to be to draw every write control live, let the user
/// press it, and report the refusal as if something had broken. Nothing broke.
/// The credential is doing exactly what it was issued to do.
///
/// Plex is a fourth, with a narrower answer. A token is a person's: the
/// owner's reads who is watching, and a shared account's is refused it while
/// the libraries read. Its probe answers `partial({})` for the second, and
/// what that costs is a read, so Plex owes no banner and dims no write: Now
/// playing says, in blue, that only the owner sees it.
///
/// Jellyfin is deliberately not one of them. Its slot can hold a non-admin
/// user's token, but every session control Cupola draws is on a session that
/// token may control — a non-admin is only ever *shown* sessions it owns — so
/// a gate there would dim controls that work. See `jellyfin_client.dart`.
///
/// So each of the three owes the same three steps:
///
///  1. probe the credential **once per credential** and remember the answer
///     (`connectionCapabilityProvider`);
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
/// The probes themselves are not here. Each belongs to its own feature — the
/// endpoint, the field and the failure shape are service knowledge — and this
/// file only defines what an answer looks like and remembers what the app
/// learned by acting.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

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
  ///
  /// The two are told apart only where they must be said differently — see
  /// [CapabilityBasis].
  readOnly,

  /// No probe has answered yet.
  ///
  /// Distinct from [readOnly] because it is a *timing* state, not a verdict.
  /// The probe runs on connect and lands in well under a second; dimming every
  /// write on the page for that window, and un-dimming them a frame later,
  /// would make a healthy connection look broken on every cold open. So
  /// [canWrite] is true here and the banner stays hidden — the window is the
  /// one moment where a refusal is a cheaper answer than a flicker, and the
  /// refusal path writes [readOnly] back the first time it happens.
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

/// Why a scope is what it is.
///
/// Gating treats every restricted basis the same — a control is dimmed or it is
/// not. The banner does not: "the service said this account is view-only" and
/// "Cupola could not ask" are different facts, need different sentences and
/// different actions (a new credential against *Check again*), and a banner
/// that folded them together would send the user to fix a key that may well be
/// fine.
enum CapabilityBasis {
  /// The service answered the probe.
  answered,

  /// The probe failed, so the scope is the restrictive fallback.
  unanswered,

  /// A write was refused with a permission error in this session. Newer
  /// evidence than any probe, so it outranks one.
  refused,
}

/// One connection's answer: the scope, why, and — for services that scope per
/// resource — which resources it covers.
@immutable
class CapabilityGrant {
  /// The service answered and the credential may write everything.
  const CapabilityGrant.readWrite()
    : scope = CapabilityScope.readWrite,
      basis = CapabilityBasis.answered,
      writable = null;

  /// The service answered and the credential may write nothing.
  const CapabilityGrant.readOnly()
    : scope = CapabilityScope.readOnly,
      basis = CapabilityBasis.answered,
      writable = null;

  /// The probe failed. Read-only, for the reason [CapabilityScope.readOnly]
  /// gives.
  const CapabilityGrant.unanswered()
    : scope = CapabilityScope.readOnly,
      basis = CapabilityBasis.unanswered,
      writable = null;

  /// A write was refused in this session.
  const CapabilityGrant.refused()
    : scope = CapabilityScope.readOnly,
      basis = CapabilityBasis.refused,
      writable = null;

  /// Nothing has answered yet — or the connection has no scoped credential to
  /// ask about. Live, for the reason [CapabilityScope.unknown] gives.
  const CapabilityGrant.unknown()
    : scope = CapabilityScope.unknown,
      basis = CapabilityBasis.answered,
      writable = null;

  /// Some resources writable, the rest read-only: NPM's per-resource
  /// permissions, Unraid's per-resource actions, TrueNAS's roles.
  ///
  /// The connection as a whole reads as writable — something on it can be
  /// changed — and [scopeFor] answers per resource.
  const CapabilityGrant.partial(Set<String> this.writable)
    : scope = CapabilityScope.readWrite,
      basis = CapabilityBasis.answered;

  final CapabilityScope scope;
  final CapabilityBasis basis;

  /// The resources this credential may write. Null means [scope] applies to
  /// every resource.
  final Set<String>? writable;

  /// The scope of one [resource]. Null asks about the connection as a whole —
  /// an NPM band that shows only when *everything* is restricted.
  ///
  /// A [partial] grant answers read-only for a resource it does not name. That
  /// is the fallback rule again: a resource the probe did not mention is one it
  /// did not say could be written.
  CapabilityScope scopeFor(String? resource) {
    final w = writable;
    if (w == null || resource == null) return scope;
    return w.contains(resource)
        ? CapabilityScope.readWrite
        : CapabilityScope.readOnly;
  }

  /// Whether a page that writes [resources] owes a banner. Null asks whether
  /// the whole connection is restricted.
  bool restrictsAny(Iterable<String>? resources) => resources == null
      ? scopeFor(null).isRestricted
      : resources.any((resource) => scopeFor(resource).isRestricted);

  @override
  bool operator ==(Object other) =>
      other is CapabilityGrant &&
      other.scope == scope &&
      other.basis == basis &&
      setEquals(other.writable, writable);

  @override
  int get hashCode => Object.hash(
    scope,
    basis,
    writable == null ? null : Object.hashAllUnordered(writable!),
  );

  @override
  String toString() =>
      'CapabilityGrant(${scope.name}, ${basis.name}'
      '${writable == null ? '' : ', writable: $writable'})';
}

/// The ledger: connection id → what the app *learned by acting*.
///
/// Only two things write it: a permission refusal on a write
/// ([CapabilityScopeNotifier.markReadOnly]) and a test injecting a state. Probe
/// answers do not go in here — they live in `connectionCapabilityProvider` and
/// are merged at read time by [capabilityGrantForProvider], which keeps one
/// provider from writing another during its build.
///
/// A plain in-memory notifier rather than something persisted. A scope is a
/// fact about a credential that the user can change from outside the app at
/// any moment — issuing a new token is the whole point of the banner's action —
/// and a persisted "read-only" would survive the fix and keep the controls
/// dimmed after the user had already corrected it.
final capabilityScopeProvider =
    NotifierProvider<CapabilityScopeNotifier, Map<String, CapabilityGrant>>(
      CapabilityScopeNotifier.new,
    );

/// What a specific connection may do: a learned refusal if there is one,
/// otherwise the probe's answer, otherwise [CapabilityGrant.unknown] while the
/// probe is out.
///
/// The one read every banner and gated control goes through.
final capabilityGrantForProvider = Provider.family<CapabilityGrant, String>((
  ref,
  connectionId,
) {
  final learned = ref.watch(
    capabilityScopeProvider.select((ledger) => ledger[connectionId]),
  );
  // A refusal (or a test) outranks the probe: the service answering the
  // question itself is newer evidence than anything asked on connect.
  if (learned != null) return learned;

  final probe = ref.watch(connectionCapabilityProvider(connectionId));
  return probe.when(
    data: (grant) => grant,
    // A timing state, and it stays live — see [CapabilityScope.unknown].
    loading: () => const CapabilityGrant.unknown(),
    // Every probe already folds its own failures into `unanswered`; this is
    // the belt to that brace, for a probe that throws anyway.
    error: (_, _) => const CapabilityGrant.unanswered(),
  );
});

/// The scope half of [capabilityGrantForProvider], for the callers that only
/// ask "may this write".
final capabilityScopeForProvider = Provider.family<CapabilityScope, String>(
  (ref, connectionId) =>
      ref.watch(capabilityGrantForProvider(connectionId)).scope,
);

class CapabilityScopeNotifier extends Notifier<Map<String, CapabilityGrant>> {
  @override
  Map<String, CapabilityGrant> build() {
    _watchCredentials();
    return const {};
  }

  /// Forgets a connection's learned verdict the moment its credential changes.
  ///
  /// The only caller of [forget] in the app, and the reason no settings screen
  /// has to know capabilities exist: saving a new key under "Update the key"
  /// changes the stamp below, and the refusal learned against the old key goes
  /// with it in the same frame.
  ///
  /// A `Map` never compares equal to the previous one, so the callback runs on
  /// every settings write; it compares entry by entry and costs one pass over
  /// the connections.
  void _watchCredentials() {
    try {
      ref.listen<Map<String, int>>(
        currentSettingsProvider.select(
          (settings) => {
            for (final instance in settings.instances)
              instance.id: Object.hash(
                instance.url,
                instance.credential,
                instance.username,
                instance.account?.session,
              ),
          },
        ),
        (previous, next) {
          if (previous == null) return;
          for (final entry in previous.entries) {
            if (next[entry.key] != entry.value) forget(entry.key);
          }
        },
      );
    } catch (_) {
      // A container with no settings at all (a unit test of the ledger alone)
      // has no credentials to watch; the ledger still works as a plain map.
    }
  }

  /// Records a scope for [connectionId].
  ///
  /// Idempotent: recording the value already held must not rebuild every write
  /// control on the page for it.
  void record(String connectionId, CapabilityScope scope) =>
      recordGrant(connectionId, switch (scope) {
        CapabilityScope.readWrite => const CapabilityGrant.readWrite(),
        CapabilityScope.readOnly => const CapabilityGrant.readOnly(),
        CapabilityScope.unknown => const CapabilityGrant.unknown(),
      });

  /// Records a whole grant for [connectionId]. Idempotent, like [record].
  void recordGrant(String connectionId, CapabilityGrant grant) {
    if (state[connectionId] == grant) return;
    state = {...state, connectionId: grant};
  }

  /// The second signal, and the one that needs no endpoint.
  ///
  /// A permission refusal on any write is the service itself answering the
  /// question the probe asked, so every action runner reports one here. It is
  /// the reason a probe that was wrong still ends up with the right banner
  /// after the first refusal, instead of letting the user press the same dead
  /// control all afternoon.
  void markReadOnly(String connectionId) =>
      recordGrant(connectionId, const CapabilityGrant.refused());

  /// Forgets a connection, so its scope falls back to the probe.
  ///
  /// Called when the credential changes: the whole point of "Update the key" is
  /// that the old verdict is now wrong.
  void forget(String connectionId) {
    if (!state.containsKey(connectionId)) return;
    state = Map<String, CapabilityGrant>.from(state)..remove(connectionId);
  }
}
