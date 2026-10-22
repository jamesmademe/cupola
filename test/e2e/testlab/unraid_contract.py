#!/usr/bin/env python3
"""The Unraid simulator's contract: what it answers, against what is committed.

Two questions, and they are different ones:

  * **Does the simulator answer what the fixtures say?** Every reading below is
    compared field by field with `test/fixtures/unraid/`, so the world in
    `mock_unraid/server.py` and the world the app parses cannot drift apart
    silently. Two of those fixtures exist only for the lab (`array_emulated.json`,
    `docker_lab.json`) because the lab's Unraid is a *day*: a disabled disk and a
    restarting container. `array.json` and `docker.json`, beside them, are the
    smaller payloads the client's own unit tests read. Nothing here claims a real
    Unraid was ever asked: the SDL next door says the same thing about itself.
  * **Does it answer what the client understands?** The nine documents are the
    ones `lib/features/unraid/data/unraid_client.dart` sends, spelled as that
    file spells them, and each answer is then read the way the client reads it:
    capacity as strings that parse, a Docker status line in the shape the
    condition parser expects, a libvirt state from the SDL's enum, a timestamp
    `DateTime.tryParse` can read, shares whose `used` and `size` divide.

Then the two things a reading cannot prove: that a transition is visible on the
next read (I-16, I-17), and that the read-only key changes nothing while
answering `FORBIDDEN` with the exact message `unraidGraphQlError` classifies as
a permission refusal.

Nothing here prints a credential. The two keys are the fixed values the Compose
service sets and the lab re-creates: they are not secrets.

    python3 test/e2e/testlab/unraid_contract.py
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
FIXTURES = REPO_ROOT / "test" / "fixtures" / "unraid"

DEFAULT_URL = "http://127.0.0.1:8480"
DEFAULT_ADMIN_KEY = "test-key"
DEFAULT_READONLY_KEY = "cupola-readonly"
UNKNOWN_KEY = "not-a-key"

# The documents `unraid_client.dart` sends. Copied, not re-derived: the Dart
# side already holds them against the committed SDL
# (`test/features/unraid/contract/unraid_schema_test.dart`), and this file's
# job is what the server says back, not what the client selects.
INFO = "query { info { os { distro release uptime } } }"
ARRAY = (
    "query { array { state capacity { kilobytes { free used total } } "
    "parities { name status temp } disks { name status temp } "
    "caches { name status temp } } }"
)
DOCKER = "query { dockerContainers { id names state status autoStart } }"
CAPABILITIES = "query { me { roles permissions { resource actions } } }"
VMS = "query { vms { domains { id name state } } }"
NOTIFICATIONS = (
    "query Notifications($filter: NotificationFilter!) { "
    "notifications { overview { unread { info warning alert total } "
    "archive { info warning alert total } } list(filter: $filter) { "
    "id title subject description importance link type timestamp "
    "formattedTimestamp } } }"
)
SHARES = "query { shares { id name used size cache comment luksStatus } }"
ARCHIVE_NOTIFICATION = (
    "mutation ArchiveNotification($id: PrefixedID!) { "
    "archiveNotification(id: $id) { id title subject description "
    "importance link type timestamp formattedTimestamp } }"
)

# `UnraidVmAction.graphQl`, and the SDL's `VmState` enum.
VM_ACTIONS = ("start", "stop", "pause", "resume", "forceStop", "reboot")
VM_STATES = {
    "NOSTATE",
    "RUNNING",
    "IDLE",
    "PAUSED",
    "SHUTDOWN",
    "SHUTOFF",
    "CRASHED",
    "PMSUSPENDED",
}

DOCKER_STATUS = re.compile(
    r"^(up\b|exited\s*\(\d+\)|restarting\s*\(\d+\)|paused\b|created\b|dead\b)",
    re.IGNORECASE,
)


class Contract:
    """The checks, and the count nobody has to read the whole log for."""

    def __init__(self) -> None:
        self.checks = 0
        self.failures: list[str] = []

    def check(self, what: str, condition: bool, detail: str = "") -> bool:
        self.checks += 1
        if condition:
            print(f"[ok]   {what}")
            return True
        self.failures.append(what)
        print(f"[fail] {what}" + (f": {detail}" if detail else ""))
        return False

    def equal(self, what: str, actual: Any, expected: Any) -> bool:
        return self.check(
            what,
            actual == expected,
            f"{_brief(actual)} != {_brief(expected)}",
        )


def _brief(value: Any, limit: int = 220) -> str:
    text = json.dumps(value, separators=(",", ":"), sort_keys=True)
    return text if len(text) <= limit else f"{text[:limit]}..."


def _difference(actual: Any, expected: Any, path: str = "") -> str:
    """Where two payloads first differ, as `/data/array/disks/1/status`."""
    here = path or "/"
    if type(actual) is not type(expected):
        return f"{here}: {_brief(actual)} != {_brief(expected)}"
    if isinstance(actual, dict):
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        if missing:
            return f"{here}: missing {missing}"
        if extra:
            return f"{here}: unexpected {extra}"
        for key in expected:
            difference = _difference(actual[key], expected[key], f"{path}/{key}")
            if difference:
                return difference
        return ""
    if isinstance(actual, list):
        if len(actual) != len(expected):
            return f"{here}: {len(actual)} entries != {len(expected)}"
        for index, (left, right) in enumerate(zip(actual, expected)):
            difference = _difference(left, right, f"{path}/{index}")
            if difference:
                return difference
        return ""
    return "" if actual == expected else f"{here}: {_brief(actual)} != {_brief(expected)}"


def graphql(
    url: str,
    api_key: str,
    document: str,
    variables: dict[str, Any] | None = None,
) -> tuple[int, dict[str, Any]]:
    body: dict[str, Any] = {"query": document}
    if variables is not None:
        body["variables"] = variables
    call = urllib.request.Request(
        f"{url}/graphql",
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/json", "x-api-key": api_key},
    )
    try:
        with urllib.request.urlopen(call, timeout=15) as response:
            raw = response.read()
            status = response.status
    except urllib.error.HTTPError as error:
        raw = error.read()
        status = error.code
    except (urllib.error.URLError, TimeoutError) as error:
        raise SystemExit(f"{url}/graphql did not answer: {error}") from error
    try:
        payload = json.loads(raw or b"{}")
    except json.JSONDecodeError as error:
        raise SystemExit(
            f"{url}/graphql answered {status} with no JSON: {raw[:200]!r}"
        ) from error
    return status, payload


def reset(url: str, api_key: str) -> None:
    call = urllib.request.Request(
        f"{url}/control/reset",
        data=b"",
        method="POST",
        headers={"x-api-key": api_key},
    )
    try:
        with urllib.request.urlopen(call, timeout=15) as response:
            response.read()
            if response.status != 200:
                raise SystemExit(f"the simulator refused a reset: {response.status}")
    except urllib.error.HTTPError as error:
        raise SystemExit(f"the simulator refused a reset: {error.code}") from error


def wait_ready(url: str, attempts: int = 30) -> None:
    """The Compose healthcheck's own question, asked until it is yes."""
    for _ in range(attempts):
        try:
            with urllib.request.urlopen(f"{url}/graphql", timeout=2) as response:
                if response.status == 200:
                    return
        except (urllib.error.URLError, TimeoutError, OSError):
            pass
        time.sleep(1)
    raise SystemExit(
        f"No Unraid simulator at {url}. Bring it up with "
        f"`docker compose -p cupola-testlab -f docker-compose.testlab.yml "
        f"up -d --no-deps unraid-mock`."
    )


def fixture(name: str) -> dict[str, Any]:
    path = FIXTURES / name
    return json.loads(path.read_text(encoding="utf-8"))


def data_of(payload: dict[str, Any]) -> Any:
    return payload.get("data")


def error_of(payload: dict[str, Any]) -> dict[str, Any]:
    errors = payload.get("errors")
    if isinstance(errors, list) and errors:
        first = errors[0]
        return first if isinstance(first, dict) else {}
    return {}


def readings(url: str, key: str, contract: Contract) -> dict[str, Any]:
    """Every reading, compared to its fixture and then read as the client does."""
    answers: dict[str, Any] = {}
    cases: list[tuple[str, str, dict[str, Any] | None, str]] = [
        ("getInfo", INFO, None, "info.json"),
        ("getArray", ARRAY, None, "array_emulated.json"),
        ("getDockerContainers", DOCKER, None, "docker_lab.json"),
        ("getCapabilities", CAPABILITIES, None, "me_admin.json"),
        ("getVms", VMS, None, "vms.json"),
        (
            "getNotifications(unread)",
            NOTIFICATIONS,
            {"filter": {"type": "UNREAD", "offset": 0, "limit": 100}},
            "notifications_unread.json",
        ),
        (
            "getNotifications(archive)",
            NOTIFICATIONS,
            {"filter": {"type": "ARCHIVE", "offset": 0, "limit": 100}},
            "notifications_archive.json",
        ),
        ("getShares", SHARES, None, "shares.json"),
    ]
    for call, document, variables, fixture_name in cases:
        status, payload = graphql(url, key, document, variables)
        contract.check(f"{call} answers 200", status == 200, str(status))
        contract.check(
            f"{call} carries no GraphQL error",
            not payload.get("errors"),
            _brief(payload.get("errors")),
        )
        expected = data_of(fixture(fixture_name))
        actual = data_of(payload)
        contract.check(
            f"{call} matches {fixture_name}",
            actual == expected,
            _difference(actual, expected),
        )
        answers[call] = actual or {}

    # The client's own reading of each answer. A field that is present but of
    # the wrong shape passes an equality test against a fixture written by the
    # same hand that wrote the world, and still breaks the page.
    info = (answers["getInfo"].get("info") or {}).get("os") or {}
    contract.check(
        "info: os.distro says Unraid",
        info.get("distro") == "Unraid",
        _brief(info),
    )
    contract.check(
        "info: os.release is a version string",
        isinstance(info.get("release"), str) and bool(info["release"].strip()),
        _brief(info.get("release")),
    )
    contract.check(
        "info: os.uptime parses as a timestamp",
        _parses_timestamp(info.get("uptime")),
        _brief(info.get("uptime")),
    )

    array = answers["getArray"].get("array") or {}
    kilobytes = ((array.get("capacity") or {}).get("kilobytes")) or {}
    free = _number(kilobytes.get("free"))
    used = _number(kilobytes.get("used"))
    total = _number(kilobytes.get("total"))
    contract.check(
        "array: capacity is three integer strings with used below total",
        None not in (free, used, total) and 0 < used < total,
        _brief(kilobytes),
    )
    contract.check(
        "array: the used share reads as sixty per cent",
        free is not None
        and used is not None
        and total is not None
        and round(used / total * 100) == 60,
        f"{used} of {total}",
    )
    slots = [
        *((array.get("parities") or [])),
        *((array.get("disks") or [])),
        *((array.get("caches") or [])),
    ]
    contract.check(
        "array: every slot names itself and its state",
        all(
            isinstance(slot.get("name"), str)
            and bool(slot["name"].strip())
            and isinstance(slot.get("status"), str)
            and bool(slot["status"].strip())
            for slot in slots
        ),
        _brief(slots),
    )
    contract.check(
        "array: a slot is missing a temperature rather than reporting zero",
        all(
            slot.get("temp") is None
            or (isinstance(slot.get("temp"), int) and 0 < slot["temp"] < 100)
            for slot in slots
        ),
        _brief(slots),
    )
    disabled = [slot for slot in slots if slot.get("status") == "DISK_DSBL"]
    contract.check(
        "array: one disabled disk, spun down, and the app flags it",
        len(disabled) == 1 and disabled[0].get("temp") is None,
        _brief(disabled),
    )
    contract.check(
        "array: one empty slot is a slot and not a fault",
        bool([slot for slot in slots if slot.get("status") == "DISK_NP"]),
        _brief(slots),
    )
    contract.check(
        "array: a warm drive is above the 45 C threshold",
        any(
            isinstance(slot.get("temp"), int) and slot["temp"] >= 45
            for slot in slots
        ),
        _brief(slots),
    )

    containers = answers["getDockerContainers"].get("dockerContainers") or []
    contract.check(
        "docker: every row has a name prefixed the way Docker writes it",
        all(
            isinstance(row.get("names"), list)
            and row["names"]
            and str(row["names"][0]).startswith("/")
            for row in containers
        ),
        _brief(containers),
    )
    contract.check(
        "docker: every status line is one the condition parser reads",
        all(DOCKER_STATUS.match(str(row.get("status") or "")) for row in containers),
        _brief([row.get("status") for row in containers]),
    )
    contract.check(
        "docker: every state is a word the SDL's enum declares",
        all(str(row.get("state")) in {"running", "exited", "restarting"} for row in containers),
        _brief([row.get("state") for row in containers]),
    )
    statuses = [str(row.get("status") or "") for row in containers]
    contract.check(
        "docker: one container is up and one is stopped on purpose",
        any(status.startswith("Up ") and "(" not in status for status in statuses)
        and "Exited (0) 4 hours ago" in statuses,
        _brief(statuses),
    )
    contract.check(
        "docker: the four faults and stops the parser tells apart are all here",
        any("(unhealthy)" in status for status in statuses)
        and any(status.startswith("Exited (137)") for status in statuses)
        and any(status.startswith("Restarting (1)") for status in statuses),
        _brief(statuses),
    )

    domains = ((answers["getVms"].get("vms") or {}).get("domains")) or []
    contract.check(
        "vms: every id is a prefixed id and every state is in the SDL enum",
        all(
            str(domain.get("id") or "").startswith("vm:")
            and str(domain.get("state") or "").upper() in VM_STATES
            and bool(str(domain.get("name") or "").strip())
            for domain in domains
        ),
        _brief(domains),
    )
    states = {str(domain.get("state") or "").upper() for domain in domains}
    contract.check(
        "vms: a running, a stopped, a paused and a crashed guest",
        {"RUNNING", "SHUTOFF", "PAUSED", "CRASHED"} <= states,
        _brief(sorted(states)),
    )

    unread = answers["getNotifications(unread)"].get("notifications") or {}
    archive = answers["getNotifications(archive)"].get("notifications") or {}
    unread_overview = unread.get("overview") or {}
    archive_overview = archive.get("overview") or {}
    contract.check(
        "notifications: the unread filter answers only unread rows",
        all(str(row.get("type")) == "UNREAD" for row in unread.get("list") or []),
        _brief(unread.get("list")),
    )
    contract.check(
        "notifications: the archive filter answers only archived rows",
        all(str(row.get("type")) == "ARCHIVE" for row in archive.get("list") or []),
        _brief(archive.get("list")),
    )
    contract.check(
        "notifications: the overview counts the lists it is beside",
        (unread_overview.get("unread") or {}).get("total") == len(unread.get("list") or [])
        and (unread_overview.get("archive") or {}).get("total") == len(archive.get("list") or []),
        _brief(unread_overview),
    )
    contract.check(
        "notifications: every importance is one the model knows",
        all(
            str(row.get("importance") or "").upper() in {"ALERT", "INFO", "WARNING"}
            for row in (unread.get("list") or []) + (archive.get("list") or [])
        ),
        _brief([row.get("importance") for row in unread.get("list") or []]),
    )
    contract.check(
        "notifications: every timestamp is one DateTime.tryParse reads",
        all(
            _parses_timestamp(row.get("timestamp"))
            for row in (unread.get("list") or []) + (archive.get("list") or [])
        ),
        _brief([row.get("timestamp") for row in unread.get("list") or []]),
    )
    contract.check(
        "notifications: the disabled disk is announced, and it is an alert",
        any(
            str(row.get("id")) == "notification:disk2-disabled"
            and str(row.get("importance")) == "ALERT"
            and "Disk 2" in str(row.get("subject"))
            for row in unread.get("list") or []
        ),
        _brief(unread.get("list")),
    )

    shares = answers["getShares"].get("shares") or []
    contract.check("shares: the lab reports its shares", len(shares) >= 3, _brief(shares))
    contract.check(
        "shares: used and size are integers that divide",
        all(
            _number(share.get("used")) is not None
            and _number(share.get("size")) is not None
            and _number(share.get("size")) > 0
            and _number(share.get("used")) <= _number(share.get("size"))
            for share in shares
        ),
        _brief(shares),
    )
    contract.check(
        "shares: cache is a boolean and luksStatus a word",
        all(
            isinstance(share.get("cache"), bool)
            and isinstance(share.get("luksStatus"), str)
            and bool(share["luksStatus"].strip())
            for share in shares
        ),
        _brief(shares),
    )
    contract.check(
        "shares: one share is on the cache pool and one is encrypted",
        any(share.get("cache") is True for share in shares)
        and any(share.get("luksStatus") == "ENCRYPTED" for share in shares),
        _brief(shares),
    )

    roles = (answers["getCapabilities"].get("me") or {}).get("roles") or []
    contract.check(
        "capabilities: the read-write key is ADMIN",
        "ADMIN" in roles,
        _brief(roles),
    )

    # Every key of every fixture is a field the client actually selects: a
    # fixture the app never reads is a fixture that proves nothing.
    documents = [INFO, ARRAY, DOCKER, CAPABILITIES, VMS, NOTIFICATIONS, SHARES]
    selected = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", " ".join(documents)))
    fixture_keys = set()
    for name in (
        "info.json",
        "array_emulated.json",
        "docker_lab.json",
        "me_admin.json",
        "vms.json",
        "notifications_unread.json",
        "notifications_archive.json",
        "shares.json",
    ):
        fixture_keys |= _keys_of(data_of(fixture(name)))
    contract.check(
        "the fixtures carry no field the client's documents do not select",
        fixture_keys <= selected,
        _brief(sorted(fixture_keys - selected)),
    )
    return answers


def transitions(url: str, key: str, contract: Contract) -> None:
    """I-16 and I-17: a transition is visible on the next read."""

    def vms() -> dict[str, str]:
        _, payload = graphql(url, key, VMS)
        domains = ((data_of(payload) or {}).get("vms") or {}).get("domains") or []
        return {str(domain["id"]): str(domain["state"]) for domain in domains}

    def act(vm_id: str, verb: str) -> dict[str, Any]:
        document = (
            "mutation VmAction($id: PrefixedID!) { vm { "
            f"{verb}(id: $id) }} }}"
        )
        _, payload = graphql(url, key, document, {"id": vm_id})
        return payload

    contract.equal("vms: the world starts as the fixture says", vms(), _domains(fixture("vms.json")))

    payload = act("vm:windows", "start")
    contract.equal("start: the daemon accepted", data_of(payload), {"vm": {"start": True}})
    contract.equal("start: the next read says running", vms().get("vm:windows"), "RUNNING")

    payload = act("vm:windows", "start")
    contract.equal(
        "start on a running guest: the daemon refused with false, not an error",
        data_of(payload),
        {"vm": {"start": False}},
    )

    payload = act("vm:windows", "stop")
    contract.equal("stop: the daemon accepted", data_of(payload), {"vm": {"stop": True}})
    contract.equal("stop: the next read says stopped", vms().get("vm:windows"), "SHUTOFF")

    payload = act("vm:windows", "stop")
    contract.equal(
        "stop on a stopped guest: the daemon refused with false",
        data_of(payload),
        {"vm": {"stop": False}},
    )

    payload = act("vm:homeassistant", "pause")
    contract.equal("pause: the daemon accepted", data_of(payload), {"vm": {"pause": True}})
    contract.equal("pause: the next read says paused", vms().get("vm:homeassistant"), "PAUSED")

    payload = act("vm:homeassistant", "resume")
    contract.equal("resume: the daemon accepted", data_of(payload), {"vm": {"resume": True}})
    contract.equal("resume: the next read says running", vms().get("vm:homeassistant"), "RUNNING")

    payload = act("vm:homeassistant", "reboot")
    contract.equal("reboot on a running guest: accepted and still running", data_of(payload), {"vm": {"reboot": True}})
    contract.equal("reboot: the guest did not leave the running state", vms().get("vm:homeassistant"), "RUNNING")

    payload = act("vm:nasbackup", "forceStop")
    contract.equal("forceStop: the daemon accepted", data_of(payload), {"vm": {"forceStop": True}})
    contract.equal("forceStop: the next read says stopped", vms().get("vm:nasbackup"), "SHUTOFF")
    act("vm:nasbackup", "start")
    contract.equal("start: the paused guest is running again", vms().get("vm:nasbackup"), "RUNNING")

    payload = act("vm:nowhere", "start")
    contract.equal(
        "an id no domain answers is an error, not a false",
        error_of(payload).get("extensions", {}).get("code"),
        "NOT_FOUND",
    )
    contract.equal("an unknown id changes nothing", vms().get("vm:homeassistant"), "RUNNING")

    before = fixture("notifications_unread.json")
    unread_filter = {"filter": {"type": "UNREAD", "offset": 0, "limit": 100}}
    status, payload = graphql(url, key, NOTIFICATIONS, unread_filter)
    contract.check("notifications: the unread read answers 200", status == 200, str(status))
    listed = ((data_of(payload) or {}).get("notifications") or {}).get("list") or []
    contract.check(
        "notifications: the alert about the disabled disk is unread to begin with",
        any(row.get("id") == "notification:disk2-disabled" for row in listed),
        _brief(listed),
    )
    unread_before = len(listed)

    payload = graphql(
        url, key, ARCHIVE_NOTIFICATION, {"id": "notification:disk2-disabled"}
    )[1]
    archived = data_of(payload) or {}
    contract.equal(
        "archiveNotification: the daemon answered the archived row",
        (archived.get("archiveNotification") or {}).get("id"),
        "notification:disk2-disabled",
    )
    contract.equal(
        "archiveNotification: the row it answers is archived",
        (archived.get("archiveNotification") or {}).get("type"),
        "ARCHIVE",
    )
    original = {
        row["id"]: row for row in before["data"]["notifications"]["list"]
    }["notification:disk2-disabled"]
    answered = dict(archived.get("archiveNotification") or {})
    answered.pop("type", None)
    expected_row = dict(original)
    expected_row.pop("type", None)
    contract.equal(
        "archiveNotification: the fields the client shows survive the archive",
        answered,
        expected_row,
    )

    _, payload = graphql(url, key, NOTIFICATIONS, unread_filter)
    after = (data_of(payload) or {}).get("notifications") or {}
    contract.check(
        "notifications: the archived id is gone from the unread list",
        all(row.get("id") != "notification:disk2-disabled" for row in after.get("list") or []),
        _brief(after.get("list")),
    )
    contract.equal(
        "notifications: the unread list shrank by one",
        (after.get("overview") or {}).get("unread", {}).get("total"),
        unread_before - 1,
    )
    contract.equal(
        "notifications: the archive grew by one",
        (after.get("overview") or {}).get("archive", {}).get("total"),
        2,
    )

    status, payload = graphql(
        url,
        key,
        NOTIFICATIONS,
        {"filter": {"type": "ARCHIVE", "offset": 0, "limit": 100}},
    )
    rows = ((data_of(payload) or {}).get("notifications") or {}).get("list") or []
    contract.equal(
        "notifications: the archive lists it first, newest first",
        [row.get("id") for row in rows][:2],
        ["notification:disk2-disabled", "notification:array-started"],
    )

    payload = graphql(
        url, key, ARCHIVE_NOTIFICATION, {"id": "notification:disk2-disabled"}
    )[1]
    contract.equal(
        "archiveNotification twice is the same state, not a failure",
        (data_of(payload) or {}).get("archiveNotification", {}).get("id"),
        "notification:disk2-disabled",
    )

    payload = graphql(
        url, key, ARCHIVE_NOTIFICATION, {"id": "notification:nowhere"}
    )[1]
    contract.equal(
        "archiving an id no notification answers is an error",
        error_of(payload).get("extensions", {}).get("code"),
        "NOT_FOUND",
    )


def keys(url: str, admin_key: str, readonly_key: str, contract: Contract) -> None:
    """The read-only key, and a key that is not one."""

    forbidden = error_of(fixture("error_forbidden.json"))
    unauthenticated = error_of(fixture("error_unauthenticated.json"))

    status, payload = graphql(
        url,
        readonly_key,
        CAPABILITIES,
    )
    contract.check("read-only: me answers 200", status == 200, str(status))
    contract.equal(
        "read-only: me is the viewer with no permissions, as the fixture says",
        data_of(payload),
        data_of(fixture("me_viewer.json")),
    )
    status, payload = graphql(url, readonly_key, ARRAY)
    contract.check(
        "read-only: the array reads",
        status == 200 and data_of(payload) == data_of(fixture("array_emulated.json")),
        _difference(data_of(payload), data_of(fixture("array_emulated.json"))),
    )

    for verb in VM_ACTIONS:
        document = (
            "mutation VmAction($id: PrefixedID!) { vm { "
            f"{verb}(id: $id) }} }}"
        )
        status, payload = graphql(url, readonly_key, document, {"id": "vm:windows"})
        error = error_of(payload)
        contract.check(
            f"read-only: vm.{verb} is refused with 200 and FORBIDDEN",
            status == 200
            and error.get("message") == forbidden.get("message")
            and error.get("extensions", {}).get("code")
            == forbidden.get("extensions", {}).get("code"),
            _brief(payload),
        )
        contract.check(
            f"read-only: vm.{verb} names the path it was refused on",
            error.get("path") == ["vm", verb],
            _brief(error.get("path")),
        )

    status, payload = graphql(
        url,
        readonly_key,
        ARCHIVE_NOTIFICATION,
        {"id": "notification:disk2-disabled"},
    )
    error = error_of(payload)
    contract.check(
        "read-only: archiveNotification is refused with the same message",
        status == 200
        and error.get("message") == forbidden.get("message")
        and error.get("extensions", {}).get("code")
        == forbidden.get("extensions", {}).get("code"),
        _brief(payload),
    )
    contract.equal(
        "read-only: the world did not move",
        data_of(graphql(url, admin_key, VMS)[1]),
        data_of(fixture("vms.json")),
    )
    contract.equal(
        "read-only: nothing was archived",
        data_of(
            graphql(
                url,
                admin_key,
                NOTIFICATIONS,
                {"filter": {"type": "UNREAD", "offset": 0, "limit": 100}},
            )[1]
        ),
        data_of(fixture("notifications_unread.json")),
    )

    status, payload = graphql(url, UNKNOWN_KEY, INFO)
    error = error_of(payload)
    contract.check(
        "unknown key: 200 with UNAUTHENTICATED, as the fixture says",
        status == 200
        and error.get("message") == unauthenticated.get("message")
        and error.get("extensions", {}).get("code")
        == unauthenticated.get("extensions", {}).get("code"),
        _brief(payload),
    )
    contract.equal(
        "unknown key: no data came with the refusal",
        data_of(payload),
        None,
    )


def _domains(payload: dict[str, Any]) -> dict[str, str]:
    domains = ((data_of(payload) or {}).get("vms") or {}).get("domains") or []
    return {str(domain["id"]): str(domain["state"]) for domain in domains}


def _keys_of(value: Any) -> set[str]:
    if isinstance(value, dict):
        found = set(value)
        for nested in value.values():
            found |= _keys_of(nested)
        return found
    if isinstance(value, list):
        found = set()
        for nested in value:
            found |= _keys_of(nested)
        return found
    return set()


def _number(value: Any) -> int | None:
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return None


def _parses_timestamp(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--key", default=DEFAULT_ADMIN_KEY)
    parser.add_argument("--readonly-key", default=DEFAULT_READONLY_KEY)
    arguments = parser.parse_args()

    url = arguments.url.rstrip("/")
    admin_key = arguments.key

    wait_ready(url)
    contract = Contract()

    reset(url, admin_key)
    readings(url, admin_key, contract)
    transitions(url, admin_key, contract)
    reset(url, admin_key)
    keys(url, admin_key, arguments.readonly_key, contract)

    # Back to the world the scenario leaves behind, so a contract run is not a
    # state change somebody finds later.
    reset(url, admin_key)
    _, payload = graphql(url, admin_key, VMS)
    contract.equal(
        "a reset restores the world the fixtures describe",
        data_of(payload),
        data_of(fixture("vms.json")),
    )

    print()
    if contract.failures:
        print(f"{contract.checks} checks, {len(contract.failures)} failed:")
        for failure in contract.failures:
            print(f"  - {failure}")
        return 1
    print(f"{contract.checks} checks, all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
