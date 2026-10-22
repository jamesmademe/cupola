#!/usr/bin/env python3
"""Jellyfin's libraries, media and household in the testlab.

The lab's Jellyfin (12.1) starts with one `Films` library over `/media/movies`,
the two users the bootstrap made (`cupola-admin`, an administrator, and
`cupola-viewer`, a household member) and nothing playing. This module brings the
rest of the media server the flow catalogue asks for, idempotently:

* `Series` (`/media/series`) and `Music` (`/media/music`) libraries beside
  `Films`, created through `POST /Library/VirtualFolders` and verified by
  reading the list back. An existing library is never recreated or deleted: if
  one with the same name points at another folder or another collection type,
  the script refuses and says so.
* Real files, copied from the forge's spike into the folders the containers
  mount at `/media`. The episode and the fourteen FLAC tracks come from
  `state/downloads/spike`; the film is the one the manual-import seed already
  put in `movies/Big Buck Bunny (2008)`. Nothing is generated: a kind the lab
  does not hold is declared, never invented.
* A scan, and a wait until `/Items` answers with a film, an episode and a track,
  which is the promise the rest of the catalogue relies on.
* Two viewer states through Jellyfin's own user-data endpoint: `Big Buck Bunny`
  watched by `cupola-viewer`, and the second episode of `Breaking Bad` left at
  30%, which is what puts it in Continue watching.

Run it on its own, or through the scenario that wraps it::

    python3 test/e2e/testlab/jellyfin_media.py
    python3 test/e2e/testlab/jellyfin_media.py --verify
    python3 test/e2e/testlab/testlab.py scenario apply jellyfin-media

The script never writes a database while the container runs, never stops a
container and never prints a credential.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import jellyfin_play as play

JELLYFIN = play.JELLYFIN

REPO_ROOT = play.REPO_ROOT
STATE_ROOT = play.STATE_ROOT
MEDIA_ROOT = STATE_ROOT / "media"
SPIKE = STATE_ROOT / "downloads" / "spike"

# The three libraries, and the folder each one is about. The container sees
# `state/media` at `/media` (the compose file mounts it read-only into Jellyfin),
# so a path here is the path the server has to be given.
LIBRARIES: tuple[tuple[str, str, str], ...] = (
    ("Films", "movies", "/media/movies"),
    ("Series", "tvshows", "/media/series"),
    ("Music", "music", "/media/music"),
)

BUCK_PROBE = SPIKE / "Big.Buck.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv"
EPISODE_SINGLE = SPIKE / "Breaking.Bad.S01E02.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv"
EPISODE_DOUBLE = SPIKE / "Breaking.Bad.S01E01E02.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv"

FILM_NAME = "Big Buck Bunny"
SERIES_NAME = "Breaking Bad"
ALBUM_ARTIST = "Daft Punk"
VIEWER = "cupola-viewer"


class MediaError(RuntimeError):
    """Something the lab cannot hold, said instead of faked."""


# ---------------------------------------------------------------- transport


def token() -> str:
    return play.admin_token()


def call(path: str, what: str, **kwargs: Any) -> Any:
    try:
        return play.call(path, what, **kwargs)
    except play.PlayError as error:
        raise MediaError(str(error)) from error


# ---------------------------------------------------------------- libraries


def virtual_folders(token_value: str | None = None) -> list[dict[str, Any]]:
    answer = call(
        "/Library/VirtualFolders",
        "reading the libraries",
        token=token_value or token(),
    )
    return [folder for folder in answer if isinstance(folder, dict)] if isinstance(answer, list) else []


def _folder_locations(folder: dict[str, Any]) -> list[str]:
    for name in ("Locations", "Locations2", "locations"):
        value = folder.get(name)
        if isinstance(value, list):
            return [str(item) for item in value]
    return []


def ensure_libraries(token_value: str | None = None) -> list[dict[str, Any]]:
    """Create `Series` and `Music` if they are absent; verify all three.

    The create call uses query parameters rather than a body: that is the
    spelling this Jellyfin answers with 204 (the seed uses it for `Films`), and
    `refreshLibrary=true` makes the first scan start without a second request.
    """
    auth = token_value or token()
    existing = virtual_folders(auth)
    by_name = {str(folder.get("Name") or ""): folder for folder in existing}
    for name, collection_type, path in LIBRARIES:
        folder = by_name.get(name)
        if folder is None:
            query = urllib.parse.urlencode(
                {
                    "name": name,
                    "collectionType": collection_type,
                    "paths": path,
                    "refreshLibrary": "true",
                }
            )
            call(
                f"/Library/VirtualFolders?{query}",
                f"creating the {name} library",
                method="POST",
                payload={},
                token=auth,
            )
            continue
        kind = str(folder.get("CollectionType") or "")
        locations = _folder_locations(folder)
        if kind != collection_type:
            raise MediaError(
                f"the library {name!r} is {kind!r}, not {collection_type!r}: "
                "this script will not repurpose a library it did not make"
            )
        if path not in locations:
            raise MediaError(
                f"the library {name!r} points at {locations}, not {path}: "
                "this script will not move a library it did not make"
            )
    after = virtual_folders(auth)
    names = {str(folder.get("Name") or "") for folder in after}
    missing = [name for name, _, _ in LIBRARIES if name not in names]
    if missing:
        raise MediaError(f"Jellyfin did not keep the libraries {missing}")
    return after


# ---------------------------------------------------------------- the files


@dataclass(frozen=True)
class Copy:
    kind: str
    source: Path
    destination: Path


def media_plan() -> list[Copy]:
    """The files this module wants under `/media`, from the forge only."""
    plan: list[Copy] = []

    # The film is already in the library: the manual-import seed copied the
    # forge's own 1080p MKV into Big Buck Bunny's folder, named as the file
    # Radarr could not match (which is the point of that specimen). Copying it
    # again would add a second version of the same movie, so it is only filled
    # in when the seed's copy is absent (a lab started without the seed).
    seeded_film = (
        MEDIA_ROOT / "movies" / "Big Buck Bunny (2008)"
        / "The.Great.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv"
    )
    if not seeded_film.exists():
        plan.append(
            Copy(
                kind="movie",
                source=BUCK_PROBE,
                destination=MEDIA_ROOT / "movies" / "Big Buck Bunny (2008)"
                / "Big Buck Bunny (2008).mkv",
            )
        )

    series_dir = MEDIA_ROOT / "series" / "Breaking Bad (2008)" / "Season 01"
    plan.append(
        Copy(
            kind="episode",
            source=EPISODE_DOUBLE,
            destination=series_dir / "Breaking Bad S01E01-E02.mkv",
        )
    )
    plan.append(
        Copy(
            kind="episode",
            source=EPISODE_SINGLE,
            destination=series_dir / "Breaking Bad S01E02.mkv",
        )
    )

    for source in sorted(SPIKE.glob("Daft Punk - Discovery - *.flac")):
        # `Daft Punk - Discovery - 04 - Title.flac` becomes
        # `Discovery/04 - Title.flac`, under the artist folder Jellyfin reads
        # the album from.
        track = source.name.split(" - ", 2)[-1]
        plan.append(
            Copy(
                kind="track",
                source=source,
                destination=MEDIA_ROOT / "music" / ALBUM_ARTIST / "Discovery" / track,
            )
        )
    return plan


def copy_media(plan: list[Copy] | None = None) -> list[dict[str, str]]:
    """Copy what is missing, keep what matches, and say which was which."""
    plan = media_plan() if plan is None else plan
    report: list[dict[str, str]] = []
    for item in plan:
        if not item.source.exists():
            raise MediaError(
                f"the forge holds no {item.kind}: {item.source} is missing. "
                "Run `python3 test/e2e/testlab/testlab.py spike` in the lab."
            )
        item.destination.parent.mkdir(parents=True, exist_ok=True)
        action = "copied"
        if item.destination.exists():
            action = (
                "kept"
                if item.destination.stat().st_size == item.source.stat().st_size
                else "replaced"
            )
        if action != "kept":
            shutil.copy2(item.source, item.destination)
            os.chmod(item.destination, 0o644)
        report.append(
            {
                "kind": item.kind,
                "action": action,
                "destination": str(item.destination.relative_to(MEDIA_ROOT)),
            }
        )
    return report


# ---------------------------------------------------------------- the scan


def request_scan(auth: str | None = None) -> None:
    # `POST /Library/Refresh` scans every library with the defaults. The one
    # misleading Jellyfin default (`metadataRefreshMode=None`, which does
    # nothing and still answers 204) belongs to `/Items/{id}/Refresh`, and the
    # client documents it there; this endpoint defaults to a real scan.
    call("/Library/Refresh", "asking for a library scan", method="POST", token=auth or token())


def counts(auth: str | None = None) -> dict[str, int]:
    """How many of each kind the server holds, as its own totals."""
    auth = auth or token()
    result: dict[str, int] = {}
    for kind in ("Movie", "Series", "Episode", "MusicAlbum", "Audio"):
        query = urllib.parse.urlencode(
            {
                "recursive": "true",
                "includeItemTypes": kind,
                "limit": 1,
                "enableUserData": "false",
            }
        )
        answer = call(f"/Items?{query}", f"counting {kind}", token=auth)
        total = answer.get("TotalRecordCount") if isinstance(answer, dict) else None
        result[kind] = int(total) if isinstance(total, (int, float)) else 0
    return result


def _has_every_kind(total: dict[str, int]) -> bool:
    return all(
        total.get(kind, 0) >= 1
        for kind in ("Movie", "Series", "Episode", "MusicAlbum", "Audio")
    )


def wait_for_media(*, timeout: float = 180, interval: float = 3) -> dict[str, int]:
    """Scan, then wait until a film, an episode and a track are in `/Items`."""
    if _has_every_kind(counts()):
        return counts()
    request_scan()
    deadline = time.monotonic() + timeout
    known: dict[str, int] = counts()
    while time.monotonic() < deadline:
        known = counts()
        if _has_every_kind(known):
            return known
        time.sleep(interval)
    raise MediaError(
        "the scan never produced every kind: "
        + ", ".join(f"{kind} {known.get(kind, 0)}" for kind in
                    ("Movie", "Series", "Episode", "MusicAlbum", "Audio"))
        + f" after {timeout:g}s. The files are under {MEDIA_ROOT}; a missing "
        "kind means the forge has no such file, not that Jellyfin ignored it."
    )


# ---------------------------------------------------------------- the items


def items(
    kinds: str,
    *,
    search: str = "",
    user_id: str = "",
    limit: int = 20,
    fields: str = "RunTimeTicks,SeriesName,Path",
    auth: str | None = None,
) -> list[dict[str, Any]]:
    query: dict[str, str] = {
        "recursive": "true",
        "includeItemTypes": kinds,
        "limit": str(limit),
        "fields": fields,
        "sortBy": "SortName",
    }
    if search:
        query["searchTerm"] = search
    if user_id:
        query["userId"] = user_id
    answer = call(
        f"/Items?{urllib.parse.urlencode(query)}",
        f"reading {kinds}",
        token=auth or token(),
    )
    rows = answer.get("Items") if isinstance(answer, dict) else None
    return [row for row in rows if isinstance(row, dict)] if isinstance(rows, list) else []


def one(rows: list[dict[str, Any]], name: str, what: str) -> dict[str, Any]:
    for row in rows:
        if (row.get("Name") or "").casefold() == name.casefold():
            return row
    raise MediaError(
        f"the server holds no {what} named {name!r}; it offered "
        + ", ".join(repr(row.get("Name")) for row in rows[:6])
    )


def episode_of_season(series_id: str, season: int, number: int) -> dict[str, Any]:
    """One episode, addressed by its place in the show and not by its title.

    A Jellyfin that cannot reach its metadata providers names episodes from the
    file alone, so `Cat's in the Bag...` is a cache and not a fact of the lab.
    The season and the episode number survive any scan.
    """
    answer = call(
        f"/Shows/{series_id}/Episodes",
        "reading the episodes",
        token=token(),
    )
    rows = answer.get("Items") if isinstance(answer, dict) else answer
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            continue
        if row.get("ParentIndexNumber") == season and row.get("IndexNumber") == number:
            return row
    raise MediaError(
        f"the series holds no season {season} episode {number}; the scan found "
        + ", ".join(
            f"S{row.get('ParentIndexNumber')}E{row.get('IndexNumber')}"
            for row in (rows if isinstance(rows, list) else [])
            if isinstance(row, dict)
        )
    )


def samples(auth: str | None = None) -> dict[str, dict[str, Any]]:
    """One movie, one episode and one track, with the ids the e2e quotes."""
    auth = auth or token()
    film = one(items("Movie", search=FILM_NAME, auth=auth), FILM_NAME, "movie")
    series = one(items("Series", search=SERIES_NAME, auth=auth), SERIES_NAME, "series")
    episode = episode_of_season(str(series.get("Id") or ""), 1, 2)
    tracks = items("Audio", search="One More Time", auth=auth)
    track = one(tracks, "One More Time", "track")
    return {
        "movie": _brief(film),
        "series": _brief(series),
        "episode": {**_brief(episode), "series": episode.get("SeriesName") or ""},
        "track": _brief(track),
    }


def _brief(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": str(item.get("Id") or ""),
        "name": str(item.get("Name") or ""),
        "runtimeTicks": int(item.get("RunTimeTicks") or 0),
        "path": str(item.get("Path") or ""),
    }


# ---------------------------------------------------------------- the states


def _viewer() -> dict[str, str]:
    try:
        return play.account(
            "viewer", play.device_id_of("states"), "Cupola TestLab States"
        )
    except play.PlayError as error:
        raise MediaError(str(error)) from error


def _user_data(item_id: str, viewer: dict[str, str]) -> dict[str, Any]:
    answer = call(
        f"/Items/{item_id}?userId={urllib.parse.quote(viewer['userId'])}"
        "&fields=UserData",
        "reading the item's user data",
        token=viewer["token"],
    )
    data = answer.get("UserData") if isinstance(answer, dict) else None
    return data if isinstance(data, dict) else {}


def ensure_watch_states(
    found: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """The film watched and the episode part-watched, for `cupola-viewer`.

    Both are written through Jellyfin's own user-data endpoints with the
    viewer's token: `POST /UserPlayedItems/{id}` for the watched film, and
    `POST /UserItems/{id}/UserData` for a resume position. Jellyfin 12 has no
    `/Users/{userId}/PlayedItems/{id}`, so an administrator's token cannot
    write another person's state; the household member has to do it themselves,
    which is also what a person watching would be.
    """
    viewer = _viewer()
    found = found or samples()
    film = found["movie"]
    episode = found["episode"]

    runtime = int(episode.get("runtimeTicks") or 0)
    if runtime <= 0:
        raise MediaError(f"the episode {episode['name']!r} reports no runtime")
    position = int(runtime * 0.3)

    film_data = _user_data(film["id"], viewer)
    if film_data.get("Played") is not True:
        call(
            f"/UserPlayedItems/{film['id']}",
            "marking the film watched",
            method="POST",
            token=viewer["token"],
            device_id=play.device_id_of("states"),
        )
        film_data = _user_data(film["id"], viewer)
        if film_data.get("Played") is not True:
            raise MediaError(
                f"{FILM_NAME} is not marked watched for {viewer['name']}: {film_data}"
            )

    episode_data = _user_data(episode["id"], viewer)
    stored = int(episode_data.get("PlaybackPositionTicks") or 0)
    # Half a percent: an earlier run of the helper may have stopped this
    # episode a few seconds further on, and the fixture is 30% exactly.
    if episode_data.get("Played") is True or abs(stored - position) > runtime * 0.005:
        call(
            f"/UserItems/{episode['id']}/UserData",
            "setting the episode's resume position",
            method="POST",
            payload={"PlaybackPositionTicks": position, "Played": False},
            token=viewer["token"],
            device_id=play.device_id_of("states"),
        )

    states = read_watch_states(found)
    if states["filmPlayed"] is not True:
        raise MediaError(f"{FILM_NAME} is not watched for {viewer['name']}")
    if states["resume"]["percent"] < 29.5 or states["resume"]["percent"] > 30.5:
        raise MediaError(
            f"the episode's resume position is {states['resume']['percent']:g}%, "
            "not the 30% asked for"
        )
    if not states["inResume"]:
        raise MediaError(
            f"{states['resume']['title']!r} has a resume position but is not in "
            "Continue watching, so the state the app reads would be empty"
        )
    return states


def read_watch_states(
    found: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """What `cupola-viewer` holds right now, without writing anything."""
    viewer = _viewer()
    found = found or samples()
    film = found["movie"]
    episode = found["episode"]
    runtime = int(episode.get("runtimeTicks") or 0)
    film_data = _user_data(film["id"], viewer)
    episode_data = _user_data(episode["id"], viewer)
    stored = int(episode_data.get("PlaybackPositionTicks") or 0)
    resume = call(
        f"/UserItems/Resume?userId={urllib.parse.quote(viewer['userId'])}"
        "&limit=20&mediaTypes=Video",
        "reading Continue watching",
        token=viewer["token"],
    )
    resume_ids = {
        str(row.get("Id"))
        for row in (resume.get("Items") or [])
        if isinstance(row, dict)
    } if isinstance(resume, dict) else set()
    return {
        "user": viewer["name"],
        "watched": FILM_NAME,
        "filmPlayed": film_data.get("Played") is True,
        "resume": {
            "title": episode["name"],
            "seconds": round(stored / play.TICKS_PER_SECOND, 1),
            "percent": round(stored / runtime * 100, 1) if runtime else 0.0,
        },
        "inResume": episode["id"] in resume_ids,
    }


# ---------------------------------------------------------------- the audit


def library_rows(auth: str | None = None) -> list[dict[str, str]]:
    """The three folders as the server holds them, with the ids browsing needs."""
    return [
        {
            "name": str(folder.get("Name") or ""),
            "collectionType": str(folder.get("CollectionType") or ""),
            "location": (_folder_locations(folder) or [""])[0],
            "itemId": str(folder.get("ItemId") or ""),
        }
        for folder in virtual_folders(auth)
    ]


def viewer_reads(rows: list[dict[str, str]] | None = None) -> dict[str, int]:
    """What `cupola-viewer` itself can see in each library.

    The administrator's token reads the server; the household member's reads
    what a household member is allowed to watch. `/Library/VirtualFolders` is
    elevated and would answer 403, so the member's view is asked for through
    `/Items?parentId=`, which is also how the app browses.
    """
    viewer = _viewer()
    kinds = {"movies": "Movie", "tvshows": "Series", "music": "MusicAlbum"}
    result: dict[str, int] = {}
    for row in rows if rows is not None else library_rows():
        kind = kinds.get(row["collectionType"])
        if kind is None or not row["itemId"]:
            result[row["name"]] = 0
            continue
        query = urllib.parse.urlencode(
            {
                "parentId": row["itemId"],
                "recursive": "true",
                "limit": 1,
                "includeItemTypes": kind,
                "userId": viewer["userId"],
            }
        )
        answer = call(
            f"/Items?{query}",
            f"reading {row['name']} as {viewer['name']}",
            token=viewer["token"],
        )
        total = answer.get("TotalRecordCount") if isinstance(answer, dict) else 0
        result[row["name"]] = int(total) if isinstance(total, (int, float)) else 0
    return result


def users(auth: str | None = None) -> list[dict[str, Any]]:
    answer = call("/Users", "reading the household", token=auth or token())
    rows = answer if isinstance(answer, list) else []
    return [
        {
            "name": str(user.get("Name") or ""),
            "id": str(user.get("Id") or ""),
            "administrator": bool((user.get("Policy") or {}).get("IsAdministrator")),
        }
        for user in rows
        if isinstance(user, dict)
    ]


def audit(*, with_states: bool = True) -> dict[str, Any]:
    auth = token()
    libraries = library_rows(auth)
    total = counts(auth)
    found = samples(auth)
    states = read_watch_states(found) if with_states else None
    session_rows = [
        play.describe(session)
        for session in play.playing_sessions(auth)
        if session.get("NowPlayingItem")
    ]
    return {
        "libraries": libraries,
        "viewer": viewer_reads(libraries),
        "counts": total,
        "samples": found,
        "users": users(auth),
        "states": states,
        "sessions": session_rows,
    }


def assert_ready(state: dict[str, Any]) -> None:
    """The scenario's own acceptance: every claim, re-read from the server."""
    libraries = {row["name"]: row for row in state["libraries"]}
    for name, collection_type, path in LIBRARIES:
        row = libraries.get(name)
        if row is None:
            raise MediaError(f"the {name} library is not on the server")
        if row["collectionType"] != collection_type:
            raise MediaError(f"the {name} library is {row['collectionType']!r}")
        if row["location"] != path:
            raise MediaError(f"the {name} library reads {row['location']!r}, not {path!r}")
    for kind in ("Movie", "Series", "Episode", "MusicAlbum", "Audio"):
        if state["counts"].get(kind, 0) < 1:
            raise MediaError(f"the server holds no {kind}: the scan found nothing")
    names = [user["name"] for user in state["users"]]
    if "cupola-admin" not in names or VIEWER not in names:
        raise MediaError(f"the household is {names}, without the admin and the requester")
    administrators = {user["name"] for user in state["users"] if user["administrator"]}
    if "cupola-admin" not in administrators:
        raise MediaError("cupola-admin is not an administrator")
    if VIEWER in administrators:
        raise MediaError(f"{VIEWER} is an administrator, not a household member")
    for name, _, _ in LIBRARIES:
        if state["viewer"].get(name, 0) < 1:
            raise MediaError(
                f"{VIEWER} sees nothing in {name}: the household member's policy "
                "does not expose that library"
            )
    if state["states"] is None:
        raise MediaError("the viewer's watch states were not verified")
    if state["states"]["filmPlayed"] is not True:
        raise MediaError(f"{FILM_NAME} is not watched by {VIEWER}")
    if not state["states"]["inResume"]:
        raise MediaError(
            f"{state['states']['resume']['title']!r} is not in {VIEWER}'s "
            "Continue watching"
        )


# ---------------------------------------------------------------- printing


def summary(state: dict[str, Any], copies: list[dict[str, str]] | None = None) -> str:
    lines: list[str] = []
    for row in state["libraries"]:
        lines.append(
            f"library {row['name']} · {row['collectionType']} · {row['location']}"
        )
    counts = state["counts"]
    lines.append(
        "items · "
        + ", ".join(f"{counts.get(kind, 0)} {kind}" for kind in
                    ("Movie", "Series", "Episode", "MusicAlbum", "Audio"))
    )
    for kind, sample in state["samples"].items():
        lines.append(f"{kind} · {sample['name']} · {sample['id']}")
    lines.append(
        "users · " + ", ".join(
            f"{user['name']}{' (admin)' if user['administrator'] else ''}"
            for user in state["users"]
        )
    )
    lines.append(
        f"{VIEWER} sees · " + ", ".join(
            f"{count} in {name}" for name, count in state["viewer"].items()
        )
    )
    if state["states"]:
        watched = state["states"]["watched"]
        resume = state["states"]["resume"]
        lines.append(
            f"states · {watched} watched by {state['states']['user']} · "
            f"{resume['title']} at {resume['percent']:g}% "
            f"({resume['seconds']:g}s), in Continue watching"
        )
    lines.append(f"sessions · {len(state['sessions'])} playing")
    if copies:
        actions: dict[str, int] = {}
        for row in copies:
            actions[row["action"]] = actions.get(row["action"], 0) + 1
        lines.append(
            "files · " + ", ".join(f"{count} {action}" for action, count in sorted(actions.items()))
        )
    return "\n".join(lines)


def setup() -> dict[str, Any]:
    copied = copy_media()
    ensure_libraries()
    found_counts = wait_for_media()
    libraries = library_rows()
    state = {
        "libraries": libraries,
        "viewer": viewer_reads(libraries),
        "counts": found_counts,
        "samples": samples(),
    }
    state["states"] = ensure_watch_states(state["samples"])
    state["users"] = users()
    state["sessions"] = [
        play.describe(session)
        for session in play.playing_sessions(token())
        if session.get("NowPlayingItem")
    ]
    assert_ready(state)
    return {"state": state, "copies": copied}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Bring Jellyfin's libraries, media and watch states into the testlab."
    )
    parser.add_argument("--verify", action="store_true",
                        help="read the server and assert, changing nothing")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    arguments = parser.parse_args(argv)
    try:
        if arguments.verify:
            state = audit()
            assert_ready(state)
            result: dict[str, Any] = {"state": state, "copies": []}
        else:
            result = setup()
        if arguments.json:
            print(json.dumps(result, indent=2))
        else:
            print(summary(result["state"], result["copies"]))
        return 0
    except MediaError as error:
        print(f"jellyfin_media: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
