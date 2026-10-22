"""A stateful Unraid GraphQL simulator for the Cupola testlab.

Unraid is the one simulator in this lab whose answers are not a reading: the
two flows the flow catalogue declares for it (I-16, I-17) are *transitions*, so
a `start` has to be visible on the next `vms` read and an archived notification
has to leave the unread list. This service keeps one world in memory and moves
it, which is why it has its own build context rather than a mode of the shared
protocol mocks beside it.

The world below is the canonical one, and `test/fixtures/unraid/` holds the same
world as the responses the app parses: `array_emulated.json`, `docker_lab.json`,
`info.json`, `vms.json`, `shares.json`, `notifications_unread.json` and
`notifications_archive.json`. The two are deliberately separate files so that
`test/e2e/testlab/unraid_contract.py` can prove they agree: it reads this
service over HTTP and compares every answer to the fixture, field by field.
`docker.json` and `array.json`, beside them, are the smaller payloads the
client's own unit tests read; the lab's Unraid is a *day*, with a disabled disk
and a restarting container.

What the array says, and why: Unraid's worst ordinary day is a disabled data
disk the array is still running on, emulated from parity. It is a slot status
(`DISK_DSBL`) and no field of the app's query carries the word *emulated*, so
the notification says it. The cache drive at 47 C exercises the warm threshold
on a drive that is present; the second parity slot is empty (`DISK_NP`), which
is a slot and not a fault.

Keys, fixed by this file and the Compose service (they are lab values, not
secrets):

  * `MOCK_API_KEY` (default `test-key`, and what Compose sets) is the
    read-write key: `me` answers ADMIN, and the mutations are accepted.
  * `MOCK_READONLY_KEY` (default `cupola-readonly`) is a real Unraid key with
    no write scope: `me` answers VIEWER with no permissions, reads work, and a
    mutation is refused the way Unraid refuses one, `200` with a GraphQL error
    whose `extensions.code` is `FORBIDDEN` and whose message is
    "Forbidden resource". That is the pair `unraidGraphQlError` reads as a
    permission refusal rather than as a broken key.
  * any other key is answered `200` with `UNAUTHENTICATED` and
    "API key is invalid", because Unraid's status line says nothing about the
    key: the GraphQL error does.

`POST /control/reset` with the read-write key puts the world back; the
`unraid-state` scenario calls it on `apply` and on `teardown`, which is what
makes a mutating run repeatable. `GET /graphql` answers `200` with an empty
body, which is what the Compose healthcheck asks.

Not simulated, on purpose: the intermediate libvirt states (`SHUTDOWN` while a
guest halts), because there is no clock here and a state that changes by itself
would make the answers depend on when they were read; and any container or
array mutation, because the app's contract does not declare one (I-19).
"""

from __future__ import annotations

import json
import os
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

API_KEY = os.environ.get("MOCK_API_KEY", "test-key")
READONLY_KEY = os.environ.get("MOCK_READONLY_KEY", "cupola-readonly")
PORT = int(os.environ.get("MOCK_PORT", "8480"))

ADMIN = "admin"
READ_ONLY = "read_only"

FORBIDDEN = {
    "message": "Forbidden resource",
    "extensions": {"code": "FORBIDDEN"},
}
UNAUTHENTICATED = {
    "message": "API key is invalid",
    "extensions": {"code": "UNAUTHENTICATED"},
}


class GraphQlError(Exception):
    """One GraphQL error, the way the client will read it."""

    def __init__(self, message: str, code: str, *, path: list[Any] | None = None):
        super().__init__(message)
        self.payload: dict[str, Any] = {
            "message": message,
            "extensions": {"code": code},
        }
        if path is not None:
            self.payload["path"] = path


# ─── The world ──────────────────────────────────────────────────────────────


def initial_world() -> dict[str, Any]:
    """The lab's Unraid, as it is before anything acts on it."""
    return {
        "info": {
            "os": {
                "distro": "Unraid",
                "release": "7.0.0",
                "uptime": "2026-07-01T00:00:00Z",
            }
        },
        "array": {
            "state": "STARTED",
            "capacity": {
                "kilobytes": {
                    "free": "4000000000",
                    "used": "6000000000",
                    "total": "10000000000",
                }
            },
            "parities": [
                {"name": "parity", "status": "DISK_OK", "temp": 36},
                {"name": "parity2", "status": "DISK_NP", "temp": None},
            ],
            "disks": [
                {"name": "disk1", "status": "DISK_OK", "temp": 38},
                # Disabled and emulated from parity: the array runs, and a
                # spun-down drive reports no temperature rather than 0 C.
                {"name": "disk2", "status": "DISK_DSBL", "temp": None},
            ],
            "caches": [
                {"name": "cache", "status": "DISK_OK", "temp": 47},
            ],
        },
        # The lab's own stack, as Unraid would run it: every row carries the
        # status line Docker writes, because that string is the field that says
        # an exit code and an age (the two-member `state` enum cannot express
        # unhealthy, paused or a restart loop). One is stopped on purpose, one
        # is unhealthy while up, one was OOM-killed and one keeps restarting.
        "dockerContainers": [
            {
                "id": "3f1c9a2b7d10",
                "names": ["/plex"],
                "state": "running",
                "status": "Up 3 days",
                "autoStart": True,
            },
            {
                "id": "9a4e2c8f10b3",
                "names": ["/radarr"],
                "state": "running",
                "status": "Up 3 days",
                "autoStart": True,
            },
            {
                "id": "b7d210e5c4a8",
                "names": ["/sonarr"],
                "state": "running",
                "status": "Up 3 days",
                "autoStart": True,
            },
            {
                "id": "1c8f3a9d20e7",
                "names": ["/lidarr"],
                "state": "running",
                "status": "Up 2 days",
                "autoStart": True,
            },
            {
                "id": "5e2b7c1a9f04",
                "names": ["/readarr"],
                "state": "exited",
                "status": "Exited (0) 4 hours ago",
                "autoStart": True,
            },
            {
                "id": "8d3a1f6b2c95",
                "names": ["/prowlarr"],
                "state": "running",
                "status": "Up 2 days",
                "autoStart": True,
            },
            {
                "id": "c41e9b7a305d",
                "names": ["/bazarr"],
                "state": "running",
                "status": "Up 2 days (unhealthy)",
                "autoStart": True,
            },
            {
                "id": "2a7d5c8e1b46",
                "names": ["/qbittorrent"],
                "state": "running",
                "status": "Up 3 days",
                "autoStart": True,
            },
            {
                "id": "f9b1e4d6a273",
                "names": ["/sabnzbd"],
                "state": "running",
                "status": "Up 1 day",
                "autoStart": True,
            },
            {
                "id": "6c2e8a4f7b19",
                "names": ["/seerr"],
                "state": "running",
                "status": "Up 3 days",
                "autoStart": True,
            },
            {
                "id": "e7a3d1b9c582",
                "names": ["/jellyfin"],
                "state": "running",
                "status": "Up 3 days",
                "autoStart": True,
            },
            {
                "id": "4b9f2e7c1d68",
                "names": ["/dockge"],
                "state": "running",
                "status": "Up 2 days",
                "autoStart": True,
            },
            {
                "id": "a1d5c3e9b742",
                "names": ["/nginx-proxy-manager"],
                "state": "restarting",
                "status": "Restarting (1) 20 seconds ago",
                "autoStart": True,
            },
            {
                "id": "7e4b1a8d3c06",
                "names": ["/nzbget"],
                "state": "exited",
                "status": "Exited (137) 2 hours ago",
                "autoStart": True,
            },
        ],
        "vms": {
            "domains": [
                {
                    "id": "vm:homeassistant",
                    "name": "Home Assistant",
                    "state": "RUNNING",
                },
                {"id": "vm:windows", "name": "Windows 11 lab", "state": "SHUTOFF"},
                {"id": "vm:nasbackup", "name": "NAS backup", "state": "PAUSED"},
                {"id": "vm:retro", "name": "Retro console", "state": "CRASHED"},
            ]
        },
        "notifications": {
            "unread": [
                {
                    "id": "notification:cache-hot",
                    "title": "Warning [TOWER] - Cache drive temperature is 47 C",
                    "subject": "Cache drive temperature is 47 C",
                    "description": "The cache pool is above the 45 C warning threshold.",
                    "importance": "WARNING",
                    "link": "",
                    "type": "UNREAD",
                    "timestamp": "2026-10-21T18:40:07.004Z",
                    "formattedTimestamp": "2026-10-21 18:40:07",
                },
                {
                    "id": "notification:disk2-disabled",
                    "title": "Alert [TOWER] - Disk 2 in error state (disk dsbl)",
                    "subject": "Disk 2 in error state (disk dsbl)",
                    "description": (
                        "Disk 2 is disabled and being emulated from parity. "
                        "Replace the drive, then rebuild."
                    ),
                    "importance": "ALERT",
                    "link": "",
                    "type": "UNREAD",
                    "timestamp": "2026-10-20T09:12:41.118Z",
                    "formattedTimestamp": "2026-10-20 09:12:41",
                },
                {
                    "id": "notification:parity-check",
                    "title": "Notice [TOWER] - Parity check finished",
                    "subject": "Parity check finished",
                    "description": "Parity check found 0 errors in 6 hours 12 minutes.",
                    "importance": "INFO",
                    "link": "",
                    "type": "UNREAD",
                    "timestamp": "2026-10-19T03:04:00.000Z",
                    "formattedTimestamp": "2026-10-19 03:04:00",
                },
            ],
            "archive": [
                {
                    "id": "notification:array-started",
                    "title": "Notice [TOWER] - Array started",
                    "subject": "Array started",
                    "description": "The array is started and all disks are online.",
                    "importance": "INFO",
                    "link": "",
                    "type": "ARCHIVE",
                    "timestamp": "2026-10-12T07:30:12.000Z",
                    "formattedTimestamp": "2026-10-12 07:30:12",
                }
            ],
        },
        "shares": [
            {
                "id": "share:media",
                "name": "media",
                "used": "6000000000",
                "size": "10000000000",
                "cache": False,
                "comment": "Movies, series and music",
                "luksStatus": "NOT_ENCRYPTED",
            },
            {
                "id": "share:backups",
                "name": "backups",
                "used": "1800000000",
                "size": "5000000000",
                "cache": False,
                "comment": "Nightly backups",
                "luksStatus": "ENCRYPTED",
            },
            {
                "id": "share:appdata",
                "name": "appdata",
                "used": "40000000",
                "size": "200000000",
                "cache": True,
                "comment": "Container appdata",
                "luksStatus": "NOT_ENCRYPTED",
            },
        ],
    }


# ─── The documents the app sends ─────────────────────────────────────────────

# The verbs `unraid_client.dart` can spell (`UnraidVmAction`), and the state
# each of them leaves behind. A verb a state cannot take answers **false**: the
# mutation ran and the daemon refused it, which is the arm the app reports
# ("<vm> did not accept <verb>"), not an exception.
VM_TRANSITIONS: dict[str, dict[str, str]] = {
    "start": {
        "SHUTOFF": "RUNNING",
        "SHUTDOWN": "RUNNING",
        "CRASHED": "RUNNING",
        "NOSTATE": "RUNNING",
    },
    "stop": {
        "RUNNING": "SHUTOFF",
        "PAUSED": "SHUTOFF",
        "PMSUSPENDED": "SHUTOFF",
        "CRASHED": "SHUTOFF",
    },
    "pause": {"RUNNING": "PAUSED"},
    "resume": {"PAUSED": "RUNNING"},
    "forceStop": {
        "RUNNING": "SHUTOFF",
        "PAUSED": "SHUTOFF",
        "PMSUSPENDED": "SHUTOFF",
        "CRASHED": "SHUTOFF",
    },
    # A reboot leaves the guest running: there is no clock to pass through the
    # halt, and a domain nobody can read back as RUNNING would fail a flow the
    # app supports.
    "reboot": {"RUNNING": "RUNNING"},
}


def role_for(api_key: str | None) -> str | None:
    if api_key and api_key == API_KEY:
        return ADMIN
    if api_key and api_key == READONLY_KEY:
        return READ_ONLY
    return None


# ─── A very small GraphQL reader ─────────────────────────────────────────────


def _matching_brace(text: str, start: int) -> int:
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    raise GraphQlError(
        "The document has an unbalanced selection set.",
        "GRAPHQL_PARSE_FAILED",
    )


def _skip_parens(text: str, start: int) -> int:
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return index + 1
    return len(text)


def fields(text: str) -> list[tuple[str, str | None]]:
    """The fields of one selection set, with their sub-selection.

    Enough GraphQL for the nine documents `unraid_client.dart` can send, and
    no more: no fragments, no directives, no literal arguments (the app passes
    every value through `variables`). An argument list is skipped whole, so a
    variable name inside it is never mistaken for a field.
    """
    found: list[tuple[str, str | None]] = []
    index = 0
    while index < len(text):
        char = text[index]
        if char == "#":
            newline = text.find("\n", index)
            index = len(text) if newline < 0 else newline + 1
        elif char == "(":
            index = _skip_parens(text, index)
        elif char == "$":
            index += 1
            while index < len(text) and (text[index].isalnum() or text[index] == "_"):
                index += 1
        elif char.isalpha() or char == "_":
            end = index
            while end < len(text) and (text[end].isalnum() or text[end] == "_"):
                end += 1
            name = text[index:end]
            index = end
            while index < len(text) and text[index].isspace():
                index += 1
            if index < len(text) and text[index] == "(":
                index = _skip_parens(text, index)
                while index < len(text) and text[index].isspace():
                    index += 1
            if index < len(text) and text[index] == "{":
                close = _matching_brace(text, index)
                found.append((name, text[index + 1 : close]))
                index = close + 1
            else:
                found.append((name, None))
        else:
            index += 1
    return found


def operation_of(document: str) -> tuple[str, list[tuple[str, str | None]]]:
    text = document.strip()
    if not text:
        raise GraphQlError("The document is empty.", "GRAPHQL_PARSE_FAILED")
    operation = "mutation" if text.startswith("mutation") else "query"
    start = text.find("{")
    if start < 0:
        raise GraphQlError(
            "The document has no selection set.",
            "GRAPHQL_PARSE_FAILED",
        )
    close = _matching_brace(text, start)
    return operation, fields(text[start + 1 : close])


def variable(variables: dict[str, Any], name: str, type_name: str) -> Any:
    if name not in variables:
        raise GraphQlError(
            f'Variable "${name}" of required type "{type_name}!" was not provided.',
            "BAD_USER_INPUT",
        )
    return variables[name]


# ─── The answers ─────────────────────────────────────────────────────────────


def counts(items: list[dict[str, Any]]) -> dict[str, int]:
    tally = {"info": 0, "warning": 0, "alert": 0}
    for item in items:
        key = str(item.get("importance", "")).lower()
        if key in tally:
            tally[key] += 1
    return {**tally, "total": len(items)}


def notifications_payload(
    world: dict[str, Any],
    variables: dict[str, Any],
) -> dict[str, Any]:
    wanted = variable(variables, "filter", "NotificationFilter")
    if not isinstance(wanted, dict):
        raise GraphQlError(
            'Variable "$filter" of required type "NotificationFilter!" was invalid.',
            "BAD_USER_INPUT",
        )
    importance = str(wanted.get("importance") or "").upper()
    list_type = str(wanted.get("type") or "UNREAD").upper()
    offset = max(0, int(wanted.get("offset") or 0))
    limit = max(0, int(wanted.get("limit") or 100))
    unread = world["notifications"]["unread"]
    archive = world["notifications"]["archive"]
    items = unread if list_type == "UNREAD" else archive
    if importance:
        items = [item for item in items if item["importance"] == importance]
    return {
        "overview": {
            "unread": counts(unread),
            "archive": counts(archive),
        },
        "list": items[offset : offset + limit],
    }


def run_vm_action(
    world: dict[str, Any],
    verb: str,
    vm_id: Any,
) -> bool:
    if verb not in VM_TRANSITIONS:
        raise GraphQlError(
            f'Cannot query field "{verb}" on type "VmMutations".',
            "GRAPHQL_VALIDATION_FAILED",
            path=["vm", str(verb)],
        )
    domain = next(
        (
            candidate
            for candidate in world["vms"]["domains"]
            if candidate["id"] == str(vm_id)
        ),
        None,
    )
    if domain is None:
        raise GraphQlError(
            f'No VM with id "{vm_id}".',
            "NOT_FOUND",
            path=["vm", verb],
        )
    state = str(domain["state"]).upper()
    after = VM_TRANSITIONS[verb].get(state)
    if after is None:
        return False
    domain["state"] = after
    return True


def archive_notification(
    world: dict[str, Any],
    notification_id: Any,
) -> dict[str, Any]:
    wanted = str(notification_id)
    for item in list(world["notifications"]["unread"]):
        if item["id"] == wanted:
            world["notifications"]["unread"].remove(item)
            archived = {**item, "type": "ARCHIVE"}
            world["notifications"]["archive"].insert(0, archived)
            return archived
    # Archiving what is already archived is the same state, not an error:
    # the app's own row disappears on the first call, so a second one is a
    # retry, and a retry that fails is a row that comes back.
    for item in world["notifications"]["archive"]:
        if item["id"] == wanted:
            return item
    raise GraphQlError(
        f'No notification with id "{wanted}".',
        "NOT_FOUND",
        path=["archiveNotification"],
    )


def me_payload(role: str) -> dict[str, Any]:
    return {
        "roles": ["ADMIN"] if role == ADMIN else ["VIEWER"],
        "permissions": [],
    }


class UnraidState:
    """The world, and the lock that makes a transition atomic."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._world = initial_world()

    def reset(self) -> None:
        with self._lock:
            self._world = initial_world()

    def answer(
        self,
        document: str,
        variables: dict[str, Any],
        role: str,
    ) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        with self._lock:
            return self._answer(document, variables, role)

    def _answer(
        self,
        document: str,
        variables: dict[str, Any],
        role: str,
    ) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        operation, roots = operation_of(document)
        data: dict[str, Any] = {}
        errors: list[dict[str, Any]] = []
        for name, selection in roots:
            try:
                if operation == "query":
                    data[name] = self._query(name, selection, variables, role)
                else:
                    data[name] = self._mutation(name, selection, variables, role)
            except GraphQlError as error:
                errors.append(error.payload)
        return data, errors

    def _query(
        self,
        name: str,
        selection: str | None,
        variables: dict[str, Any],
        role: str,
    ) -> Any:
        world = self._world
        if name == "info":
            return world["info"]
        if name == "array":
            return world["array"]
        if name == "dockerContainers":
            return world["dockerContainers"]
        if name == "shares":
            return world["shares"]
        if name == "me":
            return me_payload(role)
        if name == "vms":
            return world["vms"]
        if name == "notifications":
            return notifications_payload(world, variables)
        raise GraphQlError(
            f'Cannot query field "{name}" on type "Query".',
            "GRAPHQL_VALIDATION_FAILED",
        )

    def _mutation(
        self,
        name: str,
        selection: str | None,
        variables: dict[str, Any],
        role: str,
    ) -> Any:
        world = self._world
        if name == "vm":
            root = fields(selection or "")
            if not root:
                raise GraphQlError(
                    "The vm mutation selects no action.",
                    "GRAPHQL_PARSE_FAILED",
                )
            verb = root[0][0]
            vm_id = variable(variables, "id", "PrefixedID")
            # The refusal carries the path the document took, the way the
            # committed error fixture does (`["vm", "stop"]`); its message and
            # its code are the two fields the client classifies.
            if role != ADMIN:
                raise GraphQlError(
                    FORBIDDEN["message"],
                    "FORBIDDEN",
                    path=["vm", verb],
                )
            return {verb: run_vm_action(world, verb, vm_id)}
        if name == "archiveNotification":
            notification_id = variable(variables, "id", "PrefixedID")
            if role != ADMIN:
                raise GraphQlError(
                    FORBIDDEN["message"],
                    "FORBIDDEN",
                    path=["archiveNotification"],
                )
            return archive_notification(world, notification_id)
        raise GraphQlError(
            f'Cannot query field "{name}" on type "Mutation".',
            "GRAPHQL_VALIDATION_FAILED",
        )


# ─── HTTP ───────────────────────────────────────────────────────────────────


def json_bytes(value: object) -> bytes:
    return json.dumps(value, separators=(",", ":")).encode("utf-8")


class UnraidHandler(BaseHTTPRequestHandler):
    server_version = "CupolaUnraidSimulator/2.0"
    state = UnraidState()

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        path = urllib.parse.urlparse(self.path).path
        if path == "/graphql":
            # The Compose healthcheck asks this without a key and only wants a
            # 2xx: the API is up, and nothing else is claimed.
            self._send(200, b"", "text/plain")
            return
        self.send_error(404)

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        path = urllib.parse.urlparse(self.path).path
        if path == "/control/reset":
            self._reset()
            return
        if path != "/graphql":
            self.send_error(404)
            return
        role = role_for(self.headers.get("x-api-key"))
        if role is None:
            self._send_json(
                200,
                {"errors": [UNAUTHENTICATED], "data": None},
            )
            return
        try:
            size = int(self.headers.get("content-length", "0"))
            payload = json.loads(self.rfile.read(size))
        except (ValueError, json.JSONDecodeError):
            self.send_error(400)
            return
        if not isinstance(payload, dict):
            self.send_error(400)
            return
        document = payload.get("query")
        if not isinstance(document, str):
            self.send_error(400)
            return
        variables = payload.get("variables")
        if not isinstance(variables, dict):
            variables = {}
        try:
            data, errors = UnraidHandler.state.answer(document, variables, role)
        except GraphQlError as error:
            data, errors = {}, [error.payload]
        body: dict[str, Any] = {"data": data if data or not errors else None}
        if errors:
            body["errors"] = errors
        self._send_json(200, body)

    def _reset(self) -> None:
        # The control route is the one thing here that is not Unraid's API: a
        # simulator needs a way back to its documented state, and the scenario
        # that owns that state is the caller. It is not reachable with the
        # read-only key, so an app pointed at this port cannot wipe the lab.
        if role_for(self.headers.get("x-api-key")) != ADMIN:
            self._send_json(
                403,
                {"error": "the control route needs the read-write key"},
            )
            return
        UnraidHandler.state.reset()
        self._send_json(200, {"reset": True})

    def _send_json(self, status: int, value: object) -> None:
        self._send(status, json_bytes(value), "application/json")

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> None:
    server = ThreadingHTTPServer(("0.0.0.0", PORT), UnraidHandler)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
