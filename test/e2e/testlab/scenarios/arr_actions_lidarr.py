"""Lidarr's writes on the seeded library: profile, monitoring, the searches, and
a throwaway artist removed for real.

Rows A-04, A-06 and A-07 of the flow catalogue. The library belongs to the lab
(eight artists from L6a), so the scenario changes one artist and puts it back,
and it creates its own artist through Lidarr's lookup to have something it may
delete: ``DELETE /artist/{id}`` with ``deleteFiles`` and
``addImportListExclusion`` is proven on that record, never on a seeded artist
whose album set and counts a metadata refresh would rewrite.

Two things the server does not take back, and both are declared rather than
faked:

* a command is append-only. ``POST /command`` leaves a row in Lidarr's command
  history that no API removes, so ``apply`` reuses nothing and ``teardown``
  cannot erase it. The rows are the evidence A-06 and A-11 ask for.
* an artist is deleted with its folder, and the folder is gone for good. That is
  the row's own acceptance, so the scenario writes one file of its own into the
  throwaway folder before deleting it, and asserts the folder afterwards.
"""

from __future__ import annotations

import json
import time
import urllib.parse

from .base import STATE_ROOT, Scenario, ScenarioError, request, require_ok

LIDARR = "http://127.0.0.1:8686/api/v1"
HEADERS = {"X-Api-Key": "test-key"}
TARGET = "Air"
# The lookup's own catalogue names a person with no albums, which is what a
# throwaway record wants: adding it starts a metadata refresh with nothing to
# add, so the refresh cannot recreate the artist after the removal.
DISPOSABLE = "James Cupola"
DISPOSABLE_FILE = "cupola-testlab.txt"
BACKUP = STATE_ROOT / "backup" / "arr_actions_lidarr"
MARKER = BACKUP / "state.json"

# The words a command reports. A search without an indexer still finishes, and
# an indexer that answers slowly leaves it queued: both are a command the app
# may read back, so the scenario asserts the word is one of these rather than
# waiting for a search that has nothing to search.
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


def _require_artist(name: str) -> dict:
    artist = _artist_named(name)
    if artist is None:
        raise ScenarioError(
            f"Lidarr has no artist named {name!r}. The lab's library is the eight "
            "artists of golden-l6; reset the lab before applying this scenario."
        )
    return artist


def _put_artist(artist_id: int, fields: dict) -> dict:
    """Read the record whole and put it back whole, as the client does."""
    current = _read(f"/artist/{artist_id}")
    if not isinstance(current, dict):
        raise ScenarioError(f"Lidarr answered artist {artist_id} with something else")
    current.update(fields)
    updated = _read(f"/artist/{artist_id}", "PUT", current)
    if not isinstance(updated, dict):
        raise ScenarioError(f"Lidarr answered the update of {artist_id} with nothing")
    return updated


def _post_command(payload: dict) -> dict:
    created = _read("/command", "POST", payload)
    if not isinstance(created, dict) or not created.get("id"):
        raise ScenarioError(f"Lidarr did not accept the {payload.get('name')} command")
    return created


def _command(command_id: int) -> dict:
    command = _read(f"/command/{command_id}")
    if not isinstance(command, dict):
        raise ScenarioError(f"Lidarr answered command {command_id} with something else")
    return command


def _quality_profiles() -> list[dict]:
    body = _read("/qualityprofile")
    if not isinstance(body, list):
        raise ScenarioError("Lidarr answered the quality profiles with something else")
    return [item for item in body if isinstance(item, dict)]


def _other_profile(profiles: list[dict], current: object) -> int:
    for profile in profiles:
        if isinstance(profile.get("id"), int) and profile["id"] != current:
            return profile["id"]
    raise ScenarioError("Lidarr has a single quality profile, so nothing can change")


def _lookup(term: str) -> dict:
    body = _read(f"/artist/lookup?term={urllib.parse.quote(term)}", timeout=60)
    if not isinstance(body, list):
        raise ScenarioError(f"Lidarr answered the lookup of {term!r} with something else")
    for result in body:
        if isinstance(result, dict) and result.get("artistName") == term:
            return result
    raise ScenarioError(
        f"Lidarr's lookup found no artist named {term!r}; the lab's metadata "
        "source no longer answers that name, so reset the lab before applying"
    )


def _delete_artist(artist_id: int, *, delete_files: bool, exclusion: bool) -> None:
    query = (
        f"?deleteFiles={'true' if delete_files else 'false'}"
        f"&addImportListExclusion={'true' if exclusion else 'false'}"
    )
    status, body = _call(f"/artist/{artist_id}{query}", "DELETE")
    if status not in (200, 202, 204, 404):
        require_ok(status, body, f"Lidarr DELETE /artist/{artist_id}")


def _exclusions() -> list[dict]:
    body = _read("/importlistexclusion")
    if not isinstance(body, list):
        raise ScenarioError("Lidarr answered the import list exclusions with something else")
    return [item for item in body if isinstance(item, dict)]


def _exclusion_name(exclusion: dict) -> object:
    """Lidarr's exclusion carries ``artistName``, Radarr's and Sonarr's ``name``."""
    return exclusion.get("name") or exclusion.get("artistName")


def _exclusion_named(name: str) -> dict | None:
    for exclusion in _exclusions():
        if _exclusion_name(exclusion) == name:
            return exclusion
    return None


def _remove_exclusions() -> None:
    """Every exclusion named after the throwaway artist is this scenario's."""
    for exclusion in _exclusions():
        if _exclusion_name(exclusion) != DISPOSABLE:
            continue
        exclusion_id = exclusion.get("id")
        if not isinstance(exclusion_id, int):
            continue
        status, body = _call(f"/importlistexclusion/{exclusion_id}", "DELETE")
        if status not in (200, 202, 204, 404):
            require_ok(status, body, "Lidarr DELETE /importlistexclusion")


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


def _folder_of(path: str):
    return STATE_ROOT / str(path).lstrip("/")


class ArrActionsLidarr(Scenario):
    name = "arr-actions-lidarr"
    profiles = ("core",)

    def apply(self) -> None:
        marker = _marker()
        artist = _require_artist(TARGET)
        if "original" not in marker:
            marker["original"] = {
                key: artist.get(key)
                for key in ("qualityProfileId", "monitored", "monitorNewItems")
            }
            marker["artist"] = artist["id"]
            _save(marker)
        original = marker["original"]
        applied = {
            "qualityProfileId": _other_profile(
                _quality_profiles(), original.get("qualityProfileId")
            ),
            "monitored": not bool(original.get("monitored")),
            "monitorNewItems": "all" if original.get("monitorNewItems") == "new" else "new",
        }
        marker["applied"] = applied
        _save(marker)
        _put_artist(artist["id"], applied)

        albums = _read(f"/album?artistId={artist['id']}")
        album_ids = [
            album["id"]
            for album in albums or []
            if isinstance(album, dict) and isinstance(album.get("id"), int)
        ]
        if not album_ids:
            raise ScenarioError(f"Lidarr's {TARGET} has no album to search")
        searches = []
        for payload in (
            {"name": "ArtistSearch", "artistId": artist["id"]},
            {"name": "AlbumSearch", "albumIds": [album_ids[0]]},
        ):
            command = _post_command(payload)
            searches.append({"id": command["id"], "payload": payload})
        marker["searches"] = searches
        _save(marker)

        self._remove_disposable()
        _remove_exclusions()
        payload = dict(_lookup(DISPOSABLE))
        payload.pop("id", None)
        metadata = _read("/metadataprofile")
        folders = _read("/rootfolder")
        payload.update(
            {
                "qualityProfileId": _quality_profiles()[0]["id"],
                "metadataProfileId": metadata[0]["id"],
                "rootFolderPath": folders[0]["path"],
                "monitored": False,
                "addOptions": {"searchForMissingAlbums": False},
                "images": [],
                "tags": [],
            }
        )
        artist_id = self._create_disposable(payload)
        record = _read(f"/artist/{artist_id}")
        path = str(record.get("path") or "") if isinstance(record, dict) else ""
        if not path:
            raise ScenarioError("Lidarr created the throwaway artist without a path")
        folder = _folder_of(path)
        folder.mkdir(parents=True, exist_ok=True)
        (folder / DISPOSABLE_FILE).write_text(
            "the throwaway artist's folder, removed with deleteFiles\n", encoding="utf-8"
        )
        marker["disposable"] = {"id": artist_id, "path": path}
        _save(marker)

        _delete_artist(artist_id, delete_files=True, exclusion=True)
        exclusion = self._await_removal()
        marker["exclusion"] = exclusion.get("id")
        _save(marker)

    def teardown(self) -> None:
        marker = _marker()
        self._remove_disposable()
        _remove_exclusions()
        if isinstance(marker.get("artist"), int) and isinstance(marker.get("original"), dict):
            _put_artist(marker["artist"], marker["original"])
        if isinstance(marker.get("disposable"), dict):
            folder = _folder_of(marker["disposable"].get("path") or "")
            leftover = folder / DISPOSABLE_FILE
            if leftover.exists():
                leftover.unlink()
            if folder.exists() and not any(folder.iterdir()):
                folder.rmdir()

    def verify(self) -> None:
        marker = _marker()
        artist_id = marker.get("artist")
        applied = marker.get("applied") or {}
        if not isinstance(artist_id, int) or not applied:
            raise ScenarioError("the scenario has no applied state to verify")
        artist = _read(f"/artist/{artist_id}")
        for key, value in applied.items():
            if artist.get(key) != value:
                raise ScenarioError(
                    f"Lidarr kept {key}={artist.get(key)!r} instead of {value!r}"
                )

        searches = marker.get("searches") or []
        if len(searches) != 2:
            raise ScenarioError("the scenario did not post both searches")
        for search in searches:
            payload = search.get("payload") or {}
            command = _command(int(search["id"]))
            if command.get("name") != payload.get("name"):
                raise ScenarioError(
                    f"command {search['id']} is {command.get('name')!r}, "
                    f"not {payload.get('name')!r}"
                )
            body = command.get("body") or {}
            for key, value in payload.items():
                if key == "name":
                    continue
                if body.get(key) != value:
                    raise ScenarioError(
                        f"command {search['id']} carries {key}={body.get(key)!r}, "
                        f"not {value!r}"
                    )
            if command.get("status") not in COMMAND_STATES:
                raise ScenarioError(
                    f"command {search['id']} is in an unknown state: "
                    f"{command.get('status')!r}"
                )

        if _artist_named(DISPOSABLE) is not None:
            raise ScenarioError(f"Lidarr still lists the throwaway artist {DISPOSABLE!r}")
        exclusion = _exclusion_named(DISPOSABLE)
        if exclusion is None:
            raise ScenarioError(
                "Lidarr did not keep the import list exclusion of the removed artist"
            )
        if exclusion.get("id") != marker.get("exclusion"):
            raise ScenarioError(
                f"the exclusion is {exclusion.get('id')!r}, not the one the removal made"
            )
        disposable = marker.get("disposable") or {}
        folder = _folder_of(disposable.get("path") or "")
        if folder.exists():
            raise ScenarioError(
                f"the removed artist's folder is still on disk: {folder}"
            )

    def verify_absent(self) -> None:
        if _artist_named(DISPOSABLE) is not None:
            raise ScenarioError(f"Lidarr lists the throwaway artist {DISPOSABLE!r} again")
        if _exclusion_named(DISPOSABLE) is not None:
            raise ScenarioError(f"the import list exclusion of {DISPOSABLE!r} survived")
        marker = _marker()
        if not marker:
            return
        disposable = marker.get("disposable") or {}
        folder = _folder_of(disposable.get("path") or "")
        if folder.exists():
            raise ScenarioError(f"the throwaway folder survived the teardown: {folder}")
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

    def _remove_disposable(self) -> None:
        artist = _artist_named(DISPOSABLE)
        if artist is None:
            return
        artist_id = artist.get("id")
        if not isinstance(artist_id, int):
            raise ScenarioError("the throwaway artist has no id")
        _delete_artist(artist_id, delete_files=True, exclusion=False)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if _artist_named(DISPOSABLE) is None:
                return
            time.sleep(1)
        raise ScenarioError(f"Lidarr did not remove the throwaway artist {DISPOSABLE!r}")

    def _create_disposable(self, payload: dict) -> int:
        """Add the throwaway artist and wait for the record, not for the refresh.

        Lidarr refreshes an added artist's metadata before it answers, and the
        refresh of a real discography outlives any timeout worth waiting for:
        the add can be slow enough to lose the answer while the record exists.
        The name decides, then, and the refresh is left to finish on its own.
        """
        failure: ScenarioError | None = None
        try:
            created = _read("/artist", "POST", payload, timeout=180)
            if isinstance(created, dict) and isinstance(created.get("id"), int):
                return created["id"]
        except ScenarioError as error:
            failure = error
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            artist = _artist_named(DISPOSABLE)
            if artist is not None and isinstance(artist.get("id"), int):
                return artist["id"]
            time.sleep(1)
        raise ScenarioError(
            f"Lidarr did not create the throwaway artist {DISPOSABLE!r}"
            + (f": {failure}" if failure is not None else "")
        )

    def _await_removal(self) -> dict:
        """Wait for the artist to be gone and its exclusion recorded.

        The metadata refresh started by the add runs beside the delete and can
        fail on the record it no longer finds; if it re-creates the record, the
        delete is repeated rather than reported as a scenario failure.
        """
        deadline = time.monotonic() + 90
        settled = False
        while time.monotonic() < deadline:
            artist = _artist_named(DISPOSABLE)
            if artist is not None and isinstance(artist.get("id"), int):
                _delete_artist(artist["id"], delete_files=True, exclusion=True)
                settled = False
                time.sleep(2)
                continue
            exclusion = _exclusion_named(DISPOSABLE)
            if exclusion is None:
                time.sleep(1)
                continue
            if settled:
                return exclusion
            # One more read after a pause: the refresh the add started runs
            # beside the delete, and it must not have recreated the record.
            settled = True
            time.sleep(2)
        raise ScenarioError(
            "Lidarr removed the throwaway artist without recording its import list "
            "exclusion, or the artist came back"
        )


SCENARIO = ArrActionsLidarr()
