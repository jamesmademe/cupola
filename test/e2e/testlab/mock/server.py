"""Small deterministic protocol mocks for the Cupola lab.

They stand in for the two transports for which a generic vendor container is
not available: TrueNAS over JSON-RPC on a WebSocket, and Unraid over GraphQL.
They are not a replacement for certification against a real host; the response
shapes are the contract fixtures in ``test/fixtures/truenas`` and
``test/fixtures/unraid``, and ``test/e2e/testlab/truenas_contract.py`` compares
the simulator against them.

**TrueNAS is stateful.** The world below is built from the lab's own world
(names, folders, people, apps: see the provenance notes on ``build_world``),
kept in memory, and moved by the same methods the app calls: a scrub runs as a
job with progress in ``core.get_jobs`` and shows in ``pool.query`` and
``pool.scrub.query``; datasets, snapshots, SMB/NFS shares, users, groups,
services, apps and virt instances are created, changed and deleted for real;
alerts dismiss; an update is available; reboot and shutdown cut the socket.
Nothing is persisted: a restart of the container rebuilds the same world.

Two keys are accepted. ``test-key`` is the full administrator. ``test-readonly``
belongs to ``auditor``, a local user holding ``READONLY_ADMIN`` and no write
role: every write is refused with the middleware's own envelope (``EACCES``, or
``EPERM`` for ``service.*``, which checks the service's own write privilege).

The simulator speaks TLS only, like a TrueNAS that revokes an API key sent over
a cleartext socket, with the self-signed certificate that
``test/e2e/testlab/truenas_cert.sh`` keeps in the lab's state directory. It reads
the certificate for every connection, so one made again is served without a
restart. With ``--healthcheck`` this file performs a TLS handshake against the
running mock and exits 0 or 1, which is what the Compose healthcheck runs.

The lab needs a way to inspect and reset that state from the host without
speaking WebSocket, so the same TLS port answers a small control surface for
the testlab alone (::

    GET  /testlab/health          -> {"ok": true, "power": "on"}
    GET  /testlab/state           -> the world, its jobs and the two keys' roles
    POST /testlab/reset           -> rebuild the world; returns /testlab/state
    POST /testlab/scenario        -> {"name": "truenas-state"} marks the prepared
                                     world, {"name": null} clears the mark
    POST /testlab/power           -> {"state": "on"} comes back after a reboot
                                     or a shutdown

Control requests are answered even while the machine is "powered down", because
that is the only way to bring it back; every other connection is dropped.
"""

from __future__ import annotations

import base64
import hashlib
import json
import math
import os
import socket
import socketserver
import ssl
import struct
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl
from xml.sax.saxutils import escape


API_KEY = os.environ.get("MOCK_API_KEY", "test-key")
# Hardcoded on purpose: the lab's Compose file is shared with other work and a
# read-only key is part of the protocol surface this simulator certifies.
READONLY_API_KEY = "test-readonly"
MODE = os.environ.get("MOCK_MODE", "unraid").lower()
TLS_CERT = os.environ.get("MOCK_TLS_CERT", "/certs/truenas.crt")
TLS_KEY = os.environ.get("MOCK_TLS_KEY", "/certs/truenas.key")
TRUENAS_PORT = 8460
INDEXER_PORT = 8088
FORGE_DIR = os.environ.get("MOCK_FORGE_DIR", "/forge")


def json_bytes(value: object) -> bytes:
    return json.dumps(value, separators=(",", ":")).encode("utf-8")


def tls_context() -> ssl.SSLContext:
    """A server context over the certificate as it is on disk right now."""
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(TLS_CERT, TLS_KEY)
    return context


# ---------------------------------------------------------------------------
# TrueNAS: who the two keys are
# ---------------------------------------------------------------------------
#
# Both dictionaries are copied verbatim from test/fixtures/truenas, and the
# contract compares ``auth.me`` against those fixtures so they cannot drift.
# ``FULL_ADMIN`` expands to every role; ``READONLY_ADMIN`` expands to every
# *_READ role, so the read-only key holds no *_WRITE and no *_DELETE.

ADMIN_ME: dict[str, object] = {
    "pw_name": "truenas_admin",
    "pw_uid": 950,
    "pw_gid": 950,
    "pw_gecos": "Local Administrator",
    "pw_dir": "/home/truenas_admin",
    "pw_shell": "/usr/bin/zsh",
    "attributes": {},
    "two_factor_config": {},
    "privilege": {
        "roles": {
            "$set": [
                "FULL_ADMIN",
                "READONLY_ADMIN",
                "ACCOUNT_READ",
                "ACCOUNT_WRITE",
                "ALERT_LIST_READ",
                "ALERT_LIST_WRITE",
                "APPS_READ",
                "APPS_WRITE",
                "DATASET_READ",
                "DATASET_WRITE",
                "DATASET_DELETE",
                "POOL_READ",
                "POOL_WRITE",
                "SHARING_ADMIN",
                "SHARING_SMB_WRITE",
                "SHARING_NFS_WRITE",
                "SNAPSHOT_WRITE",
                "SNAPSHOT_DELETE",
                "SYSTEM_GENERAL_WRITE",
                "VIRT_INSTANCE_WRITE",
            ]
        },
        "allowlist": [{"method": "*", "resource": "*"}],
        "web_shell": True,
    },
    "account_attributes": ["LOCAL", "API_KEY"],
}

READONLY_ME: dict[str, object] = {
    "pw_name": "auditor",
    "pw_uid": 3001,
    "pw_gid": 3001,
    "privilege": {
        "roles": {
            "$set": [
                "READONLY_ADMIN",
                "ACCOUNT_READ",
                "ALERT_LIST_READ",
                "ALERT_READ",
                "APPS_READ",
                "CLOUD_SYNC_READ",
                "DATASET_READ",
                "POOL_READ",
                "POOL_SCRUB_READ",
                "REPLICATION_TASK_READ",
                "SERVICE_READ",
                "SHARING_READ",
                "SHARING_SMB_READ",
                "SHARING_NFS_READ",
                "SHARING_ISCSI_READ",
                "SNAPSHOT_READ",
                "SNAPSHOT_TASK_READ",
                "SYSTEM_ADVANCED_READ",
                "SYSTEM_GENERAL_READ",
                "VIRT_INSTANCE_READ",
            ]
        },
        "allowlist": [],
        "web_shell": False,
    },
    "account_attributes": ["LOCAL", "API_KEY"],
}


def roles_of(me: dict[str, object]) -> set[str]:
    privilege = me.get("privilege")
    if not isinstance(privilege, dict):
        return set()
    roles = privilege.get("roles")
    if isinstance(roles, dict):
        roles = roles.get("$set")
    return {str(role) for role in roles or []}


ADMIN_ROLES = roles_of(ADMIN_ME)
READONLY_ROLES = roles_of(READONLY_ME)

# Which role lets a key make each write. Mirror of the app's
# lib/features/truenas/domain/truenas_capability.dart, read from the same
# @api_method roles at TS-25.10.0.
WRITE_AREAS: dict[str, set[str]] = {
    "alert.dismiss": {"ALERT_LIST_WRITE"},
    "app.start": {"APPS_WRITE"},
    "app.stop": {"APPS_WRITE"},
    "app.upgrade": {"APPS_WRITE"},
    "app.delete": {"APPS_WRITE"},
    "user.create": {"ACCOUNT_WRITE"},
    "user.delete": {"ACCOUNT_WRITE"},
    "group.create": {"ACCOUNT_WRITE"},
    "group.delete": {"ACCOUNT_WRITE"},
    "iscsi.target.delete": {"SHARING_ISCSI_TARGET_WRITE"},
    "sharing.smb.create": {"SHARING_SMB_WRITE"},
    "sharing.smb.update": {"SHARING_SMB_WRITE"},
    "sharing.smb.delete": {"SHARING_SMB_WRITE"},
    "sharing.nfs.create": {"SHARING_NFS_WRITE"},
    "sharing.nfs.update": {"SHARING_NFS_WRITE"},
    "sharing.nfs.delete": {"SHARING_NFS_WRITE"},
    "pool.dataset.create": {"DATASET_WRITE"},
    "pool.dataset.update": {"DATASET_WRITE"},
    "pool.dataset.delete": {"DATASET_DELETE"},
    "zfs.snapshot.create": {"SNAPSHOT_WRITE"},
    "pool.snapshot.create": {"SNAPSHOT_WRITE"},
    "zfs.snapshot.delete": {"SNAPSHOT_DELETE"},
    "pool.snapshot.delete": {"SNAPSHOT_DELETE"},
    "pool.scrub.scrub": {"POOL_WRITE"},
    "pool.scrub.run": {"POOL_WRITE"},
    "pool.scrub.update": {"POOL_SCRUB_WRITE"},
    "pool.scrub.delete": {"POOL_SCRUB_WRITE"},
    "pool.snapshottask.run": {"SNAPSHOT_TASK_WRITE"},
    "pool.snapshottask.update": {"SNAPSHOT_TASK_WRITE"},
    "pool.snapshottask.delete": {"SNAPSHOT_TASK_WRITE"},
    "virt.instance.start": {"VIRT_INSTANCE_WRITE"},
    "virt.instance.stop": {"VIRT_INSTANCE_WRITE"},
    "virt.instance.restart": {"VIRT_INSTANCE_WRITE"},
    "virt.instance.create": {"VIRT_INSTANCE_WRITE"},
    "virt.instance.delete": {"VIRT_INSTANCE_WRITE"},
    "system.general.update": {"SYSTEM_GENERAL_WRITE"},
    "system.advanced.update": {"SYSTEM_ADVANCED_WRITE"},
    "mail.update": {"ALERT_WRITE"},
    "mail.send": {"MAIL_WRITE"},
    "system.reboot": {"FULL_ADMIN"},
    "system.shutdown": {"FULL_ADMIN"},
}

# service.* checks twice: the method role, then the service's own privilege.
SERVICE_SHARING_ROLES = {
    "cifs": "SHARING_SMB_WRITE",
    "nfs": "SHARING_NFS_WRITE",
    "iscsitarget": "SHARING_ISCSI_WRITE",
    "ftp": "SHARING_FTP_WRITE",
}

SCRUB_SECONDS = 30.0


class RpcError(Exception):
    """A JSON-RPC error frame, shaped like the middleware's own."""

    def __init__(self, reason: str, *, errno: int = 22, errname: str = "EINVAL"):
        super().__init__(reason)
        self.reason = reason
        self.errno = errno
        self.errname = errname

    def envelope(self) -> dict[str, object]:
        return {
            "code": -32001,
            "message": "Method call error",
            "data": {
                "error": self.errno,
                "errname": self.errname,
                "reason": self.reason,
                "trace": None,
                "extra": None,
            },
        }


def not_authorized() -> RpcError:
    # test/fixtures/truenas/rpc_error_eacces.json
    return RpcError("[EACCES] Not authorized", errno=13, errname="EACCES")


def no_service_privilege() -> RpcError:
    # test/fixtures/truenas/rpc_error_eperm_service.json
    return RpcError(
        "[EPERM] You do not have permission to modify this service",
        errno=1,
        errname="EPERM",
    )


def not_found(what: str) -> RpcError:
    return RpcError(f"[ENOENT] {what} not found", errno=2, errname="ENOENT")


def invalid(reason: str) -> RpcError:
    return RpcError(f"[EINVAL] {reason}")


class Job:
    """One running (or finished) middleware job, advanced by the clock."""

    def __init__(
        self,
        job_id: int,
        method: str,
        duration: float,
        description: str,
        result: object = None,
    ):
        self.id = job_id
        self.method = method
        self.duration = duration
        self.description = description
        self.result = result
        self.started = time.monotonic()
        self.started_wall = time.time()
        self.finished: float | None = None
        self.finished_wall: float | None = None
        self.state = "RUNNING"
        self.percent = 0.0
        self.error: str | None = None
        self.on_done = None
        self.on_abort = None

    def elapsed(self) -> float:
        end = self.finished if self.finished is not None else time.monotonic()
        return max(0.0, end - self.started)

    def finish(self, state: str) -> None:
        self.state = state
        self.finished = time.monotonic()
        self.finished_wall = time.time()

    def to_json(self) -> dict[str, object]:
        return {
            "id": self.id,
            "method": self.method,
            "description": self.description,
            "state": self.state,
            "progress": {
                "percent": self.percent,
                "description": self.description,
            },
            "result": self.result,
            "error": self.error,
            "time_started": {"$date": int(self.started_wall * 1000)},
            "time_finished": (
                None
                if self.finished_wall is None
                else {"$date": int(self.finished_wall * 1000)}
            ),
        }


def _ms(value: str) -> int:
    """A fixed instant, in the ``{"$date": ms}`` shape the middleware uses."""
    from datetime import datetime, timezone

    parsed = datetime.fromisoformat(value).replace(tzinfo=timezone.utc)
    return int(parsed.timestamp() * 1000)


def _human(size: int) -> str:
    value = float(size)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024 or unit == "TiB":
            return f"{value:.2f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024
    return f"{value:.2f} TiB"


def _prop(value: object) -> dict[str, object]:
    """A ZFS property object as the middleware serialises it."""
    if isinstance(value, int):
        return {"value": _human(value), "rawvalue": str(value), "parsed": value}
    return {"value": str(value)}


def build_world() -> dict[str, object]:
    """The world the simulator starts in, built from the testlab's own.

    Provenance, so this is a house and not a fixture bag:

    * the datasets carry the folders the arr instances in
      ``docker-compose.testlab.yml`` mount as ``/media`` and the seed fills:
      ``/mnt/tank/media/{movies,series,music,books}`` (``seed_lab.py``);
    * ``anna`` and ``luca`` are the household of World A, the accounts Seerr
      requests are made by (``world.dart``, ``WorldPeople``);
    * ``cupola`` is the media service account the shares authenticate as;
    * ``auditor`` is the read-only user behind ``test-readonly``;
    * ``jellyfin`` and ``plex`` are the two media servers of the lab as apps,
      and ``cupola-vm`` mirrors the VM the Unraid fixture reports, so the two
      servers agree about the house;
    * ``tank`` is the healthy pool the media live on; ``backup`` is a mirror
      with a failed leg, the amber fault the storage surfaces exist to show.

    Every figure is fixed so the fixtures in ``test/fixtures/truenas`` compare
    exactly; only jobs, scrub progress and the power state move.
    """
    tank_size = 21_990_232_555_520
    tank_allocated = 7_516_192_771_840
    backup_size = 3_995_116_290_048
    backup_allocated = 996_432_543_744
    scan_end = _ms("2026-10-21T03:14:00")
    alert_time = _ms("2026-10-22T07:41:00")

    return {
        "system": {
            "hostname": "nas",
            "version": "TrueNAS-SCALE-25.10.2.1",
            "cores": 8,
            "physmem": 17_179_869_184,
            "loadavg": [0.42, 0.31, 0.27],
            "model": "Supermicro X11SCH-F",
            "system_product": "Cupola NAS",
            "system_serial": "CUPOLA0001",
        },
        "pools": [
            {
                "id": 1,
                "name": "tank",
                "status": "ONLINE",
                "healthy": True,
                "size": tank_size,
                "allocated": tank_allocated,
                "free": tank_size - tank_allocated,
                "path": "/mnt/tank",
                "topology": {
                    "data": [
                        {
                            "type": "RAIDZ2",
                            "status": "ONLINE",
                            "children": [
                                {"disk": f"sd{letter}", "status": "ONLINE"}
                                for letter in ("a", "b", "c", "d", "e", "f")
                            ],
                        }
                    ],
                    "cache": [],
                    "log": [],
                    "spare": [],
                },
                "scan": {
                    "function": "SCRUB",
                    "state": "FINISHED",
                    "percentage": 100.0,
                    "bytes_processed": tank_size,
                    "total_secs_left": None,
                    "end_time": {"$date": scan_end},
                },
                "scrub_job": None,
            },
            {
                "id": 2,
                "name": "backup",
                "status": "DEGRADED",
                "healthy": False,
                "size": backup_size,
                "allocated": backup_allocated,
                "free": backup_size - backup_allocated,
                "path": "/mnt/backup",
                "topology": {
                    "data": [
                        {
                            "type": "MIRROR",
                            "status": "DEGRADED",
                            "children": [
                                {"disk": "sdg", "status": "ONLINE"},
                                {
                                    "disk": "sdh",
                                    "status": "FAULTED",
                                    "stats": {
                                        "read_errors": 0,
                                        "write_errors": 0,
                                        "checksum_errors": 8,
                                    },
                                },
                            ],
                        }
                    ],
                    "cache": [],
                    "log": [],
                    "spare": [],
                },
                "scan": None,
                "scrub_job": None,
            },
        ],
        "datasets": {
            "tank": {
                "id": "tank",
                "pool": "tank",
                "type": "FILESYSTEM",
                "mountpoint": "/mnt/tank",
                "used": 6_442_450_944,
                "available": 14_474_039_281_664,
                "compression": "LZ4",
                "compressratio": "1.02x",
                "recordsize": "128K",
                "comments": "Cupola lab",
            },
            "tank/media": {
                "id": "tank/media",
                "pool": "tank",
                "type": "FILESYSTEM",
                "mountpoint": "/mnt/tank/media",
                "used": 7_412_345_667_584,
                "available": 14_474_039_281_664,
                "compression": "LZ4",
                "compressratio": "1.00x",
                "recordsize": "1M",
                "comments": "Films, series, music, books",
            },
            "tank/media/movies": {
                "id": "tank/media/movies",
                "pool": "tank",
                "type": "FILESYSTEM",
                "mountpoint": "/mnt/tank/media/movies",
                "used": 3_298_534_883_328,
                "available": 14_474_039_281_664,
                "compression": "LZ4",
                "compressratio": "1.00x",
                "recordsize": "1M",
                "comments": "Radarr",
            },
            "tank/media/series": {
                "id": "tank/media/series",
                "pool": "tank",
                "type": "FILESYSTEM",
                "mountpoint": "/mnt/tank/media/series",
                "used": 3_298_534_883_328,
                "available": 14_474_039_281_664,
                "compression": "LZ4",
                "compressratio": "1.00x",
                "recordsize": "1M",
                "comments": "Sonarr",
            },
            "tank/media/music": {
                "id": "tank/media/music",
                "pool": "tank",
                "type": "FILESYSTEM",
                "mountpoint": "/mnt/tank/media/music",
                "used": 601_295_421_440,
                "available": 14_474_039_281_664,
                "compression": "ZSTD",
                "compressratio": "1.04x",
                "recordsize": "128K",
                "comments": "Lidarr",
            },
            "tank/media/books": {
                "id": "tank/media/books",
                "pool": "tank",
                "type": "FILESYSTEM",
                "mountpoint": "/mnt/tank/media/books",
                "used": 214_748_364_800,
                "available": 14_474_039_281_664,
                "compression": "ZSTD",
                "compressratio": "1.11x",
                "recordsize": "128K",
                "comments": "Readarr",
            },
            "tank/downloads": {
                "id": "tank/downloads",
                "pool": "tank",
                "type": "FILESYSTEM",
                "mountpoint": "/mnt/tank/downloads",
                "used": 42_949_672_960,
                "available": 14_474_039_281_664,
                "compression": "LZ4",
                "compressratio": "1.00x",
                "recordsize": "1M",
                "comments": "qBittorrent, Transmission, SABnzbd, NZBGet",
            },
            "tank/apps": {
                "id": "tank/apps",
                "pool": "tank",
                "type": "FILESYSTEM",
                "mountpoint": "/mnt/tank/apps",
                "used": 68_719_476_736,
                "available": 14_474_039_281_664,
                "compression": "LZ4",
                "compressratio": "1.00x",
                "recordsize": "128K",
                "comments": "App storage",
            },
            "tank/virt": {
                "id": "tank/virt",
                "pool": "tank",
                "type": "FILESYSTEM",
                "mountpoint": "/mnt/tank/virt",
                "used": 107_374_182_400,
                "available": 14_474_039_281_664,
                "compression": "LZ4",
                "compressratio": "1.00x",
                "recordsize": "128K",
                "comments": "Incus instances",
            },
            "backup": {
                "id": "backup",
                "pool": "backup",
                "type": "FILESYSTEM",
                "mountpoint": "/mnt/backup",
                "used": 996_432_543_744,
                "available": 2_998_683_746_304,
                "compression": "ZSTD",
                "compressratio": "1.00x",
                "recordsize": "1M",
                "comments": "Copies",
            },
            "backup/copies": {
                "id": "backup/copies",
                "pool": "backup",
                "type": "FILESYSTEM",
                "mountpoint": "/mnt/backup/copies",
                "used": 996_432_543_744,
                "available": 2_998_683_746_304,
                "compression": "ZSTD",
                "compressratio": "1.00x",
                "recordsize": "128K",
                "comments": "Weekly copies",
            },
        },
        "snapshots": [
            {
                "id": "tank/media@manual-2026-10-20",
                "dataset": "tank/media",
                "snapshot_name": "manual-2026-10-20",
                "name": "tank/media@manual-2026-10-20",
                "creation": _ms("2026-10-20T18:02:00"),
                "used": 0,
                "referenced": 7_412_345_667_584,
            },
            {
                "id": "tank/media@auto-daily-2026-10-21",
                "dataset": "tank/media",
                "snapshot_name": "auto-daily-2026-10-21",
                "name": "tank/media@auto-daily-2026-10-21",
                "creation": _ms("2026-10-21T04:00:00"),
                "used": 12_884_901_888,
                "referenced": 7_412_345_667_584,
            },
        ],
        "smb_shares": [
            {
                "id": 1,
                "name": "media",
                "path": "/mnt/tank/media",
                "enabled": True,
                "comment": "Films, series, music, books",
                "ro": False,
                "purpose": "DEFAULT_SHARE",
            },
            {
                "id": 2,
                "name": "downloads",
                "path": "/mnt/tank/downloads",
                "enabled": True,
                "comment": None,
                "ro": False,
                "purpose": "DEFAULT_SHARE",
            },
            {
                "id": 3,
                "name": "scratch",
                "path": "/mnt/tank/scratch",
                "enabled": False,
                "comment": "Temporary",
                "ro": True,
                "purpose": "DEFAULT_SHARE",
            },
        ],
        "nfs_shares": [
            {
                "id": 1,
                "paths": ["/mnt/tank/media/movies"],
                "enabled": True,
                "comment": "Films",
                "ro": False,
                "networks": ["192.168.1.0/24"],
                "hosts": [],
            },
            {
                "id": 2,
                "paths": ["/mnt/tank/media/series"],
                "enabled": True,
                "comment": None,
                "ro": False,
                "networks": [],
                "hosts": ["192.168.1.20"],
            },
        ],
        "iscsi_targets": [
            {
                "id": 1,
                "name": "iqn.2005-10.org.freenas.ctl:cupola",
                "alias": "Cupola",
                "mode": "ISCSI",
            }
        ],
        "users": [
            {
                "id": 950,
                "uid": 950,
                "username": "truenas_admin",
                "full_name": "Local Administrator",
                "builtin": False,
                "locked": False,
                "shell": "/usr/bin/zsh",
                "smb": False,
            },
            {
                "id": 1000,
                "uid": 1000,
                "username": "media",
                "full_name": "Media service account",
                "builtin": True,
                "locked": True,
                "shell": "/usr/sbin/nologin",
                "smb": False,
            },
            {
                "id": 3000,
                "uid": 3000,
                "username": "cupola",
                "full_name": "Cupola",
                "builtin": False,
                "locked": False,
                "shell": "/usr/sbin/nologin",
                "smb": True,
            },
            {
                "id": 3001,
                "uid": 3001,
                "username": "auditor",
                "full_name": "Read-only auditor",
                "builtin": False,
                "locked": False,
                "shell": "/usr/sbin/nologin",
                "smb": False,
            },
            {
                "id": 3002,
                "uid": 3002,
                "username": "anna",
                "full_name": "Anna",
                "builtin": False,
                "locked": False,
                "shell": "/usr/sbin/nologin",
                "smb": True,
            },
            {
                "id": 3003,
                "uid": 3003,
                "username": "luca",
                "full_name": "Luca",
                "builtin": False,
                "locked": False,
                "shell": "/usr/sbin/nologin",
                "smb": True,
            },
        ],
        "groups": [
            {"id": 950, "gid": 950, "name": "truenas_admin", "builtin": False},
            {"id": 1000, "gid": 1000, "name": "media", "builtin": False},
            {"id": 3000, "gid": 3000, "name": "cupola", "builtin": False},
            {"id": 3001, "gid": 3001, "name": "auditor", "builtin": False},
            {"id": 41, "gid": 41, "name": "wheel", "builtin": True},
            {"id": 4, "gid": 4, "name": "adm", "builtin": True},
        ],
        "group_members": {
            "truenas_admin": ["truenas_admin"],
            "cupola": ["cupola"],
            "auditor": ["auditor"],
            "media": ["cupola", "anna", "luca"],
            "wheel": ["truenas_admin"],
            "adm": [],
        },
        "services": [
            {"id": 1, "service": "cifs", "state": "RUNNING", "enable": True},
            {"id": 2, "service": "nfs", "state": "STOPPED", "enable": True},
            {"id": 3, "service": "ssh", "state": "RUNNING", "enable": False},
            {"id": 4, "service": "iscsitarget", "state": "STOPPED", "enable": False},
            {"id": 5, "service": "smartd", "state": "RUNNING", "enable": True},
            {"id": 6, "service": "ftp", "state": "STOPPED", "enable": False},
        ],
        "apps": [
            {
                "name": "jellyfin",
                "state": "RUNNING",
                "version": "1.2.4",
                "human_version": "10.10.6",
                "upgrade_available": False,
                "metadata": {
                    "title": "Jellyfin",
                    "train": "community",
                    "version": "1.2.4",
                },
                "portals": {"Web UI": "https://nas.home.arpa:8096"},
            },
            {
                "name": "immich",
                "state": "STOPPED",
                "version": "1.119.0",
                "human_version": "v1.119.0",
                "upgrade_available": False,
                "metadata": {
                    "title": "Immich",
                    "train": "community",
                    "version": "1.119.0",
                },
                "portals": {"Web UI": "https://nas.home.arpa:2283"},
            },
            {
                "name": "paperless",
                "state": "CRASHED",
                "version": "2.14.7",
                "human_version": "2.14.7",
                "upgrade_available": False,
                "metadata": {
                    "title": "Paperless-ngx",
                    "train": "community",
                    "version": "2.14.7",
                },
                "portals": {"Web UI": "https://nas.home.arpa:8000"},
            },
        ],
        "virt_global": {
            "pool": "tank",
            "dataset": "tank/virt",
            "state": "INITIALIZED",
            "bridge": "br0",
        },
        "virt_instances": [
            {
                "id": "cupola-vm",
                "name": "cupola-vm",
                "type": "VM",
                "status": "STOPPED",
                "cpu": 2,
                "memory": 4_294_967_296,
                "autostart": False,
                "image": {"os": "Debian", "release": "13"},
            },
            {
                "id": "devbox",
                "name": "devbox",
                "type": "CONTAINER",
                "status": "RUNNING",
                "cpu": 1,
                "memory": 1_073_741_824,
                "autostart": True,
                "image": {"os": "Alpine", "release": "3.21"},
            },
        ],
        "virt_devices": {
            "cupola-vm": [
                {
                    "name": "root",
                    "dev_type": "DISK",
                    "source": "tank/virt/cupola-vm",
                },
                {"name": "eth0", "dev_type": "NIC", "nic_type": "VIRTIO"},
            ],
            "devbox": [{"name": "eth0", "dev_type": "NIC", "nic_type": "VIRTIO"}],
        },
        "alerts": [
            {
                "uuid": "alert-smart-sdh",
                "level": "CRITICAL",
                "klass": "SMART",
                "dismissed": False,
                "datetime": {"$date": alert_time},
                "formatted": "8 uncorrectable errors reported for sdh (ZL2PQR7T).",
                "text": "8 uncorrectable errors reported for sdh (ZL2PQR7T).",
                "args": {
                    "ue": 8,
                    "name": "sdh",
                    "serial": "ZL2PQR7T",
                    "message": (
                        "Device: /dev/sdh [SAT], 8 Currently unreadable "
                        "(pending) sectors"
                    ),
                },
            },
            {
                "uuid": "alert-backup-degraded",
                "level": "WARNING",
                "klass": "VolumeStatus",
                "dismissed": False,
                "datetime": {"$date": alert_time + 60_000},
                "formatted": (
                    "Pool backup state is DEGRADED: One or more devices could "
                    "not be used. Sufficient replicas exist for the pool to "
                    "continue functioning in a degraded state."
                ),
                "args": {"volume": "backup", "state": "DEGRADED"},
            },
            {
                "uuid": "alert-update-available",
                "level": "INFO",
                "klass": "UpdateAvailable",
                "dismissed": False,
                "datetime": {"$date": alert_time + 120_000},
                "formatted": "A new update is available: 25.10.2.2",
                "args": {"version": "25.10.2.2"},
            },
        ],
        "update": {
            "status": "UNAVAILABLE",
            "version": "25.10.2.1",
            "release": {"name": "25.10.2.1"},
            "notice": None,
            "changelog": None,
        },
        "scrub_tasks": [
            {
                "id": 1,
                "pool_name": "tank",
                "pool": 1,
                "threshold": 35,
                "description": "",
                "enabled": True,
            },
            {
                "id": 2,
                "pool_name": "backup",
                "pool": 2,
                "threshold": 35,
                "description": "",
                "enabled": True,
            },
        ],
        "snapshot_tasks": [
            {
                "id": 1,
                "dataset": "tank/media",
                "recursive": True,
                "naming_schema": "auto-%Y-%m-%d_%H-%M",
                "enabled": True,
                "keep_policy": "WEEKLY",
                "lifetime_value": 4,
                "lifetime_unit": "WEEK",
            }
        ],
        "general_config": {
            "hostname": "nas",
            "domain": "home.arpa",
            "hostname_local": "nas",
            "hostname_virtual_host": "nas",
            "hostname_b": "nas",
            "kbdmap": "it",
            "timezone": "Europe/Rome",
            "ui_port": 80,
            "ui_httpsport": 443,
            "ui_httpsredirect": False,
            "ui_httpsprotocols": ["HTTP1", "HTTP2"],
            "ui_address": ["0.0.0.0"],
            "ui_v6address": ["::"],
            "ui_certificate": 1,
        },
        "advanced_config": {
            "autotune": False,
            "debugkernel": False,
            "consolemenu": False,
            "serialconsole": False,
            "serialport": "ttyS0",
            "serialspeed": "9600",
            "powerdaemon": True,
            "isolated_gpu_pci_ids": [],
            "boot_scrub": 7,
            "sysloglevel": "NOTICE",
            "syslogserver": None,
            "kernel_extra_options": "",
            "zfs_arc_max": 0,
        },
        "mail_config": {
            "fromemail": "nas@home.arpa",
            "fromname": "Cupola NAS",
            "outgoingserver": "",
            "port": 25,
            "security": "PLAIN",
            "smtp": False,
            "user": "",
        },
        "ntp_servers": [
            {"id": 1, "address": "0.pool.ntp.org", "burst": False, "iburst": True},
            {"id": 2, "address": "1.pool.ntp.org", "burst": False, "iburst": True},
        ],
        "certificates": [
            {
                "id": 1,
                "name": "cupola-lab",
                "cert_type": "SELF_SIGNED",
                "certificate": {"common_name": "nas.home.arpa"},
                "certificate_issuer": "cupola-lab",
                "from": "2025-10-01",
                "until": "2035-10-01",
                "digest_algorithm": "SHA256",
                "san": ["DNS:nas.home.arpa", "IP:127.0.0.1"],
            }
        ],
        "alert_services": [],
        "interfaces": [
            {
                "id": "enp1s0",
                "name": "enp1s0",
                "type": "PHYSICAL",
                "state": {
                    "link_state": "LINK_STATE_UP",
                    "link_address": "b4:2e:99:11:22:33",
                    "aliases": [
                        {"type": "INET", "address": "192.168.1.10", "netmask": 24},
                        {"type": "INET6", "address": "fe80::1", "netmask": 64},
                    ],
                },
            }
        ],
        "network_config": {
            "hostname": "nas",
            "domain": "home.arpa",
            "ipv4gateway": "192.168.1.1",
            "ipv6gateway": "",
            "nameserver1": "192.168.1.1",
            "nameserver2": "1.1.1.1",
            "nameserver3": "",
        },
    }


# The charts the app asks for, with a legend and a deterministic series each.
REPORTING = {
    "cpu": (["time", "cpu"], lambda i: round(11.5 + 4.0 * math.sin(i / 5.0), 2)),
    "memory": (
        ["time", "available"],
        lambda i: round(
            12_884_901_888 + 402_653_184 * math.sin(i / 7.0),
            2,
        ),
    ),
    "arcsize": (
        ["time", "size"],
        lambda i: round(3_221_225_472 + 134_217_728 * math.cos(i / 9.0), 2),
    ),
    "interface": (
        ["time", "received", "sent"],
        lambda i: round(1_048_576 + 524_288 * math.sin(i / 4.0), 2),
    ),
}


def _matches(row: dict[str, object], filters: object) -> bool:
    if not isinstance(filters, list):
        return True
    for item in filters:
        if not isinstance(item, (list, tuple)) or len(item) < 2:
            continue
        field, op = str(item[0]), str(item[1])
        value = item[2] if len(item) > 2 else None
        current = row.get(field)
        if op == "=" and current != value:
            if str(current) != str(value):
                return False
        elif op == "!=" and (current == value or str(current) == str(value)):
            return False
        elif op == "in" and current not in (value or []):
            return False
        elif op == "nin" and current in (value or []):
            return False
    return True


class TrueNasState:
    """The in-memory NAS: one world, mutated by the RPCs the app sends."""

    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.sockets: set[socket.socket] = set()
        self.world: dict[str, object] = {}
        self.jobs: list[Job] = []
        self.next_job = 101
        self.power = "on"
        self.booted_at: float | None = None
        self.scenario: str | None = None
        self.reset()

    # -- world lifecycle ---------------------------------------------------

    def reset(self, *, mark: str | None = None) -> None:
        with self.lock:
            self.world = build_world()
            self.jobs = []
            self.next_job = 101
            self.power = "on"
            self.booted_at = None
            self.scenario = mark

    def world_digest(self) -> str:
        """A stable digest of the world, so a reset can be proven byte-identical."""
        encoded = json.dumps(
            self.world, sort_keys=True, separators=(",", ":"), default=str
        )
        return hashlib.sha256(encoded.encode("utf-8")).hexdigest()

    def apply_scenario(self, name: str | None) -> None:
        """The state the infrastructure flows start from (catalogue I-09..I-15).

        The world is the house as it is; this is the house on the morning the
        flows run: an update is waiting, Jellyfin has one to install, no scrub
        is in flight, and the alert queue holds the two faults the storage
        surfaces exist to explain plus the update notice that dismisses.
        """
        with self.lock:
            self.scenario = name
            if name != "truenas-state":
                return
            self.world["update"] = {
                "status": "AVAILABLE",
                "version": "25.10.2.2",
                "release": {"name": "25.10.2.2"},
                "notice": None,
                "changelog": None,
            }
            for app in self.world["apps"]:
                if app["name"] == "jellyfin":
                    app["upgrade_available"] = True
            for pool in self.world["pools"]:
                pool["scrub_job"] = None

    def state_summary(self) -> dict[str, object]:
        with self.lock:
            self.tick()
            return {
                "power": self.power,
                "scenario": self.scenario,
                "hostname": self.world["system"]["hostname"],
                "worldDigest": self.world_digest(),
                "pools": [
                    {
                        "name": pool["name"],
                        "status": pool["status"],
                        "healthy": pool["healthy"],
                        "scan": (self._pool_scan(pool) or {}).get("state"),
                    }
                    for pool in self.world["pools"]
                ],
                "datasets": sorted(self.world["datasets"]),
                "snapshots": sorted(row["id"] for row in self.world["snapshots"]),
                "smb": sorted(row["name"] for row in self.world["smb_shares"]),
                "nfs": sorted(row["id"] for row in self.world["nfs_shares"]),
                "users": sorted(row["username"] for row in self.world["users"]),
                "groups": sorted(row["name"] for row in self.world["groups"]),
                "services": {
                    row["service"]: row["state"] for row in self.world["services"]
                },
                "apps": {
                    row["name"]: row["state"] for row in self.world["apps"]
                },
                "virt": {
                    row["name"]: row["status"]
                    for row in self.world["virt_instances"]
                },
                "alerts": {
                    row["uuid"]: row["dismissed"]
                    for row in self.world["alerts"]
                },
                "update": self.world["update"]["status"],
                "upgradable": [
                    app["name"]
                    for app in self.world["apps"]
                    if app["upgrade_available"]
                ],
                "jobs": [
                    {"id": job.id, "method": job.method, "state": job.state}
                    for job in self.jobs
                ],
                "keys": {
                    "admin": sorted(ADMIN_ROLES),
                    "readonly": sorted(READONLY_ROLES),
                },
            }

    def power_on(self) -> None:
        with self.lock:
            self.power = "on"
            self.booted_at = time.monotonic()
            for job in self.jobs:
                if job.state == "RUNNING":
                    job.finish("ABORTED")
                    job.error = "Job was interrupted by a restart"
            for pool in self.world["pools"]:
                pool["scrub_job"] = None
            for app in self.world["apps"]:
                app["state"] = {
                    "DEPLOYING": "RUNNING",
                    "STOPPING": "STOPPED",
                }.get(app["state"], app["state"])
            for instance in self.world["virt_instances"]:
                instance["status"] = {
                    "STARTING": "RUNNING",
                    "STOPPING": "STOPPED",
                    "RESTARTING": "RUNNING",
                }.get(instance["status"], instance["status"])

    def register(self, sock: socket.socket) -> None:
        with self.lock:
            self.sockets.add(sock)

    def unregister(self, sock: socket.socket) -> None:
        with self.lock:
            self.sockets.discard(sock)

    def cut_power(self, action: str) -> None:
        """Drop every live socket, the way the middleware dies under a reboot."""
        with self.lock:
            self.power = "rebooting" if action == "reboot" else "shutdown"
            sockets = list(self.sockets)
        for sock in sockets:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

    # -- jobs --------------------------------------------------------------

    def new_job(
        self,
        method: str,
        duration: float,
        description: str,
        result: object = None,
    ) -> Job:
        job = Job(self.next_job, method, duration, description, result)
        self.next_job += 1
        self.jobs.append(job)
        if len(self.jobs) > 40:
            self.jobs = self.jobs[-40:]
        return job

    def tick(self) -> None:
        now = time.monotonic()
        for job in self.jobs:
            if job.state != "RUNNING":
                continue
            elapsed = now - job.started
            if elapsed >= job.duration:
                job.percent = 100.0
                job.finish("SUCCESS")
                if job.on_done is not None:
                    job.on_done()
            else:
                job.percent = round(100.0 * elapsed / job.duration, 1)

    # -- authorization -----------------------------------------------------

    def authorize(self, role: str | None, method: str, params: list) -> None:
        """Refuses a write this key's user may not make, as the server does."""
        if method in {"auth.me", "auth.login_with_api_key", "core.ping"}:
            return
        if role is None:
            raise not_authorized()
        if method.startswith("service.") and method in {
            "service.start",
            "service.stop",
            "service.update",
        }:
            name = str(params[0]) if params else ""
            if not self._may_write_service(name, role):
                raise no_service_privilege()
            return
        areas = WRITE_AREAS.get(method)
        if areas is None:
            return
        roles = ADMIN_ROLES if role == "admin" else READONLY_ROLES
        if "FULL_ADMIN" in roles or roles & areas:
            return
        raise not_authorized()

    @staticmethod
    def _may_write_service(service: str, role: str) -> bool:
        roles = ADMIN_ROLES if role == "admin" else READONLY_ROLES
        if "FULL_ADMIN" in roles:
            return True
        sharing = SERVICE_SHARING_ROLES.get(service)
        if sharing is not None and sharing in roles:
            return True
        # 25.10 checks SERVICE_WRITE here; the read-only user holds none.
        return "SERVICE_WRITE" in roles

    # -- lookups -----------------------------------------------------------

    def _pool(self, name: str) -> dict[str, object]:
        for pool in self.world["pools"]:
            if pool["name"] == name:
                return pool
        raise not_found(f"Pool {name}")

    def _app(self, name: str) -> dict[str, object]:
        for app in self.world["apps"]:
            if app["name"] == name:
                return app
        raise not_found(f"App {name}")

    def _instance(self, name: str) -> dict[str, object]:
        for instance in self.world["virt_instances"]:
            if instance["id"] == name:
                return instance
        raise not_found(f"Instance {name}")

    def _service(self, name: str) -> dict[str, object]:
        for service in self.world["services"]:
            if service["service"] == name:
                return service
        raise not_found(f"Service {name}")

    # -- rows --------------------------------------------------------------

    def _pool_scan(self, pool: dict[str, object]) -> dict[str, object] | None:
        job_id = pool.get("scrub_job")
        if job_id is not None:
            for job in self.jobs:
                if job.id == job_id and job.state == "RUNNING":
                    left = max(0.0, job.duration - (time.monotonic() - job.started))
                    return {
                        "function": "SCRUB",
                        "state": "SCANNING",
                        "percentage": job.percent,
                        "bytes_processed": int(
                            int(pool["size"]) * job.percent / 100.0
                        ),
                        "total_secs_left": int(left),
                        "end_time": None,
                    }
        scan = pool.get("scan")
        return scan if isinstance(scan, dict) else None

    def pool_row(
        self, pool: dict[str, object], *, with_topology: bool
    ) -> dict[str, object]:
        row: dict[str, object] = {
            "id": pool["id"],
            "name": pool["name"],
            "guid": f"1{pool['id']:015d}",
            "status": pool["status"],
            "healthy": pool["healthy"],
            "path": pool["path"],
            "size": pool["size"],
            "allocated": pool["allocated"],
            "free": pool["free"],
            "encrypt": 0,
        }
        scan = self._pool_scan(pool)
        if scan is not None:
            row["scan"] = scan
        if with_topology:
            row["topology"] = pool["topology"]
        return row

    def dataset_row(
        self, dataset: dict[str, object], *, children: list | None = None
    ) -> dict[str, object]:
        row: dict[str, object] = {
            "id": dataset["id"],
            "name": dataset["id"],
            "pool": dataset["pool"],
            "type": dataset["type"],
            "mountpoint": dataset.get("mountpoint"),
            "encrypted": False,
            "used": _prop(int(dataset["used"])),
            "available": _prop(int(dataset["available"])),
            "quota": _prop(0),
            "refquota": _prop(0),
            "compression": _prop(dataset.get("compression", "LZ4")),
            "compressratio": _prop(dataset.get("compressratio", "1.00x")),
            "recordsize": _prop(dataset.get("recordsize", "128K")),
            "deduplication": _prop("OFF"),
            "comments": _prop(dataset.get("comments", "")),
        }
        if dataset["type"] == "VOLUME":
            row["volsize"] = _prop(int(dataset.get("volsize", 0)))
        if children is not None:
            row["children"] = children
        return row

    def snapshot_row(self, snapshot: dict[str, object]) -> dict[str, object]:
        return {
            "id": snapshot["id"],
            "name": snapshot["name"],
            "snapshot_name": snapshot["snapshot_name"],
            "dataset": snapshot["dataset"],
            "type": "SNAPSHOT",
            "properties": {
                "creation": {"parsed": {"$date": snapshot["creation"]}},
                "used": _prop(int(snapshot["used"])),
                "referenced": _prop(int(snapshot["referenced"])),
            },
        }

    def _dataset_tree(self, root: str) -> list[dict[str, object]]:
        datasets = self.world["datasets"]

        def build(identifier: str) -> dict[str, object]:
            kids = [
                build(child)
                for child in sorted(datasets)
                if child != identifier
                and child.rsplit("/", 1)[0] == identifier
            ]
            return self.dataset_row(datasets[identifier], children=kids)

        return [build(root)] if root in datasets else []

    # -- dispatch ----------------------------------------------------------

    def dispatch(
        self, role: str | None, method: str, params: list
    ) -> object:
        """Answers one RPC. Writes authorize first, then mutate the world."""
        if method == "auth.me":
            if role is None:
                raise not_authorized()
            return ADMIN_ME if role == "admin" else READONLY_ME
        if method == "core.ping":
            return "pong"
        if role is None:
            raise not_authorized()

        self.authorize(role, method, params)
        with self.lock:
            self.tick()
            return self._answer(method, params)

    def _read(self, method: str, params: list) -> object | None:
        """Reads that do not need the lock to change anything."""
        filters = params[0] if params and isinstance(params[0], list) else []
        options = (
            params[1]
            if len(params) > 1 and isinstance(params[1], dict)
            else {}
        )
        extra = options.get("extra") if isinstance(options.get("extra"), dict) else {}

        if method == "system.version":
            return self.world["system"]["version"]
        if method == "system.info":
            uptime = (
                86_400
                if self.booted_at is None
                else int(max(0.0, time.monotonic() - self.booted_at))
            )
            system = self.world["system"]
            return {
                "version": system["version"],
                "hostname": system["hostname"],
                "uptime_seconds": uptime,
                "cores": system["cores"],
                "physmem": system["physmem"],
                "loadavg": system["loadavg"],
                "model": system["model"],
                "system_product": system["system_product"],
                "system_serial": system["system_serial"],
            }
        if method == "core.get_methods":
            names = [
                "auth.me",
                "core.ping",
                "core.get_jobs",
                "system.info",
                "system.version",
                "reporting.get_data",
                "pool.query",
                "pool.dataset.query",
                "pool.scrub.query",
                "service.query",
                "app.query",
                "virt.instance.query",
                "alert.list",
                "update.check_available",
            ]
            return {
                name: {"description": f"{name} (Cupola testlab)", "roles": []}
                for name in names
            }
        if method == "core.get_jobs":
            return [
                job.to_json()
                for job in self.jobs
                if _matches(
                    {
                        "id": job.id,
                        "method": job.method,
                        "state": job.state,
                    },
                    filters,
                )
            ]
        if method == "pool.query":
            topology = bool(extra.get("topology"))
            return [
                self.pool_row(pool, with_topology=topology)
                for pool in self.world["pools"]
                if _matches(pool, filters)
            ]
        if method == "pool.get_disks":
            return [
                {
                    "name": member["disk"],
                    "serial": f"ZL2PQR{index:02d}",
                    "size": 3_998_302_388_224,
                    "type": "HDD",
                    "pool": pool["name"],
                }
                for pool in self.world["pools"]
                for vdev in pool["topology"].get("data", [])
                for index, member in enumerate(vdev.get("children", []))
            ]
        if method in {"pool.dataset.query", "pool.dataset.get_instance"}:
            datasets = self.world["datasets"]
            if not extra.get("flat", True):
                roots = sorted(
                    identifier for identifier in datasets if "/" not in identifier
                )
                tree = [self._dataset_tree(root)[0] for root in roots]
                if method == "pool.dataset.get_instance":
                    wanted = params[0] if params else None
                    for row in tree:
                        if row["id"] == wanted:
                            return row
                    raise not_found(f"Dataset {wanted}")
                return tree
            rows = [
                self.dataset_row(dataset)
                for identifier, dataset in sorted(datasets.items())
                if _matches({"id": identifier, "pool": dataset["pool"]}, filters)
            ]
            if method == "pool.dataset.get_instance":
                wanted = params[0] if params else None
                for row in rows:
                    if row["id"] == wanted:
                        return row
                raise not_found(f"Dataset {wanted}")
            return rows
        if method in {"zfs.snapshot.query", "pool.snapshot.query"}:
            return [
                self.snapshot_row(snapshot)
                for snapshot in self.world["snapshots"]
                if _matches(
                    {
                        "id": snapshot["id"],
                        "dataset": snapshot["dataset"],
                        "snapshot_name": snapshot["snapshot_name"],
                    },
                    filters,
                )
            ]
        if method == "sharing.smb.query":
            return [dict(row) for row in self.world["smb_shares"]]
        if method == "sharing.nfs.query":
            return [dict(row) for row in self.world["nfs_shares"]]
        if method == "iscsi.target.query":
            return [dict(row) for row in self.world["iscsi_targets"]]
        if method == "user.query":
            return [dict(row) for row in self.world["users"]]
        if method == "group.query":
            users = self.world["users"]
            members = self.world["group_members"]
            groups = []
            for group in self.world["groups"]:
                row = dict(group)
                row["users"] = [
                    user["username"]
                    for user in users
                    if user["username"] in members.get(group["name"], [])
                ]
                row["sudo_commands"] = ["ALL"] if group["name"] == "wheel" else []
                groups.append(row)
            return groups
        if method == "service.query":
            return [dict(row) for row in self.world["services"]]
        if method == "app.query":
            return [
                {
                    "name": app["name"],
                    "id": app["name"],
                    "state": app["state"],
                    "version": app["version"],
                    "human_version": app["human_version"],
                    "upgrade_available": app["upgrade_available"],
                    "metadata": app["metadata"],
                    "portals": app["portals"],
                }
                for app in self.world["apps"]
                if _matches({"name": app["name"], "state": app["state"]}, filters)
            ]
        if method == "virt.global.config":
            return dict(self.world["virt_global"])
        if method == "virt.instance.query":
            return [
                dict(instance)
                for instance in self.world["virt_instances"]
                if _matches({"id": instance["id"], "type": instance["type"]}, filters)
            ]
        if method == "virt.instance.device_list":
            name = str(params[0]) if params else ""
            self._instance(name)
            return [dict(row) for row in self.world["virt_devices"].get(name, [])]
        if method == "alert.list":
            return [dict(row) for row in self.world["alerts"]]
        if method == "update.check_available":
            return dict(self.world["update"])
        if method == "pool.scrub.query":
            return [
                dict(row)
                for row in self.world["scrub_tasks"]
                if _matches({"pool_name": row["pool_name"]}, filters)
            ]
        if method == "pool.snapshottask.query":
            return [dict(row) for row in self.world["snapshot_tasks"]]
        if method in {"replication.query", "cloudsync.query", "rsynctask.query"}:
            return []
        if method == "system.general.config":
            return dict(self.world["general_config"])
        if method == "system.advanced.config":
            return dict(self.world["advanced_config"])
        if method == "mail.config":
            return dict(self.world["mail_config"])
        if method == "system.ntpserver.query":
            return [dict(row) for row in self.world["ntp_servers"]]
        if method == "certificate.query":
            return [dict(row) for row in self.world["certificates"]]
        if method == "alertservice.query":
            return [dict(row) for row in self.world["alert_services"]]
        if method == "interface.query":
            return [dict(row) for row in self.world["interfaces"]]
        if method == "network.configuration.config":
            return dict(self.world["network_config"])
        if method == "reporting.get_data":
            return self._reporting(params)
        return None

    def _reporting(self, params: list) -> list[dict[str, object]]:
        graphs = params[0] if params and isinstance(params[0], list) else []
        query = params[1] if len(params) > 1 and isinstance(params[1], dict) else {}
        end = int(query.get("end") or time.time())
        live = "start" in query or "end" in query
        points = 60 if live else 12
        step = 5
        out = []
        for graph in graphs:
            name = str(graph.get("name") if isinstance(graph, dict) else graph)
            if name not in REPORTING:
                raise invalid(f"Unknown graph {name}")
            legend, value = REPORTING[name]
            rows = []
            for index in range(points):
                timestamp = end - (points - 1 - index) * step
                sample = value(index)
                if name == "interface":
                    rows.append(
                        [
                            timestamp,
                            round(sample, 2),
                            round(sample * 0.34, 2),
                        ]
                    )
                else:
                    rows.append([timestamp, sample])
            out.append(
                {
                    "name": name,
                    "identifier": None,
                    "legend": list(legend),
                    "data": rows,
                    "start": rows[0][0],
                    "end": rows[-1][0],
                }
            )
        return out

    def _answer(self, method: str, params: list) -> object:
        read = self._read(method, params)
        if read is not None:
            return read

        # -- writes --------------------------------------------------------
        if method == "pool.scrub.scrub":
            name = str(params[0]) if params else ""
            action = str(params[1] if len(params) > 1 else "START").upper()
            pool = self._pool(name)
            if action == "STOP":
                return self._stop_scrub(pool)
            return self._start_scrub(pool, "pool.scrub.scrub")
        if method == "pool.scrub.run":
            name = str(params[0]) if params else ""
            pool = self._pool(name)
            return self._start_scrub(pool, "pool.scrub.run")
        if method == "pool.scrub.update":
            task_id = int(params[0])
            patch = params[1] if len(params) > 1 and isinstance(params[1], dict) else {}
            for task in self.world["scrub_tasks"]:
                if task["id"] == task_id:
                    task.update(patch)
                    return dict(task)
            raise not_found(f"Scrub task {task_id}")
        if method == "pool.snapshottask.run":
            task_id = int(params[0])
            task = next(
                (
                    row
                    for row in self.world["snapshot_tasks"]
                    if row["id"] == task_id
                ),
                None,
            )
            if task is None:
                raise not_found(f"Snapshot task {task_id}")
            job = self.new_job(
                method, 0.9, f"Snapshot {task['dataset']}", task_id
            )
            return job.id
        if method == "pool.snapshottask.update":
            task_id = int(params[0])
            patch = params[1] if len(params) > 1 and isinstance(params[1], dict) else {}
            for task in self.world["snapshot_tasks"]:
                if task["id"] == task_id:
                    task.update(patch)
                    return dict(task)
            raise not_found(f"Snapshot task {task_id}")
        if method == "pool.snapshottask.delete":
            task_id = int(params[0])
            tasks = self.world["snapshot_tasks"]
            for index, task in enumerate(tasks):
                if task["id"] == task_id:
                    del tasks[index]
                    return True
            raise not_found(f"Snapshot task {task_id}")
        if method == "pool.dataset.create":
            return self._create_dataset(params[0])
        if method == "pool.dataset.update":
            return self._update_dataset(str(params[0]), params[1])
        if method == "pool.dataset.delete":
            return self._delete_dataset(params)
        if method in {"zfs.snapshot.create", "pool.snapshot.create"}:
            return self._create_snapshot(params[0])
        if method in {"zfs.snapshot.delete", "pool.snapshot.delete"}:
            return self._delete_snapshot(str(params[0]))
        if method == "sharing.smb.create":
            return self._create_share("smb_shares", params[0], name_key="name")
        if method == "sharing.smb.update":
            return self._update_row("smb_shares", int(params[0]), params[1])
        if method == "sharing.smb.delete":
            return self._delete_row("smb_shares", int(params[0]))
        if method == "sharing.nfs.create":
            return self._create_nfs(params[0])
        if method == "sharing.nfs.update":
            return self._update_row("nfs_shares", int(params[0]), params[1])
        if method == "sharing.nfs.delete":
            return self._delete_row("nfs_shares", int(params[0]))
        if method == "iscsi.target.delete":
            return self._delete_row("iscsi_targets", int(params[0]))
        if method == "user.create":
            return self._create_user(params[0])
        if method == "user.delete":
            return self._delete_user(params)
        if method == "group.create":
            return self._create_group(params[0])
        if method == "group.delete":
            return self._delete_group(int(params[0]))
        if method == "service.start":
            return self._set_service(str(params[0]), "RUNNING")
        if method == "service.stop":
            return self._set_service(str(params[0]), "STOPPED")
        if method == "service.update":
            service_id = int(params[0])
            patch = params[1] if len(params) > 1 and isinstance(params[1], dict) else {}
            for row in self.world["services"]:
                if row["id"] == service_id:
                    if "enable" in patch:
                        row["enable"] = bool(patch["enable"])
                    return dict(row)
            raise not_found(f"Service {service_id}")
        if method == "alert.dismiss":
            uuid = str(params[0]) if params else ""
            for alert in self.world["alerts"]:
                if alert["uuid"] == uuid:
                    alert["dismissed"] = True
                    return True
            raise not_found(f"Alert {uuid}")
        if method in {"system.reboot", "system.shutdown"}:
            return PowerCut("reboot" if method == "system.reboot" else "shutdown")
        if method == "mail.send":
            job = self.new_job("mail.send", 0.5, "Sending test email", True)
            return job.id
        if method in {"system.general.update", "system.advanced.update", "mail.update"}:
            key = {
                "system.general.update": "general_config",
                "system.advanced.update": "advanced_config",
                "mail.update": "mail_config",
            }[method]
            patch = params[0] if params and isinstance(params[0], dict) else {}
            self.world[key].update(patch)
            return dict(self.world[key])
        if method.startswith("app."):
            return self._app_action(method, params)
        if method.startswith("virt.instance."):
            return self._virt_action(method, params)
        raise RpcError(
            f"[ENOMETHOD] Method {method} not found",
            errno=64,
            errname="ENOMETHOD",
        )

    # -- scrub -------------------------------------------------------------

    def _start_scrub(self, pool: dict[str, object], method: str) -> int:
        active = pool.get("scrub_job")
        if active is not None:
            raise invalid(f"A scrub is already running on '{pool['name']}'")
        job = self.new_job(
            method, SCRUB_SECONDS, f"Scrubbing pool {pool['name']}"
        )

        def done() -> None:
            pool["scan"] = {
                "function": "SCRUB",
                "state": "FINISHED",
                "percentage": 100.0,
                "bytes_processed": int(pool["size"]),
                "total_secs_left": None,
                "end_time": {"$date": int(time.time() * 1000)},
            }
            pool["scrub_job"] = None

        def aborted() -> None:
            pool["scan"] = {
                "function": "SCRUB",
                "state": "FINISHED",
                "percentage": job.percent,
                "bytes_processed": int(int(pool["size"]) * job.percent / 100.0),
                "total_secs_left": 0,
                "end_time": {"$date": int(time.time() * 1000)},
            }
            pool["scrub_job"] = None

        job.on_done = done
        job.on_abort = aborted
        pool["scrub_job"] = job.id
        return job.id

    def _stop_scrub(self, pool: dict[str, object]) -> int:
        job_id = pool.get("scrub_job")
        if job_id is None:
            raise invalid(f"No scrub is running on '{pool['name']}'")
        for job in self.jobs:
            if job.id == job_id:
                job.finish("ABORTED")
                job.error = "Scrub stopped by the user"
                if job.on_abort is not None:
                    job.on_abort()
                return job.id
        pool["scrub_job"] = None
        raise invalid(f"No scrub is running on '{pool['name']}'")

    # -- datasets and snapshots -------------------------------------------

    def _create_dataset(self, payload: object) -> dict[str, object]:
        values = payload if isinstance(payload, dict) else {}
        name = str(values.get("name") or "").strip("/")
        if not name:
            raise invalid("The dataset name is required")
        datasets = self.world["datasets"]
        if name in datasets:
            raise invalid(f"Dataset {name} already exists")
        parent = name.rsplit("/", 1)[0] if "/" in name else None
        if parent is None or parent not in datasets:
            raise invalid(f"Parent dataset {parent} does not exist")
        pool_name = name.split("/", 1)[0]
        parent_row = datasets[parent]
        dataset = {
            "id": name,
            "pool": pool_name,
            "type": str(values.get("type") or "FILESYSTEM"),
            "mountpoint": f"/mnt/{name}",
            "used": 0,
            "available": parent_row["available"],
            "compression": str(values.get("compression") or "LZ4"),
            "compressratio": "1.00x",
            "recordsize": str(values.get("recordsize") or "128K"),
            "comments": str(values.get("comments") or ""),
        }
        if dataset["type"] == "VOLUME":
            dataset["volsize"] = int(values.get("volsize") or 10_737_418_240)
        datasets[name] = dataset
        return self.dataset_row(dataset)

    def _update_dataset(self, identifier: str, patch: object) -> dict[str, object]:
        datasets = self.world["datasets"]
        if identifier not in datasets:
            raise not_found(f"Dataset {identifier}")
        changes = patch if isinstance(patch, dict) else {}
        allowed = {"comments", "compression", "recordsize", "quota", "refquota"}
        for key, value in changes.items():
            if key in allowed:
                datasets[identifier][key] = value
        return self.dataset_row(datasets[identifier])

    def _delete_dataset(self, params: list) -> bool:
        identifier = str(params[0]) if params else ""
        options = params[1] if len(params) > 1 and isinstance(params[1], dict) else {}
        recursive = bool(options.get("recursive"))
        datasets = self.world["datasets"]
        if identifier not in datasets:
            raise not_found(f"Dataset {identifier}")
        doomed = [
            name
            for name in datasets
            if name == identifier or name.startswith(f"{identifier}/")
        ]
        if len(doomed) > 1 and not recursive:
            raise invalid(
                f"Dataset {identifier} has children; recursive is required"
            )
        for name in doomed:
            del datasets[name]
        self.world["snapshots"] = [
            snapshot
            for snapshot in self.world["snapshots"]
            if snapshot["dataset"] not in doomed
        ]
        return True

    def _create_snapshot(self, payload: object) -> dict[str, object]:
        values = payload if isinstance(payload, dict) else {}
        dataset = str(values.get("dataset") or "")
        name = str(values.get("name") or "")
        if dataset not in self.world["datasets"]:
            raise not_found(f"Dataset {dataset}")
        if not name:
            raise invalid("The snapshot name is required")
        identifier = f"{dataset}@{name}"
        for snapshot in self.world["snapshots"]:
            if snapshot["id"] == identifier:
                raise invalid(f"Snapshot {identifier} already exists")
        snapshot = {
            "id": identifier,
            "dataset": dataset,
            "snapshot_name": name,
            "name": identifier,
            "creation": int(time.time() * 1000),
            "used": 0,
            "referenced": int(self.world["datasets"][dataset]["used"]),
        }
        self.world["snapshots"].append(snapshot)
        return self.snapshot_row(snapshot)

    def _delete_snapshot(self, identifier: str) -> bool:
        snapshots = self.world["snapshots"]
        for index, snapshot in enumerate(snapshots):
            if snapshot["id"] == identifier or snapshot["snapshot_name"] == identifier:
                del snapshots[index]
                return True
        raise not_found(f"Snapshot {identifier}")

    # -- shares ------------------------------------------------------------

    def _next_id(self, key: str) -> int:
        rows = self.world[key]
        return max((int(row["id"]) for row in rows), default=0) + 1

    def _create_share(
        self, key: str, payload: object, *, name_key: str
    ) -> dict[str, object]:
        values = payload if isinstance(payload, dict) else {}
        name = str(values.get(name_key) or "")
        if not name:
            raise invalid(f"The share {name_key} is required")
        for row in self.world[key]:
            if row.get(name_key) == name:
                raise invalid(f"A share named {name} already exists")
        row = {
            "id": self._next_id(key),
            name_key: name,
            "path": str(values.get("path") or ""),
            "enabled": bool(values.get("enabled", True)),
            "comment": values.get("comment"),
            "ro": bool(values.get("ro", False)),
            "purpose": values.get("purpose", "DEFAULT_SHARE"),
        }
        self.world[key].append(row)
        return dict(row)

    def _create_nfs(self, payload: object) -> dict[str, object]:
        values = payload if isinstance(payload, dict) else {}
        paths = values.get("paths")
        if not isinstance(paths, list):
            single = values.get("path")
            paths = [single] if single else []
        if not paths:
            raise invalid("At least one path is required")
        row = {
            "id": self._next_id("nfs_shares"),
            "paths": [str(path) for path in paths],
            "enabled": bool(values.get("enabled", True)),
            "comment": values.get("comment"),
            "ro": bool(values.get("ro", False)),
            "networks": [str(v) for v in values.get("networks") or []],
            "hosts": [str(v) for v in values.get("hosts") or []],
        }
        self.world["nfs_shares"].append(row)
        return dict(row)

    def _update_row(self, key: str, row_id: int, patch: object) -> dict[str, object]:
        changes = patch if isinstance(patch, dict) else {}
        for row in self.world[key]:
            if int(row["id"]) == row_id:
                row.update(changes)
                return dict(row)
        raise not_found(f"Share {row_id}")

    def _delete_row(self, key: str, row_id: int) -> bool:
        rows = self.world[key]
        for index, row in enumerate(rows):
            if int(row["id"]) == row_id:
                del rows[index]
                return True
        raise not_found(f"Share {row_id}")

    # -- users and groups --------------------------------------------------

    def _create_user(self, payload: object) -> dict[str, object]:
        values = payload if isinstance(payload, dict) else {}
        username = str(values.get("username") or "")
        if not username:
            raise invalid("The username is required")
        for user in self.world["users"]:
            if user["username"] == username:
                raise invalid(f"User {username} already exists")
        uid = max(int(user["uid"]) for user in self.world["users"]) + 1
        user = {
            "id": uid,
            "uid": uid,
            "username": username,
            "full_name": str(values.get("full_name") or username),
            "builtin": False,
            "locked": False,
            "shell": str(values.get("shell") or "/usr/sbin/nologin"),
            "smb": bool(values.get("smb", False)),
        }
        self.world["users"].append(user)
        group = str(values.get("group") or "")
        if values.get("group_create") and not group:
            group = username
            self.world["groups"].append(
                {"id": uid, "gid": uid, "name": group, "builtin": False}
            )
        if group:
            self.world["group_members"].setdefault(group, []).append(username)
        return user

    def _delete_user(self, params: list) -> bool:
        user_id = int(params[0])
        options = params[1] if len(params) > 1 and isinstance(params[1], dict) else {}
        users = self.world["users"]
        for index, user in enumerate(users):
            if int(user["id"]) == user_id:
                username = user["username"]
                del users[index]
                for members in self.world["group_members"].values():
                    if username in members:
                        members.remove(username)
                if options.get("delete_group"):
                    self.world["groups"] = [
                        group
                        for group in self.world["groups"]
                        if group["name"] != username
                    ]
                    self.world["group_members"].pop(username, None)
                return True
        raise not_found(f"User {user_id}")

    def _create_group(self, payload: object) -> dict[str, object]:
        values = payload if isinstance(payload, dict) else {}
        name = str(values.get("name") or "")
        if not name:
            raise invalid("The group name is required")
        for group in self.world["groups"]:
            if group["name"] == name:
                raise invalid(f"Group {name} already exists")
        gid = max(int(group["gid"]) for group in self.world["groups"]) + 1
        group = {"id": gid, "gid": gid, "name": name, "builtin": False}
        self.world["groups"].append(group)
        return dict(group)

    def _delete_group(self, group_id: int) -> bool:
        groups = self.world["groups"]
        for index, group in enumerate(groups):
            if int(group["id"]) == group_id:
                del groups[index]
                return True
        raise not_found(f"Group {group_id}")

    # -- services ----------------------------------------------------------

    def _set_service(self, name: str, state: str) -> dict[str, object]:
        service = self._service(name)
        if service["state"] == state:
            raise invalid(f"Service {name} is already {state.lower()}")
        service["state"] = state
        return dict(service)

    # -- apps --------------------------------------------------------------

    def _app_action(self, method: str, params: list) -> int:
        name = str(params[0]) if params else ""
        app = self._app(name)
        action = method.split(".", 1)[1]
        title = app["metadata"]["title"]
        if action == "start":
            if app["state"] == "RUNNING":
                raise invalid(f"Application {name} is already running")
            app["state"] = "DEPLOYING"
            job = self.new_job(method, 1.2, f"Starting {title}")

            def done() -> None:
                app["state"] = "RUNNING"

            job.on_done = done
            return job.id
        if action == "stop":
            if app["state"] == "STOPPED":
                raise invalid(f"Application {name} is already stopped")
            app["state"] = "STOPPING"
            job = self.new_job(method, 1.0, f"Stopping {title}")

            def done() -> None:
                app["state"] = "STOPPED"

            job.on_done = done
            return job.id
        if action == "upgrade":
            if not app["upgrade_available"]:
                raise invalid(f"Application {name} is already up to date")
            job = self.new_job(method, 2.0, f"Upgrading {title}")

            def done() -> None:
                app["upgrade_available"] = False
                app["human_version"] = self._newer(app["human_version"])

            job.on_done = done
            return job.id
        if action == "delete":
            job = self.new_job(method, 0.8, f"Deleting {title}")

            def done() -> None:
                self.world["apps"] = [
                    row for row in self.world["apps"] if row["name"] != name
                ]

            job.on_done = done
            return job.id
        raise RpcError(
            f"[ENOMETHOD] Method {method} not found",
            errno=64,
            errname="ENOMETHOD",
        )

    @staticmethod
    def _newer(version: str) -> str:
        """The next patch of a version string, for an upgrade that happened."""
        head, _, patch = version.rpartition(".")
        if not head:
            return version
        try:
            return f"{head}.{int(patch) + 1}"
        except ValueError:
            return version

    # -- virt --------------------------------------------------------------

    def _virt_action(self, method: str, params: list) -> int:
        action = method.rsplit(".", 1)[1]
        if action == "create":
            payload = params[0] if params and isinstance(params[0], dict) else {}
            name = str(payload.get("name") or "")
            if not name:
                raise invalid("The instance name is required")
            if any(row["id"] == name for row in self.world["virt_instances"]):
                raise invalid(f"Instance {name} already exists")
            image = str(payload.get("image") or "alpine/edge")
            os_name, _, release = image.partition("/")
            cpu = payload.get("cpu")
            try:
                cpu_count = int(cpu) if cpu is not None else 1
            except (TypeError, ValueError):
                cpu_count = 1
            instance = {
                "id": name,
                "name": name,
                "type": str(payload.get("instance_type") or "CONTAINER"),
                "status": "STOPPED",
                "cpu": cpu_count,
                "memory": int(payload.get("memory") or 1_073_741_824),
                "autostart": False,
                "image": {"os": os_name, "release": release or "edge"},
            }
            job = self.new_job(method, 1.4, f"Creating {name}")

            def done() -> None:
                self.world["virt_instances"].append(instance)

            job.on_done = done
            return job.id
        name = str(params[0]) if params else ""
        instance = self._instance(name)
        if action == "start":
            if instance["status"] == "RUNNING":
                raise invalid(f"Instance {name} is already running")
            instance["status"] = "STARTING"
            job = self.new_job(method, 1.2, f"Starting {name}")

            def done() -> None:
                instance["status"] = "RUNNING"

            job.on_done = done
            return job.id
        if action == "stop":
            if instance["status"] == "STOPPED":
                raise invalid(f"Instance {name} is already stopped")
            instance["status"] = "STOPPING"
            job = self.new_job(method, 1.0, f"Stopping {name}")

            def done() -> None:
                instance["status"] = "STOPPED"

            job.on_done = done
            return job.id
        if action == "restart":
            instance["status"] = "RESTARTING"
            job = self.new_job(method, 1.6, f"Restarting {name}")

            def done() -> None:
                instance["status"] = "RUNNING"

            job.on_done = done
            return job.id
        if action == "delete":
            job = self.new_job(method, 0.8, f"Deleting {name}")

            def done() -> None:
                self.world["virt_instances"] = [
                    row
                    for row in self.world["virt_instances"]
                    if row["id"] != name
                ]
                self.world["virt_devices"].pop(name, None)

            job.on_done = done
            return job.id
        raise RpcError(
            f"[ENOMETHOD] Method {method} not found",
            errno=64,
            errname="ENOMETHOD",
        )


class PowerCut:
    """The reply that never comes: the host is going down under the socket."""

    def __init__(self, action: str):
        self.action = action


STATE = TrueNasState()


class WebSocketConnection:
    def __init__(self, sock: socket.socket):
        self.sock = sock

    def send_text(self, value: str) -> None:
        payload = value.encode("utf-8")
        length = len(payload)
        if length < 126:
            header = bytes([0x81, length])
        elif length < 65536:
            header = bytes([0x81, 126]) + struct.pack("!H", length)
        else:
            header = bytes([0x81, 127]) + struct.pack("!Q", length)
        self.sock.sendall(header + payload)

    def read_exact(self, size: int) -> bytes | None:
        # A TLS socket returns what is left of one record, which can be fewer
        # bytes than asked for, so every read here loops until it has them all.
        data = bytearray()
        while len(data) < size:
            chunk = self.sock.recv(size - len(data))
            if not chunk:
                return None
            data.extend(chunk)
        return bytes(data)

    def read_frame(self) -> tuple[int, bytes] | None:
        header = self.read_exact(2)
        if header is None:
            return None
        opcode = header[0] & 0x0F
        masked = bool(header[1] & 0x80)
        length = header[1] & 0x7F
        if length == 126:
            extended = self.read_exact(2)
            if extended is None:
                return None
            length = struct.unpack("!H", extended)[0]
        elif length == 127:
            extended = self.read_exact(8)
            if extended is None:
                return None
            length = struct.unpack("!Q", extended)[0]
        mask = b""
        if masked:
            mask = self.read_exact(4)
            if mask is None:
                return None
        data = bytearray()
        while len(data) < length:
            chunk = self.sock.recv(length - len(data))
            if not chunk:
                return None
            data.extend(chunk)
        if masked:
            for index in range(length):
                data[index] ^= mask[index % 4]
        return opcode, bytes(data)


class TrueNasHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        # The handshake runs here, on the connection's own thread: a client that
        # stalls in it holds only itself. One that refuses the certificate, or
        # connects to look at it and leaves (the healthcheck, the app's
        # certificate probe), ends the connection with an error and nothing
        # more: ssl.SSLError is an OSError, so one clause says it all.
        try:
            connection = tls_context().wrap_socket(self.request, server_side=True)
            with connection:
                STATE.register(connection)
                try:
                    self.serve(connection)
                finally:
                    STATE.unregister(connection)
        except OSError:
            return

    def serve(self, sock: ssl.SSLSocket) -> None:
        request = b""
        while b"\r\n\r\n" not in request:
            chunk = sock.recv(4096)
            if not chunk:
                return
            request += chunk
        head, _, rest = request.partition(b"\r\n\r\n")
        lines = head.decode("latin1").split("\r\n")
        method, path = (lines[0].split(" ") + ["", ""])[:2]
        headers = {}
        for line in lines[1:]:
            if ":" in line:
                name, _, value = line.partition(":")
                headers[name.strip().lower()] = value.strip()

        # The testlab's control surface answers even while the machine is
        # powered down: it is the only way back up.
        if urllib.parse.urlparse(path).path.startswith("/testlab/"):
            self.control(sock, method, path, headers, rest)
            return
        if STATE.power != "on":
            return

        key = headers.get("sec-websocket-key", "")
        if not key:
            self.http(sock, 426, {"error": "This port speaks WebSocket only"})
            return
        accept = base64.b64encode(
            hashlib.sha1(
                (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")
            ).digest()
        ).decode("ascii")
        response = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        ).encode("latin1")
        sock.sendall(response)
        connection = WebSocketConnection(sock)
        session = {"role": None}
        while True:
            frame = connection.read_frame()
            if frame is None:
                return
            opcode, payload = frame
            if opcode == 0x8:
                return
            if opcode != 0x1:
                continue
            try:
                message = json.loads(payload.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if not isinstance(message, dict) or "id" not in message:
                continue
            params = message.get("params", [])
            if not isinstance(params, list):
                params = []
            method_name = str(message.get("method", ""))
            if method_name == "auth.login_with_api_key":
                key_value = str(params[0]) if params else ""
                if key_value == API_KEY:
                    session["role"] = "admin"
                    result: object = True
                elif key_value == READONLY_API_KEY:
                    session["role"] = "readonly"
                    result = True
                else:
                    session["role"] = None
                    result = False
                connection.send_text(
                    json.dumps(
                        {"jsonrpc": "2.0", "id": message["id"], "result": result}
                    )
                )
                continue
            try:
                result = STATE.dispatch(session["role"], method_name, params)
            except RpcError as error:
                connection.send_text(
                    json.dumps(
                        {
                            "jsonrpc": "2.0",
                            "id": message["id"],
                            "error": error.envelope(),
                        }
                    )
                )
                continue
            if isinstance(result, PowerCut):
                # The middleware is killed under the reply: no frame is sent,
                # every socket is dropped, and the client sees it go.
                STATE.cut_power(result.action)
                return
            connection.send_text(
                json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": result})
            )

    # -- the testlab control surface --------------------------------------

    def control(
        self,
        sock: ssl.SSLSocket,
        method: str,
        path: str,
        headers: dict[str, str],
        rest: bytes,
    ) -> None:
        route = urllib.parse.urlparse(path).path
        try:
            length = int(headers.get("content-length", "0"))
        except ValueError:
            length = 0
        body = rest
        while len(body) < length:
            chunk = sock.recv(length - len(body))
            if not chunk:
                break
            body += chunk
        payload: object = None
        if body:
            try:
                payload = json.loads(body)
            except (UnicodeDecodeError, json.JSONDecodeError):
                self.http(sock, 400, {"error": "The body is not JSON"})
                return

        if route == "/testlab/health" and method == "GET":
            self.http(sock, 200, {"ok": True, "power": STATE.power})
            return
        if route == "/testlab/state" and method == "GET":
            self.http(sock, 200, STATE.state_summary())
            return
        if route == "/testlab/reset" and method == "POST":
            STATE.reset()
            self.http(sock, 200, STATE.state_summary())
            return
        if route == "/testlab/scenario" and method == "POST":
            values = payload if isinstance(payload, dict) else {}
            name = values.get("name")
            STATE.apply_scenario(None if name is None else str(name))
            self.http(sock, 200, STATE.state_summary())
            return
        if route == "/testlab/power" and method == "POST":
            values = payload if isinstance(payload, dict) else {}
            state = str(values.get("state") or "")
            if state != "on":
                self.http(sock, 400, {"error": "the only state is 'on'"})
                return
            STATE.power_on()
            self.http(sock, 200, STATE.state_summary())
            return
        self.http(sock, 404, {"error": f"No control route {method} {route}"})

    def http(self, sock: ssl.SSLSocket, status: int, payload: object) -> None:
        body = json_bytes(payload)
        reason = {
            200: "OK",
            400: "Bad Request",
            404: "Not Found",
            426: "Upgrade Required",
        }.get(status, "OK")
        head = (
            f"HTTP/1.1 {status} {reason}\r\n"
            "Content-Type: application/json\r\n"
            f"Content-Length: {len(body)}\r\n"
            "Connection: close\r\n\r\n"
        ).encode("latin1")
        try:
            sock.sendall(head + body)
        except OSError:
            return


class UnraidHandler(BaseHTTPRequestHandler):
    server_version = "CupolaUnraidMock/1.0"

    def do_GET(self) -> None:  # noqa: N802 - healthcheck endpoint
        if self.path == "/graphql":
            self.send_response(200)
            self.end_headers()
            return
        self.send_error(404)

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path != "/graphql":
            self.send_error(404)
            return
        if self.headers.get("x-api-key") != API_KEY:
            self.send_response(401)
            self.end_headers()
            return
        try:
            size = int(self.headers.get("content-length", "0"))
            payload = json.loads(self.rfile.read(size))
        except (ValueError, json.JSONDecodeError):
            self.send_error(400)
            return
        query = str(payload.get("query", ""))
        data: dict[str, object] = {}
        if "info" in query:
            data["info"] = {"os": {"distro": "Unraid", "release": "7.0.0-mock", "uptime": 86400}}
        if "array" in query:
            data["array"] = {
                "state": "STARTED",
                "capacity": {"kilobytes": {"free": 8000000, "used": 2000000, "total": 10000000}},
                "disks": [{"name": "disk1", "status": "DISK_OK", "temp": 34}],
            }
        if "dockerContainers" in query:
            data["dockerContainers"] = [{"id": "mock-1", "names": ["cupola-lab"], "state": "running", "status": "Up", "autoStart": True}]
        if "me" in query:
            data["me"] = {"roles": ["ADMIN"], "permissions": [{"resource": "VM", "actions": ["START", "STOP"]}]}
        if "vms" in query:
            data["vms"] = {"domains": [{"id": "vm-1", "name": "cupola-vm", "state": "RUNNING"}]}
        if "notifications" in query:
            data["notifications"] = {
                "overview": {"unread": {"info": 0, "warning": 1, "alert": 0, "total": 1}, "archive": {"info": 0, "warning": 0, "alert": 0, "total": 0}},
                "list": [{"id": "notice-1", "title": "Lab notice", "subject": "Fixture", "description": "Deterministic Unraid mock", "importance": "WARNING", "link": "", "type": "SYSTEM", "timestamp": 1700000000, "formattedTimestamp": "2023-11-14 22:13"}],
            }
        if "shares" in query:
            data["shares"] = [{"id": "share-1", "name": "media", "used": 1000, "size": 10000, "cache": "", "comment": "Lab share", "luksStatus": "NOT_ENCRYPTED"}]
        if "archiveNotification" in query:
            data["archiveNotification"] = {"id": "notice-1", "title": "Lab notice", "subject": "Fixture", "description": "Archived", "importance": "INFO", "link": "", "type": "SYSTEM", "timestamp": 1700000000, "formattedTimestamp": "2023-11-14 22:13"}
        if "mutation" in query and "archiveNotification" not in query:
            data["vm"] = {"start": True, "stop": True, "pause": True, "resume": True, "restart": True, "shutdown": True}
        self._send_json({"data": data})

    def _send_json(self, payload: object) -> None:
        body = json_bytes(payload)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return


def bencode(value: object) -> bytes:
    if isinstance(value, int):
        return b"i" + str(value).encode("ascii") + b"e"
    if isinstance(value, str):
        value = value.encode("utf-8")
    if isinstance(value, bytes):
        return str(len(value)).encode("ascii") + b":" + value
    if isinstance(value, list):
        return b"l" + b"".join(bencode(item) for item in value) + b"e"
    if isinstance(value, dict):
        items = []
        for key in sorted(value):
            encoded = key.encode("utf-8") if isinstance(key, str) else key
            items.append(bencode(encoded) + bencode(value[key]))
        return b"d" + b"".join(items) + b"e"
    raise TypeError(f"cannot bencode {type(value).__name__}")


class IndexerHandler(BaseHTTPRequestHandler):
    """Torznab search and a BEP 3 tracker, in one local service.

    Radarr asks for the release; qBittorrent announces here and receives the
    seeder's address. The tracker keeps peers in memory, so a restarted lab
    simply waits for the next announce.
    """

    server_version = "CupolaTestlabIndexer/1.0"
    peers: dict[bytes, dict[tuple[str, int], int]] = {}

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/healthz":
            self._send(200, b"ok", "text/plain")
            return
        if parsed.path == "/api":
            query = dict(parse_qsl(parsed.query, keep_blank_values=True))
            if query.get("t") == "caps":
                self._send(200, self._caps(), "application/xml")
            else:
                self._send(200, self._search(query), "application/xml")
            return
        if parsed.path == "/announce":
            query = dict(
                parse_qsl(
                    parsed.query,
                    keep_blank_values=True,
                    encoding="latin-1",
                )
            )
            self._announce(query)
            return
        if parsed.path.startswith("/torrents/"):
            self._torrent(parsed.path.removeprefix("/torrents/"))
            return
        self.send_error(404)

    def _release(self) -> dict[str, object]:
        path = os.path.join(FORGE_DIR, "release.json")
        try:
            with open(path, encoding="utf-8") as handle:
                value = json.load(handle)
        except (OSError, ValueError):
            return {}
        return value if isinstance(value, dict) else {}

    def _caps(self) -> bytes:
        return b"""<?xml version="1.0" encoding="UTF-8"?>
<caps>
  <server version="1.0" title="Cupola testlab"/>
  <limits max="100" default="100"/>
  <searching>
    <search available="yes" supportedParams="q"/>
    <movie-search available="yes" supportedParams="q,tmdbid,imdbid"/>
  </searching>
  <categories>
    <category id="2000" name="Movies"/>
  </categories>
</caps>
"""

    def _search(self, query: dict[str, str]) -> bytes:
        release = self._release()
        if not release:
            return self._rss([])
        catalogue = release.get("releases")
        if not isinstance(catalogue, list) or not catalogue:
            catalogue = [release]
        base = "http://testlab-indexer:8088"
        items = []
        for entry in catalogue:
            if not isinstance(entry, dict):
                continue
            title = str(entry.get("title") or "")
            torrent = str(entry.get("torrent") or "")
            if not title or not torrent:
                continue
            items.append(
                f"""    <item>
      <title>{escape(title)}</title>
      <guid isPermaLink="false">{escape(str(entry.get("infohash", "")))}</guid>
      <link>{base}/torrents/{escape(torrent)}</link>
      <enclosure url="{base}/torrents/{escape(torrent)}" length="{entry.get("size", 0)}" type="application/x-bittorrent"/>
      <description>Synthetic release for the Cupola testlab.</description>
      <pubDate>Wed, 01 Jan 2025 00:00:00 +0000</pubDate>
      <category>2000</category>
      <torznab:attr name="size" value="{entry.get("size", 0)}"/>
      <torznab:attr name="seeders" value="{entry.get("seeders", 1)}"/>
      <torznab:attr name="peers" value="{entry.get("peers", 2)}"/>
      <torznab:attr name="category" value="2000"/>
      <torznab:attr name="infohash" value="{escape(str(entry.get("infohash", "")))}"/>
    </item>
"""
            )
        return self._rss(items)

    def _rss(self, items: list[str]) -> bytes:
        body = "".join(items)
        return f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:torznab="http://torznab.com/schemas/2015/feed">
  <channel>
    <title>Cupola testlab</title>
    <link>http://testlab-indexer:8088/</link>
    <description>Cupola testlab indexer</description>
{body}  </channel>
</rss>
""".encode("utf-8")

    def _torrent(self, name: str) -> None:
        """A torrent file the forge wrote, by its bare name.

        Every forged release has its own torrent, so a grab of each one is a
        download of its own (its own infohash, its own queue record). The name
        is a single path segment ending in `.torrent`; nothing outside the
        forge's torrent folder is ever read.
        """
        if (
            not name.endswith(".torrent")
            or "/" in name
            or "\\" in name
            or name.startswith(".")
        ):
            self.send_error(404)
            return
        path = os.path.join(FORGE_DIR, "torrents", name)
        try:
            with open(path, "rb") as handle:
                body = handle.read()
        except OSError:
            self.send_error(404)
            return
        self._send(200, body, "application/x-bittorrent")

    def _announce(self, query: dict[str, str]) -> None:
        info_hash = (query.get("info_hash") or "").encode("latin-1")
        if not info_hash:
            self.send_error(400)
            return
        try:
            port = int(query.get("port") or 0)
        except ValueError:
            self.send_error(400)
            return
        ip = self.client_address[0]
        event = query.get("event") or ""
        peers = self.peers.setdefault(info_hash, {})
        if event == "stopped":
            peers.pop((ip, port), None)
        else:
            peers[(ip, port)] = int(query.get("left") or 1)
        others = [
            (peer_ip, peer_port)
            for (peer_ip, peer_port) in peers
            if (peer_ip, peer_port) != (ip, port)
        ]
        if query.get("compact", "1") == "1":
            compact = b"".join(
                socket.inet_aton(peer_ip) + struct.pack(">H", peer_port & 0xFFFF)
                for peer_ip, peer_port in others
            )
            payload = (
                b"d8:intervali60e5:peers"
                + str(len(compact)).encode("ascii")
                + b":"
                + compact
                + b"e"
            )
        else:
            payload = bencode(
                {
                    "interval": 60,
                    "peers": [
                        {"ip": peer_ip, "port": peer_port, "peer id": b"-CU0001-"}
                        for peer_ip, peer_port in others
                    ],
                }
            )
        self._send(200, payload, "text/plain")

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return


def healthcheck() -> int:
    """Exit status for the Compose healthcheck: does the mock finish a TLS handshake?"""
    if MODE != "truenas":
        return 1
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    # The certificate is self-signed on purpose and this only asks whether the
    # server answers a handshake, so nothing is verified.
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    try:
        with socket.create_connection(("127.0.0.1", TRUENAS_PORT), timeout=3) as plain:
            with context.wrap_socket(plain):
                return 0
    except OSError:
        return 1


def main() -> None:
    if "--healthcheck" in sys.argv[1:]:
        sys.exit(healthcheck())
    if MODE == "truenas":
        # Fail at start, loudly, when the certificate is not where the lab keeps
        # it: a mock that cannot do TLS is worse than one that is not running,
        # since the app refuses to talk to anything else.
        try:
            tls_context()
        except (ssl.SSLError, OSError) as error:
            sys.exit(
                f"The TrueNAS mock needs a TLS certificate at {TLS_CERT} and its key at "
                f"{TLS_KEY} ({error}). Make them with test/e2e/testlab/truenas_cert.sh."
            )
        server = socketserver.ThreadingTCPServer(("0.0.0.0", TRUENAS_PORT), TrueNasHandler)
        server.daemon_threads = True
    elif MODE == "indexer":
        server = ThreadingHTTPServer(("0.0.0.0", INDEXER_PORT), IndexerHandler)
    else:
        server = ThreadingHTTPServer(("0.0.0.0", 8480), UnraidHandler)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
