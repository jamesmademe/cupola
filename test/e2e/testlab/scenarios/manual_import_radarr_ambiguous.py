"""The Radarr manual import slice: a real download whose file name does not
name a movie, waiting for a person to choose one.

The chain is real: the local seeder holds a private torrent, the app's
qBittorrent fetches it, and Radarr's own `manualimport` scan rejects the file
as `Unknown Movie`. The journey then uses the app's manual import wizard from
Activity, chooses Big Buck Bunny, and imports. Nothing writes a vendor database
while its container runs.
"""

from __future__ import annotations

import http.cookiejar
import time
import urllib.parse
import urllib.request

from .base import Scenario, ScenarioError, credentials, request, require_ok

RADARR = "http://127.0.0.1:7878/api/v3"
# qBittorrent checks the Host against its WebUI port (8080): see seed_lab.
QBITTORRENT = "http://127.0.0.1:18080"
QBIT_HOST = {"Host": "127.0.0.1:8080"}
HEADERS = {"X-Api-Key": "test-key", "Accept": "application/json"}
FOLDER = "The.Great.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA"
TMDB_ID = 10378


def _json(path: str, method: str = "GET", payload: dict | None = None) -> object:
    status, body = request(
        f"{RADARR}{path}", method=method, payload=payload, headers=HEADERS
    )
    require_ok(status, body, f"Radarr {method} {path}")
    return body


def _movie() -> dict:
    movies = _json(f"/movie?tmdbId={TMDB_ID}")
    if isinstance(movies, list):
        for movie in movies:
            if isinstance(movie, dict) and movie.get("tmdbId") == TMDB_ID:
                return movie
    raise ScenarioError("Big Buck Bunny is not in Radarr's library")


def _manual_items() -> list[dict]:
    body = _json(
        f"/manualimport?folder=/downloads/{FOLDER}&filterExistingFiles=true"
    )
    if not isinstance(body, list):
        return []
    return [item for item in body if isinstance(item, dict)]


def _qbittorrent_opener():
    env = credentials()
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar)
    )
    form = urllib.parse.urlencode(
        {
            "username": env.get("CUPOLA_TESTLAB_QBITTORRENT_USERNAME", "admin"),
            "password": env.get("CUPOLA_TESTLAB_QBITTORRENT_PASSWORD", ""),
        }
    ).encode()
    status, body = request(
        f"{QBITTORRENT}/api/v2/auth/login",
        method="POST",
        payload=form,
        headers={"Content-Type": "application/x-www-form-urlencoded", **QBIT_HOST},
        opener=opener,
    )
    require_ok(status, body, "qBittorrent login")
    return opener


def _torrents(opener) -> list[dict]:
    status, body = request(
        f"{QBITTORRENT}/api/v2/torrents/info", headers=QBIT_HOST, opener=opener
    )
    require_ok(status, body, "qBittorrent torrents")
    return [item for item in body or [] if isinstance(item, dict)]


def _ensure_torrent(opener) -> dict:
    for torrent in _torrents(opener):
        if torrent.get("name") == FOLDER:
            return torrent
    form = urllib.parse.urlencode(
        {
            "urls": "http://testlab-indexer:8088/torrents/the-great-bunny.torrent",
            "savepath": "/downloads",
            "category": "radarr",
            "paused": "false",
        }
    ).encode()
    status, body = request(
        f"{QBITTORRENT}/api/v2/torrents/add",
        method="POST",
        payload=form,
        headers={"Content-Type": "application/x-www-form-urlencoded", **QBIT_HOST},
        opener=opener,
    )
    require_ok(status, body, "qBittorrent add")
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        for torrent in _torrents(opener):
            if torrent.get("name") == FOLDER:
                if float(torrent.get("progress") or 0) >= 1:
                    return torrent
                break
        time.sleep(2)
    raise ScenarioError("the torrent never finished downloading")


class ManualImportRadarrAmbiguous(Scenario):
    name = "manual-import-radarr-ambiguous"
    profiles = ("core", "downloads")

    def apply(self) -> None:
        movie = _movie()
        if movie.get("hasFile"):
            raise ScenarioError(
                "Big Buck Bunny already has a file; reset the golden first"
            )
        opener = _qbittorrent_opener()
        _ensure_torrent(opener)
        if not _manual_items():
            raise ScenarioError(
                "Radarr's manual import scan found no file in the download"
            )

    def teardown(self) -> None:
        opener = _qbittorrent_opener()
        for torrent in _torrents(opener):
            if torrent.get("name") != FOLDER:
                continue
            form = urllib.parse.urlencode(
                {"hashes": torrent["hash"], "deleteFiles": "true"}
            ).encode()
            status, body = request(
                f"{QBITTORRENT}/api/v2/torrents/delete",
                method="POST",
                payload=form,
                headers={"Content-Type": "application/x-www-form-urlencoded", **QBIT_HOST},
                opener=opener,
            )
            require_ok(status, body, "qBittorrent delete")

    def verify(self) -> None:
        opener = _qbittorrent_opener()
        torrent = next(
            (item for item in _torrents(opener) if item.get("name") == FOLDER),
            None,
        )
        if torrent is None:
            raise ScenarioError("the download is not in qBittorrent")
        if float(torrent.get("progress") or 0) < 1:
            raise ScenarioError("the download did not finish")
        items = _manual_items()
        if not items:
            raise ScenarioError("Radarr's manual import scan found no file")
        if not any(item.get("rejections") for item in items):
            raise ScenarioError(
                "Radarr accepts the file by itself; it should need a match"
            )
        if _movie().get("hasFile"):
            raise ScenarioError("Big Buck Bunny already has a file")

    def verify_absent(self) -> None:
        opener = _qbittorrent_opener()
        if any(item.get("name") == FOLDER for item in _torrents(opener)):
            raise ScenarioError("the download is still in qBittorrent")
        if _manual_items():
            raise ScenarioError("Radarr still sees an importable file")
        if _movie().get("hasFile"):
            raise ScenarioError("Big Buck Bunny kept a file after teardown")


SCENARIO = ManualImportRadarrAmbiguous()
