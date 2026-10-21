"""Shared plumbing for the Radarr and Sonarr scenarios of L6b.

The five ``arr_*`` scenarios drive the two arr services the way the app does:
their own v3 API, one API key, no writes to a database while a container runs.
This module holds only what more than one of them needs: the two base URLs, a
call that fails loudly, the JSON bookkeeping a scenario keeps between ``apply``
and ``verify``, and the three pieces of state the flows add and take back (a
cloned quality profile, a root folder, a tag).

Nothing here prints a credential: the lab's arr API key is the fixed test key
the compose file seeds, and it is not a secret.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any, Callable

from scenarios.base import STATE_ROOT, ScenarioError, request, require_ok

RADARR = "http://127.0.0.1:7878/api/v3"
SONARR = "http://127.0.0.1:8989/api/v3"
HEADERS = {"X-Api-Key": "test-key"}

# Where a scenario keeps the ids it created and the readings it took, so that
# ``verify`` (a second pass, not a second process) can assert them and
# ``teardown`` can take the same state out even after a failed run.
STATE_DIR = STATE_ROOT / "scenario-state"

# The two host folders the scenarios add as root folders. The compose file
# mounts ``state/media`` at ``/media`` in both containers, so a directory made
# here is the one the service sees.
MOVIES_4K = STATE_ROOT / "media" / "movies4k"
TV_ANIME = STATE_ROOT / "media" / "tv-anime"


def call(
    base: str,
    path: str,
    method: str = "GET",
    payload: Any | None = None,
) -> tuple[int, Any]:
    return request(
        f"{base}{path}", method=method, payload=payload, headers=HEADERS
    )


def get(base: str, path: str, what: str) -> Any:
    status, body = call(base, path)
    require_ok(status, body, what)
    return body


def write(
    base: str,
    path: str,
    method: str,
    payload: Any | None,
    what: str,
) -> Any:
    status, body = call(base, path, method=method, payload=payload)
    require_ok(status, body, what)
    return body


def wait_until(
    read: Callable[[], Any],
    predicate: Callable[[Any], bool],
    *,
    what: str,
    timeout: float = 60,
    interval: float = 1,
) -> Any:
    """Poll ``read`` until ``predicate`` holds, or say what never happened."""
    deadline = time.monotonic() + timeout
    last: Any = None
    while time.monotonic() < deadline:
        last = read()
        if predicate(last):
            return last
        time.sleep(interval)
    raise ScenarioError(f"{what} did not happen within {timeout:.0f}s: {last}")


def state_path(name: str) -> Path:
    return STATE_DIR / f"{name}.json"


def save_state(name: str, values: dict[str, Any]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state_path(name).write_text(
        json.dumps(values, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def load_state(name: str) -> dict[str, Any]:
    path = state_path(name)
    if not path.is_file():
        raise ScenarioError(
            f"{path.name} is missing; apply the scenario before verifying it"
        )
    return json.loads(path.read_text(encoding="utf-8"))


def clear_state(name: str) -> None:
    path = state_path(name)
    if path.exists():
        path.unlink()
    if STATE_DIR.is_dir() and not any(STATE_DIR.iterdir()):
        STATE_DIR.rmdir()


def host_dir(path: Path) -> bool:
    """Make the folder the root folder names. True when it was not there."""
    if path.is_dir():
        return False
    path.mkdir(parents=True)
    return True


def remove_host_dir(path: Path) -> None:
    if not path.is_dir():
        return
    for child in sorted(path.rglob("*"), reverse=True):
        if child.is_file():
            child.unlink()
        elif child.is_dir():
            child.rmdir()
    path.rmdir()


def quality_profiles(base: str) -> list[dict[str, Any]]:
    body = get(base, "/qualityprofile", f"{base} quality profiles")
    return [item for item in body if isinstance(item, dict)]


def find_profile(base: str, name: str) -> dict[str, Any] | None:
    return next(
        (item for item in quality_profiles(base) if item.get("name") == name),
        None,
    )


def ensure_profile(
    base: str, source_id: int, name: str, **changes: Any
) -> tuple[int, bool]:
    """Clone profile ``source_id`` under ``name``, unless it is already there.

    Returns the id and whether this call created it. The clone is the app's
    own case: a second quality profile a person made by copying one, with the
    source's items untouched and only the chosen fields different.
    """
    existing = find_profile(base, name)
    if existing is not None:
        return int(existing["id"]), False
    source = get(base, f"/qualityprofile/{source_id}", f"{base} profile {source_id}")
    clone = dict(source)
    clone["id"] = 0
    clone["name"] = name
    clone.update(changes)
    created = write(base, "/qualityprofile", "POST", clone, f"creating {name}")
    return int(created["id"]), True


def delete_profile(base: str, profile_id: int) -> None:
    status, body = call(base, f"/qualityprofile/{profile_id}", method="DELETE")
    if status == 404:
        return
    require_ok(status, body, f"deleting profile {profile_id}")


def ensure_root_folder(base: str, path: str) -> tuple[int, bool]:
    folders = get(base, "/rootfolder", f"{base} root folders")
    for folder in folders:
        if folder.get("path") == path:
            return int(folder["id"]), False
    created = write(
        base, "/rootfolder", "POST", {"path": path}, f"adding root folder {path}"
    )
    return int(created["id"]), True


def delete_root_folder(base: str, path: str) -> None:
    folders = get(base, "/rootfolder", f"{base} root folders")
    for folder in folders:
        if folder.get("path") != path:
            continue
        status, body = call(
            base, f"/rootfolder/{folder['id']}", method="DELETE"
        )
        require_ok(status, body, f"removing root folder {path}")


def ensure_tag(base: str, label: str) -> tuple[int, bool]:
    tags = get(base, "/tag", f"{base} tags")
    for tag in tags:
        if tag.get("label") == label:
            return int(tag["id"]), False
    created = write(base, "/tag", "POST", {"label": label}, f"adding tag {label}")
    return int(created["id"]), True


def delete_tag(base: str, label: str) -> None:
    tags = get(base, "/tag", f"{base} tags")
    for tag in tags:
        if tag.get("label") != label:
            continue
        status, body = call(base, f"/tag/{tag['id']}", method="DELETE")
        require_ok(status, body, f"removing tag {label}")


# The two services spell the same list differently: Radarr's own route is
# `/exclusions`, Sonarr's is `/importlistexclusion` (both under v3). The app
# only writes the flag, so the path is ours to get right.
EXCLUSION_ROUTES = {RADARR: "/exclusions", SONARR: "/importlistexclusion"}


def exclusion_route(base: str) -> str:
    try:
        return EXCLUSION_ROUTES[base]
    except KeyError as error:
        raise ScenarioError(f"no exclusion route known for {base}") from error


def import_exclusions(base: str) -> list[dict[str, Any]]:
    route = exclusion_route(base)
    body = get(base, route, f"{base} import list exclusions")
    return [item for item in body or [] if isinstance(item, dict)]


def delete_import_exclusion(
    base: str, *, tmdb_id: int | None = None, tvdb_id: int | None = None
) -> int:
    """Drop the exclusion a removal added. Returns how many it dropped."""
    dropped = 0
    for exclusion in import_exclusions(base):
        matches = (tmdb_id is not None and exclusion.get("tmdbId") == tmdb_id) or (
            tvdb_id is not None and exclusion.get("tvdbId") == tvdb_id
        )
        if not matches:
            continue
        status, body = call(
            base, f"{exclusion_route(base)}/{exclusion['id']}", method="DELETE"
        )
        require_ok(status, body, "removing the import list exclusion")
        dropped += 1
    return dropped


def command(base: str, payload: dict[str, Any], what: str) -> dict[str, Any]:
    return write(base, "/command", "POST", payload, what)


def wait_command(
    base: str, command_id: int, *, what: str, timeout: float = 180
) -> dict[str, Any]:
    """Read a command until the service stops running it."""

    def read() -> dict[str, Any]:
        body = get(base, f"/command/{command_id}", f"reading {what}")
        return body if isinstance(body, dict) else {}

    def settled(body: dict[str, Any]) -> bool:
        return str(body.get("status") or "") in (
            "completed",
            "failed",
            "aborted",
            "cancelled",
        )

    return wait_until(
        read, settled, what=f"{what} settling", timeout=timeout, interval=1
    )


def movies(base: str = RADARR) -> list[dict[str, Any]]:
    body = get(base, "/movie", "reading the movie library")
    return [item for item in body if isinstance(item, dict)]


def series(base: str = SONARR) -> list[dict[str, Any]]:
    body = get(base, "/series", "reading the series library")
    return [item for item in body if isinstance(item, dict)]


def find_movie(base: str, tmdb_id: int) -> dict[str, Any] | None:
    body = get(base, f"/movie?tmdbId={tmdb_id}", "looking the movie up by TMDB id")
    for item in body or []:
        if isinstance(item, dict) and item.get("tmdbId") == tmdb_id:
            return item
    return None


def find_series(base: str, tvdb_id: int) -> dict[str, Any] | None:
    body = get(base, f"/series?tvdbId={tvdb_id}", "looking the series up by TVDB id")
    for item in body or []:
        if isinstance(item, dict) and item.get("tvdbId") == tvdb_id:
            return item
    return None


def queue_records(base: str) -> list[dict[str, Any]]:
    body = get(base, "/queue?pageSize=200", f"{base} queue")
    records = body.get("records") if isinstance(body, dict) else None
    return [item for item in records or [] if isinstance(item, dict)]


def page(base: str, path: str, what: str) -> dict[str, Any]:
    body = get(base, path, what)
    if not isinstance(body, dict):
        raise ScenarioError(f"{what} answered without a page envelope: {body!r}")
    return body
