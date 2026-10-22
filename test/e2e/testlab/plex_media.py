#!/usr/bin/env python3
"""Plex's three libraries, the watch marks and the on-deck row (L8).

The lab's Plex (Compose service `plex`, 127.0.0.1:32400) is claimed with the
owner's real plex.tv account. Nothing here touches that account: no user, no
invitation, no plex.tv call. Every write is a library or watch-mark write on
the lab's own server, through its HTTP API, with the owner's token from
`credentials.env`.

What this script builds, idempotently:

  1. the three library sections the app's Plex tabs read, all on the forge's
     own folders: `Films` (`/media/movies`, type 1), `Series` (`/media/series`,
     type 2) and `Music` (`/media/music`, type 8). A section of the right kind
     already pointing at the right folder is adopted, and renamed to the title
     above if an older run left another name on it;
  2. the media those sections need. The movies come from the seed (Radarr's own
     folder) and from the forge's spike. `Series` and `Music` are the forge's
     too: the seed fills neither folder. If the folders are still empty (the
     Jellyfin block of L8 fills them from the same forge), this script waits,
     then copies the very files the forge made: `s01e01` and `s01e02` from
     `Breaking.Bad.S01E01E02` and `Breaking.Bad.S01E02`, and the fourteen
     `Daft Punk - Discovery` tracks. No file is invented;
  3. one watched movie and one watched episode, read back through Plex's own
     user data (`viewCount`, `lastViewedAt`), and the on-deck row that follows
     from them: watching `Breaking Bad` s01e01 leaves s01e02 on deck, which is
     Plex's own next-up rule;
  4. `<state>/plex-media.json`, the contract `testlab_plex_e2e_test.dart`
     reads. No secret is in it (no token, no account name), so it is 0644 like
     `world.json`.

What it cannot build, and says so in the report rather than faking:

  * **a movie on deck.** Plex fills `viewOffset` only from a client that really
    plays the file, and this server (1.43.4) ignores every API path that could
    set it: `/:/timeline` plus a range read of the part registers a session
    with a nested `Session` element but never writes a resume point,
    `PUT /library/metadata/{id}?viewOffset=` answers 200 and changes nothing,
    and `/library/metadata/{id}/scrobble` answers 404. Watching a movie is a
    mark (`/:/scrobble`), not a resume point: the on-deck row this script can
    prove is the series one;
  * **stopping a stream.** This server has no Plex Pass
    (`myPlexSubscription: false`), and `/status/sessions/terminate` is a Plex
    Pass feature: `plex_play.py` carries the spike and its evidence.

"An episode appears" is checked where Plex keeps episodes: a show section's
`/all` lists shows, its `/allLeaves` lists every episode, and a music section's
`/all` lists artists, so a track is `/all?type=10`. Reading the primary type
would answer a different question and pass for the wrong reason.

Usage:

    python3 test/e2e/testlab/plex_media.py            # build, then verify
    python3 test/e2e/testlab/plex_media.py --check    # verify only, no write
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
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRATCH_ROOT = REPO_ROOT / ".ai" / "scratch" / "zz_testlab"

PLEX_URL = os.environ.get("CUPOLA_TESTLAB_PLEX_URL", "http://127.0.0.1:32400")
CONTRACT_NAME = "plex-media.json"
CLIENT_ID = "cupola-testlab-plex-media"

# Plex's own type ids, as `/library/sections` reports and accepts them.
SECTION_SPECS: tuple[dict[str, Any], ...] = (
    {
        "title": "Films",
        "kind": "movie",
        "type": 1,
        "path": "/media/movies",
        "agent": "tv.plex.agents.movie",
        "scanner": "Plex Movie",
    },
    {
        "title": "Series",
        "kind": "show",
        "type": 2,
        "path": "/media/series",
        "agent": "tv.plex.agents.series",
        "scanner": "Plex TV Series",
    },
    {
        "title": "Music",
        "kind": "artist",
        "type": 8,
        "path": "/media/music",
        "agent": "tv.plex.agents.music",
        "scanner": "Plex Music",
    },
)

# Where each section's folder sits on this machine. The container sees it at
# the same relative place under `/media`.
FOLDER_NAMES = {"movie": "movies", "show": "series", "artist": "music"}

# The forge's spike folder: the very files the synthetic media were made from.
FORGE_SPIKE = SCRATCH_ROOT / "state" / "downloads" / "spike"

# The two episodes and the album are copied from the forge to these names.
# The layout is the one the Jellyfin block also writes (same file names, same
# folders), so two blocks filling the same forge folder cannot duplicate an
# episode. `source` is the forge artifact.
SERIES_FILES: tuple[dict[str, str], ...] = (
    {
        "source": "Breaking.Bad.S01E01E02.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
        "target": "Breaking Bad (2008)/Season 01/Breaking Bad S01E01-E02.mkv",
    },
    {
        "source": "Breaking.Bad.S01E02.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
        "target": "Breaking Bad (2008)/Season 01/Breaking Bad S01E02.mkv",
    },
)
MUSIC_SHOW = "Daft Punk"
MUSIC_ALBUM = "Discovery"


class PlexError(RuntimeError):
    """A step that Plex refused, or a library that stayed empty."""


def state_root() -> Path:
    return Path(
        os.environ.get("CUPOLA_TESTLAB_STATE_DIR", SCRATCH_ROOT / "state")
    ).resolve()


def credentials(state: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    file = state / "credentials.env"
    if not file.exists():
        return values
    for line in file.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def token(state: Path) -> str:
    """The owner's server token, from the chmod-600 file. Never printed."""
    value = credentials(state).get("CUPOLA_TESTLAB_PLEX_TOKEN", "").strip()
    if not value:
        raise PlexError(
            "the lab credentials have no CUPOLA_TESTLAB_PLEX_TOKEN: run "
            "test/e2e/testlab/bootstrap.sh against a claimed Plex"
        )
    return value


def headers(state: Path) -> dict[str, str]:
    """Plex's client identity, on every request.

    `X-Plex-Client-Identifier` is one dedicated value, so the lab's own device
    row is one row and never the app's.
    """
    return {
        "X-Plex-Token": token(state),
        "Accept": "application/json",
        "X-Plex-Client-Identifier": CLIENT_ID,
        "X-Plex-Product": "Cupola TestLab",
        "X-Plex-Version": "1.0",
        "X-Plex-Device": "Cupola TestLab",
        "X-Plex-Device-Name": "Cupola TestLab",
        "X-Plex-Platform": "macOS",
    }


def call(
    state: Path,
    path: str,
    *,
    method: str = "GET",
    query: dict[str, Any] | None = None,
    timeout: float = 30,
) -> tuple[int, bytes]:
    url = PLEX_URL.rstrip("/") + path
    if query:
        url = f"{url}?{urllib.parse.urlencode(query)}"
    request = urllib.request.Request(url, headers=headers(state), method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def container(
    state: Path,
    path: str,
    *,
    method: str = "GET",
    query: dict[str, Any] | None = None,
    timeout: float = 30,
) -> dict[str, Any]:
    status, body = call(state, path, method=method, query=query, timeout=timeout)
    if not 200 <= status < 300:
        raise PlexError(
            f"{method} {path} answered {status}: "
            f"{body.decode('utf-8', errors='replace')[:200]}"
        )
    try:
        return json.loads(body)["MediaContainer"]
    except (json.JSONDecodeError, KeyError, TypeError) as error:
        raise PlexError(f"{method} {path} did not answer a MediaContainer") from error


# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------


def sections(state: Path) -> list[dict[str, Any]]:
    answer = container(state, "/library/sections")
    return [entry for entry in answer.get("Directory", []) if isinstance(entry, dict)]


def _paths_of(section: dict[str, Any]) -> list[str]:
    return [
        str(location.get("path") or "")
        for location in section.get("Location", [])
        if isinstance(location, dict)
    ]


def _kind_of(section: dict[str, Any]) -> str:
    return str(section.get("type") or "")


def find_section(
    current: list[dict[str, Any]], spec: dict[str, Any]
) -> dict[str, Any] | None:
    """A section of the right kind already pointing at the right folder.

    A section of the right kind whose folder is the one this spec names: a
    section that holds the forge's files is the one the flows read, whatever a
    previous run called it.
    """
    for section in current:
        if (
            _kind_of(section) == spec["kind"]
            and spec["path"] in _paths_of(section)
        ):
            return section
    return None


def ensure_sections(state: Path) -> list[dict[str, Any]]:
    """The three sections, made or adopted, and never duplicated."""
    for spec in SECTION_SPECS:
        current = sections(state)
        existing = find_section(current, spec)
        if existing is None:
            query = {
                "name": spec["title"],
                "type": spec["type"],
                "agent": spec["agent"],
                "scanner": spec["scanner"],
                "language": "en-US",
                "location": spec["path"],
            }
            status, body = call(
                state, "/library/sections", method="POST", query=query
            )
            if not 200 <= status < 300:
                raise PlexError(
                    f"creating the {spec['title']} section answered {status}: "
                    f"{body.decode('utf-8', errors='replace')[:200]}"
                )
            print(f"[plex-media] section {spec['title']} on {spec['path']}")
            _wait_for_section(state, spec)
            continue
        title = str(existing.get("title") or "")
        if title != spec["title"]:
            # Plex answers 400 to a rename that carries the name alone: its
            # own edit call always sends the section's agent beside it.
            status, _ = call(
                state,
                f"/library/sections/{existing['key']}",
                method="PUT",
                query={
                    "name": spec["title"],
                    "agent": str(existing.get("agent") or spec["agent"]),
                },
            )
            if not 200 <= status < 300:
                raise PlexError(
                    f"renaming {title!r} to {spec['title']!r} answered {status}"
                )
            print(
                f"[plex-media] section {existing['key']}: "
                f"{title!r} renamed to {spec['title']!r}"
            )
    return sections(state)


def _wait_for_section(state: Path, spec: dict[str, Any]) -> dict[str, Any]:
    """Plex answers the create before the read endpoint lists the section."""
    for _ in range(30):
        time.sleep(0.5)
        existing = find_section(sections(state), spec)
        if existing is not None:
            return existing
    raise PlexError(f"the {spec['title']} section never appeared")


def library_of(state: Path) -> dict[str, dict[str, Any]]:
    """The contract's view of the three sections, keyed by kind."""
    current = sections(state)
    found: dict[str, dict[str, Any]] = {}
    for spec in SECTION_SPECS:
        section = find_section(current, spec)
        if section is None:
            continue
        found[spec["kind"]] = {
            "id": str(section.get("key") or ""),
            "title": str(section.get("title") or ""),
            "kind": spec["kind"],
            "type": int(spec["type"]),
            "path": spec["path"],
        }
    return found


# ---------------------------------------------------------------------------
# Media on disk
# ---------------------------------------------------------------------------


def folder_of(state: Path, spec: dict[str, Any]) -> Path:
    return state / "media" / FOLDER_NAMES[spec["kind"]]


def files_under(folder: Path, suffixes: tuple[str, ...]) -> list[Path]:
    if not folder.is_dir():
        return []
    return sorted(
        path
        for path in folder.rglob("*")
        if path.is_file() and path.suffix.lower() in suffixes
    )


def copy_series_files(state: Path) -> list[str]:
    """The forge's two episodes, at the names Plex's matcher reads."""
    target_root = folder_of(
        state, next(spec for spec in SECTION_SPECS if spec["kind"] == "show")
    )
    written: list[str] = []
    for entry in SERIES_FILES:
        source = FORGE_SPIKE / entry["source"]
        target = target_root / entry["target"]
        if target.exists() and target.stat().st_size > 0:
            continue
        if not source.is_file():
            raise PlexError(
                f"the forge file {source.name} is not in {FORGE_SPIKE}: run "
                "the forge (docker compose run testlab-forge)"
            )
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        written.append(str(target.relative_to(state)))
    return written


def copy_music_files(state: Path) -> list[str]:
    """The forge's fourteen Discovery tracks, under one artist and album."""
    target_root = (
        folder_of(
            state, next(spec for spec in SECTION_SPECS if spec["kind"] == "artist")
        )
        / MUSIC_SHOW
        / MUSIC_ALBUM
    )
    written: list[str] = []
    sources = sorted(FORGE_SPIKE.glob("Daft Punk - Discovery - *.flac"))
    if not sources:
        raise PlexError(
            f"the forge's Discovery tracks are not in {FORGE_SPIKE}: run the "
            "forge (docker compose run testlab-forge)"
        )
    for source in sources:
        name = source.name.replace("Daft Punk - Discovery - ", "", 1)
        target = target_root / name
        if target.exists() and target.stat().st_size > 0:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        written.append(str(target.relative_to(state)))
    return written


def wait_for_media(
    state: Path, spec: dict[str, Any], *, timeout: float
) -> bool:
    """Wait for the Jellyfin block's files before copying the forge's own.

    `Series` and `Music` are that block's folders too; its layout is the one
    the lab should keep when it is there, and the contract reads a library, not
    a copy. A folder that stays empty for `timeout` seconds is filled here.
    """
    folder = folder_of(state, spec)
    suffixes = (".mkv", ".mp4") if spec["kind"] == "show" else (".flac", ".mp3")
    if files_under(folder, suffixes):
        return True
    if timeout <= 0:
        return False
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        time.sleep(2)
        if files_under(folder, suffixes):
            print(
                f"[plex-media] {spec['title']}: files arrived from the "
                "Jellyfin block, nothing copied"
            )
            return True
    return False


def ensure_media(state: Path, *, wait: float) -> dict[str, list[str]]:
    """Every section has at least one real file under it."""
    copied: dict[str, list[str]] = {"series": [], "music": []}
    for spec in SECTION_SPECS:
        folder = folder_of(state, spec)
        folder.mkdir(parents=True, exist_ok=True)
        if spec["kind"] == "movie":
            if not files_under(folder, (".mkv", ".mp4")):
                raise PlexError(
                    f"{folder} is empty: the seed and the forge both put the "
                    "movies there, run the seed again"
                )
            continue
        if wait_for_media(state, spec, timeout=wait):
            continue
        if spec["kind"] == "show":
            copied["series"] = copy_series_files(state)
        else:
            copied["music"] = copy_music_files(state)
        if not copied["series" if spec["kind"] == "show" else "music"]:
            raise PlexError(f"{folder} stayed empty after the copy")
        print(
            f"[plex-media] {spec['title']}: copied "
            f"{len(copied['series' if spec['kind'] == 'show' else 'music'])} "
            "files from the forge"
        )
    return copied


# ---------------------------------------------------------------------------
# Scans and reads
# ---------------------------------------------------------------------------


def scan(state: Path, library: dict[str, dict[str, Any]]) -> None:
    for entry in library.values():
        status, body = call(
            state, f"/library/sections/{entry['id']}/refresh", method="POST"
        )
        if not 200 <= status < 300:
            raise PlexError(
                f"refreshing {entry['title']} answered {status}: "
                f"{body.decode('utf-8', errors='replace')[:120]}"
            )
        print(f"[plex-media] {entry['title']}: scan asked")


def _wait_not_refreshing(
    state: Path, library: dict[str, dict[str, Any]], *, timeout: float = 120
) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        busy = [
            str(entry.get("title") or "")
            for entry in sections(state)
            if _refreshing(entry)
        ]
        if not busy:
            return
        time.sleep(1)
    raise PlexError(f"Plex is still scanning {busy} after {timeout:.0f}s")


def _refreshing(section: dict[str, Any]) -> bool:
    """`refreshing` arrives as a bool or as `0`/`1`, by endpoint."""
    value = section.get("refreshing", False)
    if isinstance(value, bool):
        return value
    return str(value) not in ("0", "", "false", "False", "None")


def _items(
    state: Path, path: str, query: dict[str, Any] | None = None
) -> list[dict[str, Any]]:
    answer = container(state, path, query=query)
    metadata = answer.get("Metadata")
    if not isinstance(metadata, list):
        return []
    return [entry for entry in metadata if isinstance(entry, dict)]


def items_of(
    state: Path, library: dict[str, dict[str, Any]], kind: str
) -> list[dict[str, Any]]:
    entry = library[kind]
    section = f"/library/sections/{entry['id']}"
    if kind == "movie":
        return _items(state, f"{section}/all", {"type": 1})
    if kind == "show":
        return _items(state, f"{section}/allLeaves")
    return _items(state, f"{section}/all", {"type": 10})


def wait_for_items(
    state: Path,
    library: dict[str, dict[str, Any]],
    kind: str,
    *,
    timeout: float = 180,
) -> list[dict[str, Any]]:
    deadline = time.monotonic() + timeout
    while True:
        found = items_of(state, library, kind)
        if found or time.monotonic() >= deadline:
            return found
        time.sleep(2)


def item(state: Path, rating_key: str) -> dict[str, Any]:
    answer = container(state, f"/library/metadata/{rating_key}")
    metadata = answer.get("Metadata")
    if not isinstance(metadata, list) or not metadata:
        raise PlexError(f"/library/metadata/{rating_key} answered no item")
    return metadata[0]


def pick_movie(items: list[dict[str, Any]]) -> dict[str, Any]:
    """A movie the flows can name. The seed's own specimen first."""
    for item_row in items:
        if item_row.get("title") == "Cupola Test Feature":
            return item_row
    return items[0]


def show_named(items: list[dict[str, Any]], title: str) -> dict[str, Any] | None:
    for item_row in items:
        if str(item_row.get("grandparentTitle") or item_row.get("title") or "") == title:
            return item_row
    return None


def episode_with(items: list[dict[str, Any]], index: int) -> dict[str, Any] | None:
    for item_row in items:
        if int(item_row.get("index") or 0) == index:
            return item_row
    return None


def scrobble(state: Path, rating_key: str) -> None:
    status, body = call(
        state,
        "/:/scrobble",
        query={
            "key": rating_key,
            "identifier": "com.plexapp.plugins.library",
        },
    )
    if not 200 <= status < 300:
        raise PlexError(
            f"marking {rating_key} watched answered {status}: "
            f"{body.decode('utf-8', errors='replace')[:120]}"
        )
    print(f"[plex-media] item {rating_key}: marked watched")


def mark_watched(
    state: Path, library: dict[str, dict[str, Any]]
) -> dict[str, Any]:
    """One watched movie and one watched episode, left watched.

    Watched state is the lab's, like the Seerr world and the Readarr library:
    a rerun reads it rather than writing it again, so the on-deck row is stable.
    """
    movies = wait_for_items(state, library, "movie")
    if not movies:
        raise PlexError("the Films section holds no movie to mark watched")
    movie = pick_movie(movies)
    movie_row = item(state, str(movie["ratingKey"]))
    if int(movie_row.get("viewCount") or 0) < 1:
        scrobble(state, str(movie["ratingKey"]))
        movie_row = item(state, str(movie["ratingKey"]))
    if int(movie_row.get("viewCount") or 0) < 1:
        raise PlexError(f"{movie_row.get('title')} did not read back as watched")

    episodes = wait_for_items(state, library, "show")
    show = show_named(episodes, "Breaking Bad")
    if show is None:
        raise PlexError("the Series section holds no Breaking Bad episode")
    first = episode_with(episodes, 1)
    if first is None:
        raise PlexError("the Series section holds no Breaking Bad s01e01")
    first_row = item(state, str(first["ratingKey"]))
    if int(first_row.get("viewCount") or 0) < 1:
        scrobble(state, str(first["ratingKey"]))
        first_row = item(state, str(first["ratingKey"]))
    if int(first_row.get("viewCount") or 0) < 1:
        raise PlexError("the first episode did not read back as watched")

    return {
        "movie": {
            "ratingKey": str(movie_row.get("ratingKey") or ""),
            "title": str(movie_row.get("title") or ""),
            "year": movie_row.get("year"),
            "viewCount": int(movie_row.get("viewCount") or 0),
            "lastViewedAt": movie_row.get("lastViewedAt"),
        },
        "episode": {
            "ratingKey": str(first_row.get("ratingKey") or ""),
            "show": str(first_row.get("grandparentTitle") or ""),
            "season": first_row.get("parentIndex"),
            "index": first_row.get("index"),
            "title": str(first_row.get("title") or ""),
            "viewCount": int(first_row.get("viewCount") or 0),
            "lastViewedAt": first_row.get("lastViewedAt"),
        },
    }


def on_deck(state: Path) -> list[dict[str, Any]]:
    """`/hubs/continueWatching`, as the app's On deck tab reads it."""
    answer = container(state, "/hubs/continueWatching", query={"count": 20})
    rows: list[dict[str, Any]] = []
    for hub in answer.get("Hub", []):
        if not isinstance(hub, dict):
            continue
        for entry in hub.get("Metadata", []):
            if not isinstance(entry, dict):
                continue
            rows.append(
                {
                    "ratingKey": str(entry.get("ratingKey") or ""),
                    "type": str(entry.get("type") or ""),
                    "title": str(entry.get("title") or ""),
                    "show": entry.get("grandparentTitle"),
                    "index": entry.get("index"),
                    "viewOffset": entry.get("viewOffset"),
                }
            )
    return rows


# ---------------------------------------------------------------------------
# Build and verify
# ---------------------------------------------------------------------------


def build(state: Path, *, wait: float) -> dict[str, Any]:
    ensure_sections(state)
    library = library_of(state)
    for spec in SECTION_SPECS:
        if spec["kind"] not in library:
            raise PlexError(f"the {spec['title']} section is not on the server")
    ensure_media(state, wait=wait)
    scan(state, library)
    _wait_not_refreshing(state, library)
    for kind, title in (("movie", "movie"), ("show", "episode"), ("artist", "track")):
        found = wait_for_items(state, library, kind)
        if not found:
            raise PlexError(f"the {title} never appeared in the library")
        print(f"[plex-media] {title}: {len(found)} in the library")
    watched = mark_watched(state, library)
    rows = on_deck(state)
    if not rows:
        raise PlexError(
            "continueWatching is empty after watching s01e01: Plex's next-up "
            "row is not there"
        )
    return contract(state, library, watched, rows)


def contract(
    state: Path,
    library: dict[str, dict[str, Any]],
    watched: dict[str, Any],
    rows: list[dict[str, Any]],
) -> dict[str, Any]:
    server = container(state, "/")
    movie = pick_movie(wait_for_items(state, library, "movie"))
    episodes = wait_for_items(state, library, "show")
    tracks = wait_for_items(state, library, "artist")
    track = tracks[0]
    second = episode_with(episodes, 2)
    return {
        "plex": {
            "url": PLEX_URL,
            "version": str(server.get("version") or ""),
            "machineIdentifier": str(server.get("machineIdentifier") or ""),
            "plexPass": bool(server.get("myPlexSubscription")),
        },
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "libraries": list(library.values()),
        "items": {
            "movie": {
                "ratingKey": str(movie.get("ratingKey") or ""),
                "title": str(movie.get("title") or ""),
                "year": movie.get("year"),
                "duration": movie.get("duration"),
            },
            "episode": {
                "ratingKey": str(episodes[0].get("ratingKey") or ""),
                "show": str(episodes[0].get("grandparentTitle") or ""),
                "season": episodes[0].get("parentIndex"),
                "index": episodes[0].get("index"),
                "title": str(episodes[0].get("title") or ""),
            },
            "nextEpisode": (
                {
                    "ratingKey": str(second.get("ratingKey") or ""),
                    "index": second.get("index"),
                }
                if second
                else None
            ),
            "track": {
                "ratingKey": str(track.get("ratingKey") or ""),
                "title": str(track.get("title") or ""),
                "artist": str(track.get("grandparentTitle") or ""),
                "album": str(track.get("parentTitle") or ""),
                "duration": track.get("duration"),
            },
        },
        "counts": {
            "movies": len(items_of(state, library, "movie")),
            "episodes": len(episodes),
            "tracks": len(tracks),
        },
        "watched": watched,
        "onDeck": rows,
        "limits": {
            "movieOnDeck": (
                "not made: Plex writes a movie's viewOffset only from a real "
                "client playback; /:/timeline, a range read of the part and "
                "PUT viewOffset all leave viewOffset unset on 1.43.4"
            ),
            "stopSession": (
                "Plex Pass is required for /status/sessions/terminate and this "
                "server reports myPlexSubscription false"
            ),
            "householdUser": (
                "no Plex Home user is created: the server is claimed with the "
                "owner's real account, which this lab never writes"
            ),
        },
    }


def verify(state: Path) -> list[str]:
    """What the flows read, read back from the server. No write."""
    problems: list[str] = []
    library = library_of(state)
    for spec in SECTION_SPECS:
        if spec["kind"] not in library:
            problems.append(f"no {spec['title']} section on {spec['path']}")
    if problems:
        return problems

    for kind, label in (("movie", "movie"), ("show", "episode"), ("artist", "track")):
        if not items_of(state, library, kind):
            problems.append(f"the {label} library is empty")

    episodes = items_of(state, library, "show")
    show = show_named(episodes, "Breaking Bad")
    if show is None:
        problems.append("the Series library holds no Breaking Bad episode")
    first = episode_with(episodes, 1)
    if first is not None:
        row = item(state, str(first["ratingKey"]))
        if int(row.get("viewCount") or 0) < 1:
            problems.append("Breaking Bad s01e01 is not marked watched")

    movies = items_of(state, library, "movie")
    if movies:
        row = item(state, str(pick_movie(movies)["ratingKey"]))
        if int(row.get("viewCount") or 0) < 1:
            problems.append(f"{row.get('title')} is not marked watched")

    rows = on_deck(state)
    if not any(str(row.get("show") or row.get("title")) == "Breaking Bad" for row in rows):
        problems.append("continueWatching carries no Breaking Bad row")
    return problems


def write_contract(state: Path, document: dict[str, Any]) -> Path:
    path = state / CONTRACT_NAME
    path.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    os.chmod(path, 0o644)
    return path


def seed(state: Path, *, wait: float | None = None) -> dict[str, Any]:
    """Build the libraries and the watch state, then write the contract."""
    wait_seconds = (
        wait
        if wait is not None
        else float(os.environ.get("CUPOLA_TESTLAB_MEDIA_WAIT", "120"))
    )
    document = build(state, wait=wait_seconds)
    write_contract(state, document)
    return document


def verify_only(state: Path) -> list[str]:
    return verify(state)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Plex's three libraries, the watch marks and on deck (L8)."
    )
    parser.add_argument(
        "--state-dir",
        default=os.environ.get(
            "CUPOLA_TESTLAB_STATE_DIR", str(state_root())
        ),
        help="the lab's disposable state directory",
    )
    parser.add_argument(
        "--wait",
        type=float,
        default=float(os.environ.get("CUPOLA_TESTLAB_MEDIA_WAIT", "120")),
        help=(
            "seconds to wait for the Jellyfin block's series and music files "
            "before copying the forge's own"
        ),
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="only verify the libraries and the watch state, and change nothing",
    )
    arguments = parser.parse_args()
    state = Path(arguments.state_dir).resolve()
    try:
        if arguments.check:
            problems = verify_only(state)
            if problems:
                raise PlexError("; ".join(problems))
            print(json.dumps({"plex": "verified"}, indent=2))
            return 0
        document = seed(state, wait=arguments.wait)
        print(
            json.dumps(
                {
                    "libraries": [
                        entry["title"] for entry in document["libraries"]
                    ],
                    "counts": document["counts"],
                    "watched": {
                        "movie": document["watched"]["movie"]["title"],
                        "episode": document["watched"]["episode"]["title"],
                    },
                    "onDeck": [row["title"] for row in document["onDeck"]],
                    "plexPass": document["plex"]["plexPass"],
                    "contract": str(state / CONTRACT_NAME),
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0
    except PlexError as error:
        print(f"[plex-media] {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
