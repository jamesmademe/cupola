import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// What the app keeps about a Seerr account between requests, written to the
/// connection it belongs to.
///
/// The account lives on its connection (`ServiceInstance.account`), saved
/// with the rest of the settings: its session in secure storage, the rest
/// beside the address. This is the one place that changes it after it signed
/// in, so an ended session and a new answer from `/auth/me` land the same way
/// from every client that met them.
final seerrAccountsProvider = Provider<SeerrAccounts>(SeerrAccounts.new);

class SeerrAccounts {
  SeerrAccounts(this._ref, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Ref _ref;
  final DateTime Function() _now;

  /// The account connection [connectionId] signs in with, or null.
  SeerrAccountSignIn? accountOf(String connectionId) =>
      _ref.read(currentSettingsProvider).instanceById(connectionId)?.account;

  /// The server no longer knows [connectionId]'s session: it is emptied, and
  /// the connection is signed out. Everything else stays, so signing in again
  /// is one step.
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
