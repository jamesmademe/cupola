/// Seerr's permission bits, and its own rule for reading them.
///
/// A Seerr user's `permissions` is one integer: a bitmask of
/// `server/lib/permissions.ts`. The values below are Seerr v3.5.0's. Jellyseerr
/// 2.x has the same bits (its two blocklist bits are still spelt *blacklist*),
/// Jellyseerr 1.x lacks the two blocklist bits, and Overseerr 1.x lacks those
/// and [SeerrPermission.manageSettings] as well. No server ever reused a value,
/// so one table reads all four.
library;

/// One bit of a Seerr user's `permissions`, at the value the server uses.
enum SeerrPermission {
  none(0),
  admin(2),

  /// Not in Overseerr.
  manageSettings(4),
  manageUsers(8),
  manageRequests(16),
  request(32),
  vote(64),
  autoApprove(128),
  autoApproveMovie(256),
  autoApproveTv(512),
  request4k(1024),
  request4kMovie(2048),
  request4kTv(4096),
  requestAdvanced(8192),
  requestView(16384),
  autoApprove4k(32768),
  autoApprove4kMovie(65536),
  autoApprove4kTv(131072),
  requestMovie(262144),
  requestTv(524288),
  manageIssues(1048576),
  viewIssues(2097152),
  createIssues(4194304),
  autoRequest(8388608),
  autoRequestMovie(16777216),
  autoRequestTv(33554432),
  recentView(67108864),
  watchlistView(134217728),

  /// Not in Overseerr or Jellyseerr 1.x.
  manageBlocklist(268435456),

  /// Not in Overseerr or Jellyseerr 1.x. The server skips 2^29.
  viewBlocklist(1073741824);

  const SeerrPermission(this.value);

  /// The bit, as the server writes it.
  final int value;
}

/// How a list of permissions is read: Seerr's `{type: 'and'}` and
/// `{type: 'or'}`.
enum SeerrPermissionCheck {
  /// Every permission in the list. The server's default.
  all,

  /// At least one permission in the list.
  any,
}

/// Whether a user whose `permissions` is [value] holds [permission], read
/// exactly as Seerr's `hasPermission` reads a single permission.
///
/// [SeerrPermission.admin] holds everything, and [SeerrPermission.none] is
/// held by everyone: the server bails out with yes before it looks at the bits.
bool hasSeerrPermission(int value, SeerrPermission permission) {
  if (permission == SeerrPermission.none) return true;
  return value & SeerrPermission.admin.value != 0 ||
      value & permission.value != 0;
}

/// Whether a user whose `permissions` is [value] holds [permissions], read
/// exactly as Seerr's `hasPermission` reads a list: every one of them unless
/// [check] asks for any.
///
/// [SeerrPermission.admin] holds every list, an empty one included. Without
/// it the list is read bit by bit, so [SeerrPermission.none] inside a list is
/// never held, and an empty list is held under [SeerrPermissionCheck.all] and
/// not under [SeerrPermissionCheck.any]. Odd, and the server's.
bool hasSeerrPermissions(
  int value,
  List<SeerrPermission> permissions, {
  SeerrPermissionCheck check = SeerrPermissionCheck.all,
}) {
  if (value & SeerrPermission.admin.value != 0) return true;
  bool held(SeerrPermission permission) => value & permission.value != 0;
  return switch (check) {
    SeerrPermissionCheck.all => permissions.every(held),
    SeerrPermissionCheck.any => permissions.any(held),
  };
}
