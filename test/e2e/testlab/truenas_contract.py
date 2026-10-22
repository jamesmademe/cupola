#!/usr/bin/env python3
"""Contract test for the TrueNAS simulator.

``test/e2e/testlab/mock/server.py`` speaks the middleware's JSON-RPC over TLS.
This script is the second opinion on it: it drives the running simulator with
its own small WebSocket client (not the simulator's), compares every stable
answer with the fixture in ``test/fixtures/truenas`` that the app's unit tests
already read, and then exercises the transitions the app's flows need, reading
each one back.

Run it from the repository root, with the lab up::

    python3 test/e2e/testlab/truenas_contract.py
    python3 test/e2e/testlab/truenas_contract.py --write   # record missing fixtures

``--write`` records a fixture only when it is missing; existing files are
compared, never overwritten. The world is reset first, so a run starts from the
same state the container starts in.

The script is part of L9 of the testlab plan (``A-20261021-piano-testlab-0aa1``)
and covers I-09..I-15 of the flow catalogue
(``A-20261021-catalogo-dei-flussi-4a87``).
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import http.client
import json
import os
import socket
import ssl
import struct
import sys
import time
import urllib.parse
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
STATE_ROOT = Path(
    os.environ.get("CUPOLA_TESTLAB_STATE_DIR", REPO_ROOT / ".ai" / "scratch" / "zz_testlab" / "state")
).resolve()
FIXTURES = REPO_ROOT / "test" / "fixtures" / "truenas"
URL = urllib.parse.urlparse(
    os.environ.get("CUPOLA_TESTLAB_TRUENAS_URL", "https://127.0.0.1:8460")
)
ADMIN_KEY = os.environ.get("MOCK_API_KEY", "test-key")
READONLY_KEY = "test-readonly"
CERT = STATE_ROOT / "truenas" / "truenas.crt"

# (method, params, fixture). Each fixture is a stable answer the app parses, so
# a shape change breaks the contract before it reaches a screen.
EXPECTATIONS: list[tuple[str, list[Any], str]] = [
    ("system.info", [], "system_info.json"),
    ("pool.query", [], "pools.json"),
    (
        "pool.query",
        [[["name", "=", "tank"]], {"extra": {"topology": True}}],
        "pool_tank.json",
    ),
    ("pool.dataset.query", [[], {"extra": {"flat": False}}], "datasets.json"),
    (
        "zfs.snapshot.query",
        [[["dataset", "=", "tank/media"]]],
        "snapshots_tank_media.json",
    ),
    ("sharing.smb.query", [], "sharing_smb.json"),
    ("sharing.nfs.query", [], "sharing_nfs.json"),
    ("iscsi.target.query", [], "iscsi_targets.json"),
    ("user.query", [], "users.json"),
    ("group.query", [], "groups.json"),
    ("service.query", [], "services.json"),
    ("app.query", [], "apps.json"),
    ("virt.instance.query", [], "virt_instances.json"),
    ("virt.global.config", [], "virt_global.json"),
    ("alert.list", [], "alerts.json"),
    ("update.check_available", [], "update_check.json"),
    ("pool.scrub.query", [], "scrub_tasks.json"),
    ("pool.snapshottask.query", [], "snapshot_tasks.json"),
]

EACCES = {
    "errname": "EACCES",
    "reason": "[EACCES] Not authorized",
}
EPERM = {
    "errname": "EPERM",
    "reason": "[EPERM] You do not have permission to modify this service",
}


class ContractError(RuntimeError):
    pass


# ---------------------------------------------------------------------------
# A plain JSON-RPC client: the contract must not borrow the simulator's frames
# ---------------------------------------------------------------------------


class Session:
    def __init__(self, api_key: str, *, timeout: float = 10.0, login: bool = True):
        context = ssl.create_default_context(cafile=str(CERT))
        raw = socket.create_connection((URL.hostname, URL.port or 443), timeout=timeout)
        self.sock = context.wrap_socket(raw, server_hostname=URL.hostname)
        self.sock.settimeout(timeout)
        self.buffer = b""
        self.next_id = 1
        self._upgrade()
        if login:
            result = self.call("auth.login_with_api_key", [api_key])
            if result is not True:
                raise ContractError(f"The simulator refused the key {api_key!r}")

    def _upgrade(self) -> None:
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        request = (
            f"GET /api/current HTTP/1.1\r\n"
            f"Host: {URL.hostname}:{URL.port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        ).encode("latin1")
        self.sock.sendall(request)
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ContractError("The simulator closed the upgrade")
            head += chunk
        header, _, rest = head.partition(b"\r\n\r\n")
        if b"101" not in header.split(b"\r\n")[0]:
            raise ContractError(f"The upgrade was refused: {header[:200]!r}")
        self.buffer = rest

    def close(self) -> None:
        try:
            self._frame(0x8, b"")
            self.sock.close()
        except OSError:
            pass

    def _frame(self, opcode: int, payload: bytes) -> None:
        mask = os.urandom(4)
        length = len(payload)
        if length < 126:
            header = bytes([0x80 | opcode, 0x80 | length])
        elif length < 65536:
            header = bytes([0x80 | opcode, 0x80 | 126]) + struct.pack("!H", length)
        else:
            header = bytes([0x80 | opcode, 0x80 | 127]) + struct.pack("!Q", length)
        masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        self.sock.sendall(header + mask + masked)

    def _read_exact(self, size: int) -> bytes:
        while len(self.buffer) < size:
            chunk = self.sock.recv(max(4096, size - len(self.buffer)))
            if not chunk:
                raise EOFError("The simulator closed the socket")
            self.buffer += chunk
        data, self.buffer = self.buffer[:size], self.buffer[size:]
        return data

    def read(self) -> dict[str, Any] | None:
        """One JSON-RPC frame, or None when the socket closes."""
        try:
            head = self._read_exact(2)
        except EOFError:
            return None
        opcode = head[0] & 0x0F
        length = head[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", self._read_exact(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self._read_exact(8))[0]
        payload = self._read_exact(length) if length else b""
        if opcode == 0x8:
            return None
        if opcode != 0x1:
            return self.read()
        return json.loads(payload)

    def raw(self, method: str, params: list[Any]) -> dict[str, Any] | None:
        message = {
            "jsonrpc": "2.0",
            "id": self.next_id,
            "method": method,
            "params": params,
        }
        self.next_id += 1
        self._frame(0x1, json.dumps(message).encode("utf-8"))
        while True:
            frame = self.read()
            if frame is None:
                return None
            if frame.get("id") == message["id"]:
                return frame

    def call(self, method: str, params: list[Any] | None = None) -> Any:
        frame = self.raw(method, list(params or []))
        if frame is None:
            raise EOFError(f"{method}: the socket closed")
        if "error" in frame:
            raise ContractError(f"{method}: {frame['error']}")
        return frame.get("result")

    def attempt(self, method: str, params: list[Any] | None = None) -> dict[str, Any]:
        """The error envelope of a call that must be refused, or a failure."""
        frame = self.raw(method, list(params or []))
        if frame is None:
            raise ContractError(f"{method}: the socket closed instead of refusing")
        error = frame.get("error")
        if not isinstance(error, dict):
            raise ContractError(f"{method}: accepted, expected a refusal")
        data = error.get("data")
        if not isinstance(data, dict):
            raise ContractError(f"{method}: the error has no data envelope")
        if error.get("code") != -32001 or error.get("message") != "Method call error":
            raise ContractError(f"{method}: unexpected envelope {error}")
        return data


# ---------------------------------------------------------------------------
# The control surface (HTTP over the same TLS port)
# ---------------------------------------------------------------------------


def control(method: str, path: str, payload: Any | None = None) -> Any:
    context = ssl.create_default_context(cafile=str(CERT))
    connection = http.client.HTTPSConnection(
        URL.hostname, URL.port or 443, context=context, timeout=10
    )
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    connection.request(method, path, body=body)
    response = connection.getresponse()
    data = response.read()
    connection.close()
    if response.status != 200:
        raise ContractError(f"{method} {path} answered {response.status}: {data!r}")
    return json.loads(data) if data else None


def reset_world() -> dict[str, Any]:
    return control("POST", "/testlab/reset")


def apply_scenario(name: str = "truenas-state") -> dict[str, Any]:
    return control("POST", "/testlab/scenario", {"name": name})


def power_on() -> dict[str, Any]:
    return control("POST", "/testlab/power", {"state": "on"})


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------


class Contract:
    def __init__(self, write: bool):
        self.write = write
        self.checks = 0
        self.failures: list[str] = []
        self.recorded: list[str] = []

    def ok(self, label: str) -> None:
        self.checks += 1
        print(f"[ok] {label}")

    def fail(self, label: str, detail: str) -> None:
        self.checks += 1
        self.failures.append(f"{label}: {detail}")
        print(f"[FAIL] {label}: {detail}")

    def expect(self, condition: bool, label: str, detail: str = "") -> None:
        if condition:
            self.ok(label)
        else:
            self.fail(label, detail or "condition was false")

    def fixture(self, session: Session, method: str, params: list[Any], name: str) -> None:
        result = session.call(method, params)
        path = FIXTURES / name
        label = f"{method} == test/fixtures/truenas/{name}"
        if not path.exists():
            if not self.write:
                self.fail(label, "the fixture is missing (run again with --write)")
                return
            FIXTURES.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
            self.recorded.append(name)
            self.ok(f"{method} -> fixtures/truenas/{name} (recorded)")
            return
        expected = json.loads(path.read_text())
        if expected == result:
            self.ok(label)
        else:
            self.fail(label, _first_difference(expected, result))

    def expectation_set(self, session: Session) -> None:
        for method, params, name in EXPECTATIONS:
            try:
                self.fixture(session, method, params, name)
            except (ContractError, EOFError) as error:
                self.fail(f"{method} == {name}", str(error))


def _first_difference(expected: Any, actual: Any, path: str = "") -> str:
    if type(expected) is not type(actual):
        return f"{path or 'root'}: {expected!r} is not {actual!r}"
    if isinstance(expected, dict):
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        if missing:
            return f"{path}: missing {missing[:4]}"
        if extra:
            return f"{path}: unexpected {extra[:4]}"
        for key in expected:
            found = _first_difference(expected[key], actual[key], f"{path}.{key}")
            if found:
                return found
        return ""
    if isinstance(expected, list):
        if len(expected) != len(actual):
            return f"{path}: {len(expected)} items, not {len(actual)}"
        for index, (left, right) in enumerate(zip(expected, actual)):
            found = _first_difference(left, right, f"{path}[{index}]")
            if found:
                return found
        return ""
    return "" if expected == actual else f"{path or 'root'}: {expected!r} != {actual!r}"


def _wait_for(read, predicate, label: str, *, timeout: float = 12.0):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            value = read()
            last = value
            if predicate(value):
                return value
        except (ContractError, EOFError) as error:
            last = error
        time.sleep(0.15)
    raise ContractError(f"{label} did not settle (last: {last!r})")


def check_keys(contract: Contract) -> None:
    """I-15: the two keys, and what a key without a write role is refused."""
    admin = Session(ADMIN_KEY)
    readonly = Session(READONLY_KEY)
    try:
        contract.expect(
            admin.call("auth.me") == json.loads((FIXTURES / "auth_me_full_admin.json").read_text()),
            "the admin key answers auth.me as truenas_admin (fixture)",
        )
        contract.expect(
            readonly.call("auth.me")
            == json.loads((FIXTURES / "auth_me_readonly_admin.json").read_text()),
            "the read-only key answers auth.me as auditor (fixture)",
        )
        services = readonly.call("service.query")
        contract.expect(
            isinstance(services, list) and len(services) >= 4,
            "the read-only key can still list services",
            f"service.query answered {services!r}",
        )

        refusals = [
            ("pool.dataset.create", [{"name": "tank/nope"}], EACCES, "a dataset"),
            ("zfs.snapshot.delete", ["tank/media@manual-2026-10-20"], EACCES, "a snapshot"),
            ("sharing.smb.create", [{"name": "nope", "path": "/mnt/tank/nope"}], EACCES, "an SMB share"),
            ("alert.dismiss", ["alert-update-available"], EACCES, "an alert"),
            ("app.start", ["immich"], EACCES, "an app"),
            ("virt.instance.start", ["cupola-vm"], EACCES, "a virt instance"),
            ("system.reboot", ["contract"], EACCES, "a reboot"),
            ("service.start", ["nfs"], EPERM, "a service"),
        ]
        for method, params, expected, what in refusals:
            try:
                data = readonly.attempt(method, params)
            except ContractError as error:
                contract.fail(f"read-only key cannot change {what}", str(error))
                continue
            contract.expect(
                data.get("errname") == expected["errname"]
                and data.get("reason") == expected["reason"],
                f"read-only key cannot change {what} ({expected['errname']})",
                f"{method} answered {data}",
            )

        # Nothing the refusals named changed: a refused write leaves no trace.
        summary = control("GET", "/testlab/state")
        contract.expect(
            summary["apps"].get("immich") == "STOPPED"
            and summary["services"].get("nfs") == "STOPPED"
            and summary["virt"].get("cupola-vm") == "STOPPED"
            and summary["alerts"].get("alert-update-available") is False
            and summary["power"] == "on",
            "the refused writes changed nothing",
            json.dumps(summary, sort_keys=True)[:400],
        )

        # An unknown key is refused at login, as the app reports a key problem.
        anonymous = Session("", login=False)
        contract.expect(
            anonymous.call("auth.login_with_api_key", ["not-a-key"]) is False,
            "an unknown key is refused at login",
        )
        frame = anonymous.raw("pool.query", [])
        anonymous.close()
        contract.expect(
            frame is not None
            and isinstance(frame.get("error"), dict)
            and frame["error"]["data"]["errname"] == "EACCES",
            "a call before a successful login is refused as EACCES",
            f"answer {frame!r}",
        )
    finally:
        admin.close()
        readonly.close()


def check_scrub(contract: Contract) -> None:
    """I-09: a scrub is a job with progress, and the pool says it is scanning."""
    session = Session(ADMIN_KEY)
    try:
        job_id = session.call("pool.scrub.scrub", ["tank", "START"])
        contract.expect(
            isinstance(job_id, int),
            "pool.scrub.scrub answers a job id",
            f"answered {job_id!r}",
        )
        job = _wait_for(
            lambda: session.call("core.get_jobs", [[["id", "=", job_id]]]),
            lambda rows: bool(rows) and rows[0]["state"] == "RUNNING" and rows[0]["progress"]["percent"] > 0,
            "the scrub job",
        )[0]
        contract.expect(
            job["method"] == "pool.scrub.scrub"
            and 0 < job["progress"]["percent"] < 100,
            "core.get_jobs carries the scrub with real progress",
            f"{job!r}",
        )

        tasks = session.call("pool.scrub.query")
        contract.expect(
            any(task.get("pool_name") == "tank" for task in tasks),
            "pool.scrub.query lists the tank scrub task",
            f"{tasks!r}",
        )
        pool = session.call(
            "pool.query", [[["name", "=", "tank"]], {"extra": {"topology": True}}]
        )[0]
        contract.expect(
            pool.get("scan", {}).get("state") == "SCANNING"
            and 0 < pool["scan"].get("percentage", 0) < 100,
            "pool.query shows the running scrub and its percentage",
            f"{pool.get('scan')!r}",
        )

        session.call("pool.scrub.scrub", ["tank", "STOP"])
        stopped = _wait_for(
            lambda: session.call("core.get_jobs", [[["id", "=", job_id]]])[0],
            lambda row: row["state"] == "ABORTED",
            "the stopped scrub job",
        )
        contract.expect(
            stopped["state"] == "ABORTED",
            "stopping a scrub aborts its job",
            f"{stopped!r}",
        )
        pool = session.call("pool.query", [[["name", "=", "tank"]]])[0]
        contract.expect(
            pool.get("scan", {}).get("state") == "FINISHED",
            "the pool records the interrupted scrub as finished",
            f"{pool.get('scan')!r}",
        )
        try:
            session.call("pool.scrub.scrub", ["tank", "STOP"])
            contract.fail("stopping a scrub that is not running is refused", "it was accepted")
        except ContractError as error:
            contract.expect(
                "[EINVAL]" in str(error),
                "stopping a scrub that is not running is refused (EINVAL)",
                str(error),
            )

        # "Run now" on the periodic snapshot task, the other fire-and-forget
        # job the data protection page offers.
        snapshot_tasks = session.call("pool.snapshottask.query")
        contract.expect(
            isinstance(snapshot_tasks, list) and snapshot_tasks,
            "pool.snapshottask.query lists the periodic snapshot task",
            f"{snapshot_tasks!r}",
        )
        job = session.call("pool.snapshottask.run", [snapshot_tasks[0]["id"]])
        finished = _wait_for(
            lambda: session.call("core.get_jobs", [[["id", "=", job]]])[0],
            lambda row: row["state"] == "SUCCESS",
            "pool.snapshottask.run",
        )
        contract.expect(
            finished["method"] == "pool.snapshottask.run",
            "pool.snapshottask.run completes as a job",
            f"{finished!r}",
        )
    finally:
        session.close()


def check_datasets(contract: Contract) -> None:
    """I-10: dataset create/update/delete and snapshot create/delete."""
    session = Session(ADMIN_KEY)
    try:
        created = session.call(
            "pool.dataset.create",
            [{"name": "tank/media/podcasts", "type": "FILESYSTEM", "comments": "Cupola contract"}],
        )
        contract.expect(
            isinstance(created, dict) and created.get("id") == "tank/media/podcasts",
            "pool.dataset.create answers the new dataset",
            f"{created!r}",
        )
        tree = session.call(
            "pool.dataset.query", [[], {"extra": {"flat": False}}]
        )

        def child_ids(node: dict[str, Any]) -> list[str]:
            out = [node["id"]]
            for child in node.get("children", []):
                out.extend(child_ids(child))
            return out

        flat = [identifier for root in tree for identifier in child_ids(root)]
        contract.expect(
            "tank/media/podcasts" in flat,
            "pool.dataset.query returns the new dataset in the tree",
            f"{flat!r}",
        )

        updated = session.call(
            "pool.dataset.update", ["tank/media/podcasts", {"comments": "Updated"}]
        )
        contract.expect(
            updated.get("comments", {}).get("value") == "Updated",
            "pool.dataset.update changes the comment",
            f"{updated!r}",
        )
        read_back = session.call(
            "pool.dataset.query", [[["id", "=", "tank/media/podcasts"]]]
        )
        contract.expect(
            len(read_back) == 1 and read_back[0]["comments"]["value"] == "Updated",
            "the change is read back by pool.dataset.query",
            f"{read_back!r}",
        )

        snapshot = session.call(
            "zfs.snapshot.create",
            [{"dataset": "tank/media/podcasts", "name": "contract", "recursive": False}],
        )
        contract.expect(
            isinstance(snapshot, dict)
            and snapshot.get("id") == "tank/media/podcasts@contract",
            "zfs.snapshot.create answers the snapshot",
            f"{snapshot!r}",
        )
        listed = session.call(
            "zfs.snapshot.query", [[["dataset", "=", "tank/media/podcasts"]]]
        )
        contract.expect(
            [row["snapshot_name"] for row in listed] == ["contract"],
            "zfs.snapshot.query lists the snapshot",
            f"{listed!r}",
        )
        contract.expect(
            session.call(
                "zfs.snapshot.delete", ["tank/media/podcasts@contract"]
            )
            is True,
            "zfs.snapshot.delete removes it",
        )
        contract.expect(
            session.call(
                "zfs.snapshot.query", [[["dataset", "=", "tank/media/podcasts"]]]
            )
            == [],
            "the snapshot is gone",
        )

        try:
            session.call("pool.dataset.delete", ["tank", {"recursive": False}])
            contract.fail("a dataset with children needs recursive", "it was accepted")
        except ContractError as error:
            contract.expect(
                "[EINVAL]" in str(error),
                "deleting a dataset with children needs recursive (EINVAL)",
                str(error),
            )
        contract.expect(
            session.call(
                "pool.dataset.delete", ["tank/media/podcasts", {"recursive": True}]
            )
            is True,
            "pool.dataset.delete removes the dataset",
        )
        contract.expect(
            session.call(
                "pool.dataset.query", [[["id", "=", "tank/media/podcasts"]]]
            )
            == [],
            "the dataset is gone",
        )
    finally:
        session.close()


def check_shares(contract: Contract) -> None:
    """I-11: SMB and NFS shares, and the two sharing services."""
    session = Session(ADMIN_KEY)
    try:
        created = session.call(
            "sharing.smb.create",
            [{"path": "/mnt/tank/media/books", "name": "books", "comment": "Contract", "enabled": True}],
        )
        contract.expect(
            isinstance(created, dict) and created.get("name") == "books",
            "sharing.smb.create answers the share",
            f"{created!r}",
        )
        shares = session.call("sharing.smb.query")
        contract.expect(
            [row["name"] for row in shares if row["name"] == "books"] == ["books"],
            "sharing.smb.query lists the share",
            f"{shares!r}",
        )
        session.call("sharing.smb.update", [created["id"], {"enabled": False}])
        shares = session.call("sharing.smb.query")
        contract.expect(
            [row["enabled"] for row in shares if row["name"] == "books"] == [False],
            "sharing.smb.update disables the share",
            f"{shares!r}",
        )
        contract.expect(
            session.call("sharing.smb.delete", [created["id"]]) is True,
            "sharing.smb.delete removes the share",
        )

        export = session.call(
            "sharing.nfs.create",
            [{"path": "/mnt/tank/media/books", "comment": "Contract", "enabled": True}],
        )
        contract.expect(
            isinstance(export, dict) and export.get("paths") == ["/mnt/tank/media/books"],
            "sharing.nfs.create answers the export",
            f"{export!r}",
        )
        exports = session.call("sharing.nfs.query")
        contract.expect(
            any(row["id"] == export["id"] for row in exports),
            "sharing.nfs.query lists the export",
            f"{exports!r}",
        )
        contract.expect(
            session.call("sharing.nfs.delete", [export["id"]]) is True,
            "sharing.nfs.delete removes the export",
        )

        nfs = session.call("service.start", ["nfs"])
        contract.expect(
            nfs.get("state") == "RUNNING",
            "service.start runs NFS",
            f"{nfs!r}",
        )
        nfs = session.call("service.stop", ["nfs"])
        contract.expect(
            nfs.get("state") == "STOPPED",
            "service.stop stops NFS",
            f"{nfs!r}",
        )
        services = session.call("service.query")
        cifs = next(row for row in services if row["service"] == "cifs")
        session.call("service.update", [cifs["id"], {"enable": False}])
        services = session.call("service.query")
        cifs = next(row for row in services if row["service"] == "cifs")
        contract.expect(
            cifs["enable"] is False and cifs["state"] == "RUNNING",
            "service.update changes autostart without stopping the service",
            f"{cifs!r}",
        )
        try:
            session.call("service.start", ["cifs"])
            contract.fail("starting a running service is refused", "it was accepted")
        except ContractError as error:
            contract.expect(
                "[EINVAL]" in str(error),
                "starting a service that already runs is refused (EINVAL)",
                str(error),
            )
    finally:
        session.close()


def check_accounts(contract: Contract) -> None:
    """I-12: users and groups."""
    session = Session(ADMIN_KEY)
    try:
        user = session.call(
            "user.create",
            [{"username": "cupola-e2e", "full_name": "Cupola E2E", "password": "irrelevant", "group_create": True}],
        )
        contract.expect(
            isinstance(user, dict) and user.get("username") == "cupola-e2e",
            "user.create answers the user",
            f"{user!r}",
        )
        users = session.call("user.query")
        contract.expect(
            any(row["username"] == "cupola-e2e" for row in users),
            "user.query lists the user",
            f"{[row['username'] for row in users]!r}",
        )
        groups = session.call("group.query")
        contract.expect(
            any(row["name"] == "cupola-e2e" for row in groups),
            "group_create made the matching group",
            f"{[row['name'] for row in groups]!r}",
        )
        contract.expect(
            session.call(
                "user.delete", [user["id"], {"delete_group": True}]
            )
            is True,
            "user.delete removes the user",
        )
        contract.expect(
            all(row["username"] != "cupola-e2e" for row in session.call("user.query")),
            "the user is gone from user.query",
        )

        group = session.call("group.create", [{"name": "cupola-e2e"}])
        contract.expect(
            isinstance(group, dict) and group.get("name") == "cupola-e2e",
            "group.create answers the group",
            f"{group!r}",
        )
        contract.expect(
            session.call("group.delete", [group["id"]]) is True,
            "group.delete removes the group",
        )
    finally:
        session.close()


def check_apps(contract: Contract) -> None:
    """I-13 (apps): start, stop, upgrade and delete, each a job."""
    session = Session(ADMIN_KEY)
    try:
        # The scenario makes jellyfin upgradable; the contract applies it first.
        job = session.call("app.start", ["immich"])
        _wait_for(
            lambda: session.call("core.get_jobs", [[["id", "=", job]]])[0],
            lambda row: row["state"] == "SUCCESS",
            "app.start",
        )
        apps = {row["name"]: row for row in session.call("app.query")}
        contract.expect(
            apps["immich"]["state"] == "RUNNING",
            "app.start runs the app once its job succeeds",
            f"{apps['immich']!r}",
        )
        job = session.call("app.stop", ["immich"])
        _wait_for(
            lambda: session.call("core.get_jobs", [[["id", "=", job]]])[0],
            lambda row: row["state"] == "SUCCESS",
            "app.stop",
        )
        apps = {row["name"]: row for row in session.call("app.query")}
        contract.expect(
            apps["immich"]["state"] == "STOPPED",
            "app.stop stops the app",
            f"{apps['immich']!r}",
        )

        job = session.call("app.upgrade", ["jellyfin"])
        _wait_for(
            lambda: session.call("core.get_jobs", [[["id", "=", job]]])[0],
            lambda row: row["state"] == "SUCCESS",
            "app.upgrade",
        )
        apps = {row["name"]: row for row in session.call("app.query")}
        contract.expect(
            apps["jellyfin"]["upgrade_available"] is False
            and apps["jellyfin"]["human_version"] != "10.10.6",
            "app.upgrade moves the version and clears the flag",
            f"{apps['jellyfin']!r}",
        )

        job = session.call("app.delete", ["paperless"])
        _wait_for(
            lambda: session.call("core.get_jobs", [[["id", "=", job]]])[0],
            lambda row: row["state"] == "SUCCESS",
            "app.delete",
        )
        contract.expect(
            all(row["name"] != "paperless" for row in session.call("app.query")),
            "app.delete removes the app when its job succeeds",
        )
        try:
            session.call("app.start", ["jellyfin"])
            contract.fail("starting a running app is refused", "it was accepted")
        except ContractError as error:
            contract.expect(
                "[EINVAL]" in str(error),
                "starting an app that already runs is refused (EINVAL)",
                str(error),
            )
    finally:
        session.close()


def check_virt(contract: Contract) -> None:
    """I-13 (virtualization): start, restart, stop, create and delete."""
    session = Session(ADMIN_KEY)
    try:
        job = session.call("virt.instance.start", ["cupola-vm"])
        _wait_for(
            lambda: session.call("core.get_jobs", [[["id", "=", job]]])[0],
            lambda row: row["state"] == "SUCCESS",
            "virt.instance.start",
        )
        instances = {row["name"]: row for row in session.call("virt.instance.query")}
        contract.expect(
            instances["cupola-vm"]["status"] == "RUNNING",
            "virt.instance.start runs the VM",
            f"{instances['cupola-vm']!r}",
        )
        job = session.call("virt.instance.restart", ["cupola-vm"])
        _wait_for(
            lambda: session.call("core.get_jobs", [[["id", "=", job]]])[0],
            lambda row: row["state"] == "SUCCESS",
            "virt.instance.restart",
        )
        instances = {row["name"]: row for row in session.call("virt.instance.query")}
        contract.expect(
            instances["cupola-vm"]["status"] == "RUNNING",
            "virt.instance.restart comes back running",
            f"{instances['cupola-vm']!r}",
        )
        job = session.call("virt.instance.stop", ["cupola-vm"])
        _wait_for(
            lambda: session.call("core.get_jobs", [[["id", "=", job]]])[0],
            lambda row: row["state"] == "SUCCESS",
            "virt.instance.stop",
        )
        instances = {row["name"]: row for row in session.call("virt.instance.query")}
        contract.expect(
            instances["cupola-vm"]["status"] == "STOPPED",
            "virt.instance.stop stops the VM",
            f"{instances['cupola-vm']!r}",
        )

        job = session.call(
            "virt.instance.create",
            [
                {
                    "name": "cupola-ct",
                    "instance_type": "CONTAINER",
                    "source_type": "IMAGE",
                    "image": "alpine/3.21",
                    "cpu": "2",
                    "memory": 1_073_741_824,
                }
            ],
        )
        _wait_for(
            lambda: session.call("core.get_jobs", [[["id", "=", job]]])[0],
            lambda row: row["state"] == "SUCCESS",
            "virt.instance.create",
        )
        instances = {row["name"]: row for row in session.call("virt.instance.query")}
        contract.expect(
            instances.get("cupola-ct", {}).get("status") == "STOPPED"
            and instances["cupola-ct"]["type"] == "CONTAINER",
            "virt.instance.create adds the instance, stopped",
            f"{instances.get('cupola-ct')!r}",
        )
        job = session.call("virt.instance.delete", ["cupola-ct"])
        _wait_for(
            lambda: session.call("core.get_jobs", [[["id", "=", job]]])[0],
            lambda row: row["state"] == "SUCCESS",
            "virt.instance.delete",
        )
        contract.expect(
            all(
                row["name"] != "cupola-ct"
                for row in session.call("virt.instance.query")
            ),
            "virt.instance.delete removes the instance",
        )
    finally:
        session.close()


def check_alerts_and_power(contract: Contract) -> None:
    """I-14: dismiss an alert, read the update, then reboot and shut down."""
    session = Session(ADMIN_KEY)
    try:
        contract.expect(
            session.call("alert.dismiss", ["alert-update-available"]) is True,
            "alert.dismiss accepts a known alert",
        )
        alerts = session.call("alert.list")
        dismissed = {
            row["uuid"]: row.get("dismissed") for row in alerts
        }
        contract.expect(
            dismissed.get("alert-update-available") is True,
            "the dismissed alert is flagged in alert.list",
            f"{dismissed!r}",
        )
        contract.expect(
            dismissed.get("alert-smart-sdh") is False,
            "the other alerts stay active",
            f"{dismissed!r}",
        )
        update = session.call("update.check_available")
        contract.expect(
            update.get("status") == "AVAILABLE" and update.get("version"),
            "update.check_available reports the update the scenario staged",
            f"{update!r}",
        )
        try:
            session.call("alert.dismiss", ["alert-that-does-not-exist"])
            contract.fail("dismissing an unknown alert is refused", "it was accepted")
        except ContractError as error:
            contract.expect(
                "[ENOENT]" in str(error),
                "dismissing an unknown alert is refused (ENOENT)",
                str(error),
            )

        # A reboot kills the middleware under the reply: no frame comes back,
        # the socket closes, and the machine is down until it is powered on.
        session._frame(
            0x1,
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": 9001,
                    "method": "system.reboot",
                    "params": ["contract"],
                }
            ).encode("utf-8"),
        )
        closed = session.read()
        contract.expect(
            closed is None,
            "system.reboot drops the socket without a reply",
            f"read {closed!r}",
        )
        state = control("GET", "/testlab/state")
        contract.expect(
            state["power"] == "rebooting",
            "the machine reports it is rebooting",
            f"{state['power']!r}",
        )
        reset_for_refused = control("GET", "/testlab/health")
        contract.expect(
            reset_for_refused.get("power") == "rebooting",
            "the control surface still answers while the machine is down",
            f"{reset_for_refused!r}",
        )
        try:
            refused = Session(ADMIN_KEY)
        except (OSError, ContractError, EOFError):
            contract.ok("a WebSocket upgrade is refused while the machine is down")
        else:
            refused.close()
            contract.fail("a WebSocket upgrade is refused while down", "it was accepted")

        state = power_on()
        contract.expect(
            state["power"] == "on",
            "the control surface powers the machine back on",
        )
        session = Session(ADMIN_KEY)
        info = session.call("system.info")
        contract.expect(
            info.get("uptime_seconds", 99) < 60,
            "the machine comes back with a fresh uptime",
            f"{info.get('uptime_seconds')!r}",
        )
        contract.expect(session.call("core.ping") == "pong", "the machine answers again")
    finally:
        session.close()


def check_net_and_reporting(contract: Contract) -> None:
    """The reads the dashboard and the system screens make."""
    session = Session(ADMIN_KEY)
    try:
        info = session.call("system.info")
        contract.expect(
            info.get("hostname") == "nas"
            and info.get("cores") == 8
            and info.get("physmem") == 17_179_869_184,
            "system.info carries the hosted identity",
            f"{info!r}",
        )
        contract.expect(
            session.call("system.version").startswith("TrueNAS-SCALE-25.10"),
            "system.version is a SCALE string the app parses",
            f"{session.call('system.version')!r}",
        )
        graphs = session.call(
            "reporting.get_data",
            [
                [{"name": "cpu"}, {"name": "memory"}, {"name": "arcsize"}, {"name": "interface"}],
                {"unit": "HOUR", "page": 1},
            ],
        )
        contract.expect(
            [graph["name"] for graph in graphs]
            == ["cpu", "memory", "arcsize", "interface"]
            and all(len(graph["data"]) > 0 for graph in graphs),
            "reporting.get_data answers every graph the dashboard asks for",
            f"{[graph['name'] for graph in graphs]!r}",
        )
        live = session.call(
            "reporting.get_data",
            [[{"name": "cpu"}], {"start": int(time.time()) - 300, "end": int(time.time())}],
        )
        contract.expect(
            len(live) == 1 and len(live[0]["data"]) == 60,
            "reporting.get_data honours a start/end window",
            f"{(len(live), len(live[0]['data']) if live else None)!r}",
        )
        interfaces = session.call("interface.query")
        contract.expect(
            interfaces
            and interfaces[0]["state"]["aliases"][0]["address"] == "192.168.1.10",
            "interface.query answers a physical interface with an address",
            f"{interfaces!r}",
        )
        config = session.call("network.configuration.config")
        contract.expect(
            config.get("hostname") == "nas", "network.configuration.config answers"
        )
        general = session.call("system.general.config")
        contract.expect(
            general.get("hostname") == "nas" and general.get("timezone") == "Europe/Rome",
            "system.general.config answers",
            f"{general!r}",
        )
        methods = session.call("core.get_methods")
        contract.expect(
            isinstance(methods, dict) and "reporting.get_data" in methods,
            "core.get_methods names the reporting method",
        )
        jobs = session.call("core.get_jobs")
        contract.expect(
            isinstance(jobs, list),
            "core.get_jobs answers a list",
            f"{jobs!r}",
        )
    finally:
        session.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write",
        action="store_true",
        help="record a fixture that does not exist yet, then compare the rest",
    )
    arguments = parser.parse_args()

    if not CERT.exists():
        print(
            f"The lab's TrueNAS certificate is missing at {CERT}: "
            "run test/e2e/testlab/truenas_cert.sh",
            file=sys.stderr,
        )
        return 2

    contract = Contract(arguments.write)
    try:
        reset_world()
        admin = Session(ADMIN_KEY)
        try:
            contract.expect(
                admin.call("core.ping") == "pong", "core.ping answers pong"
            )
            contract.expectation_set(admin)
        finally:
            admin.close()

        check_keys(contract)
        reset_world()
        check_scrub(contract)
        reset_world()
        check_datasets(contract)
        reset_world()
        check_shares(contract)
        reset_world()
        check_accounts(contract)
        reset_world()
        check_net_and_reporting(contract)
        reset_world()
        apply_scenario("truenas-state")
        check_apps(contract)
        check_virt(contract)
        check_alerts_and_power(contract)
    except (ContractError, EOFError, OSError) as error:
        contract.fail("the contract run", str(error))
    finally:
        try:
            reset_world()
        except OSError:
            pass

    print()
    if contract.recorded:
        print(f"Recorded {len(contract.recorded)} fixture(s): {', '.join(contract.recorded)}")
    if contract.failures:
        print(f"{len(contract.failures)} of {contract.checks} checks failed:")
        for failure in contract.failures:
            print(f"  - {failure}")
        return 1
    print(f"{contract.checks} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
