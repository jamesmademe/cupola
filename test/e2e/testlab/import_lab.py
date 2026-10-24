"""The manual import's fixtures: forged files, seeded releases, the arrs' state.

The manual import journeys (catalogue M-01..M-15) need two kinds of
arrangement, and this module holds both:

- **Files in the client's downloads**, for the wizard: Radarr, Sonarr and
  Lidarr read the same ``/downloads`` the app's qBittorrent writes, so a forged
  file in ``downloads/manual-import/<case>/`` is what a finished download looks
  like to the wizard, without a grab. Nothing in the arr's queue or history.
- **A real release through the arr's queue**, for the blocked imports: the forge
  writes a folder and its own private torrent, ``qbittorrent-seed`` seeds it, the
  arr receives it through ``release/push`` with the indexer's torrent URL, and
  its own download handling decides. Each release has its own infohash, so each
  grab is a queue record of its own (the L13 phase 0 recipes).

Every file is a test pattern at 1 fps, long enough for the arr not to call it a
sample, unless the case wants a sample. The forge runs in its own container;
nothing here writes a vendor database, and the keys are the arrs' fixed lab key
or the ones in ``credentials.env``, never printed.
"""

from __future__ import annotations

import json
import shutil
import sys
import time
import urllib.request
import uuid
from dataclasses import dataclass
from typing import Any

import queue_probe as probe
import testlab
from scenarios.base import ScenarioError, request, require_ok

#: The arrs the wizard serves, straight to the service (never the fault layer).
ARRS = {
    "radarr": "http://127.0.0.1:7878/api/v3",
    "sonarr": "http://127.0.0.1:8989/api/v3",
    "lidarr": "http://127.0.0.1:8686/api/v1",
}
HEADERS = {"X-Api-Key": "test-key", "Accept": "application/json"}

#: Where the wizard's fixtures live, inside the downloads the arrs read.
WIZARD_ROOT = "manual-import"
INDEXER = "http://testlab-indexer:8088/torrents"


@dataclass(frozen=True)
class Media:
    """One forged file: its name, frame size and duration in seconds."""

    name: str
    size: str = "1920x1080"
    seconds: int = 600


def arr(service: str, path: str, method: str = "GET", payload: Any = None) -> Any:
    status, body = request(
        f"{ARRS[service]}{path}", method=method, payload=payload, headers=HEADERS
    )
    require_ok(status, body, f"{service} {method} {path}")
    return body


# --- forging ---------------------------------------------------------------


def forge(folders: dict[str, list[Media]], *, under: str) -> None:
    """Forge every folder in one forge run.

    ``under`` is ``downloads`` (the wizard's files, at
    ``/downloads/manual-import/<folder>``) or ``seed-data`` (a release the seeder
    shares, at ``/seed-data/<folder>``, with its torrent in
    ``/forge/torrents/<folder>.torrent``).
    """
    if under not in ("downloads", "seed-data"):
        raise ScenarioError(f"nowhere to forge {under!r}")
    plan = {
        folder: [(media.name, media.size, media.seconds) for media in files]
        for folder, files in folders.items()
    }
    base = "/downloads/" + WIZARD_ROOT if under == "downloads" else "/seed-data"
    torrents = under == "seed-data"
    code = f"""
import sys
sys.path.insert(0, '/app')
import forge
from pathlib import Path
for folder, files in {plan!r}.items():
    target = Path({base!r}) / folder
    for name, size, seconds in files:
        forge.make_media(target / name, size, '300k', duration=seconds)
    if {torrents!r}:
        torrent = Path('/forge/torrents') / (folder + '.torrent')
        if not torrent.exists():
            forge.run(['mktorrent', '-a', 'http://testlab-indexer:8088/announce',
                       '-o', str(torrent), '-l', '16', '-p', str(target)])
"""
    testlab.run(
        testlab.compose_command(
            "run",
            "--rm",
            "--entrypoint",
            "python3",
            "testlab-forge",
            "-c",
            code,
            profiles=(*testlab.PROFILES, "forge"),
        ),
        capture=True,
        timeout=900,
    )


def wizard_path(folder: str) -> str:
    """The folder as the arrs see it."""
    return f"/downloads/{WIZARD_ROOT}/{folder}"


def remove_wizard(folder: str) -> None:
    shutil.rmtree(
        testlab.STATE_ROOT / "downloads" / WIZARD_ROOT / folder, ignore_errors=True
    )


def remove_wizard_file(folder: str, name: str) -> None:
    (testlab.STATE_ROOT / "downloads" / WIZARD_ROOT / folder / name).unlink(
        missing_ok=True
    )


def wizard_files(folder: str) -> list[str]:
    directory = testlab.STATE_ROOT / "downloads" / WIZARD_ROOT / folder
    if not directory.is_dir():
        return []
    return sorted(path.name for path in directory.iterdir() if path.is_file())


# --- releases through the queue ----------------------------------------------


def infohash_of(folder: str) -> str:
    """The infohash of the forged release, or "" before the forge wrote it."""
    torrent = testlab.STATE_ROOT / "forge" / "torrents" / f"{folder}.torrent"
    if not torrent.is_file():
        return ""
    sys.path.insert(0, str(testlab.TESTLAB_DIR / "forge"))
    import forge as forge_module  # noqa: E402 - the forge's own reader

    return forge_module.infohash(torrent)


def seed_release(folder: str) -> str:
    """Seed the forged release and return its infohash."""
    torrent = testlab.STATE_ROOT / "forge" / "torrents" / f"{folder}.torrent"
    if not torrent.is_file():
        raise ScenarioError(f"the forge wrote no torrent for {folder}")
    opener = probe.opener_for(probe.SEEDER)
    if probe.named(opener, folder, base=probe.SEEDER) is None:
        boundary = uuid.uuid4().hex
        fields = b"".join(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"'
            f"\r\n\r\n{value}\r\n".encode()
            for name, value in (("savepath", "/downloads"), ("category", "l13"))
        )
        body = (
            fields
            + f'--{boundary}\r\nContent-Disposition: form-data; name="torrents"; '
            f'filename="{torrent.name}"\r\nContent-Type: application/x-bittorrent'
            "\r\n\r\n".encode()
            + torrent.read_bytes()
            + f"\r\n--{boundary}--\r\n".encode()
        )
        add = urllib.request.Request(
            f"{probe.SEEDER}/api/v2/torrents/add",
            data=body,
            method="POST",
            headers={
                "Content-Type": f"multipart/form-data; boundary={boundary}",
                "Referer": probe.SEEDER,
            },
        )
        with opener.open(add, timeout=30) as response:
            if response.status != 200:
                raise ScenarioError(f"the seeder refused {folder}")
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        item = probe.named(opener, folder, base=probe.SEEDER)
        if item and item.get("state") in (
            "uploading",
            "stalledUP",
            "queuedUP",
            "forcedUP",
        ):
            return str(item["hash"]).lower()
        time.sleep(2)
    raise ScenarioError(f"the seeder never shared {folder}")


def push_release(service: str, folder: str, *, size: int) -> None:
    """Hand the release to the arr as an indexer would, and require the grab.

    ``size`` is what the release claims: the arrs judge a release's size
    against the quality definition, and the forged files are tiny on purpose.
    """
    decisions = arr(
        service,
        "/release/push",
        "POST",
        {
            "title": folder,
            "downloadUrl": f"{INDEXER}/{folder}.torrent",
            "protocol": "torrent",
            "publishDate": "2025-01-01T00:00:00Z",
            "size": size,
            "indexer": "Cupola testlab",
        },
    )
    rejected = [
        reason
        for decision in decisions or []
        for reason in decision.get("rejections") or []
    ]
    if rejected:
        raise ScenarioError(f"{service} would not grab {folder}: {rejected}")


def queue_of(service: str, download_id: str) -> list[dict[str, Any]]:
    unknown = "includeUnknownMovieItems" if service == "radarr" else (
        "includeUnknownSeriesItems"
    )
    body = arr(service, f"/queue?page=1&pageSize=100&{unknown}=true")
    return [
        record
        for record in body.get("records", [])
        if str(record.get("downloadId", "")).lower() == download_id.lower()
    ]


def wait_settled(service: str, download_id: str, *, timeout: float = 300) -> dict:
    """The queue record once the arr has decided and stopped changing its mind.

    Settled is ``importBlocked``, or ``importPending`` with a warning: the two
    states the app reads as "needs a manual import". Four equal readings five
    seconds apart, because a download passes through a bare ``importPending``
    for a few seconds before the decision.
    """
    deadline = time.monotonic() + timeout
    last: Any = None
    equal = 0
    while time.monotonic() < deadline:
        records = queue_of(service, download_id)
        reading = [
            (r.get("trackedDownloadState"), r.get("trackedDownloadStatus"))
            for r in records
        ]
        settled = bool(records) and (
            records[0].get("trackedDownloadState") == "importBlocked"
            or (
                records[0].get("trackedDownloadState") == "importPending"
                and records[0].get("trackedDownloadStatus") == "warning"
            )
        )
        equal = equal + 1 if settled and reading == last else (1 if settled else 0)
        last = reading
        if equal >= 4:
            return records[0]
        time.sleep(5)
    raise ScenarioError(f"{service} never settled {download_id}: {last}")


def messages_of(record: dict[str, Any]) -> list[str]:
    words: list[str] = []
    for message in record.get("statusMessages") or []:
        if message.get("title"):
            words.append(str(message["title"]))
        words.extend(str(text) for text in message.get("messages") or [])
    return words


def remove_from_queue(service: str, download_id: str) -> None:
    """Remove the download from the arr and from the client, with its bytes."""
    seen: set[int] = set()
    for record in queue_of(service, download_id):
        record_id = int(record["id"])
        if record_id in seen:
            continue
        seen.add(record_id)
        status, body = request(
            f"{ARRS[service]}/queue/{record_id}?removeFromClient=true&blocklist=false",
            method="DELETE",
            headers=HEADERS,
        )
        if status not in (200, 404):
            raise ScenarioError(f"{service} kept queue record {record_id}: {body}")


def unseed(folder: str) -> None:
    opener = probe.opener_for(probe.SEEDER)
    item = probe.named(opener, folder, base=probe.SEEDER)
    if item is not None:
        probe.api(
            opener,
            "/api/v2/torrents/delete",
            base=probe.SEEDER,
            method="POST",
            form={"hashes": item["hash"], "deleteFiles": "true"},
            what=f"removing {folder} from the seeder",
        )
    (testlab.STATE_ROOT / "forge" / "torrents" / f"{folder}.torrent").unlink(
        missing_ok=True
    )
    # qBittorrent deletes the data after it answers; once the torrent is gone
    # the folder is nobody's, and the bind mount is the lab's own.
    data = testlab.STATE_ROOT / "seed-data" / folder
    deadline = time.monotonic() + 20
    while data.exists() and time.monotonic() < deadline:
        time.sleep(1)
    shutil.rmtree(data, ignore_errors=True)


# --- the library -------------------------------------------------------------


def movie_by_title(title: str, year: int) -> dict[str, Any]:
    for movie in arr("radarr", "/movie"):
        if movie.get("title") == title and movie.get("year") == year:
            return movie
    raise ScenarioError(f"{title} ({year}) is not in Radarr's library")


def movie(movie_id: int) -> dict[str, Any]:
    return arr("radarr", f"/movie/{movie_id}")


def delete_movie_file(movie_id: int) -> None:
    """Take a movie's file out of the library and off the disk."""
    current = movie(movie_id).get("movieFile")
    if current:
        status, body = request(
            f"{ARRS['radarr']}/moviefile/{current['id']}",
            method="DELETE",
            headers=HEADERS,
        )
        if status not in (200, 404):
            raise ScenarioError(f"Radarr kept movie file {current['id']}: {body}")


def scan(service: str, folder: str) -> list[dict[str, Any]]:
    """What the arr's manual import scan says about a wizard folder."""
    path = urllib.request.quote(wizard_path(folder))
    body = arr(service, f"/manualimport?folder={path}&filterExistingFiles=false")
    return [item for item in body or [] if isinstance(item, dict)]


def describe(items: list[dict[str, Any]]) -> str:
    return json.dumps(
        [
            {
                "file": item.get("relativePath"),
                "movie": (item.get("movie") or {}).get("title"),
                "rejections": [r.get("reason") for r in item.get("rejections") or []],
            }
            for item in items
        ]
    )
