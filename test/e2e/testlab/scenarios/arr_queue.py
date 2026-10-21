"""A-10 on the two arr services: the queue they answer, and its empty state.

The app's Queue tab reads ``GET /api/v3/queue`` and turns each record's
``trackedDownloadState`` and ``status`` into a word
(``lib/core/status/arr_queue_snapshot.dart``: ``importPending``, ``importBlocked``,
``failed``, ``clientUnavailable``, ``stalled`` and the rest). This scenario
proves the read the tab depends on and the state the golden lab is in: the
queue answers a whole, empty page for Radarr and for Sonarr, the download client
and the indexer answer, and a per-movie queue read answers ``[]``. That is the
app's "Queue is empty", and it is not a fault: the two services that could fill
it are healthy.

What this scenario does **not** prove, and why, because it is the honest half:

* ``trackedDownloadState`` values (``importPending``, ``importBlocked``,
  ``imported``, ``failed``) cannot be reached in this lab. Radarr builds its
  queue from its own grab history, and a download id that already carries an
  import event is not tracked again (that is what the measurements show, not
  only what the source says: three grabs, three ``grabbed`` rows in the
  history, an empty queue). The lab's catalogue holds one torrent, so every
  release of every movie has the same infohash, and the golden snapshot already
  carries that infohash's ``downloadFolderImported``.
* Sonarr has no download client and no indexer in the seeded lab (its
  ``/downloadclient`` and ``/indexer`` are empty by the seed's design), so it
  cannot have a queue record at all.
* ``clientUnavailable`` needs the download client to stop answering, which means
  stopping or faulting a container, and the lab's rules for this lot forbid
  that.

The four client-side states L6a does prove (``stalledDL``, ``stoppedDL``,
``missingFiles``, ``queuedDL``) are qBittorrent's own, read through its WebUI by
``queue-stuck-47``, ``queue-paused``, ``queue-missing-files`` and
``queue-queued``; they are what the arr would have translated, not a substitute
for the arr's queue.
"""

from __future__ import annotations

from typing import Any

import arr_probe as probe

from .base import Scenario, ScenarioError

NAME = "arr-queue"
QUEUE_MOVIE_TMDB = 550  # Fight Club, a movie with a file
QUEUE_MOVIE_EMPTY_TMDB = 348  # Alien, a movie without one


def _queue_page(base: str) -> dict[str, Any]:
    return probe.page(base, "/queue?pageSize=200", f"{base} queue")


def _readings() -> dict[str, Any]:
    readings: dict[str, Any] = {}
    for label, base in (("radarr", probe.RADARR), ("sonarr", probe.SONARR)):
        page = _queue_page(base)
        records = page.get("records") or []
        readings[label] = {
            "total": page.get("totalRecords"),
            "records": len(records),
            "states": sorted(
                {
                    str(record.get("trackedDownloadState"))
                    for record in records
                    if isinstance(record, dict)
                }
            ),
        }
    movie = probe.find_movie(probe.RADARR, QUEUE_MOVIE_TMDB)
    if movie is None:
        raise ScenarioError(f"Radarr does not hold TMDB id {QUEUE_MOVIE_TMDB}")
    readings["movieQueue"] = probe.get(
        probe.RADARR,
        f"/queue/details?movieId={movie['id']}",
        "reading the movie's queue details",
    )
    empty = probe.find_movie(probe.RADARR, QUEUE_MOVIE_EMPTY_TMDB)
    if empty is not None:
        readings["emptyMovieQueue"] = probe.get(
            probe.RADARR,
            f"/queue/details?movieId={empty['id']}",
            "reading the queue details of a movie with no file",
        )
    return readings


def _client_answers() -> dict[str, Any]:
    """The two services that could put a record in the queue, answering."""
    clients = probe.get(
        probe.RADARR, "/downloadclient", "reading Radarr's download clients"
    )
    enabled = [item for item in clients or [] if item.get("enable")]
    if not enabled:
        raise ScenarioError("Radarr has no enabled download client")
    # The endpoint answers 200 with an empty body when the client is reachable
    # and 400 with the reason when it is not, so the status is the answer.
    probe.write(
        probe.RADARR,
        "/downloadclient/test",
        "POST",
        enabled[0],
        "testing Radarr's download client",
    )
    indexers = probe.get(probe.RADARR, "/indexer", "reading Radarr's indexers")
    automatic = [
        item
        for item in indexers or []
        if item.get("enableAutomaticSearch") or item.get("enableInteractiveSearch")
    ]
    return {
        "downloadClients": len(enabled),
        "downloadClientTest": "answered",
        "searchIndexers": len(automatic),
    }


class ArrQueue(Scenario):
    name = NAME
    profiles = ("core",)

    def apply(self) -> None:
        values = _readings()
        for label in ("radarr", "sonarr"):
            if values[label]["records"]:
                raise ScenarioError(
                    f"the {label} queue already holds {values[label]['records']} "
                    "records; this scenario proves its empty state"
                )
            if values[label]["total"] != 0:
                raise ScenarioError(
                    f"the {label} queue's envelope counts {values[label]['total']}"
                )
        if values.get("movieQueue"):
            raise ScenarioError("the per-movie queue read holds a record")
        values.update(_client_answers())
        probe.save_state(NAME, values)

    def verify(self) -> None:
        values = probe.load_state(NAME)
        current = _readings()
        for label in ("radarr", "sonarr"):
            if current[label] != values[label]:
                raise ScenarioError(
                    f"the {label} queue reads {current[label]}, "
                    f"not {values[label]}"
                )
            if current[label]["records"] or current[label]["total"]:
                raise ScenarioError(f"the {label} queue is no longer empty")
        if current.get("movieQueue"):
            raise ScenarioError("the per-movie queue read gained a record")
        if values.get("downloadClientTest") != "answered":
            raise ScenarioError("the download client was never tested")
        if not values.get("searchIndexers"):
            raise ScenarioError("Radarr has no indexer that could fill its queue")

    def teardown(self) -> None:
        # Nothing to take out: the scenario reads, it does not write.
        probe.clear_state(NAME)

    def verify_absent(self) -> None:
        # Teardown leaves the lab as it found it, so absence would be the fault.
        current = _readings()
        for label in ("radarr", "sonarr"):
            if current[label]["records"] or current[label]["total"]:
                raise ScenarioError(
                    f"the {label} queue holds {current[label]['records']} records"
                )


SCENARIO = ArrQueue()
