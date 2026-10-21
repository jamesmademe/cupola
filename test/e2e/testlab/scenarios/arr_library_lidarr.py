"""Lidarr's library reads: the filters' server fields, the calendar, the queue,
the wanted pages and the history.

Rows A-08, A-09, A-10, A-11 and A-12 of the flow catalogue, on the eight artists
of L6a. The scenario makes one row of the Unmonitored filter by unmonitoring an
artist, reads every other filter's source, and puts the artist back.

What the golden lab can and cannot show, and why the scenario says so instead of
inventing a row:

* **Available** needs ``statistics.trackFileCount >= trackCount`` on an artist.
  The lab's ``/media/music`` is empty (the L4 spike's FLACs are in ``/downloads``),
  so every artist is missing tracks and the chip has no row. The scenario
  asserts the fields the rule reads rather than a row that does not exist.
* **In queue** needs a download client and a grab. Lidarr in this lab has no
  download client at all, so the queue is empty; the four real queue states are
  L6a's, proven through qBittorrent and the other arrs. The scenario asserts the
  empty envelope and the missing client.
* **Cutoff unmet** needs a file below the artist's cutoff. With no files there
  is nothing to be below the cutoff, so ``wanted/cutoff`` is empty here. The
  scenario asserts its envelope, and the chip's own source (the paginated
  ``wanted/cutoff`` walk) is what the app reads.

The calendar is asked the way the app asks it: thirty days from a local day,
with ``includeArtist``. The lab's releases are historical plus one future album,
so the app's own window is usually empty and the "Nothing scheduled" state is
what it shows; the historical window proves the dates the server reports.

``apply`` posts an ``AlbumSearch`` for the first missing album, which is A-11's
"il command parte". A command is append-only: ``teardown`` restores the artist
and cannot erase the command row, which stays as the evidence.
"""

from __future__ import annotations

import json
from datetime import date, datetime, timedelta

from .base import STATE_ROOT, Scenario, ScenarioError, request, require_ok

LIDARR = "http://127.0.0.1:8686/api/v1"
HEADERS = {"X-Api-Key": "test-key"}
TARGET = "Massive Attack"
KNOWN_RELEASE = ("Drukqs", "2001-10-22")
HISTORICAL_START = "2000-01-01"
HISTORICAL_END = "2003-12-31"
BACKUP = STATE_ROOT / "backup" / "arr_library_lidarr"
MARKER = BACKUP / "state.json"

COMMAND_STATES = ("queued", "started", "completed", "failed", "aborted")


def _call(
    path: str,
    method: str = "GET",
    payload: object | None = None,
    timeout: float = 30,
) -> tuple[int, object]:
    return request(
        f"{LIDARR}{path}",
        method=method,
        payload=payload,
        headers=HEADERS,
        timeout=timeout,
    )


def _read(
    path: str,
    method: str = "GET",
    payload: object | None = None,
    timeout: float = 30,
) -> object:
    status, body = _call(path, method, payload, timeout)
    require_ok(status, body, f"Lidarr {method} {path}")
    return body


def _envelope(body: object, what: str) -> tuple[int, list[dict]]:
    """The page envelope every arr read answers, or a named failure."""
    if not isinstance(body, dict):
        raise ScenarioError(f"{what} did not answer with a page envelope")
    records = body.get("records")
    total = body.get("totalRecords")
    if not isinstance(records, list) or not isinstance(total, int):
        raise ScenarioError(f"{what} answered an envelope without records or total")
    return total, [row for row in records if isinstance(row, dict)]


def _artists() -> list[dict]:
    body = _read("/artist")
    if not isinstance(body, list):
        raise ScenarioError("Lidarr answered the artist list with something else")
    return [item for item in body if isinstance(item, dict)]


def _artist_named(name: str) -> dict | None:
    for artist in _artists():
        if artist.get("artistName") == name:
            return artist
    return None


def _put_artist(artist_id: int, fields: dict) -> dict:
    current = _read(f"/artist/{artist_id}")
    if not isinstance(current, dict):
        raise ScenarioError(f"Lidarr answered artist {artist_id} with something else")
    current.update(fields)
    updated = _read(f"/artist/{artist_id}", "PUT", current)
    if not isinstance(updated, dict):
        raise ScenarioError(f"Lidarr answered the update of {artist_id} with nothing")
    return updated


def _stamp(value: object) -> datetime:
    if not isinstance(value, str) or not value:
        raise ScenarioError(f"a record carries no date: {value!r}")
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _calendar(start: date, end: date) -> list[dict]:
    body = _read(
        "/calendar"
        f"?start={start.isoformat()}&end={end.isoformat()}&includeArtist=true"
    )
    if not isinstance(body, list):
        raise ScenarioError("Lidarr answered the calendar with something else")
    return [row for row in body if isinstance(row, dict)]


def _marker() -> dict:
    if not MARKER.exists():
        return {}
    try:
        value = json.loads(MARKER.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ScenarioError(f"the scenario's marker is unreadable: {error}") from error
    return value if isinstance(value, dict) else {}


def _save(marker: dict) -> None:
    BACKUP.mkdir(parents=True, exist_ok=True)
    MARKER.write_text(json.dumps(marker, indent=2, sort_keys=True) + "\n", encoding="utf-8")


class ArrLibraryLidarr(Scenario):
    name = "arr-library-lidarr"
    profiles = ("core",)

    def apply(self) -> None:
        marker = _marker()
        artist = _artist_named(TARGET)
        if artist is None:
            raise ScenarioError(
                f"Lidarr has no artist named {TARGET!r}. The lab's library is the "
                "eight artists of golden-l6; reset the lab before applying."
            )
        if "original" not in marker:
            marker["original"] = {"monitored": artist.get("monitored")}
            marker["artist"] = artist["id"]
            _save(marker)
        original = marker["original"]
        _put_artist(artist["id"], {"monitored": not bool(original.get("monitored"))})

        missing_total, missing = _envelope(
            _read("/wanted/missing?page=1&pageSize=50&includeArtist=true"),
            "Lidarr wanted/missing",
        )
        if missing_total < 1 or not missing:
            raise ScenarioError(
                "Lidarr's wanted/missing is empty: the lab's artists have no albums"
            )
        album = missing[0]
        album_id = album.get("id")
        if not isinstance(album_id, int):
            raise ScenarioError("a wanted album carries no id")
        created = _read(
            "/command", "POST", {"name": "AlbumSearch", "albumIds": [album_id]}
        )
        if not isinstance(created, dict) or not created.get("id"):
            raise ScenarioError("Lidarr did not accept the AlbumSearch command")
        marker["search"] = {"id": created["id"], "albumId": album_id}
        _save(marker)

    def teardown(self) -> None:
        marker = _marker()
        artist_id = marker.get("artist")
        original = marker.get("original")
        if isinstance(artist_id, int) and isinstance(original, dict):
            _put_artist(artist_id, original)

    def verify(self) -> None:
        marker = _marker()
        artist_id = marker.get("artist")
        original = marker.get("original") or {}
        if not isinstance(artist_id, int) or not original:
            raise ScenarioError("the scenario has no applied state to verify")

        # A-08, All and Unmonitored, and the fields Available reads.
        artists = _artists()
        if len(artists) < 6:
            raise ScenarioError(
                f"Lidarr lists {len(artists)} artists, not the lab's library"
            )
        for artist in artists:
            if not isinstance(artist.get("id"), int) or not artist.get("artistName"):
                raise ScenarioError(f"an artist has no id or name: {artist!r}")
        target = _read(f"/artist/{artist_id}")
        if target.get("monitored") == original.get("monitored"):
            raise ScenarioError(f"{TARGET} is still monitored as before")
        with_statistics = [
            artist for artist in artists if isinstance(artist.get("statistics"), dict)
        ]
        if not with_statistics:
            raise ScenarioError("no artist carries statistics, so no status can be read")
        for artist in with_statistics:
            stats = artist["statistics"]
            files = stats.get("trackFileCount")
            tracks = stats.get("trackCount")
            if not isinstance(files, int) or not isinstance(tracks, int):
                raise ScenarioError(
                    f"{artist['artistName']}'s statistics carry no track counts"
                )
            if files > tracks:
                raise ScenarioError(
                    f"{artist['artistName']} counts more files ({files}) than tracks ({tracks})"
                )

        # A-08, Missing, with the artist the client asks for.
        missing_total, missing = _envelope(
            _read("/wanted/missing?page=1&pageSize=50&includeArtist=true"),
            "Lidarr wanted/missing",
        )
        if missing_total < 1 or not missing:
            raise ScenarioError("Lidarr's wanted/missing is empty")
        for row in missing:
            if not isinstance(row.get("id"), int) or not row.get("title"):
                raise ScenarioError(f"a wanted album has no id or title: {row!r}")
            if not isinstance(row.get("artistId"), int):
                raise ScenarioError(f"a wanted album has no artistId: {row!r}")
            artist = row.get("artist")
            if not isinstance(artist, dict) or not artist.get("artistName"):
                raise ScenarioError(
                    "a wanted album came back without its artist: the client asks "
                    "includeArtist=true"
                )

        # A-11, the walk: two pages share no row.
        first_total, first = _envelope(
            _read("/wanted/missing?page=1&pageSize=5&includeArtist=true"),
            "Lidarr wanted/missing page 1",
        )
        if first_total != missing_total:
            raise ScenarioError("the wanted total moved between two reads")
        if first_total > 5:
            _, second = _envelope(
                _read("/wanted/missing?page=2&pageSize=5&includeArtist=true"),
                "Lidarr wanted/missing page 2",
            )
            first_ids = {row.get("id") for row in first}
            shared = [row.get("id") for row in second if row.get("id") in first_ids]
            if shared:
                raise ScenarioError(f"two wanted pages repeat albums: {shared}")

        # A-11, Cutoff unmet: the envelope the chip's source walks.
        cutoff_total, cutoff = _envelope(
            _read("/wanted/cutoff?page=1&pageSize=50&includeArtist=false"),
            "Lidarr wanted/cutoff",
        )
        for row in cutoff:
            if not isinstance(row.get("id"), int) or not isinstance(row.get("artistId"), int):
                raise ScenarioError(f"a cutoff album has no id or artistId: {row!r}")
        if cutoff_total != len(cutoff):
            raise ScenarioError("the cutoff page reports a total its rows do not match")

        # A-10, the queue and the client it would come from.
        queue_total, queue = _envelope(
            _read("/queue?page=1&pageSize=50"), "Lidarr queue"
        )
        clients = _read("/downloadclient")
        if not isinstance(clients, list):
            raise ScenarioError("Lidarr answered the download clients with something else")
        if not clients and queue_total != 0:
            raise ScenarioError("Lidarr reports queue rows without a download client")
        for row in queue:
            if not row.get("title"):
                raise ScenarioError(f"a queue row has no title: {row!r}")
            if "trackedDownloadState" not in row:
                raise ScenarioError(
                    f"a queue row carries no trackedDownloadState: {row!r}"
                )

        # A-11, the search the Wanted tab starts.
        search = marker.get("search") or {}
        if not isinstance(search.get("id"), int):
            raise ScenarioError("the scenario did not post the AlbumSearch")
        command = _read(f"/command/{search['id']}")
        if not isinstance(command, dict) or command.get("name") != "AlbumSearch":
            raise ScenarioError("the AlbumSearch command is not the one that was posted")
        if (command.get("body") or {}).get("albumIds") != [search.get("albumId")]:
            raise ScenarioError("the AlbumSearch command carries another album")
        if command.get("status") not in COMMAND_STATES:
            raise ScenarioError(
                f"the AlbumSearch is in an unknown state: {command.get('status')!r}"
            )

        # A-09, the calendar: the app's window and a window with releases in it.
        today = date.today()
        app_start = today
        app_end = today + timedelta(days=30)
        for row in _calendar(app_start, app_end):
            moment = _stamp(row.get("releaseDate")).date()
            if not app_start <= moment <= app_end:
                raise ScenarioError(
                    f"{row.get('title')!r} is dated {moment}, outside the app's window"
                )
        historical = _calendar(
            date.fromisoformat(HISTORICAL_START), date.fromisoformat(HISTORICAL_END)
        )
        if not historical:
            raise ScenarioError("Lidarr's calendar is empty for 2000 to 2003")
        titles = set()
        for row in historical:
            moment = _stamp(row.get("releaseDate")).date()
            if not date.fromisoformat(HISTORICAL_START) <= moment <= date.fromisoformat(
                HISTORICAL_END
            ):
                raise ScenarioError(
                    f"{row.get('title')!r} is dated {moment}, outside the window asked"
                )
            if not isinstance(row.get("artist"), dict):
                raise ScenarioError(
                    f"{row.get('title')!r} came back without its artist: the client "
                    "asks includeArtist=true"
                )
            titles.add(row.get("title"))
        if KNOWN_RELEASE[0] not in titles:
            raise ScenarioError(
                f"the calendar does not date {KNOWN_RELEASE[0]!r} in its own year"
            )

        # A-12, the history envelope, and its embeds when it has rows.
        history_total, history = _envelope(
            _read("/history?page=1&pageSize=20&includeArtist=true&includeAlbum=true"),
            "Lidarr history",
        )
        for row in history:
            if not isinstance(row.get("eventType"), str) or not row.get("eventType"):
                raise ScenarioError(f"a history row has no eventType: {row!r}")
            _stamp(row.get("date"))
            if isinstance(row.get("albumId"), int):
                if not isinstance(row.get("album"), dict):
                    raise ScenarioError(
                        "a history row came back without its album: the client asks "
                        "includeAlbum=true"
                    )
                if not isinstance(row.get("artist"), dict):
                    raise ScenarioError(
                        "a history row came back without its artist: the client asks "
                        "includeArtist=true"
                    )
        if history_total < len(history):
            raise ScenarioError("the history reports fewer rows than it returned")

    def verify_absent(self) -> None:
        marker = _marker()
        if not marker:
            return
        artist_id = marker.get("artist")
        original = marker.get("original") or {}
        if isinstance(artist_id, int) and original:
            artist = _read(f"/artist/{artist_id}")
            for key, value in original.items():
                if artist.get(key) != value:
                    raise ScenarioError(
                        f"{TARGET}'s {key} is {artist.get(key)!r}, not the lab's {value!r}"
                    )
        MARKER.unlink(missing_ok=True)
        if BACKUP.exists() and not any(BACKUP.iterdir()):
            BACKUP.rmdir()


SCENARIO = ArrLibraryLidarr()
