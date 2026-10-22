"""The TrueNAS simulator, in the state the infrastructure flows start from.

Catalogue I-09..I-15 (``A-20261021-catalogo-dei-flussi-4a87``) need a NAS that
has somewhere to scrub, a pool that is degraded, a dataset tree, shares, users,
apps with an update waiting, an instance to start, alerts to dismiss, and a key
that may only read. The simulator's world already is that house; what this
scenario adds is the *moment*: an update available, Jellyfin with one to
install, no scrub in flight, and nothing left over from a previous journey.

``apply`` resets the simulator to its world, proves the reset is deterministic
(two resets, the same digest), then stages the moment. ``teardown`` resets
again, so a journey cannot poison the next one. ``verify_absent`` proves the
teardown left the base world and none of the staged state behind.

The state is reached through the simulator's own control surface on its TLS
port, which is the API it publishes for exactly this purpose; nothing here
writes files or restarts a container.
"""

from __future__ import annotations

import http.client
import json
import os
import ssl
import urllib.parse
from typing import Any

from .base import STATE_ROOT, Scenario, ScenarioError

URL = urllib.parse.urlparse(
    os.environ.get("CUPOLA_TESTLAB_TRUENAS_URL", "https://127.0.0.1:8460")
)
CERT = STATE_ROOT / "truenas" / "truenas.crt"
SCENARIO_NAME = "truenas-state"


def control(method: str, path: str, payload: Any | None = None) -> Any:
    """One request to the simulator's control surface, over its TLS cert."""
    if not CERT.exists():
        raise ScenarioError(
            f"the lab's TrueNAS certificate is missing at {CERT}; "
            "run test/e2e/testlab/truenas_cert.sh"
        )
    connection = http.client.HTTPSConnection(
        URL.hostname,
        URL.port or 443,
        context=ssl.create_default_context(cafile=str(CERT)),
        timeout=15,
    )
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    try:
        connection.request(method, path, body=body)
        response = connection.getresponse()
        data = response.read()
        status = response.status
    except OSError as error:
        raise ScenarioError(f"{method} {path} did not answer: {error}") from error
    finally:
        connection.close()
    if status != 200:
        raise ScenarioError(f"{method} {path} answered {status}: {data!r}")
    return json.loads(data) if data else None


def reset() -> dict[str, Any]:
    return control("POST", "/testlab/reset")


def state() -> dict[str, Any]:
    return control("GET", "/testlab/state")


def stage(name: str | None) -> dict[str, Any]:
    return control("POST", "/testlab/scenario", {"name": name})


class TrueNasStateScenario(Scenario):
    name = SCENARIO_NAME
    profiles = ("core",)

    base_digest: str | None = None

    def apply(self) -> None:
        first = reset()
        second = reset()
        if first["worldDigest"] != second["worldDigest"]:
            raise ScenarioError(
                "two resets of the simulator produced different worlds: "
                f"{first['worldDigest']} != {second['worldDigest']}"
            )
        type(self).base_digest = second["worldDigest"]
        stage(SCENARIO_NAME)

    def teardown(self) -> None:
        summary = reset()
        type(self).base_digest = summary["worldDigest"]
        stage(None)

    def verify(self) -> None:
        summary = state()
        if summary.get("scenario") != SCENARIO_NAME:
            raise ScenarioError("the simulator is not marked as prepared")
        pools = {pool["name"]: pool for pool in summary["pools"]}
        if pools.get("tank", {}).get("status") != "ONLINE" or not pools["tank"]["healthy"]:
            raise ScenarioError(f"the healthy pool is not healthy: {pools.get('tank')}")
        if pools.get("backup", {}).get("status") != "DEGRADED" or pools["backup"]["healthy"]:
            raise ScenarioError(f"the degraded pool is not degraded: {pools.get('backup')}")
        if pools["tank"].get("scan") == "SCANNING":
            raise ScenarioError("a scrub is already running on tank")
        for dataset in (
            "tank/media/movies",
            "tank/media/series",
            "tank/media/music",
            "tank/media/books",
        ):
            if dataset not in summary["datasets"]:
                raise ScenarioError(f"the dataset tree lacks {dataset}")
        if summary["apps"].get("immich") != "STOPPED":
            raise ScenarioError("immich is not stopped, so a start proves nothing")
        if summary["apps"].get("jellyfin") != "RUNNING":
            raise ScenarioError("jellyfin is not running")
        if "jellyfin" not in summary["upgradable"]:
            raise ScenarioError("jellyfin has no upgrade waiting")
        if summary["update"] != "AVAILABLE":
            raise ScenarioError(f"no update is available: {summary['update']}")
        if summary["virt"].get("cupola-vm") != "STOPPED":
            raise ScenarioError("the VM is not stopped, so a start proves nothing")
        for alert in ("alert-smart-sdh", "alert-backup-degraded", "alert-update-available"):
            if summary["alerts"].get(alert) is not False:
                raise ScenarioError(f"the alert {alert} is not active")
        if summary["services"].get("nfs") != "STOPPED":
            raise ScenarioError("NFS is not stopped, so a start proves nothing")
        if summary["jobs"]:
            raise ScenarioError(f"the prepared world carries jobs: {summary['jobs']}")
        readonly = set(summary["keys"]["readonly"])
        writes = {role for role in readonly if role.endswith(("_WRITE", "_DELETE"))}
        if writes:
            raise ScenarioError(
                "the read-only key carries write roles: " + ", ".join(sorted(writes))
            )
        if "FULL_ADMIN" not in set(summary["keys"]["admin"]):
            raise ScenarioError("the admin key is not a full administrator")

    def verify_absent(self) -> None:
        summary = state()
        if summary.get("scenario") is not None:
            raise ScenarioError(
                f"the simulator is still marked as {summary['scenario']!r}"
            )
        if summary["update"] != "UNAVAILABLE":
            raise ScenarioError(
                f"the staged update is still there: {summary['update']}"
            )
        if summary["upgradable"]:
            raise ScenarioError(
                f"apps still carry an upgrade: {summary['upgradable']}"
            )
        if summary["jobs"]:
            raise ScenarioError(f"the base world carries jobs: {summary['jobs']}")
        if self.base_digest is not None and summary["worldDigest"] != self.base_digest:
            raise ScenarioError(
                "teardown did not leave the world it started from: "
                f"{summary['worldDigest']} != {self.base_digest}"
            )


SCENARIO = TrueNasStateScenario()
