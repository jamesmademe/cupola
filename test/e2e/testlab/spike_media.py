"""The L4 spike: what the three arrs make of the forge's files.

The forge writes a small set of variants into `/downloads/spike`; this script
asks Radarr, Sonarr and Lidarr's own `manualimport` scan what they see: the
quality each file parses to, the match, and the rejections. It is deliberately
a report first and an assertion second, because the one question that matters
is whether a short file *without* `sample` in its name is treated as a sample
from its duration alone.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any

ROOT = "http://127.0.0.1"
SPIKE_FOLDER = "/downloads/spike"
HEADERS = {"X-Api-Key": "test-key", "Accept": "application/json"}

RADARR = f"{ROOT}:7878/api/v3"
SONARR = f"{ROOT}:8989/api/v3"
LIDARR = f"{ROOT}:8686/api/v1"


def _items(base: str) -> list[dict[str, Any]]:
    url = f"{base}/manualimport?folder={SPIKE_FOLDER}&filterExistingFiles=false"
    try:
        with urllib.request.urlopen(
            urllib.request.Request(url, headers=HEADERS), timeout=60
        ) as answer:
            body = json.load(answer)
    except (urllib.error.URLError, TimeoutError) as error:
        return [{"error": str(error)}]
    return [item for item in body or [] if isinstance(item, dict)]


def _quality(item: dict[str, Any]) -> str | None:
    quality = item.get("quality")
    if not isinstance(quality, dict):
        return None
    inner = quality.get("quality")
    if isinstance(inner, dict):
        return inner.get("name")
    return None


def _rejections(item: dict[str, Any]) -> list[str]:
    values = item.get("rejections")
    if not isinstance(values, list):
        return []
    return [
        str(value.get("reason"))
        for value in values
        if isinstance(value, dict) and value.get("reason")
    ]


def _match(item: dict[str, Any]) -> str | None:
    movie = item.get("movie")
    if isinstance(movie, dict) and movie.get("title"):
        return f"movie: {movie['title']}"
    series = item.get("series")
    if isinstance(series, dict) and series.get("title"):
        episodes = item.get("episodes")
        if isinstance(episodes, list) and episodes:
            labels = [
                f"S{episode.get('seasonNumber')}E{episode.get('episodeNumber')}"
                for episode in episodes
                if isinstance(episode, dict)
            ]
            return f"series: {series['title']} {', '.join(labels)}"
        return f"series: {series['title']}"
    artist = item.get("artist")
    if isinstance(artist, dict) and artist.get("artistName"):
        return f"artist: {artist['artistName']}"
    return None


def _row(service: str, item: dict[str, Any]) -> dict[str, Any]:
    return {
        "service": service,
        "file": item.get("relativePath") or item.get("path"),
        "quality": _quality(item),
        "match": _match(item),
        "rejections": _rejections(item),
    }


def _find(
    rows: list[dict[str, Any]], suffix: str, service: str
) -> dict[str, Any] | None:
    for row in rows:
        if row.get("service") == service and str(row.get("file") or "").endswith(
            suffix
        ):
            return row
    return None


def _sample_rejected(row: dict[str, Any] | None) -> bool:
    if row is None:
        return False
    return any("sample" in reason.lower() for reason in row["rejections"])


def run() -> dict[str, Any]:
    rows = [
        *(_row("radarr", item) for item in _items(RADARR)),
        *(_row("sonarr", item) for item in _items(SONARR)),
        *(_row("lidarr", item) for item in _items(LIDARR)),
    ]
    rows = [row for row in rows if row.get("file")]
    checks: list[dict[str, Any]] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        checks.append({"check": name, "ok": ok, "detail": detail})

    def quality(name: str, suffix: str, expected: str, service: str) -> None:
        row = _find(rows, suffix, service)
        check(
            name,
            row is not None and row["quality"] == expected,
            f"{row['quality'] if row else 'missing'}",
        )

    quality(
        "a 1080p file parses as WEBDL-1080p",
        "Big.Buck.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
        "WEBDL-1080p",
        "radarr",
    )
    quality(
        "a 2160p file parses as WEBDL-2160p",
        "Big.Buck.Bunny.2008.2160p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
        "WEBDL-2160p",
        "radarr",
    )
    quality(
        "a 480p file parses as WEBDL-480p",
        "Big.Buck.Bunny.2008.480p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
        "WEBDL-480p",
        "radarr",
    )
    sample = _find(
        rows,
        "Big.Buck.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.sample.mkv",
        "radarr",
    )
    check("a file named sample is refused as a sample", _sample_rejected(sample))
    short = _find(
        rows,
        "Big.Buck.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.short.mkv",
        "radarr",
    )
    # The finding, not a verdict yet: the plan's premise is that duration alone
    # makes a sample. If this is false, the forge has to put the word in the
    # name and the catalog's sample case is a name case, not a duration case.
    check(
        "a 20s file without the word sample is refused as a sample",
        _sample_rejected(short),
        "duration-only sample detection",
    )
    episode = _find(
        rows,
        "Breaking.Bad.S01E02.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
        "sonarr",
    )
    check(
        "an episode file parses with its series and episode",
        episode is not None
        and episode["match"] == "series: Breaking Bad S1E2",
        episode["match"] if episode else "missing",
    )
    music = _find(
        rows,
        "Daft Punk - Discovery - 01 - One More Time.flac",
        "lidarr",
    )
    check(
        "a FLAC track parses as FLAC",
        music is not None and music["quality"] == "FLAC",
        music["quality"] if music else "missing",
    )
    unreadable = _find(
        rows,
        "Unreadable.Name.2024.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
        "radarr",
    )
    check(
        "a file that names no library title needs a match",
        unreadable is not None
        and (unreadable["match"] is None or bool(unreadable["rejections"])),
        str(unreadable["rejections"]) if unreadable else "missing",
    )
    return {
        "ok": all(item["ok"] for item in checks),
        "checks": checks,
        "rows": rows,
    }
