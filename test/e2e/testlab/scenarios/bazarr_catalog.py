"""Bazarr's wanted list, its history and its provider throttles, on top of the
L6a embedded-subtitle case. The flow catalogue's A-18, A-19 and A-20.

The state comes from ``bazarr-embedded``, imported and left untouched: Big Buck
Bunny gets a real English track, Bazarr extracts it with the
``embeddedsubtitles`` provider, and The Matrix keeps only its French track and
stays wanted. This scenario reads that state the way the app does:

* ``/movies/wanted`` and ``/episodes/wanted``, against the badge counts, so a
  wanted row and the number over the rail cannot disagree;
* ``/movies``, so every movie either has a subtitle or is wanted, never
  neither;
* ``/movies/history`` and ``/episodes/history``, including the row of the
  extraction this run produced (a count taken before the case is applied);
* ``/providers`` and ``POST /providers?action=reset``, then the same list again.

``throttled`` is the app's word, not the API's: ``BazarrProviderStatus`` calls
a provider throttled when its ``status`` is anything but ``Good`` (``History``
excepted) and reads the wait from ``retry``. The API has no ``throttled`` key,
so this scenario asserts the two fields the app derives it from, plus the badge
count of throttled providers, which must be zero.

``teardown`` calls ``bazarr-embedded``'s own teardown and removes nothing else:
the extraction's history row is Bazarr's audit trail, and a reset of an already
clean provider list changes nothing. ``apply`` therefore refuses to run while a
provider is being waited out: a reset cannot be undone through the API, and a
scenario that cannot restore what it changed is not a scenario.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .base import STATE_ROOT, Scenario, ScenarioError, request, require_ok
from .bazarr_embedded import BazarrEmbedded

BAZARR = "http://127.0.0.1:6767/api"
HEADERS = {"X-API-KEY": "test-key", "Accept": "application/json"}
MARKER = STATE_ROOT / "backup" / "bazarr_catalog" / "state.json"

BIG_BUCK_BUNNY = "Big Buck Bunny"
THE_MATRIX = "The Matrix"
ENGLISH = "en"
EMBEDDED = "embeddedsubtitles"
DOWNLOADED = 1
HEALTHY = ("", "good", "history")


def _call(
    path: str, *, method: str = "GET", timeout: float = 30.0
) -> tuple[int, Any]:
    return request(
        f"{BAZARR}{path}", method=method, headers=HEADERS, timeout=timeout
    )


def _get(path: str) -> Any:
    status, body = _call(path)
    require_ok(status, body, f"Bazarr GET {path}")
    return body


def _page(path: str, what: str) -> dict:
    body = _get(path)
    if not isinstance(body, dict) or not isinstance(body.get("data"), list):
        raise ScenarioError(f"Bazarr answered {what} without a page: {body}")
    if not isinstance(body.get("total"), int):
        raise ScenarioError(f"Bazarr answered {what} without a total: {body}")
    return body


def _rows(page: dict) -> list[dict]:
    return [row for row in page["data"] if isinstance(row, dict)]


def _codes(languages: Any) -> set[str]:
    return {
        str(language.get("code2"))
        for language in languages or []
        if isinstance(language, dict) and language.get("code2")
    }


def _one(rows: list[dict], title: str, what: str) -> dict:
    matches = [row for row in rows if row.get("title") == title]
    if len(matches) != 1:
        raise ScenarioError(
            f"Bazarr's {what} lists {len(matches)} rows called {title!r}"
        )
    return matches[0]


def _badges() -> dict:
    body = _get("/badges")
    if not isinstance(body, dict):
        raise ScenarioError(f"Bazarr answered /badges without an object: {body}")
    return body


def _providers() -> list[dict]:
    body = _get("/providers")
    data = body.get("data") if isinstance(body, dict) else body
    if not isinstance(data, list):
        raise ScenarioError(f"Bazarr answered /providers without a list: {body}")
    return [item for item in data if isinstance(item, dict)]


def _throttled(providers: list[dict]) -> list[dict]:
    return [
        provider
        for provider in providers
        if str(provider.get("status") or "").strip().lower() not in HEALTHY
    ]


def _settings() -> dict:
    body = _get("/system/settings")
    if not isinstance(body, dict) or not isinstance(body.get("general"), dict):
        raise ScenarioError("Bazarr answered /system/settings without settings")
    return body


def _host(path: str) -> Path:
    """The host path of a container path: /media is the state root."""
    return STATE_ROOT / str(path).lstrip("/")


def _downloads(page: dict, title: str) -> list[dict]:
    return [
        row
        for row in _rows(page)
        if row.get("title") == title
        and row.get("provider") == EMBEDDED
        and row.get("action") == DOWNLOADED
    ]


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


class BazarrCatalog(Scenario):
    name = "bazarr-catalog"
    profiles = ("core", "media")

    def apply(self) -> None:
        throttled = _throttled(_providers())
        if throttled:
            raise ScenarioError(
                "Bazarr is already waiting out "
                f"{[provider.get('name') for provider in throttled]}; a reset "
                "cannot be undone through the API, so this scenario needs a lab "
                "with every provider ready"
            )

        marker = _load()
        marker["embeddedDownloads"] = len(
            _downloads(_page("/movies/history", "movie history"), BIG_BUCK_BUNNY)
        )
        _save(marker)

        BazarrEmbedded().apply()

        status, body = _call("/providers?action=reset", method="POST")
        if status not in (200, 204):
            raise ScenarioError(
                f"Bazarr did not reset the provider throttles: {status} {body}"
            )

    def teardown(self) -> None:
        BazarrEmbedded().teardown()
        throttled = _throttled(_providers())
        if throttled:
            raise ScenarioError(
                "the teardown left a provider waiting: "
                f"{[(item.get('name'), item.get('status')) for item in throttled]}"
            )
        _forget()

    def verify(self) -> None:
        marker = _load()
        settings = _settings()
        if settings["general"].get("use_embedded_subs"):
            raise ScenarioError(
                "Bazarr counts embedded tracks as existing; the L6a case needs false"
            )

        badges = _badges()
        wanted_movies = _page("/movies/wanted", "wanted movies")
        wanted_episodes = _page("/episodes/wanted", "wanted episodes")
        movies = _page("/movies", "movies")
        history = _page("/movies/history", "movie history")
        episode_history = _page("/episodes/history", "episode history")

        # A-18: the wanted list is the badge count, and every row names what it
        # is missing. The Matrix is the movie with only its French track.
        if wanted_movies["total"] != badges.get("movies"):
            raise ScenarioError(
                f"the badge says {badges.get('movies')} wanted movies, "
                f"the list says {wanted_movies['total']}"
            )
        for row in _rows(wanted_movies):
            if not _codes(row.get("missing_subtitles")):
                raise ScenarioError(f"a wanted movie misses nothing: {row}")
        matrix = _one(_rows(wanted_movies), THE_MATRIX, "wanted movies")
        if ENGLISH not in _codes(matrix.get("missing_subtitles")):
            raise ScenarioError(
                f"{THE_MATRIX} is wanted, but not in English: {matrix.get('missing_subtitles')}"
            )
        if _codes(matrix.get("subtitles")):
            raise ScenarioError(
                f"{THE_MATRIX} has subtitles and should have none: {matrix.get('subtitles')}"
            )
        if any(row.get("title") == BIG_BUCK_BUNNY for row in _rows(wanted_movies)):
            raise ScenarioError(
                f"{BIG_BUCK_BUNNY} is still wanted after the extraction"
            )

        if wanted_episodes["total"] != badges.get("episodes"):
            raise ScenarioError(
                f"the badge says {badges.get('episodes')} wanted episodes, "
                f"the list says {wanted_episodes['total']}"
            )
        for row in _rows(wanted_episodes):
            if not _codes(row.get("missing_subtitles")):
                raise ScenarioError(f"a wanted episode misses nothing: {row}")

        # The coverage the app prints: every movie has a subtitle or is wanted.
        bunny = _one(_rows(movies), BIG_BUCK_BUNNY, "movies")
        if ENGLISH not in _codes(bunny.get("subtitles")):
            raise ScenarioError(
                f"{BIG_BUCK_BUNNY} has no English subtitle: {bunny.get('subtitles')}"
            )
        if ENGLISH in _codes(bunny.get("missing_subtitles")):
            raise ScenarioError(
                f"{BIG_BUCK_BUNNY} is still missing English: {bunny.get('missing_subtitles')}"
            )
        for row in _rows(movies):
            if not _codes(row.get("subtitles")) and not _codes(
                row.get("missing_subtitles")
            ):
                raise ScenarioError(f"a movie is neither covered nor wanted: {row}")

        # A-20: the extraction's own row, from this run.
        downloads = _downloads(history, BIG_BUCK_BUNNY)
        if not downloads:
            raise ScenarioError(
                f"Bazarr's movie history has no {EMBEDDED} download row for "
                f"{BIG_BUCK_BUNNY}"
            )
        before = marker.get("embeddedDownloads")
        if isinstance(before, int) and len(downloads) <= before:
            raise ScenarioError(
                f"the history holds {len(downloads)} extraction rows, no more than "
                f"the {before} there before the case was applied"
            )
        latest = downloads[0]
        # Bazarr lists its history newest first, so the first row is this run's.
        path = str(latest.get("subtitles_path") or "")
        if not path.endswith(".en.srt"):
            raise ScenarioError(f"the extraction row points at {path!r}")
        if not _host(path).exists():
            raise ScenarioError(f"the extraction row names a file that is gone: {path}")
        if not latest.get("parsed_timestamp"):
            raise ScenarioError(f"the extraction row has no timestamp: {latest}")

        if len(episode_history["data"]) > episode_history["total"]:
            raise ScenarioError(
                "Bazarr's episode history is longer than its own total: "
                f"{episode_history['total']}"
            )
        for row in _rows(episode_history):
            if not row.get("parsed_timestamp"):
                raise ScenarioError(f"an episode history row has no timestamp: {row}")

        # A-19: the reset endpoint, and the reading that decides the badge.
        status, body = _call("/providers?action=reset", method="POST")
        if status not in (200, 204):
            raise ScenarioError(
                f"Bazarr did not reset the provider throttles: {status} {body}"
            )
        providers = _providers()
        if not providers:
            raise ScenarioError("Bazarr lists no provider at all")
        throttled = _throttled(providers)
        if throttled:
            raise ScenarioError(
                "a provider is still waiting after the reset: "
                f"{[(item.get('name'), item.get('status')) for item in throttled]}"
            )
        enabled = settings["general"].get("enabled_providers") or []
        if {item.get("name") for item in providers} != set(enabled):
            raise ScenarioError(
                f"/providers lists {[item.get('name') for item in providers]}, "
                f"the settings enable {enabled}"
            )
        after = _badges()
        if after.get("providers") != len(throttled):
            raise ScenarioError(
                f"the badge says {after.get('providers')} throttled providers, "
                f"the list says {len(throttled)}"
            )

    def verify_absent(self) -> None:
        BazarrEmbedded().verify_absent()
        throttled = _throttled(_providers())
        if throttled:
            raise ScenarioError(
                "the lab came out of teardown with a waiting provider: "
                f"{[(item.get('name'), item.get('status')) for item in throttled]}"
            )
        if MARKER.exists():
            raise ScenarioError("the scenario left its marker behind")


SCENARIO = BazarrCatalog()
