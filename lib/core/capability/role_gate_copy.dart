import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_quota.dart';

/// Every reason `RoleGate` gives for a dimmed control, in one place.
///
/// Two voices. The operator reads about an *account*, because the operator
/// may hold a friend's Seerr account beside their own key and has to be told
/// which one cannot: *"Your account on Seerr can't approve requests."* The
/// requester reads about themselves on *this server*, and never a service
/// name: *"You can't ask for series on this server."*
///
/// Sentence case, a full stop, no em dash. Movies, as Seerr and Radarr say
/// and as the rest of the app does.
abstract final class RoleGateCopy {
  /// Why an account on [server] cannot do [ability], for the operator.
  static String accountCannot(
    SeerrAbility ability, {
    required String server,
    SeerrMediaKind? kind,
  }) => "Your account on $server can't ${_doing(ability, kind)}.";

  /// Why the requester cannot do [ability].
  static String youCannot(SeerrAbility ability, {SeerrMediaKind? kind}) =>
      "You can't ${_doing(ability, kind)} on this server.";

  /// Why an account on [server] cannot ask for more of [kind] now, for the
  /// operator.
  static String accountQuotaReached(
    SeerrQuotaStatus quota,
    SeerrMediaKind kind, {
    required String server,
  }) {
    final limit = quota.limit;
    if (limit == null) {
      return 'Your account on $server has asked for as many '
          '${_unit(kind, 2)} as the server allows.';
    }
    return 'Your account on $server has asked for $limit '
        '${_unit(kind, limit)}${_window(quota.days)}, the most the server '
        'allows.';
  }

  /// Why the requester cannot ask for more of [kind] now.
  static String youQuotaReached(SeerrQuotaStatus quota, SeerrMediaKind kind) {
    final limit = quota.limit;
    if (limit == null) {
      return "You've asked for as many ${_unit(kind, 2)} as this server "
          'allows.';
    }
    return "You've asked for $limit ${_unit(kind, limit)}"
        '${_window(quota.days)}, the most this server allows.';
  }

  /// How much of its quota for [kind] the requester has left, while it has
  /// some: `You can ask for 3 more movies. This server allows 10 every 7
  /// days.` Null without a limit, or once it is reached ([youQuotaReached]
  /// says that).
  static String? youQuotaLeft(SeerrQuotaStatus quota, SeerrMediaKind kind) {
    final limit = quota.limit;
    if (limit == null || quota.restricted) return null;
    final left = quota.remaining ?? (limit - quota.used).clamp(0, limit);
    return 'You can ask for $left more ${_unit(kind, left)}. This server '
        'allows $limit${_every(quota.days)}.';
  }

  /// How much of its quota for [kind] an account on [server] has left, for
  /// the operator. Null as for [youQuotaLeft].
  static String? accountQuotaLeft(
    SeerrQuotaStatus quota,
    SeerrMediaKind kind, {
    required String server,
  }) {
    final limit = quota.limit;
    if (limit == null || quota.restricted) return null;
    final left = quota.remaining ?? (limit - quota.used).clamp(0, limit);
    return 'Your account on $server can ask for $left more '
        '${_unit(kind, left)}. The server allows $limit${_every(quota.days)}.';
  }

  /// Why an account on [server] cannot cancel somebody else's request.
  static String accountCannotCancelOthers({required String server}) =>
      "Your account on $server can't cancel other people's requests.";

  /// Why a request that no longer waits cannot be cancelled.
  static const notWaitingForApproval =
      'Only a request still waiting for approval can be cancelled.';

  /// What [ability] is, as the tail of "can't …".
  static String _doing(SeerrAbility ability, SeerrMediaKind? kind) =>
      switch (ability) {
        SeerrAbility.request => 'ask for ${_kinds(kind)}',
        SeerrAbility.request4k => 'ask for ${_kinds(kind)} in 4K',
        SeerrAbility.autoApproved => 'skip approval',
        SeerrAbility.autoApproved4k => 'skip approval in 4K',
        SeerrAbility.chooseDestination => 'choose where requests go',
        SeerrAbility.bypassQuota => 'go past request limits',
        SeerrAbility.approve => 'approve requests',
        SeerrAbility.manageMedia => 'manage media',
        SeerrAbility.seeEveryonesRequests => "see everyone's requests",
        SeerrAbility.cancelOwnPending => 'cancel requests',
        SeerrAbility.viewIssues => 'see issues',
        SeerrAbility.manageIssues => 'manage issues',
        SeerrAbility.manageUsers => 'manage users',
        SeerrAbility.readSettings => 'read settings',
      };

  static String _kinds(SeerrMediaKind? kind) => switch (kind) {
    SeerrMediaKind.movie => 'movies',
    SeerrMediaKind.tv => 'series',
    null => 'movies or series',
  };

  /// A series quota counts seasons, not series.
  static String _unit(SeerrMediaKind kind, int count) => switch (kind) {
    SeerrMediaKind.movie => count == 1 ? 'movie' : 'movies',
    SeerrMediaKind.tv => count == 1 ? 'season' : 'seasons',
  };

  static String _every(int? days) => switch (days) {
    null => ' in all',
    1 => ' a day',
    _ => ' every $days days',
  };

  static String _window(int? days) => switch (days) {
    null => '',
    1 => ' in the last day',
    _ => ' in the last $days days',
  };
}
