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
    with client.open(request_object, timeout=8) as response:
        return response.status, response.read()


def json_request(
    url: str,
    *,
    method: str = "GET",
    payload: Any | None = None,
    headers: dict[str, str] | None = None,
    opener: urllib.request.OpenerDirector | None = None,
) -> Any:
    _, body = request(
        url,
        method=method,
        payload=payload,
        headers=headers,
        opener=opener,
    )
    return json.loads(body) if body else None


def warn(label: str, error: Exception) -> None:
    print(f"[maclab-seed] warning {label}: {type(error).__name__}: {error}")


def api_headers(version: str) -> dict[str, str]:
    return {"X-Api-Key": "test-key", "Accept": "application/json"}


def list_value(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, list):
        return [entry for entry in value if isinstance(entry, dict)]
    if isinstance(value, dict) and isinstance(value.get("records"), list):
        return [entry for entry in value["records"] if isinstance(entry, dict)]
    return []


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
        print(f"[maclab-seed] {name}: root folder {path}")
    except Exception as error:
        warn(f"{name} root folder", error)


def seed_arrs() -> None:
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
            print("[maclab-seed] Radarr: movie specimen")
    except Exception as error:
        warn("Radarr movie", error)

    try:
        url = f"{ROOT}:8989/api/v3/series"
        headers = api_headers("v3")
        series = list_value(json_request(url, headers=headers))
        if not any(item.get("title") == "Breaking Bad" for item in series):
            request(
                url,
                method="POST",
                headers=headers,
                payload={
                    "title": "Cupola Test Series",
                    "tvdbId": 81189,
                    "year": 2008,
                    "qualityProfileId": 1,
                    "rootFolderPath": "/media/series",
                    "monitored": True,
                    "seasonFolder": True,
                    "addOptions": {"searchForMissingEpisodes": False},
                    "images": [],
                    "seasons": [],
                },
            )
            print("[maclab-seed] Sonarr: series specimen")
    except Exception as error:
        warn("Sonarr series", error)

    try:
        url = f"{ROOT}:8686/api/v1/artist"
        headers = api_headers("v1")
        artists = list_value(json_request(url, headers=headers))
        if not any(item.get("artistName") == "Daft Punk" for item in artists):
            request(
                url,
                method="POST",
                headers=headers,
                payload={
                    "artistName": "Daft Punk",
                    "foreignArtistId": "056e4f3e-d505-4dad-8ec1-d04f521cbb56",
                    "qualityProfileId": 1,
                    "metadataProfileId": 1,
                    "rootFolderPath": "/media/music",
                    "monitored": True,
                    "addOptions": {"searchForMissingAlbums": False},
                    "images": [],
                },
            )
            print("[maclab-seed] Lidarr: artist specimen")
    except Exception as error:
        warn("Lidarr artist", error)

    # Readarr's public metadata host is not available in every offline lab.
    # Keep its real root folder seeded, but do not fabricate an author record
    # when the upstream lookup cannot resolve one.


def seed_seerr(env: dict[str, str]) -> None:
    """Connect Seerr to the disposable Radarr and Sonarr applications."""

    headers = {
        "X-Api-Key": env.get("CUPOLA_MACLAB_SEERR_API_KEY", ""),
        "Content-Type": "application/json",
    }
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
            print(f"[maclab-seed] Seerr: {service} application")
        except Exception as error:
            warn(f"Seerr {service} application", error)


def jellyfin_headers(env: dict[str, str]) -> dict[str, str]:
    token = env.get("CUPOLA_MACLAB_JELLYFIN_TOKEN", "")
    return {
        "Authorization": (
            'MediaBrowser Client="Cupola", Device="Cupola MacLab", '
            f'DeviceId="cupola-maclab", Version="1.0", Token="{token}"'
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
                print("[maclab-seed] media: generated 2s movie specimen")
            except Exception as error:
                warn("media fixture", error)
        else:
            print("[maclab-seed] warning media fixture: ffmpeg not installed")

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
            print("[maclab-seed] Jellyfin: Films library")
        request(
            f"{ROOT}:8096/Library/Refresh",
            method="POST",
            headers=headers,
        )
    except Exception as error:
        warn("Jellyfin library", error)

    try:
        headers = {
            "X-Plex-Token": env.get("CUPOLA_MACLAB_PLEX_TOKEN", "test-token"),
            "X-Plex-Client-Identifier": "cupola-maclab-seed",
        }
        _, body = request(
            f"{ROOT}:32400/library/sections",
            headers=headers,
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
            )
            print("[maclab-seed] Plex: Films library")
    except Exception as error:
        warn("Plex library", error)


def seed_qbittorrent(env: dict[str, str]) -> None:
    try:
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        login = urllib.parse.urlencode(
            {
                "username": env.get("CUPOLA_MACLAB_QBITTORRENT_USERNAME", "admin"),
                "password": env.get("CUPOLA_MACLAB_QBITTORRENT_PASSWORD", ""),
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
            print("[maclab-seed] qBittorrent: paused torrent")
    except Exception as error:
        warn("qBittorrent torrent", error)


def transmission_call(
    env: dict[str, str],
    session: str | None,
    method: str,
    arguments: dict[str, Any] | None = None,
) -> tuple[str | None, dict[str, Any]]:
    user = env.get("CUPOLA_MACLAB_TRANSMISSION_USERNAME", "transmission")
    password = env.get("CUPOLA_MACLAB_TRANSMISSION_PASSWORD", "transmission")
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
            print("[maclab-seed] Transmission: paused torrent")
    except Exception as error:
        warn("Transmission torrent", error)


def multipart_body(field: str, filename: str, content: bytes) -> tuple[str, bytes]:
    boundary = "----CupolaMacLabSeed"
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
            print("[maclab-seed] SABnzbd: NZB specimen")
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
        user = env.get("CUPOLA_MACLAB_NZBGET_USERNAME", "nzbget")
        password = env.get("CUPOLA_MACLAB_NZBGET_PASSWORD", "")
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
            print(f"[maclab-seed] NZBGet: NZB specimen ({result})")
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
                "identity": env.get("CUPOLA_MACLAB_NPM_USERNAME", ""),
                "secret": env.get("CUPOLA_MACLAB_NPM_PASSWORD", ""),
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
        print("[maclab-seed] NPM: proxy host")
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
    seed_arrs()
    seed_seerr(env)
    seed_media_servers(args.state_dir, env)
    seed_qbittorrent(env)
    seed_transmission(env)
    seed_sabnzbd(args.state_dir)
    seed_nzbget(args.state_dir, env)
    seed_npm(env)
    print("[maclab-seed] done")


if __name__ == "__main__":
    main()
