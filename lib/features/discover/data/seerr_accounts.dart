import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/data/seerr_auth_service.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_quota.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

/// What the app keeps about a Seerr account between requests, written to the
/// connection it belongs to.
///
/// The account lives on its connection (`ServiceInstance.account`), saved
/// with the rest of the settings: its session in secure storage, the rest
/// beside the address. This is the one place that changes it once it is
/// signed in, so an ended session and a new answer from `/auth/me` land the
/// same way from every client that met them.
final seerrAccountsProvider = Provider<SeerrAccounts>(SeerrAccounts.new);

/// How old the saved permissions may be before coming back to the app reads
/// them again.
const seerrPermissionsMaxAge = Duration(minutes: 15);

class SeerrAccounts {
  SeerrAccounts(this._ref, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Ref _ref;
  final DateTime Function() _now;

  /// The account connection [connectionId] signs in with, or null.
  SeerrAccountSignIn? accountOf(String connectionId) =>
      _ref.read(currentSettingsProvider).instanceById(connectionId)?.account;

  /// [account] signed in on connection [connectionId]: kept, and the key the
  /// connection held, if any, dropped. A connection that is not saved yet is
  /// [instance], saved with it.
  Future<void> signedIn(
    ServiceInstance instance,
    SeerrAccountSignIn account,
  ) async {
    final settings = _ref.read(currentSettingsProvider);
    final live = settings.instanceById(instance.id) ?? instance;
    await _ref
        .read(settingsProvider.notifier)
        .updateSettings(
          settings.copyWithInstance(
            live.copyWith(
              url: instance.url,
              access: instance.access,
              // An invite's address away comes with the draft; a draft
              // without one keeps the saved one.
              away: instance.away,
              label: instance.label,
              credential: '',
              account: account,
            ),
          ),
        );
  }

  /// Signs [connectionId]'s account out of the server, then empties the
  /// saved session whatever the server said. Address, login and permissions
  /// stay, so signing in again is one step.
  Future<void> signOut(String connectionId) async {
    final settings = _ref.read(currentSettingsProvider);
    final instance = settings.instanceById(connectionId);
    if (instance == null || instance.account == null) return;
    await signOutOfSeerr(instance, reach: _reachOf(connectionId));
    await sessionEnded(connectionId);
  }

  /// Removes [connectionId]'s account from this device: signed out of the
  /// server first, so its session ends there too rather than 30 days after it
  /// was last used, then the whole connection forgotten, with its pinned
  /// certificate when nothing else reaches that address, and the lens if it
  /// was on it. Nothing on the server changes: the requests stay there.
  Future<void> remove(String connectionId) async {
    final settings = _ref.read(currentSettingsProvider);
    final instance = settings.instanceById(connectionId);
    if (instance == null) return;
    await signOutOfSeerr(instance, reach: _reachOf(connectionId));
    final now = _ref.read(currentSettingsProvider);
    await _ref
        .read(settingsProvider.notifier)
        .updateSettings(
          now
              .copyWithoutInstance(connectionId)
              .copyWithoutUnusedCertificatesOf(instance),
        );
    if (_ref.read(activeInstancesProvider)[ServiceKey.seerr] == connectionId) {
      await _ref.read(activeInstancesProvider.notifier).clear(ServiceKey.seerr);
    }
  }

  /// Where connection [connectionId] is reached now: a request sent once
  /// goes to the address that answers.
  ConnectionReach? _reachOf(String connectionId) =>
      _ref.read(connectionReachProvider(connectionId));

  /// The server no longer knows [connectionId]'s session: it is emptied, and
  /// the connection is signed out. Everything else stays.
  Future<void> sessionEnded(String connectionId) =>
      _update(connectionId, (account) => account.signedOut);

  /// `/auth/me` answered [whoAmI] for [connectionId]'s account: its
  /// permissions now, and when they were read. Nothing else of the answer is
  /// kept (it carries the email).
  Future<void> recordWhoAmI(String connectionId, Map<String, dynamic> whoAmI) =>
      _update(
        connectionId,
        (account) => account.copyWith(
          permissions: SeerrGrant.fromWhoAmI(whoAmI).permissions,
          checkedAt: _now(),
        ),
      );

  /// Reads `/auth/me` again for [connectionId]'s account and keeps what it
  /// says: its permissions, or that the session ended. Quiet: a server that
  /// does not answer leaves the saved permissions as they were.
  Future<void> refresh(String connectionId) async {
    final settings = _ref.read(currentSettingsProvider);
    final instance = settings.instanceById(connectionId);
    if (instance?.account?.isSignedIn != true) return;
    final client = seerrClientFor(
      instance!,
      reach: _reachOf(connectionId),
      events: SeerrSessionEvents(
        onSessionEnded: () => unawaited(sessionEnded(connectionId)),
      ),
    );
    try {
      final me = mapOrNull((await client.get('/api/v1/auth/me')).data);
      if (me != null) {
        await recordWhoAmI(connectionId, me.cast<String, dynamic>());
      }
    } catch (_) {
      // An ended session was handled by the transport; anything else keeps
      // what was saved.
    } finally {
      client.close();
    }
  }

  /// [refresh] for every signed-in account, or, with [olderThan], for those
  /// whose permissions were read longer ago than that.
  Future<void> refreshAll({Duration? olderThan}) async {
    final now = _now();
    final due = [
      for (final instance
          in _ref.read(currentSettingsProvider).instancesOf(ServiceKey.seerr))
        if (instance.account case final account? when account.isSignedIn)
          if (olderThan == null ||
              account.checkedAt == null ||
              now.difference(account.checkedAt!) > olderThan)
            instance.id,
    ];
    await Future.wait([for (final id in due) refresh(id)]);
  }

  Future<void> _update(
    String connectionId,
    SeerrAccountSignIn Function(SeerrAccountSignIn account) change,
  ) async {
    final settings = _ref.read(currentSettingsProvider);
    final instance = settings.instanceById(connectionId);
    final account = instance?.account;
    if (instance == null || account == null) return;
    final next = change(account);
    if (next == account) return;
    await _ref
        .read(settingsProvider.notifier)
        .updateSettings(
          settings.copyWithInstance(instance.copyWith(account: next)),
        );
  }
}

/// Keeps every account's permissions current: read once when the app starts,
/// and again when it comes back to the foreground with permissions older
/// than [seerrPermissionsMaxAge]. Watched by the app's root.
///
/// The gate redraws from the new permissions at once; the app's shell, which
/// follows the audience, changes on the next return to the foreground and
/// never under the person's finger.
final seerrAccountKeeperProvider = Provider<void>((ref) {
  final accounts = ref.read(seerrAccountsProvider);
  void quietly(Future<void> work) => unawaited(work.catchError((Object _) {}));
  scheduleMicrotask(() => quietly(accounts.refreshAll()));
  final listener = AppLifecycleListener(
    onResume: () =>
        quietly(accounts.refreshAll(olderThan: seerrPermissionsMaxAge)),
  );
  ref.onDispose(listener.dispose);
});

/// What Seerr connection [connectionId] may do, or null when there is no
/// such Seerr. Empty means the lens.
///
/// The key may do everything, always. An account starts from the
/// permissions it saved, so the first frame is right without a request, and
/// follows every new answer of `/auth/me` ([SeerrAccounts.recordWhoAmI]).
final seerrGrantProvider = Provider.family<SeerrGrant?, String>((
  ref,
  connectionId,
) {
  final id = connectionId.isEmpty
      ? ref.watch(activeInstanceProvider(ServiceKey.seerr))?.id
      : connectionId;
  if (id == null) return null;
  return ref.watch(
    currentSettingsProvider.select((settings) {
      final instance = settings.instanceById(id);
      if (instance == null || instance.service != ServiceKey.seerr) return null;
      final account = instance.account;
      return account == null
          ? const SeerrGrant.apiKey()
          : SeerrGrant.account(permissions: account.permissions);
    }),
  );
});

/// How much of its quota connection [connectionId]'s account has left, read
/// each time it is asked (the request sheet opens), or null: for the key,
/// which has none to read, and when the server did not say.
///
/// Never skipped for an account: its own limit is often empty and the
/// server's default applies, which `/auth/me` does not say.
final seerrQuotaProvider = FutureProvider.autoDispose
    .family<SeerrQuota?, String>((ref, connectionId) async {
      final account = ref.watch(
        currentSettingsProvider.select(
          (settings) => settings.instanceById(connectionId)?.account,
        ),
      );
      if (account == null || !account.isSignedIn) return null;
      try {
        return await ref
            .read(seerrServiceForProvider(connectionId))
            .getQuota(account.userId);
      } catch (_) {
        return null;
      }
    }, retry: noProviderRetry);

/// What Seerr connection [connectionId] says about itself before anyone
/// signs in: its title, its ways in, its 4K servers. Public routes only.
final seerrServerFactsProvider = FutureProvider.autoDispose
    .family<SeerrServerFacts, String>((ref, connectionId) async {
      final instance = ref.watch(
        currentSettingsProvider.select(
          (settings) => settings.instanceById(connectionId),
        ),
      );
      final reach = ref.watch(connectionReachProvider(connectionId));
      if (instance == null || reach == null || reach.url.isEmpty) {
        throw const ServiceNotConfigured(ServiceKey.seerr);
      }
      final service = SeerrAuthService.forConnection(instance, reach: reach);
      try {
        return await service.readServer();
      } finally {
        service.close();
      }
    }, retry: noProviderRetry);
