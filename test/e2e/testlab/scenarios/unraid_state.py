"""The Unraid simulator's documented world, on demand.

Unraid's two flows (I-16, I-17) are transitions, so their state is not a file
somebody can drop: a VM that was started stays started, and a notification that
was archived does not come back through the API. This scenario therefore owns
the simulator's *clock*: it resets the world through the control route the
simulator exposes for exactly this reason, then proves the state the flows
expect by reading it back through the GraphQL API the app reads.

`apply` is idempotent (a second run resets to the same world), and `teardown`
is the same call, because the world *is* the state a finished run has to leave
behind. `verify_absent` is the interesting half: it proves that what a run does
(stopping, pausing, archiving) is gone, rather than merely that the service
still answers.

The key is the fixed lab key the Compose file sets for the read-write scope.
It is not a secret, and nothing here prints it.

    python3 test/e2e/testlab/testlab.py scenario apply unraid-state
    python3 test/e2e/testlab/testlab.py scenario teardown unraid-state
"""

from __future__ import annotations

from typing import Any

from .base import Scenario, ScenarioError, request, require_ok

UNRAID = "http://127.0.0.1:8480"
HEADERS = {"x-api-key": "test-key"}

ARRAY = (
    "query { array { state capacity { kilobytes { free used total } } "
    "parities { name status temp } disks { name status temp } "
    "caches { name status temp } } }"
)
VMS = "query { vms { domains { id name state } } }"
CONTAINERS = "query { dockerContainers { id names state } }"
SHARES = "query { shares { id name } }"
NOTIFICATIONS = (
    "query Notifications($filter: NotificationFilter!) { "
    "notifications { overview { unread { total } archive { total } } "
    "list(filter: $filter) { id type } } }"
)

# What the world says, and what the two flows need it to say. The full field by
# field comparison lives in `unraid_contract.py`: these are the facts a run
# depends on, not a second copy of the fixtures.
EXPECTED_VMS = {
    "vm:homeassistant": "RUNNING",
    "vm:windows": "SHUTOFF",
    "vm:nasbackup": "PAUSED",
    "vm:retro": "CRASHED",
}
EXPECTED_UNREAD = {
    "notification:cache-hot",
    "notification:disk2-disabled",
    "notification:parity-check",
}


def graphql(document: str, variables: dict[str, Any] | None = None) -> Any:
    status, body = request(
        f"{UNRAID}/graphql",
        method="POST",
        payload={"query": document, "variables": variables or {}},
        headers=HEADERS,
    )
    require_ok(status, body, "the Unraid simulator")
    if not isinstance(body, dict):
        raise ScenarioError(
            f"the Unraid simulator answered {type(body).__name__}, not an object"
        )
    errors = body.get("errors")
    if errors:
        raise ScenarioError(f"the Unraid simulator refused: {errors[0]}")
    data = body.get("data")
    if not isinstance(data, dict):
        raise ScenarioError("the Unraid simulator answered with no data")
    return data


def _domains() -> dict[str, str]:
    data = graphql(VMS)
    domains = (data.get("vms") or {}).get("domains") or []
    return {str(domain.get("id")): str(domain.get("state")) for domain in domains}


def _notifications(list_type: str) -> dict[str, Any]:
    data = graphql(
        NOTIFICATIONS,
        {"filter": {"type": list_type, "offset": 0, "limit": 100}},
    )
    return (data.get("notifications") or {})


def reset() -> None:
    status, body = request(
        f"{UNRAID}/control/reset",
        method="POST",
        payload=b"",
        headers=HEADERS,
    )
    require_ok(status, body, "resetting the Unraid simulator")


class UnraidStateScenario(Scenario):
    name = "unraid-state"
    profiles = ("core",)

    def apply(self) -> None:
        reset()

    def teardown(self) -> None:
        reset()

    def verify(self) -> None:
        array = (graphql(ARRAY).get("array") or {})
        if str(array.get("state")) != "STARTED":
            raise ScenarioError(f"the array is {array.get('state')!r}, not STARTED")

        slots = [
            *((array.get("parities") or [])),
            *((array.get("disks") or [])),
            *((array.get("caches") or [])),
        ]
        disabled = [slot for slot in slots if slot.get("status") == "DISK_DSBL"]
        if len(disabled) != 1 or disabled[0].get("name") != "disk2":
            raise ScenarioError(
                "the array has no single disabled disk 2 to emulate: "
                f"{[slot.get('name') for slot in slots]}"
            )

        kilobytes = (array.get("capacity") or {}).get("kilobytes") or {}
        try:
            used = int(str(kilobytes.get("used")))
            total = int(str(kilobytes.get("total")))
        except (TypeError, ValueError) as error:
            raise ScenarioError(
                f"the array capacity is not readable: {kilobytes}"
            ) from error
        if total <= 0 or round(used / total * 100) != 60:
            raise ScenarioError(
                f"the array is not sixty per cent used: {kilobytes}"
            )

        domains = _domains()
        if domains != EXPECTED_VMS:
            raise ScenarioError(f"the VMs are not the documented set: {domains}")

        unread = _notifications("UNREAD")
        ids = {str(row.get("id")) for row in unread.get("list") or []}
        if ids != EXPECTED_UNREAD:
            raise ScenarioError(f"the unread notifications are {sorted(ids)}")
        if (unread.get("overview") or {}).get("unread", {}).get("total") != 3:
            raise ScenarioError("the unread count does not say three")
        archive = _notifications("ARCHIVE")
        if (archive.get("overview") or {}).get("archive", {}).get("total") != 1:
            raise ScenarioError("the archive does not hold one notification")

        containers = graphql(CONTAINERS).get("dockerContainers") or []
        names = {str(row.get("names")[0]).removeprefix("/") for row in containers}
        missing = {"plex", "radarr", "sonarr", "jellyfin"} - names
        if missing:
            raise ScenarioError(
                f"the Docker tab is missing the lab's stack: {sorted(missing)}"
            )
        counts = {"running": 0, "exited": 0, "restarting": 0}
        for row in containers:
            state = str(row.get("state"))
            if state not in counts:
                raise ScenarioError(f"a container is in {state!r}, not a state")
            counts[state] += 1
        if counts["running"] < 2 or counts["exited"] < 2:
            raise ScenarioError(f"the containers are not a running lab: {counts}")

        shares = graphql(SHARES).get("shares") or []
        if {str(share.get("name")) for share in shares} != {
            "media",
            "backups",
            "appdata",
        }:
            raise ScenarioError(
                f"the shares are {[share.get('name') for share in shares]}"
            )

    def verify_absent(self) -> None:
        # The world itself is what `verify` proves. What a run adds is movement:
        # a guest left running or paused, a notification left in the archive.
        domains = _domains()
        moved = {
            key: value
            for key, value in domains.items()
            if EXPECTED_VMS.get(key) != value
        }
        if moved:
            raise ScenarioError(
                f"a run's VM transitions are still in place: {moved}"
            )
        unread = _notifications("UNREAD")
        ids = {str(row.get("id")) for row in unread.get("list") or []}
        if ids != EXPECTED_UNREAD:
            raise ScenarioError(
                f"a run's archive is still in place, unread: {sorted(ids)}"
            )
        archive = _notifications("ARCHIVE")
        if (archive.get("overview") or {}).get("archive", {}).get("total") != 1:
            raise ScenarioError("the archive did not come back to one notification")


SCENARIO = UnraidStateScenario()
