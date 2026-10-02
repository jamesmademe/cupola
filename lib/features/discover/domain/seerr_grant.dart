import 'package:flutter/foundation.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';

/// Something a Seerr connection may or may not do, as one surface asks it.
///
/// Each one is a rule the **server** enforces; [SeerrGrant.may] holds them, one
/// per ability. Adding an ability means writing its rule there, because the
/// switch is exhaustive.
enum SeerrAbility {
  /// Ask for a title. Depends on the kind.
  request,

  /// Ask for a title in 4K. Depends on the kind. An option of the request,
  /// never a control of its own.
  request4k,

  /// A request goes straight to approved instead of waiting. Depends on the
  /// kind.
  autoApproved,

  /// A 4K request goes straight to approved. Depends on the kind.
  autoApproved4k,

  /// Pick the server, the quality profile and the folder a request goes to.
  chooseDestination,

  /// Send a request past the account's quota.
  bypassQuota,

  /// Approve, decline and retry requests.
  approve,

  /// Change a title's status, remove it and remove its files.
  manageMedia,

  /// See everybody's requests, and who made them.
  seeEveryonesRequests,

  /// Cancel one's own request while it waits for approval.
  cancelOwnPending,

  /// Open the issues list at all.
  viewIssues,

  /// Resolve, reopen and delete anybody's issues.
  manageIssues,

  /// Create, edit and delete users.
  manageUsers,

  /// Read the server's settings, its Radarr and Sonarr servers included.
  readSettings;

  /// Whether the answer differs for a movie and a series.
  bool get dependsOnKind => switch (this) {
    request || request4k || autoApproved || autoApproved4k => true,
    chooseDestination ||
    bypassQuota ||
    approve ||
    manageMedia ||
    seeEveryonesRequests ||
    cancelOwnPending ||
    viewIssues ||
    manageIssues ||
    manageUsers ||
    readSettings => false,
  };

  /// Whether this is the operator's to do rather than the requester's own.
  ///
  /// The requester's app has no place for the operator's abilities at all,
  /// whatever the account may do: they are left out of it, not dimmed in it.
  bool get belongsToOperator => switch (this) {
    request || request4k || autoApproved || autoApproved4k => false,
    cancelOwnPending => false,
    chooseDestination ||
    bypassQuota ||
    approve ||
    manageMedia ||
    seeEveryonesRequests ||
    viewIssues ||
    manageIssues ||
    manageUsers ||
    readSettings => true,
  };
}

/// The two kinds of title Seerr requests, as its `mediaType` names them.
enum SeerrMediaKind {
  movie,
  tv;

  /// The kind a Seerr `mediaType` names, or null for anything else.
  static SeerrMediaKind? fromWire(Object? mediaType) => switch (mediaType) {
    'movie' => SeerrMediaKind.movie,
    'tv' => SeerrMediaKind.tv,
    _ => null,
  };
}

/// Who an account is to the household: someone who decides on requests, or
/// someone who makes them.
enum SeerrRole { manager, requester }

/// What one Seerr connection may do, read the way the server reads it.
///
/// Two ways in. The API key is user 1, Seerr's first admin, so it may do
/// everything. An account carries the `permissions` its last `/auth/me`
/// answered, and each ability is decided from those bits by the rule the
/// server applies (`server/entity/MediaRequest.ts`, `server/routes/*.ts`).
///
/// Presentation, not security: Seerr enforces every one of these rules itself.
/// A grant only keeps the app from promising what the server would refuse.
@immutable
final class SeerrGrant {
  /// The instance API key: user 1, everything.
  const SeerrGrant.apiKey() : permissions = null;

  /// A household member's own account, with its `permissions` bitmask.
  const SeerrGrant.account({required int this.permissions});

  /// An account's grant from its `/auth/me` answer.
  ///
  /// Reads `permissions` and nothing else, so nothing personal in the answer
  /// (the email, the name) ends up held here. An answer without the field
  /// grants nothing: the restrictive reading, so a control the server might
  /// refuse is not promised.
  factory SeerrGrant.fromWhoAmI(Map<String, dynamic> json) =>
      SeerrGrant.account(permissions: intOrNull(json['permissions']) ?? 0);

  /// The bitmask, or null for the API key.
  final int? permissions;

  bool get isApiKey => permissions == null;

  /// Whether this connection may do [ability].
  ///
  /// [kind] matters only where [SeerrAbility.dependsOnKind]. Left null there,
  /// it asks whether the account may do it for either kind: "may this account
  /// ask for anything at all".
  ///
  /// Each rule cites the line of Seerr v3.5.0 that enforces it.
  bool may(SeerrAbility ability, {SeerrMediaKind? kind}) {
    final value = permissions;
    if (value == null) return true;
    if (ability.dependsOnKind && kind == null) {
      return may(ability, kind: SeerrMediaKind.movie) ||
          may(ability, kind: SeerrMediaKind.tv);
    }
    bool any(List<SeerrPermission> list) =>
        hasSeerrPermissions(value, list, check: SeerrPermissionCheck.any);
    bool one(SeerrPermission permission) =>
        hasSeerrPermission(value, permission);
    final movie = kind == SeerrMediaKind.movie;

    return switch (ability) {
      // `MediaRequest.ts:107-139`: REQUEST or the kind's own bit.
      SeerrAbility.request => any([
        SeerrPermission.request,
        movie ? SeerrPermission.requestMovie : SeerrPermission.requestTv,
      ]),
      // `MediaRequest.ts:110-111,126-127`: REQUEST_4K or the kind's own 4K
      // bit. The plain request bits are not asked.
      SeerrAbility.request4k => any([
        SeerrPermission.request4k,
        movie ? SeerrPermission.request4kMovie : SeerrPermission.request4kTv,
      ]),
      // `MediaRequest.ts:316-327,431-442`.
      SeerrAbility.autoApproved => any([
        SeerrPermission.autoApprove,
        movie
            ? SeerrPermission.autoApproveMovie
            : SeerrPermission.autoApproveTv,
        SeerrPermission.manageRequests,
      ]),
      // The same lines, with the 4K bits.
      SeerrAbility.autoApproved4k => any([
        SeerrPermission.autoApprove4k,
        movie
            ? SeerrPermission.autoApprove4kMovie
            : SeerrPermission.autoApprove4kTv,
        SeerrPermission.manageRequests,
      ]),
      // `MediaRequest.ts:276-279`. The server does not refuse a pick from
      // anybody else: it lays its override rules over it.
      SeerrAbility.chooseDestination => any([
        SeerrPermission.manageRequests,
        SeerrPermission.requestAdvanced,
      ]),
      // `MediaRequest.ts:143`.
      SeerrAbility.bypassQuota => one(SeerrPermission.manageRequests),
      // `request.ts:745,786`: retry and approve or decline.
      SeerrAbility.approve => one(SeerrPermission.manageRequests),
      // `media.ts:106,172,205`.
      SeerrAbility.manageMedia => one(SeerrPermission.manageRequests),
      // `request.ts:147-162`. Without it the list filters itself down to the
      // account's own requests.
      SeerrAbility.seeEveryonesRequests => any([
        SeerrPermission.manageRequests,
        SeerrPermission.requestView,
      ]),
      // `request.ts:717-726`: anybody, on a request of their own that still
      // waits. Which request is the caller's to say: [mayCancelRequest].
      SeerrAbility.cancelOwnPending => true,
      // `issue.ts:18-27`.
      SeerrAbility.viewIssues => any([
        SeerrPermission.manageIssues,
        SeerrPermission.viewIssues,
        SeerrPermission.createIssues,
      ]),
      // `issue.ts:345`. Anybody else may resolve only an issue of their own.
      SeerrAbility.manageIssues => one(SeerrPermission.manageIssues),
      // `user/index.ts:172,515,553,593`.
      SeerrAbility.manageUsers => one(SeerrPermission.manageUsers),
      // `routes/index.ts:156`: every `/settings` route.
      SeerrAbility.readSettings => one(SeerrPermission.admin),
    };
  }

  /// Whether this connection may cancel one request: anybody's with
  /// MANAGE_REQUESTS, otherwise only an [own] request still
  /// [waitingForApproval] (`request.ts:717-726`, which refuses with a 401).
  bool mayCancelRequest({required bool own, required bool waitingForApproval}) {
    final value = permissions;
    if (value == null) return true;
    if (hasSeerrPermission(value, SeerrPermission.manageRequests)) return true;
    return own && waitingForApproval;
  }

  /// Whether this connection may resolve or reopen one issue: anybody's with
  /// MANAGE_ISSUES, otherwise only an [own] issue, and only with
  /// CREATE_ISSUES (`issue.ts:329-346`: the route admits either permission,
  /// then refuses with a 401 anybody else's issue).
  bool mayResolveIssue({required bool own}) {
    final value = permissions;
    if (value == null) return true;
    if (hasSeerrPermission(value, SeerrPermission.manageIssues)) return true;
    return own && hasSeerrPermission(value, SeerrPermission.createIssues);
  }

  /// A manager decides on requests; everybody else asks.
  SeerrRole get role =>
      may(SeerrAbility.approve) ? SeerrRole.manager : SeerrRole.requester;

  /// The resource a [CapabilityGrant] names for [ability].
  ///
  /// The ability's name, and for an ability that depends on the kind and is
  /// asked about one kind, the name and the kind: `request.tv`.
  static String resource(SeerrAbility ability, {SeerrMediaKind? kind}) =>
      ability.dependsOnKind && kind != null
      ? '${ability.name}.${kind.name}'
      : ability.name;

  /// This grant in the shape the capability widgets read, so the operator's
  /// gated controls can reuse them.
  ///
  /// The key writes everything. An account writes the abilities it may, each
  /// under [resource]: the bare name when it may for either kind, and the
  /// kind's own name for each kind it may.
  CapabilityGrant asCapability() {
    if (isApiKey) return const CapabilityGrant.readWrite();
    return CapabilityGrant.partial({
      for (final ability in SeerrAbility.values) ...[
        if (may(ability)) resource(ability),
        if (ability.dependsOnKind)
          for (final kind in SeerrMediaKind.values)
            if (may(ability, kind: kind)) resource(ability, kind: kind),
      ],
    });
  }

  @override
  bool operator ==(Object other) =>
      other is SeerrGrant && other.permissions == permissions;

  @override
  int get hashCode => Object.hash(SeerrGrant, permissions);

  @override
  String toString() => isApiKey
      ? 'SeerrGrant.apiKey()'
      : 'SeerrGrant.account(permissions: $permissions)';
}
