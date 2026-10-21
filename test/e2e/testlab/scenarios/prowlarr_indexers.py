"""Prowlarr and a throwaway indexer: added, tested, toggled, edited in bulk,
deleted. The flow catalogue's A-13, A-14 and A-15.

The indexer is a second Torznab definition pointing at the same local fake
indexer as the lab's own ``Cupola testlab``, so its test really walks out to a
tracker and the app's "answered" is the fake indexer's answer, not a stub. It
carries its own name so nothing it does can reach the seeded one: the scenario
records the seeded indexer's shape, never touches it, and proves on teardown
that it is unchanged.

Two things this scenario leaves behind on purpose, and takes out again:

* Prowlarr syncs a new indexer to Radarr within seconds, without a command.
* Deleting an indexer does **not** delete the copy Radarr holds, so ``teardown``
  ends with an ``ApplicationIndexerSync`` and waits for Radarr to drop it.

``verify`` re-tests the throwaway and re-runs ``testall``, so the two answers
the app shows ("<name> answered", "All N indexers passed") are the server's
own at the moment they are read.
"""

from __future__ import annotations

import json
from pathlib import Path

import prowlarr_lab as lab

from .base import STATE_ROOT, Scenario, ScenarioError

NAME = "Cupola testlab throwaway"
MARKER = STATE_ROOT / "backup" / "prowlarr_indexers" / "state.json"
# A port nothing listens on inside the lab network: the refusal is a socket
# error, not a timeout, so the failing test answers in under a second.
DEAD_URL = "http://testlab-indexer:1"


def _load() -> dict:
    if not MARKER.exists():
        return {}
    try:
        return json.loads(MARKER.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ScenarioError(f"the scenario marker is unreadable: {error}") from error


def _forget() -> None:
    """Take the marker out, and the folder it lived in when it is the last one."""
    if MARKER.exists():
        MARKER.unlink()
    if MARKER.parent.is_dir() and not any(MARKER.parent.iterdir()):
        MARKER.parent.rmdir()


def _save(marker: dict) -> None:
    MARKER.parent.mkdir(parents=True, exist_ok=True)
    MARKER.write_text(json.dumps(marker, indent=2, sort_keys=True), encoding="utf-8")


def _require_shape(item: dict) -> None:
    """The indexer as the app's row reads it: a Torznab, on, at priority 2."""
    if item.get("name") != NAME:
        raise ScenarioError(f"the throwaway indexer is named {item.get('name')!r}")
    if item.get("implementation") != "Torznab":
        raise ScenarioError(
            f"{NAME} is a {item.get('implementation')!r}, not a Torznab"
        )
    if not item.get("enable"):
        raise ScenarioError(f"{NAME} is not enabled")
    if item.get("priority") != 2:
        raise ScenarioError(
            f"{NAME} reads priority {item.get('priority')}, not the bulk edit's 2"
        )
    if lab.field_value(item, "baseUrl") != lab.LOCAL_INDEXER_URL:
        raise ScenarioError(
            f"{NAME} points at {lab.field_value(item, 'baseUrl')!r}, "
            f"not the local indexer"
        )


class ProwlarrIndexers(Scenario):
    name = "prowlarr-indexers"
    profiles = ("core",)

    def apply(self) -> None:
        seeded = lab.seeded()
        if not seeded.get("enable"):
            raise ScenarioError(
                f"the lab's {lab.SEEDED_INDEXER!r} indexer is disabled; "
                "this scenario does not fix lab state"
            )
        marker = _load()
        recorded = marker.get("seeded")
        if isinstance(recorded, dict) and recorded != lab.summary(seeded):
            raise ScenarioError(
                f"the lab's indexer changed since the marker was written: "
                f"{lab.summary(seeded)} != {recorded}"
            )
        marker["seeded"] = lab.summary(seeded)

        item = lab.by_name(NAME)
        if item is None:
            item = lab.create(NAME)
        marker["throwaway"] = item["id"]
        _save(marker)

        # A-14: the tracker answers, and a dead address does not.
        lab.test_indexer(item)
        failures = lab.test_refusal(item, DEAD_URL)
        if not any(
            "onnect" in str(failure.get("errorMessage"))
            or "onnect" in str(failure.get("detailedDescription"))
            for failure in failures
        ):
            raise ScenarioError(
                f"the dead-address test failed without a connection reason: {failures}"
            )
        report = lab.test_all()
        by_id = {entry.get("id"): entry for entry in report}
        for indexer in (seeded, item):
            entry = by_id.get(indexer["id"])
            if entry is None:
                raise ScenarioError(
                    f"testall reported nothing for {indexer['name']!r}: {report}"
                )
            if not entry.get("isValid"):
                raise ScenarioError(
                    f"testall reports {indexer['name']!r} invalid: "
                    f"{entry.get('validationFailures')}"
                )

        # A-15: off, then on again with a bulk edit, exactly as the row toggle
        # and the "Edit N indexers" sheet do it.
        lab.bulk([item["id"]], enable=False)
        if lab.require_by_name(NAME).get("enable"):
            raise ScenarioError(f"{NAME} stayed enabled after the bulk disable")
        lab.bulk([item["id"]], enable=True, priority=2)
        _require_shape(lab.require_by_name(NAME))

    def teardown(self) -> None:
        marker = _load()
        item = lab.by_name(NAME)
        if item is not None:
            lab.bulk_delete([item["id"]])
            if lab.by_name(NAME) is not None:
                raise ScenarioError(f"{NAME} survived the bulk delete")

        # Prowlarr does not push the deletion: only a sync reconciles Radarr.
        lab.sync_apps()
        lab.wait_app(lab.MOVIE_APP, f"{NAME}{lab.SYNC_SUFFIX}", present=False)

        seeded = marker.get("seeded")
        if isinstance(seeded, dict) and seeded.get("id"):
            current = lab.require_by_name(lab.SEEDED_INDEXER)
            if lab.summary(current) != seeded:
                restore = {
                    key: seeded[key]
                    for key in ("enable", "priority", "appProfileId")
                    if seeded.get(key) is not None
                }
                lab.bulk([seeded["id"]], **restore)
        _forget()

    def verify(self) -> None:
        seeded = lab.require_by_name(lab.SEEDED_INDEXER)
        marker = _load()
        expected = marker.get("seeded")
        if isinstance(expected, dict) and lab.summary(seeded) != expected:
            raise ScenarioError(
                f"the seeded indexer changed: {lab.summary(seeded)} != {expected}"
            )
        if not seeded.get("enable"):
            raise ScenarioError(f"{lab.SEEDED_INDEXER} is disabled")

        item = lab.require_by_name(NAME)
        _require_shape(item)
        lab.test_indexer(item)
        report = lab.test_all()
        if not all(entry.get("isValid") for entry in report):
            raise ScenarioError(f"an indexer is failing its test: {report}")

    def verify_absent(self) -> None:
        if lab.by_name(NAME) is not None:
            raise ScenarioError(f"{NAME} is still in Prowlarr")
        seeded = lab.require_by_name(lab.SEEDED_INDEXER)
        if not seeded.get("enable"):
            raise ScenarioError(f"{lab.SEEDED_INDEXER} came out of teardown disabled")
        names = lab.app_indexer_names(lab.MOVIE_APP)
        if f"{NAME}{lab.SYNC_SUFFIX}" in names:
            raise ScenarioError(
                f"{lab.MOVIE_APP} still holds {NAME!r}: {names}"
            )
        if f"{lab.SEEDED_INDEXER}{lab.SYNC_SUFFIX}" not in names:
            raise ScenarioError(
                f"{lab.MOVIE_APP} lost the lab's indexer: {names}"
            )
        if MARKER.exists():
            raise ScenarioError("the scenario left its marker behind")


SCENARIO = ProwlarrIndexers()
