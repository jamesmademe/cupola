/// Which TrueNAS roles let a key make which of Cupola's writes.
///
/// A TrueNAS API key carries its owning user's privilege (TS-25.04.0 onwards),
/// and `auth.me` reports that privilege's roles **already expanded**:
/// `FULL_ADMIN` expands to every role name (itself included), and
/// `READONLY_ADMIN` to every role whose name ends in `_READ`, so it holds no
/// `_WRITE` and no `_DELETE` role. Broader roles (`SHARING_ADMIN`,
/// `ALERT_WRITE`, `POOL_WRITE`) are expanded into the specific names too, so
/// "any of these names is present" is a sound check.
///
/// Role names come from each method's `@api_method(roles=…)` and its service's
/// `role_prefix`, read at TS-25.04.0 and TS-25.10.0.
library;

import 'package:cupola/features/truenas/domain/models/data_protection.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';

/// The role that grants everything, and that a few methods require outright.
const trueNasFullAdmin = 'FULL_ADMIN';

/// The first release whose rules differ from 25.04's in a way the gate sees.
const _v25_10 = TrueNasVersion(25, 10);

/// One group of TrueNAS writes that a single set of roles governs.
///
/// [key] is the resource string the capability layer gates on.
enum TrueNasCapabilityArea {
  /// `alert.dismiss`.
  alerts({'ALERT_LIST_WRITE'}),

  /// `app.start` / `stop` / `upgrade` / `delete`. Absent in STIG mode.
  apps({'APPS_WRITE'}),

  /// `user.create` / `delete`, `group.create` / `delete`.
  accounts({'ACCOUNT_WRITE'}),

  /// `iscsi.target.delete`.
  iscsi({'SHARING_ISCSI_TARGET_WRITE'}),

  /// `sharing.smb.create` / `update` / `delete`.
  smb({'SHARING_SMB_WRITE'}),

  /// `sharing.nfs.create` / `update` / `delete`.
  nfs({'SHARING_NFS_WRITE'}),

  /// `mail.update` — mail's role prefix is `ALERT`.
  mailConfig({'ALERT_WRITE'}),

  /// `mail.send`: no role declared on 25.04, so full admin only; `MAIL_WRITE`
  /// from 25.10.
  mailSend({}, since25_10: {'MAIL_WRITE'}),

  /// `pool.dataset.create` / `update`.
  datasetWrite({'DATASET_WRITE'}),

  /// `pool.dataset.delete` — its own role; `SHARING_ADMIN` does not imply it.
  datasetDelete({'DATASET_DELETE'}),

  /// `zfs.snapshot.create`.
  snapshotWrite({'SNAPSHOT_WRITE'}),

  /// `zfs.snapshot.delete`.
  snapshotDelete({'SNAPSHOT_DELETE'}),

  /// `pool.scrub.scrub` / `pool.scrub.run`.
  scrubRun({'POOL_WRITE'}),

  /// `pool.scrub.update` / `delete`.
  scrubTask({'POOL_SCRUB_WRITE'}),

  /// `pool.snapshottask.update` / `delete` / `run`.
  snapshotTask({'SNAPSHOT_TASK_WRITE'}),

  /// `replication.update` / `delete` / `run` for a PUSH task.
  replication({'REPLICATION_TASK_WRITE'}),

  /// The same for a PULL task, which needs its own role.
  replicationPull({'REPLICATION_TASK_WRITE_PULL'}),

  /// `cloudsync.update` / `delete` / `sync`.
  cloudSync({'CLOUD_SYNC_WRITE'}),

  /// `rsynctask.update` / `delete` — rsync's role prefix is `SNAPSHOT_TASK`.
  rsyncTask({'SNAPSHOT_TASK_WRITE'}),

  /// `rsynctask.run`: full admin only on 25.04, `SNAPSHOT_TASK_WRITE` from
  /// 25.10.
  rsyncRun({}, since25_10: {'SNAPSHOT_TASK_WRITE'}),

  /// `virt.instance.create` / `delete` / `restart` / `start` / `stop`. Absent
  /// in STIG mode.
  virt({'VIRT_INSTANCE_WRITE'}),

  /// `system.general.update`.
  systemGeneral({'SYSTEM_GENERAL_WRITE'}),

  /// `system.advanced.update`.
  systemAdvanced({'SYSTEM_ADVANCED_WRITE'}),

  /// `system.reboot` / `shutdown`: full admin only, explicitly.
  power({});

  const TrueNasCapabilityArea(this._roles, {Set<String>? since25_10})
    : _since25_10 = since25_10;

  final Set<String> _roles;
  final Set<String>? _since25_10;

  /// The capability-layer resource key.
  String get key => name;

  /// The role names that grant this area on [version]. An unknown version gets
  /// the 25.04 rules, which are the stricter ones. [trueNasFullAdmin] always
  /// grants, and is checked before this.
  Set<String> grantedBy(TrueNasVersion? version) {
    final later = _since25_10;
    if (later != null && version != null && version >= _v25_10) return later;
    return _roles;
  }
}

/// The capability key for one `service.*` target.
String trueNasServiceArea(String service) => 'service:$service';

/// The sharing role that lets a non-admin change the matching service.
const _serviceSharingRoles = {
  'cifs': 'SHARING_SMB_WRITE',
  'nfs': 'SHARING_NFS_WRITE',
  'iscsitarget': 'SHARING_ISCSI_WRITE',
  'ftp': 'SHARING_FTP_WRITE',
};

/// Whether [roles] may start, stop or update [service].
///
/// `service.*` checks twice: the method's role, then — inside the method —
/// `app_has_write_privilege_for_service`, which admits only `FULL_ADMIN`, the
/// general service-write role, or the sharing role matching the service.
/// Anyone else is refused with EPERM. On 25.04 the general arm checks for
/// `SERVICES_WRITE`, a role that does not exist, so only the other two can
/// pass; 25.10 checks `SERVICE_WRITE`.
bool trueNasMayWriteService(
  String service,
  Set<String> roles,
  TrueNasVersion? version,
) {
  if (roles.contains(trueNasFullAdmin)) return true;
  final sharing = _serviceSharingRoles[service];
  if (sharing != null && roles.contains(sharing)) return true;
  return version != null &&
      version >= _v25_10 &&
      roles.contains('SERVICE_WRITE');
}

/// The roles in an `auth.me` result, or null when it carries none — an answer
/// that says nothing.
Set<String>? trueNasRolesFromMe(Object? me) {
  if (me is! Map) return null;
  final privilege = me['privilege'];
  if (privilege is! Map) return null;
  final roles = privilege['roles'];
  if (roles is! List) return null;
  return {for (final role in roles) role.toString().toUpperCase()};
}

/// Which area governs a data-protection task's writes.
extension TrueNasProtectionTaskCapability on TrueNasProtectionTask {
  /// "Run now".
  TrueNasCapabilityArea get runArea => switch (kind) {
    TrueNasTaskKind.snapshot => TrueNasCapabilityArea.snapshotTask,
    TrueNasTaskKind.replication =>
      isPull
          ? TrueNasCapabilityArea.replicationPull
          : TrueNasCapabilityArea.replication,
    TrueNasTaskKind.cloudSync => TrueNasCapabilityArea.cloudSync,
    TrueNasTaskKind.rsync => TrueNasCapabilityArea.rsyncRun,
    TrueNasTaskKind.scrub => TrueNasCapabilityArea.scrubRun,
  };

  /// Delete, and the Enabled switch.
  TrueNasCapabilityArea get writeArea => switch (kind) {
    TrueNasTaskKind.snapshot => TrueNasCapabilityArea.snapshotTask,
    TrueNasTaskKind.replication =>
      isPull
          ? TrueNasCapabilityArea.replicationPull
          : TrueNasCapabilityArea.replication,
    TrueNasTaskKind.cloudSync => TrueNasCapabilityArea.cloudSync,
    TrueNasTaskKind.rsync => TrueNasCapabilityArea.rsyncTask,
    TrueNasTaskKind.scrub => TrueNasCapabilityArea.scrubTask,
  };
}

/// The areas the Data protection page writes.
///
/// `replicationPull` is left out on purpose: it governs only pull tasks,
/// which most servers do not have, and a banner over a page with none would
/// describe a restriction nothing on it has. A pull task's own controls still
/// dim and say why.
final trueNasDataProtectionAreas = {
  TrueNasCapabilityArea.snapshotTask.key,
  TrueNasCapabilityArea.replication.key,
  TrueNasCapabilityArea.cloudSync.key,
  TrueNasCapabilityArea.rsyncTask.key,
  TrueNasCapabilityArea.rsyncRun.key,
  TrueNasCapabilityArea.scrubTask.key,
  TrueNasCapabilityArea.scrubRun.key,
};
