import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';

/// How much this connection is allowed to change (decision 34).
enum NpmWriteAccessState {
  /// The probe has not answered yet.
  checking,

  /// NPM named the permissions and they include a write.
  granted,

  /// NPM named the permissions and they do not.
  viewOnly,

  /// The probe itself failed — no answer, a 403 on `/api/users/me`, an NPM too
  /// old to carry the route. **Treated as read-only.** Cross-cutting C is
  /// explicit that a probe which fails falls back to read-only and never to
  /// optimistic writes: offering a control that then 403s teaches the user
  /// nothing except that the app guesses.
  unknown,
}

/// The answer to "may this connection change anything", resolved once and read
/// by every control on the screen.
class NpmWriteAccess {
  const NpmWriteAccess({required this.state, this.account});

  final NpmWriteAccessState state;
  final NpmAccount? account;

  /// Per resource, because NPM scopes per resource: an account may manage proxy
  /// hosts and only read certificates, and a single boolean would dim the wrong
  /// half of the screen.
  bool canManage(NpmResource resource) =>
      state == NpmWriteAccessState.granted &&
      (account?.canManage(resource) ?? false);

  /// Whether to draw the band at all. Never while the probe is still out — a
  /// banner that appears and then disappears is worse than a beat of silence.
  bool get showBand =>
      state == NpmWriteAccessState.viewOnly ||
      state == NpmWriteAccessState.unknown;

  /// The band's sentence. The two read-only states are **not** the same fact
  /// and must not claim to be: one is NPM telling us this account may not
  /// write, the other is us not having been able to ask.
  String get bandMessage => switch (state) {
    NpmWriteAccessState.viewOnly =>
      'This Nginx Proxy Manager account is view-only. Every host, certificate '
          'and access list reads; nothing here can be changed.',
    NpmWriteAccessState.unknown =>
      'Cupola could not read this account\'s permissions, so changes are held '
          'back until it can. Reads are unaffected.',
    _ => '',
  };

  /// What a dimmed control says when a screen reader reaches it, and what the
  /// toast repeats when it is tapped.
  String get hint => switch (state) {
    NpmWriteAccessState.viewOnly => 'requires an admin account',
    NpmWriteAccessState.unknown => 'this account\'s permissions are unknown',
    NpmWriteAccessState.checking => 'checking this account\'s permissions',
    NpmWriteAccessState.granted => '',
  };
}

/// `GET /api/users/me`, once per connection.
///
/// Null on any failure. The failure is not rethrown because this provider is
/// not a screen's data — it is the gate in front of the screen's controls, and
/// a gate that throws would replace the page with an error over a question the
/// page does not otherwise need answered.
final npmAccountProvider = FutureProvider<NpmAccount?>((ref) async {
  try {
    return await ref.watch(npmClientProvider).currentUser();
  } catch (_) {
    return null;
  }
});

/// Set when a write comes back refused, which is the second half of the design's
/// rule: "the role comes back with the connect probe, and a 403 on any write
/// marks the connection too". NPM's 403 is unambiguous — it has no other
/// meaning on an authenticated call — so one refusal is enough to stop offering
/// the rest.
class NpmWriteRefusal extends Notifier<bool> {
  @override
  bool build() => false;

  void markRefused() => state = true;
}

final npmWriteRefusedProvider = NotifierProvider<NpmWriteRefusal, bool>(
  NpmWriteRefusal.new,
);

final npmWriteAccessProvider = Provider<NpmWriteAccess>((ref) {
  if (ref.watch(npmWriteRefusedProvider)) {
    // NPM refused a write in this session. That outranks whatever the probe
    // said, in either direction.
    return const NpmWriteAccess(state: NpmWriteAccessState.viewOnly);
  }
  final probe = ref.watch(npmAccountProvider);
  return probe.when(
    loading: () => const NpmWriteAccess(state: NpmWriteAccessState.checking),
    error: (_, _) => const NpmWriteAccess(state: NpmWriteAccessState.unknown),
    data: (account) {
      if (account == null) {
        return const NpmWriteAccess(state: NpmWriteAccessState.unknown);
      }
      return NpmWriteAccess(
        state: account.isViewOnly
            ? NpmWriteAccessState.viewOnly
            : NpmWriteAccessState.granted,
        account: account,
      );
    },
  );
});
