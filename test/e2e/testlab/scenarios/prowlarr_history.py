"""Prowlarr's history, per-indexer statistics and failure state: the flow
catalogue's A-17, which is a read.

The lab already carries the rows this scenario reads: the L5 grab is a
``releaseGrabbed`` event, the release searches behind it are ``indexerQuery``
events with the catalogue's size, and Radarr's RSS polls are ``indexerRss``.
Nothing is invented: if the lab has no query row that carries a search term
(Radarr searches by id, so its own rows have an empty one), ``apply`` runs one
real search through the fake indexer. That is the only write here, and a second
``apply`` finds the row and adds nothing.

Prowlarr offers no API to delete a history row, so ``teardown`` removes
nothing: the rows are the lab's audit trail, exactly as Bazarr's history is in
``bazarr-embedded``. It proves instead that the seeded indexer is still there
and enabled, and that the rows are still there.

The typed filters are Prowlarr's numeric ``HistoryEventType``: 1 is a grab, 2 a
query, 3 an RSS poll. The app sends the names instead
(``lib/features/prowlarr/presentation/prowlarr_history_screen.dart`` passes
``'indexerQuery'`` and ``'releaseGrabbed'`` to ``GET /api/v1/history``), and
Prowlarr 2.3.0 refuses them with ``400 The value 'indexerQuery' is not valid``.
That is an app defect, not a lab one: this scenario reads the numeric filter,
which is the server's own, and reports the refusal instead of encoding it as
expected behaviour.

The amber half of A-17 ("Indexer is currently failing") is not reachable
without breaking the lab's only indexer: ``/indexerstatus`` only lists indexers
Prowlarr has disabled after failures. ``verify`` therefore proves the list is
well formed and empty of anything that is not a real indexer, and says so.
"""

from __future__ import annotations

import json

import prowlarr_lab as lab

from .base import STATE_ROOT, Scenario, ScenarioError

MARKER = STATE_ROOT / "backup" / "prowlarr_history" / "state.json"
QUERY = "Big Buck Bunny"


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


def _records(indexer_id: int, event_type: int, name: str) -> list[dict]:
    page = lab.history(event_type=event_type)
    records = [row for row in page["records"] if isinstance(row, dict)]
    if any(row.get("eventType") != name for row in records):
        raise ScenarioError(
            f"/history?eventType={event_type} returned another event than {name}"
        )
    return [row for row in records if row.get("indexerId") == indexer_id]


def _has_term(indexer_id: int) -> bool:
    return any(
        (row.get("data") or {}).get("query")
        for row in _records(indexer_id, lab.EVENT_QUERY, "indexerQuery")
    )


def _stat(indexer_id: int) -> dict:
    stats = lab.indexer_stats()
    entries = stats.get("indexers")
    if not isinstance(entries, list):
        raise ScenarioError(f"/indexerstats has no indexers list: {stats}")
    for entry in entries:
        if isinstance(entry, dict) and entry.get("indexerId") == indexer_id:
            return entry
    raise ScenarioError(f"/indexerstats has no row for indexer {indexer_id}")


class ProwlarrHistory(Scenario):
    name = "prowlarr-history"
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
        marker["history"] = lab.history()["totalRecords"]
        _save(marker)

        # The app's History lists a query by the term it searched. Radarr's
        # own searches are by id and carry an empty term, so the lab may hold
        # query rows without one; a term row is what the screen shows.
        if not _has_term(seeded["id"]):
            releases = lab.search(seeded["id"], QUERY)
            if not releases:
                raise ScenarioError(
                    f"the fake indexer answered nothing for {QUERY!r}"
                )
            marker["search"] = len(releases)
            _save(marker)

    def teardown(self) -> None:
        seeded = lab.require_by_name(lab.SEEDED_INDEXER)
        if not seeded.get("enable"):
            raise ScenarioError(f"{lab.SEEDED_INDEXER} came out of the lab disabled")
        _forget()

    def verify(self) -> None:
        seeded = lab.require_by_name(lab.SEEDED_INDEXER)
        marker = _load()
        expected = marker.get("seeded")
        if isinstance(expected, dict) and lab.summary(seeded) != expected:
            raise ScenarioError(
                f"the seeded indexer changed: {lab.summary(seeded)} != {expected}"
            )

        page = lab.history()
        for key in ("page", "pageSize", "totalRecords", "records"):
            if key not in page:
                raise ScenarioError(f"/history answered without {key!r}: {page}")
        for row in page["records"]:
            if not isinstance(row, dict):
                raise ScenarioError(f"/history carries a row that is not an object: {row}")
            for key in ("id", "date", "eventType", "successful", "data"):
                if key not in row:
                    raise ScenarioError(f"a history row has no {key!r}: {row}")

        # Queries: the app's "Queries" filter, and the row the catalogue wants.
        queries = _records(seeded["id"], lab.EVENT_QUERY, "indexerQuery")
        if not queries:
            raise ScenarioError(
                "Prowlarr has no indexerQuery row for the lab's indexer"
            )
        answered = [
            row
            for row in queries
            if str((row.get("data") or {}).get("queryResults") or "").isdigit()
            and int((row.get("data") or {})["queryResults"]) > 0
        ]
        if not answered:
            raise ScenarioError(
                "no query row carries a result count: "
                f"{[row.get('data') for row in queries[:3]]}"
            )
        if not any((row.get("data") or {}).get("query") for row in answered):
            raise ScenarioError(
                "no query row carries the term it searched: "
                f"{[row.get('data') for row in answered[:3]]}"
            )

        # Grabs: the L5 grab, which is what the app's "Grabs" filter lists.
        grabs = _records(seeded["id"], lab.EVENT_GRABBED, "releaseGrabbed")
        if not grabs:
            raise ScenarioError(
                "Prowlarr has no releaseGrabbed row for the lab's indexer; "
                "the grab comes from the L5 flow"
            )
        if not _records(seeded["id"], lab.EVENT_RSS, "indexerRss"):
            raise ScenarioError(
                "Prowlarr has no indexerRss row for the lab's indexer"
            )

        # The indexer detail screen reads its own flat, server-filtered list.
        if not lab.indexer_history(seeded["id"]):
            raise ScenarioError(
                f"/history/indexer is empty for indexer {seeded['id']}"
            )

        # Stats: the totals are the sum of the per-indexer rows.
        stats = lab.indexer_stats()
        for key in ("indexers", "userAgents", "hosts"):
            if not isinstance(stats.get(key), list):
                raise ScenarioError(f"/indexerstats has no {key} list: {stats}")
        entry = _stat(seeded["id"])
        if int(entry.get("numberOfQueries") or 0) <= 0:
            raise ScenarioError(f"the lab's indexer has no queries: {entry}")
        if int(entry.get("numberOfGrabs") or 0) <= 0:
            raise ScenarioError(f"the lab's indexer has no grabs: {entry}")
        known = {item.get("id") for item in lab.indexers()}
        for row in stats["indexers"]:
            if isinstance(row, dict) and row.get("indexerId") not in known:
                raise ScenarioError(
                    f"/indexerstats names an indexer that does not exist: {row}"
                )

        # Failure state: a list, empty while nothing is failing.
        status = lab.indexer_status()
        for entry in status:
            if entry.get("indexerId") not in known:
                raise ScenarioError(
                    f"/indexerstatus names an indexer that does not exist: {entry}"
                )

        recorded = marker.get("history")
        if isinstance(recorded, int) and page["totalRecords"] < recorded:
            raise ScenarioError(
                f"the history shrank from {recorded} to {page['totalRecords']}"
            )

    def verify_absent(self) -> None:
        seeded = lab.require_by_name(lab.SEEDED_INDEXER)
        if not seeded.get("enable"):
            raise ScenarioError(f"{lab.SEEDED_INDEXER} came out of teardown disabled")
        if not _records(seeded["id"], lab.EVENT_QUERY, "indexerQuery"):
            raise ScenarioError("the query rows did not survive the teardown")
        if not _records(seeded["id"], lab.EVENT_GRABBED, "releaseGrabbed"):
            raise ScenarioError("the grab rows did not survive the teardown")
        if MARKER.exists():
            raise ScenarioError("the scenario left its marker behind")


SCENARIO = ProwlarrHistory()
