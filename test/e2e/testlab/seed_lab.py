#!/usr/bin/env python3
"""Populate the disposable macOS lab with small, safe, repeatable specimens.

The vendor services are real containers, but most of them start with empty
databases.  This script only talks to the loopback endpoints owned by the
Compose project; every mutation is idempotent by a stable title, path, or
domain name.  A vendor metadata service may be unavailable on an offline
machine, so a failed optional seed is reported and does not make bootstrap
remove a working lab.
"""

from __future__ import annotations

import argparse
import base64
import http.cookiejar
import json
import os
import shutil
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any


ROOT = "http://127.0.0.1"
QBIT_MAGNET = (
    "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
    "&dn=Cupola%20Test%20Torrent"
)
TRANSMISSION_MAGNET = (
    "magnet:?xt=urn:btih:89abcdef0123456789abcdef0123456789abcdef"
    "&dn=Cupola%20Test%20Transmission"
)


def read_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def request(
    url: str,
    *,
    method: str = "GET",
    payload: Any | None = None,
    headers: dict[str, str] | None = None,
    opener: urllib.request.OpenerDirector | None = None,
    timeout: float = 8,
) -> tuple[int, bytes]:
    body: bytes | None
    request_headers = dict(headers or {})
    if payload is None:
        body = None
    elif isinstance(payload, bytes):
        body = payload
    elif isinstance(payload, str):
        body = payload.encode()
    else:
        body = json.dumps(payload).encode()
        request_headers.setdefault("Content-Type", "application/json")
    request_object = urllib.request.Request(
        url,
        data=body,
        headers=request_headers,
        method=method,
    )
    client = opener or urllib.request.build_opener()
    with client.open(request_object, timeout=timeout) as response:
        return response.status, response.read()


def json_request(
    url: str,
    *,
    method: str = "GET",
    payload: Any | None = None,
    headers: dict[str, str] | None = None,
    opener: urllib.request.OpenerDirector | None = None,
    timeout: float = 8,
) -> Any:
    _, body = request(
        url,
        method=method,
        payload=payload,
        headers=headers,
        opener=opener,
        timeout=timeout,
    )
    return json.loads(body) if body else None


def warn(label: str, error: Exception) -> None:
    print(f"[testlab-seed] warning {label}: {type(error).__name__}: {error}")


def api_headers(version: str) -> dict[str, str]:
    return {"X-Api-Key": "test-key", "Accept": "application/json"}


def list_value(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, list):
        return [entry for entry in value if isinstance(entry, dict)]
    if isinstance(value, dict) and isinstance(value.get("records"), list):
        return [entry for entry in value["records"] if isinstance(entry, dict)]
    return []


def load_world(state_dir: Path) -> dict[str, Any]:
    path = state_dir / "world.json"
    if not path.is_file():
        raise RuntimeError(
            "world.json is missing; run "
            "dart run tool/testlab/export_world.dart --output <state>/world.json"
        )
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError("world.json is not an object")
    return value


def world_title(world: dict[str, Any], key: str) -> dict[str, Any]:
    for title in world.get("titles", []):
        if isinstance(title, dict) and title.get("key") == key:
            return title
    raise RuntimeError(f"world.json has no title {key!r}")


def world_artist(world: dict[str, Any], key: str) -> dict[str, Any]:
    for artist in world.get("artists", []):
        if isinstance(artist, dict) and artist.get("key") == key:
            return artist
    raise RuntimeError(f"world.json has no artist {key!r}")


def ensure_arr_root(
    name: str,
    port: int,
    version: str,
    path: str,
    root_name: str,
    *,
    metadata_profile: int | None = None,
) -> None:
    try:
        url = f"{ROOT}:{port}/api/{version}/rootfolder"
        headers = api_headers(version)
        roots = list_value(json_request(url, headers=headers))
        if any(root.get("path") == path for root in roots):
            return
        payload: dict[str, Any] = {
            "path": path,
            "name": root_name,
            "defaultQualityProfileId": 1,
        }
        if metadata_profile is not None:
            payload["defaultMetadataProfileId"] = metadata_profile
        request(url, method="POST", payload=payload, headers=headers)
        print(f"[testlab-seed] {name}: root folder {path}")
    except Exception as error:
        warn(f"{name} root folder", error)


def seed_arrs(world: dict[str, Any]) -> None:
    ensure_arr_root("Radarr", 7878, "v3", "/media/movies", "Movies")
    ensure_arr_root("Sonarr", 8989, "v3", "/media/series", "Series")
    ensure_arr_root(
        "Lidarr",
        8686,
        "v1",
        "/media/music",
        "Music",
        metadata_profile=1,
    )
    ensure_arr_root(
        "Readarr",
        8787,
        "v1",
        "/media/books",
        "Books",
        metadata_profile=1,
    )

    try:
        url = f"{ROOT}:7878/api/v3/movie"
        headers = api_headers("v3")
        movies = list_value(json_request(url, headers=headers))
        if not any(movie.get("title") == "Fight Club" for movie in movies):
            request(
                url,
                method="POST",
                headers=headers,
                payload={
                    "title": "Cupola Test Feature",
                    "originalTitle": "Cupola Test Feature",
                    "tmdbId": 550,
                    "year": 1999,
                    "qualityProfileId": 1,
                    "rootFolderPath": "/media/movies",
                    "monitored": True,
                    "minimumAvailability": "announced",
                    "addOptions": {"searchForMovie": False},
                    "images": [],
                    "tags": [],
                },
            )
            print("[testlab-seed] Radarr: movie specimen")
    except Exception as error:
        warn("Radarr movie", error)

    try:
        url = f"{ROOT}:8989/api/v3/series"
        headers = api_headers("v3")
        series = list_value(json_request(url, headers=headers))
        breaking_bad = world_title(world, "breakingBad")
        if not any(
            item.get("title") == breaking_bad["title"] for item in series
        ):
            request(
                url,
                method="POST",
                headers=headers,
                payload={
                    "title": breaking_bad["title"],
                    "tvdbId": breaking_bad["tvdbId"],
                    "year": breaking_bad["year"],
                    "qualityProfileId": 1,
                    "rootFolderPath": "/media/series",
                    "monitored": True,
                    "seasonFolder": True,
                    "addOptions": {"searchForMissingEpisodes": False},
                    "images": [],
                    "seasons": [],
                },
            )
            print("[testlab-seed] Sonarr: series specimen")

        series = list_value(json_request(url, headers=headers))
        breaking = next(
            (item for item in series if item.get("title") == breaking_bad["title"]),
            None,
        )
        if breaking is not None:
            statistics = breaking.get("statistics") or {}
            if (
                int(statistics.get("totalEpisodeCount") or 0) == 0
                and int(statistics.get("episodeCount") or 0) == 0
            ):
                json_request(
                    f"{ROOT}:8989/api/v3/command",
                    method="POST",
                    payload={"name": "RefreshSeries", "seriesId": breaking["id"]},
                    headers=headers,
                )
                time.sleep(10)
                print("[testlab-seed] Sonarr: series refreshed for episodes")
    except Exception as error:
        warn("Sonarr series", error)

    try:
        url = f"{ROOT}:8686/api/v1/artist"
        headers = api_headers("v1")
        artists = list_value(json_request(url, headers=headers))
        daft_punk = world_artist(world, "daftPunk")
        if not any(
            item.get("artistName") == daft_punk["name"] for item in artists
        ):
            request(
                url,
                method="POST",
                headers=headers,
                payload={
                    "artistName": daft_punk["name"],
                    "foreignArtistId": daft_punk["foreignArtistId"],
                    "qualityProfileId": 1,
                    "metadataProfileId": 1,
                    "rootFolderPath": "/media/music",
                    "monitored": True,
                    "addOptions": {"searchForMissingAlbums": False},
                    "images": [],
                },
            )
            print("[testlab-seed] Lidarr: artist specimen")

        artists = list_value(json_request(url, headers=headers))
        daft = next(
            (item for item in artists if item.get("artistName") == daft_punk["name"]),
            None,
        )
        if daft is not None:
            albums_url = f"{ROOT}:8686/api/v1/album?artistId={daft['id']}"
            albums = list_value(json_request(albums_url, headers=headers))
            if not any(album.get("title") == "Discovery" for album in albums):
                lookup = json_request(
                    f"{ROOT}:8686/api/v1/album/lookup?term=daft%20punk%20discovery",
                    headers=headers,
                )
                album = next(
                    (
                        item
                        for item in list_value(lookup)
                        if item.get("title") == "Discovery"
                        and item.get("artistId") == daft["id"]
                    ),
                    None,
                )
                if album is not None:
                    album["artistId"] = daft["id"]
                    album["monitored"] = True
                    album["addOptions"] = {"searchForNewAlbum": False}
                    json_request(
                        f"{ROOT}:8686/api/v1/album",
                        method="POST",
                        payload=album,
                        headers=headers,
                    )
                    print("[testlab-seed] Lidarr: Discovery album")
    except Exception as error:
        warn("Lidarr artist", error)

    # Readarr's public metadata host is not available in every offline lab.
    # Keep its real root folder seeded, but do not fabricate an author record
    # when the upstream lookup cannot resolve one.


def ensure_radarr_s1(env: dict[str, str], world: dict[str, Any]) -> None:
    """The Radarr side of the import slice: a movie, a client and an indexer.

    This is deliberately loud rather than best effort: the slice cannot run
    without these three, and a warning here would turn into a mysterious empty
    queue later.
    """
    headers = api_headers("v3")
    base = f"{ROOT}:7878/api/v3"
    title = world_title(world, "bigBuckBunny")
    tmdb_id = title["tmdbId"]
    movies = list_value(json_request(f"{base}/movie", headers=headers))
    if not any(movie.get("tmdbId") == tmdb_id for movie in movies):
        lookup = json_request(
            f"{base}/movie/lookup/tmdb?tmdbId={tmdb_id}", headers=headers
        )
        if not isinstance(lookup, dict) or not lookup.get("title"):
            raise RuntimeError(
                f"Radarr could not look up {title['title']}"
            )
        payload = dict(lookup)
        payload.update(
            {
                "qualityProfileId": 1,
                "rootFolderPath": "/media/movies",
                "monitored": True,
                "minimumAvailability": "released",
                "addOptions": {"searchForMovie": False},
                "tags": [],
            }
        )
        json_request(f"{base}/movie", method="POST", payload=payload, headers=headers)
        print("[testlab-seed] Radarr: Big Buck Bunny added")

    movie = next(
        (
            item
            for item in list_value(json_request(f"{base}/movie", headers=headers))
            if item.get("tmdbId") == tmdb_id
        ),
        None,
    )
    if movie is None:
        raise RuntimeError("Radarr did not keep Big Buck Bunny")
    if movie.get("hasFile"):
        print(
            "[testlab-seed] Radarr: Big Buck Bunny has a file; the manual "
            "import slice expects a movie with none"
        )

    clients = list_value(json_request(f"{base}/downloadclient", headers=headers))
    if not any(client.get("name") == "qBittorrent (testlab)" for client in clients):
        payload = {
            "enable": True,
            "protocol": "torrent",
            "priority": 1,
            "name": "qBittorrent (testlab)",
            "implementation": "QBittorrent",
            "configContract": "QBittorrentSettings",
            "fields": [
                {"name": "host", "value": "qbittorrent"},
                {"name": "port", "value": 8080},
                {"name": "useSsl", "value": False},
                {"name": "urlBase", "value": ""},
                {
                    "name": "username",
                    "value": env.get(
                        "CUPOLA_TESTLAB_QBITTORRENT_USERNAME", "admin"
                    ),
                },
                {
                    "name": "password",
                    "value": env.get("CUPOLA_TESTLAB_QBITTORRENT_PASSWORD", ""),
                },
                {"name": "movieCategory", "value": "radarr"},
                {"name": "movieImportedCategory", "value": ""},
                {"name": "recentMoviePriority", "value": 0},
                {"name": "olderMoviePriority", "value": 0},
                {"name": "initialState", "value": 0},
                {"name": "sequentialOrder", "value": False},
                {"name": "firstAndLast", "value": False},
                {"name": "contentLayout", "value": 0},
            ],
            "tags": [],
        }
        json_request(
            f"{base}/downloadclient",
            method="POST",
            payload=payload,
            headers=headers,
        )
        print("[testlab-seed] Radarr: qBittorrent client")

    indexers = list_value(json_request(f"{base}/indexer", headers=headers))
    if not any(item.get("name") == "Cupola testlab" for item in indexers):
        payload = {
            "enableRss": True,
            "enableAutomaticSearch": True,
            "enableInteractiveSearch": True,
            "name": "Cupola testlab",
            "implementation": "Torznab",
            "configContract": "TorznabSettings",
            "protocol": "torrent",
            "priority": 1,
            "fields": [
                {"name": "baseUrl", "value": "http://testlab-indexer:8088"},
                {"name": "apiPath", "value": "/api"},
                {"name": "apiKey", "value": "test-key"},
                {
                    "name": "categories",
                    "value": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060],
                },
                {"name": "additionalParameters", "value": ""},
                {"name": "minimumSeeders", "value": 1},
            ],
            "tags": [],
        }
        json_request(
            f"{base}/indexer",
            method="POST",
            payload=payload,
            headers=headers,
        )
        print("[testlab-seed] Radarr: Torznab indexer")


def seed_seeder(env: dict[str, str], state_dir: Path) -> None:
    """Make the local seeder hold the forged release, once."""
    release_file = state_dir / "forge" / "release.json"
    if not release_file.is_file():
        raise RuntimeError("the forge did not write release.json")
    release = json.loads(release_file.read_text(encoding="utf-8"))
    torrent = release.get("torrent")
    if not torrent:
        raise RuntimeError("release.json names no torrent")
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    login = urllib.parse.urlencode(
        {
            "username": env.get("CUPOLA_TESTLAB_QBITTORRENT_USERNAME", "admin"),
            "password": env.get("CUPOLA_TESTLAB_QBITTORRENT_PASSWORD", ""),
        }
    ).encode()
    request(
        f"{ROOT}:8081/api/v2/auth/login",
        method="POST",
        payload=login,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        opener=opener,
    )
    torrents = json_request(f"{ROOT}:8081/api/v2/torrents/info", opener=opener)
    if any(
        isinstance(item, dict) and item.get("name") == release.get("folder")
        for item in torrents or []
    ):
        return
    form = urllib.parse.urlencode(
        {
            "urls": f"http://testlab-indexer:8088/torrents/{torrent}",
            "savepath": "/downloads",
            "paused": "false",
        }
    ).encode()
    request(
        f"{ROOT}:8081/api/v2/torrents/add",
        method="POST",
        payload=form,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        opener=opener,
    )
    print("[testlab-seed] qBittorrent seeder: release added")


def seed_seerr(env: dict[str, str]) -> None:
    """Connect Seerr to the disposable Radarr and Sonarr applications."""

    headers = seerr_write_headers(env)
    services = (
        (
            "radarr",
            {
                "name": "Radarr",
                "hostname": "radarr",
                "port": 7878,
                "apiKey": "test-key",
                "useSsl": False,
                "baseUrl": "",
                "activeProfileId": 1,
                "activeProfileName": "Any",
                "activeDirectory": "/media/movies",
                "is4k": False,
                "minimumAvailability": "released",
                "isDefault": True,
                "externalUrl": "",
                "syncEnabled": True,
            },
        ),
        (
            "sonarr",
            {
                "name": "Sonarr",
                "hostname": "sonarr",
                "port": 8989,
                "apiKey": "test-key",
                "useSsl": False,
                "baseUrl": "",
                "activeProfileId": 1,
                "activeProfileName": "Any",
                "activeDirectory": "/media/series",
                "is4k": False,
                "minimumAvailability": "released",
                "isDefault": True,
                "externalUrl": "",
                "syncEnabled": True,
                "enableSeasonFolders": True,
            },
        ),
    )
    for service, payload in services:
        try:
            url = f"{ROOT}:5055/api/v1/settings/{service}"
            configured = list_value(json_request(url, headers=headers))
            if configured:
                continue
            request(url, method="POST", payload=payload, headers=headers)
            print(f"[testlab-seed] Seerr: {service} application")
        except Exception as error:
            warn(f"Seerr {service} application", error)


def seerr_write_headers(env: dict[str, str]) -> dict[str, str]:
    """The API key, plus what Seerr's CSRF guard asks of a write when it is on.

    The requester test turns the guard on and puts it back; a run stopped in
    between leaves it on, and a write without the token is then refused even
    with the key. A public read hands out the secret cookie and its token.
    """

    headers = {
        "X-Api-Key": env.get("CUPOLA_TESTLAB_SEERR_API_KEY", ""),
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    request(f"{ROOT}:5055/api/v1/settings/public", opener=opener)
    cookies = {cookie.name: cookie.value for cookie in jar}
    if "_csrf" in cookies and "XSRF-TOKEN" in cookies:
        headers["Cookie"] = f"_csrf={cookies['_csrf']}"
        headers["X-XSRF-TOKEN"] = cookies["XSRF-TOKEN"]
    return headers


def seed_seerr_requesters(env: dict[str, str]) -> None:
    """The two household members the requester test signs in as.

    A local Seerr account and a Jellyfin user Seerr has imported, each with
    REQUEST alone: no manage permission, no auto-approve. Their passwords are
    generated by the bootstrap and set again on every run, so a rerun leaves
    the accounts exactly as the fresh credentials file describes them.
    """

    seerr = f"{ROOT}:5055/api/v1"
    request_only = 32
    local_email = env.get("CUPOLA_TESTLAB_SEERR_REQUESTER_EMAIL", "")
    local_password = env.get("CUPOLA_TESTLAB_SEERR_REQUESTER_PASSWORD", "")
    viewer_name = env.get("CUPOLA_TESTLAB_JELLYFIN_REQUESTER_USERNAME", "")
    viewer_password = env.get("CUPOLA_TESTLAB_JELLYFIN_REQUESTER_PASSWORD", "")
    if not (local_email and local_password and viewer_name and viewer_password):
        print("[testlab-seed] warning Seerr requesters: no credentials to seed")
        return

    def seerr_users() -> list[dict[str, Any]]:
        listing = json_request(
            f"{seerr}/user?take=500",
            headers=seerr_write_headers(env),
        )
        return list_value(listing.get("results") if listing else [])

    def request_only_for(user_id: int) -> None:
        request(
            f"{seerr}/user/{user_id}/settings/permissions",
            method="POST",
            payload={"permissions": request_only},
            headers=seerr_write_headers(env),
        )

    try:
        # Both ways in on, as Seerr ships them. The route merges what it is
        # sent, and refuses the read-only key, so only the two flags go.
        main = json_request(
            f"{seerr}/settings/main",
            headers=seerr_write_headers(env),
        )
        if main.get("localLogin") is not True or main.get("mediaServerLogin") is not True:
            request(
                f"{seerr}/settings/main",
                method="POST",
                payload={"localLogin": True, "mediaServerLogin": True},
                headers=seerr_write_headers(env),
            )
            print("[testlab-seed] Seerr: local and Jellyfin sign-in on")

        local = next(
            (
                user
                for user in seerr_users()
                if (user.get("email") or "").lower() == local_email.lower()
            ),
            None,
        )
        if local is None:
            local = json_request(
                f"{seerr}/user",
                method="POST",
                payload={
                    "email": local_email,
                    "username": "requester",
                    "password": local_password,
                },
                headers=seerr_write_headers(env),
            )
            print("[testlab-seed] Seerr: local requester account")
        else:
            request(
                f"{seerr}/user/{local['id']}/settings/password",
                method="POST",
                payload={"newPassword": local_password},
                headers=seerr_write_headers(env),
            )
        request_only_for(int(local["id"]))
    except Exception as error:
        warn("Seerr local requester", error)

    try:
        jellyfin = jellyfin_headers(env)
        users = json_request(f"{ROOT}:8096/Users", headers=jellyfin) or []
        viewer = next(
            (user for user in users if user.get("Name") == viewer_name),
            None,
        )
        if viewer is None:
            viewer = json_request(
                f"{ROOT}:8096/Users/New",
                method="POST",
                payload={"Name": viewer_name, "Password": viewer_password},
                headers=jellyfin,
            )
            print("[testlab-seed] Jellyfin: requester user")
        else:
            request(
                f"{ROOT}:8096/Users/{viewer['Id']}/Password",
                method="POST",
                payload={"NewPw": viewer_password},
                headers=jellyfin,
            )
        viewer_id = viewer["Id"]

        known = next(
            (
                user
                for user in seerr_users()
                if (user.get("jellyfinUserId") or "").lower() == viewer_id.lower()
            ),
            None,
        )
        if known is None:
            imported = json_request(
                f"{seerr}/user/import-from-jellyfin",
                method="POST",
                payload={"jellyfinUserIds": [viewer_id]},
                headers=seerr_write_headers(env),
            )
            known = list_value(imported)[0]
            print("[testlab-seed] Seerr: Jellyfin requester imported")
        request_only_for(int(known["id"]))
    except Exception as error:
        warn("Seerr Jellyfin requester", error)


def jellyfin_headers(env: dict[str, str]) -> dict[str, str]:
    token = env.get("CUPOLA_TESTLAB_JELLYFIN_TOKEN", "")
    return {
        "Authorization": (
            'MediaBrowser Client="Cupola", Device="Cupola TestLab", '
            f'DeviceId="cupola-testlab", Version="1.0", Token="{token}"'
        ),
        "Accept": "application/json",
        "Content-Type": "application/json",
    }


def seed_media_servers(state_dir: Path, env: dict[str, str]) -> None:
    media_dir = state_dir / "media" / "movies" / "Cupola Test Feature (1999)"
    media_dir.mkdir(parents=True, exist_ok=True)
    media_file = media_dir / "Cupola Test Feature (1999).mp4"
    if not media_file.exists():
        ffmpeg = shutil.which("ffmpeg")
        if ffmpeg:
            try:
                subprocess.run(
                    [
                        ffmpeg,
                        "-hide_banner",
                        "-loglevel",
                        "error",
                        "-y",
                        "-f",
                        "lavfi",
                        "-i",
                        "color=c=0x283044:s=640x360:r=24",
                        "-f",
                        "lavfi",
                        "-i",
                        "anullsrc=r=48000:cl=stereo",
                        "-t",
                        "2",
                        "-c:v",
                        "libx264",
                        "-preset",
                        "ultrafast",
                        "-c:a",
                        "aac",
                        "-shortest",
                        str(media_file),
                    ],
                    check=True,
                )
                print("[testlab-seed] media: generated 2s movie specimen")
            except Exception as error:
                warn("media fixture", error)
        else:
            print("[testlab-seed] warning media fixture: ffmpeg not installed")

    try:
        headers = jellyfin_headers(env)
        folders = json_request(
            f"{ROOT}:8096/Library/VirtualFolders",
            headers=headers,
        )
        if not any(
            isinstance(folder, dict)
            and (folder.get("name") or folder.get("Name")) == "Films"
            for folder in (folders or [])
        ):
            query = urllib.parse.urlencode(
                {
                    "name": "Films",
                    "collectionType": "movies",
                    "paths": "/media/movies",
                    "refreshLibrary": "true",
                }
            )
            request(
                f"{ROOT}:8096/Library/VirtualFolders?{query}",
                method="POST",
                payload=b"{}",
                headers=headers,
            )
            print("[testlab-seed] Jellyfin: Films library")
        request(
            f"{ROOT}:8096/Library/Refresh",
            method="POST",
            headers=headers,
        )
    except Exception as error:
        warn("Jellyfin library", error)

    try:
        headers = {
            "X-Plex-Token": env.get("CUPOLA_TESTLAB_PLEX_TOKEN", "test-token"),
            "X-Plex-Client-Identifier": "cupola-testlab-seed",
        }
        _, body = request(
            f"{ROOT}:32400/library/sections",
            headers=headers,
            timeout=30,
        )
        sections = ET.fromstring(body)
        if not any(section.attrib.get("title") == "Films" for section in sections):
            query = urllib.parse.urlencode(
                {
                    "name": "Films",
                    "type": "1",
                    "agent": "tv.plex.agents.movie",
                    "scanner": "Plex Movie",
                    "language": "en-US",
                    "location": "/media/movies",
                }
            )
            request(
                f"{ROOT}:32400/library/sections?{query}",
                method="POST",
                headers=headers,
                timeout=30,
            )
            # Plex accepts the write before its library manager exposes the
            # section to the read endpoint. Poll the same endpoint so the
            # fixture never reports a successful seed while the transport
            # harness still sees an empty library.
            for _ in range(20):
                time.sleep(0.5)
                _, body = request(
                    f"{ROOT}:32400/library/sections",
                    headers=headers,
                    timeout=15,
                )
                sections = ET.fromstring(body)
                if any(
                    section.attrib.get("title") == "Films" for section in sections
                ):
                    break
            print("[testlab-seed] Plex: Films library")
    except Exception as error:
        warn("Plex library", error)


def seed_qbittorrent(env: dict[str, str]) -> None:
    try:
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        login = urllib.parse.urlencode(
            {
                "username": env.get("CUPOLA_TESTLAB_QBITTORRENT_USERNAME", "admin"),
                "password": env.get("CUPOLA_TESTLAB_QBITTORRENT_PASSWORD", ""),
            }
        ).encode()
        request(
            f"{ROOT}:8080/api/v2/auth/login",
            method="POST",
            payload=login,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            opener=opener,
        )
        torrents = json_request(
            f"{ROOT}:8080/api/v2/torrents/info",
            opener=opener,
        )
        if not any(
            isinstance(item, dict) and item.get("name") == "Cupola Test Torrent"
            for item in torrents or []
        ):
            form = urllib.parse.urlencode(
                {"urls": QBIT_MAGNET, "paused": "true"}
            ).encode()
            request(
                f"{ROOT}:8080/api/v2/torrents/add",
                method="POST",
                payload=form,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                opener=opener,
            )
            print("[testlab-seed] qBittorrent: paused torrent")
    except Exception as error:
        warn("qBittorrent torrent", error)


def transmission_call(
    env: dict[str, str],
    session: str | None,
    method: str,
    arguments: dict[str, Any] | None = None,
) -> tuple[str | None, dict[str, Any]]:
    user = env.get("CUPOLA_TESTLAB_TRANSMISSION_USERNAME", "transmission")
    password = env.get("CUPOLA_TESTLAB_TRANSMISSION_PASSWORD", "transmission")
    encoded = base64.b64encode(f"{user}:{password}".encode()).decode()
    headers = {
        "Authorization": f"Basic {encoded}",
        "Content-Type": "application/json",
    }
    if session:
        headers["X-Transmission-Session-Id"] = session
    payload = {"method": method, "arguments": arguments or {}}
    try:
        _, body = request(
            f"{ROOT}:9091/transmission/rpc",
            method="POST",
            payload=payload,
            headers=headers,
        )
        return session, json.loads(body)
    except urllib.error.HTTPError as error:
        if error.code != 409:
            raise
        refreshed = error.headers.get("X-Transmission-Session-Id")
        if not refreshed or refreshed == session:
            raise
        return transmission_call(env, refreshed, method, arguments)


def seed_transmission(env: dict[str, str]) -> None:
    try:
        session, result = transmission_call(env, None, "torrent-get", {"fields": ["name"]})
        torrents = result.get("arguments", {}).get("torrents", [])
        if not any(
            isinstance(item, dict)
            and item.get("name") == "Cupola Test Transmission"
            for item in torrents
        ):
            session, _ = transmission_call(
                env,
                session,
                "torrent-add",
                {"filename": TRANSMISSION_MAGNET, "paused": True},
            )
            print("[testlab-seed] Transmission: paused torrent")
    except Exception as error:
        warn("Transmission torrent", error)


def multipart_body(field: str, filename: str, content: bytes) -> tuple[str, bytes]:
    boundary = "----CupolaTestLabSeed"
    body = b"".join(
        [
            f"--{boundary}\r\n".encode(),
            (
                f'Content-Disposition: form-data; name="{field}"; '
                f'filename="{filename}"\r\n'
            ).encode(),
            b"Content-Type: application/x-nzb\r\n\r\n",
            content,
            f"\r\n--{boundary}--\r\n".encode(),
        ]
    )
    return f"multipart/form-data; boundary={boundary}", body


def seed_sabnzbd(state_dir: Path) -> None:
    try:
        query = urllib.parse.urlencode(
            {
                "mode": "queue",
                "output": "json",
                "apikey": "test-key",
                "start": 0,
                "limit": 50,
            }
        )
        queue = json_request(f"{ROOT}:8082/api?{query}") or {}
        slots = (queue.get("queue") or {}).get("slots", [])
        ids = [
            slot.get("nzo_id")
            for slot in slots
            if isinstance(slot, dict)
            and str(slot.get("filename", "")).startswith("cupola-test")
            and slot.get("nzo_id")
        ]
        if not ids:
            file_path = state_dir / "cupola-test.nzb"
            content_type, body = multipart_body(
                "nzbfile", file_path.name, file_path.read_bytes()
            )
            query = urllib.parse.urlencode(
                {"mode": "addfile", "output": "json", "apikey": "test-key"}
            )
            result = json_request(
                f"{ROOT}:8082/api?{query}",
                method="POST",
                payload=body,
                headers={"Content-Type": content_type},
            ) or {}
            ids = result.get("nzo_ids", [])
            print("[testlab-seed] SABnzbd: NZB specimen")
        for nzo_id in ids:
            query = urllib.parse.urlencode(
                {
                    "mode": "queue",
                    "name": "pause",
                    "value": nzo_id,
                    "output": "json",
                    "apikey": "test-key",
                }
            )
            json_request(f"{ROOT}:8082/api?{query}")
    except Exception as error:
        warn("SABnzbd NZB", error)


def seed_nzbget(state_dir: Path, env: dict[str, str]) -> None:
    try:
        user = env.get("CUPOLA_TESTLAB_NZBGET_USERNAME", "nzbget")
        password = env.get("CUPOLA_TESTLAB_NZBGET_PASSWORD", "")
        auth = base64.b64encode(f"{user}:{password}".encode()).decode()
        headers = {
            "Authorization": f"Basic {auth}",
            "Content-Type": "application/json",
        }

        def call(method: str, params: list[Any]) -> Any:
            result = json_request(
                f"{ROOT}:6789/jsonrpc",
                method="POST",
                payload={
                    "jsonrpc": "2.0",
                    "method": method,
                    "params": params,
                    "id": 1,
                },
                headers=headers,
            )
            if isinstance(result, dict) and result.get("error"):
                raise RuntimeError(str(result["error"]))
            return result.get("result") if isinstance(result, dict) else None

        groups = call("listgroups", [0]) or []
        history = call("history", [False]) or []
        has_fixture = any(
            isinstance(item, dict) and item.get("Name") == "cupola-test"
            for item in [*groups, *history]
        )
        if not has_fixture:
            content = (state_dir / "cupola-test.nzb").read_text(encoding="utf-8")
            result = call(
                "append",
                ["cupola-test.nzb", content, "", 0, False, True, "cupola-test", 0, "FORCE"],
            )
            print(f"[testlab-seed] NZBGet: NZB specimen ({result})")
    except Exception as error:
        warn("NZBGet NZB", error)


def seed_npm(env: dict[str, str]) -> None:
    # Keep the token handling separate from the generic helper: it is never
    # printed, persisted, or included in a warning.
    try:
        base = f"{ROOT}:8181/api"
        auth = json_request(
            f"{base}/tokens",
            method="POST",
            payload={
                "identity": env.get("CUPOLA_TESTLAB_NPM_USERNAME", ""),
                "secret": env.get("CUPOLA_TESTLAB_NPM_PASSWORD", ""),
            },
        )
        token = auth.get("token") if isinstance(auth, dict) else None
        if not token:
            raise RuntimeError("NPM did not return a token")
        headers = {"Authorization": f"Bearer {token}"}
        hosts = json_request(f"{base}/nginx/proxy-hosts", headers=headers)
        if any(
            isinstance(host, dict)
            and "cupola.test" in (host.get("domain_names") or [])
            for host in hosts or []
        ):
            return
        request(
            f"{base}/nginx/proxy-hosts",
            method="POST",
            headers={**headers, "Content-Type": "application/json"},
            payload={
                "domain_names": ["cupola.test"],
                "forward_scheme": "http",
                "forward_host": "127.0.0.1",
                "forward_port": 5001,
                "access_list_id": 0,
                "certificate_id": 0,
                "ssl_forced": False,
                "caching_enabled": False,
                "block_exploits": True,
                "allow_websocket_upgrade": True,
                "http2_support": False,
                "hsts_enabled": False,
                "hsts_subdomains": False,
                "meta": {},
            },
        )
        print("[testlab-seed] NPM: proxy host")
    except Exception as error:
        warn("NPM proxy host", error)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-dir", required=True, type=Path)
    args = parser.parse_args()
    env = read_env(args.state_dir / "credentials.env")
    (args.state_dir / "media").mkdir(parents=True, exist_ok=True)
    for media_section in ("movies", "series", "music", "books"):
        (args.state_dir / "media" / media_section).mkdir(
            parents=True, exist_ok=True
        )
    world = load_world(args.state_dir)
    seed_arrs(world)
    ensure_radarr_s1(env, world)
    seed_seeder(env, args.state_dir)
    seed_seerr(env)
    seed_seerr_requesters(env)
    seed_media_servers(args.state_dir, env)
    seed_qbittorrent(env)
    seed_transmission(env)
    seed_sabnzbd(args.state_dir)
    seed_nzbget(args.state_dir, env)
    seed_npm(env)
    print("[testlab-seed] done")


if __name__ == "__main__":
    main()
