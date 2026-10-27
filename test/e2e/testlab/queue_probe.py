"""qBittorrent plumbing shared by the queue-state scenarios.

The lab's torrent chain is real: ``qbittorrent-seed`` seeds a forged private
release out of ``seed-data``, and the app's ``qbittorrent`` fetches it from the
local tracker. The four queue states of the flow catalogue (D-16, and the two
journeys that read them, G-28 and G-29) are therefore reached by moving real
bytes and asking the clients for their own raw state, never by writing a
fixture:

- ``stalledDL`` at a fixed percentage: the seeder's file is truncated to 47%
  (rounded down to a whole piece) and rechecked, so it can serve exactly those
  pieces; the client's copy stops there for good.
- ``stoppedDL``: a download stopped by a person, with the bytes that arrived
  still on disk.
- ``missingFiles``: the client's data is gone and qBittorrent has looked for it.
  qBittorrent only looks at start-up, so this one restarts the app's
  qBittorrent container (never the arrs, never the indexers).
- ``queuedDL``: ``max_active_downloads=1`` with two downloads in the client, so
  the one behind the magnet waits its turn.

Nothing here prints a credential. The two WebUI passwords come from
``credentials.env`` and stay inside the opener.
"""

from __future__ import annotations

import http.client
import http.cookiejar
import json
import os
import shutil
import subprocess
import time
import urllib.parse
import urllib.request
from typing import Any, Callable

from scenarios.base import (
    REPO_ROOT,
    STATE_ROOT,
    ScenarioError,
    credentials,
    request,
    require_ok,
)

# The client is read on its direct port (18080). qBittorrent checks the
# Host it is sent against its own WebUI port (8080), so the reading sends
# that Host and the origin it expects. See docker-compose.testlab.yml.
CLIENT = "http://127.0.0.1:18080"
CLIENT_ORIGIN = "http://127.0.0.1:8080"
CLIENT_HOST = {"Host": "127.0.0.1:8080"}


def _host_for(base: str) -> dict[str, str]:
    """The Host the WebUI expects, for the client and no other service."""
    return dict(CLIENT_HOST) if base == CLIENT else {}
SEEDER = "http://127.0.0.1:8081"
INDEXER_TORRENT = "http://testlab-indexer:8088/torrents/the-great-bunny.torrent"
TORRENT_NAME = "The.Great.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA"
QUEUED_MAGNET_NAME = "Cupola Test Torrent"
QUEUED_MAGNET = (
    "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
    "&dn=Cupola%20Test%20Torrent"
)

# The forged release: 5 582 223 bytes in 86 pieces of 64 KiB. 47% of the file
# is 40 whole pieces, which the seeder can hold and serve exactly.
SEED_FILE = STATE_ROOT / "seed-data" / TORRENT_NAME / f"{TORRENT_NAME}.mkv"
CLIENT_DATA = STATE_ROOT / "downloads" / TORRENT_NAME
SCENARIO_STATE = STATE_ROOT / "scenario-state"
SEED_BACKUP = SCENARIO_STATE / "the-great-bunny.mkv"
CLIENT_DATA_AWAY = SCENARIO_STATE / "the-great-bunny-client-data"
PREFERENCES_FILE = SCENARIO_STATE / "qbittorrent-preferences.json"
PIECE_LENGTH = 65536
FULL_SIZE = 5582223
STUCK_BYTES = int(FULL_SIZE * 0.47) // PIECE_LENGTH * PIECE_LENGTH
STUCK_PROGRESS = STUCK_BYTES / FULL_SIZE

# qBittorrent's wire values, as the app reads them: `stoppedDL` and `pausedDL`
# are a pause, `queuedDL` waits behind the active limit, `missingFiles` and
# `error` are the two failures (lib/features/services/domain/
# download_client_faults.dart decides the words).
DOWNLOADING_STATES = (
    "downloading",
    "stalledDL",
    "metaDL",
    "forcedDL",
    "allocating",
    "checkingDL",
    "checkingResumeData",
)
HELD_STATES = ("stoppedDL", "pausedDL")
NUDGE_AFTER = 10

PREFERENCE_KEYS = ("max_active_downloads", "queueing_enabled")

COMPOSE_PROJECT = "cupola-testlab"
COMPOSE_FILE = REPO_ROOT / "docker-compose.testlab.yml"


def opener_for(base: str) -> urllib.request.OpenerDirector:
    """A logged-in WebUI session for one of the two qBittorrent instances."""
    environment = credentials()
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar)
    )
    form = urllib.parse.urlencode(
        {
            "username": environment.get(
                "CUPOLA_TESTLAB_QBITTORRENT_USERNAME", "admin"
            ),
            "password": environment.get(
                "CUPOLA_TESTLAB_QBITTORRENT_PASSWORD", ""
            ),
        }
    ).encode()
    status, body = request(
        f"{base}/api/v2/auth/login",
        method="POST",
        payload=form,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Referer": CLIENT_ORIGIN if base == CLIENT else base,
            **_host_for(base),
        },
        opener=opener,
    )
    require_ok(status, body, "qBittorrent login")
    return opener


def api(
    opener: urllib.request.OpenerDirector,
    path: str,
    *,
    base: str = CLIENT,
    method: str = "GET",
    form: dict[str, Any] | None = None,
    what: str | None = None,
) -> Any:
    payload = None
    headers = _host_for(base)
    if form is not None:
        payload = urllib.parse.urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    status, body = request(
        f"{base}{path}",
        method=method,
        payload=payload,
        headers=headers,
        opener=opener,
    )
    require_ok(status, body, what or f"qBittorrent {method} {path}")
    return body


def torrents(
    opener: urllib.request.OpenerDirector, *, base: str = CLIENT
) -> list[dict[str, Any]]:
    body = api(opener, "/api/v2/torrents/info", base=base, what="qBittorrent torrents")
    return [item for item in body or [] if isinstance(item, dict)]


def named(
    opener: urllib.request.OpenerDirector,
    name: str,
    *,
    base: str = CLIENT,
) -> dict[str, Any] | None:
    return next(
        (item for item in torrents(opener, base=base) if item.get("name") == name),
        None,
    )


def require_named(
    opener: urllib.request.OpenerDirector,
    name: str,
    *,
    base: str = CLIENT,
) -> dict[str, Any]:
    torrent = named(opener, name, base=base)
    if torrent is None:
        raise ScenarioError(f"{name} is not in qBittorrent at {base}")
    return torrent


def add(
    opener: urllib.request.OpenerDirector,
    *,
    url: str = INDEXER_TORRENT,
    what: str = "the release",
    stopped: bool = False,
    savepath: str = "/downloads",
    category: str = "radarr",
) -> None:
    form: dict[str, Any] = {
        "urls": url,
        "savepath": savepath,
        "category": category,
    }
    if stopped:
        # qBittorrent 5 renamed the add parameter: `paused` is the legacy
        # spelling, `stopped` is the one this client reads.
        form["stopped"] = "true"
    api(
        opener,
        "/api/v2/torrents/add",
        method="POST",
        form=form,
        what=f"adding {what}",
    )


def remove(
    opener: urllib.request.OpenerDirector,
    name: str = TORRENT_NAME,
    *,
    delete_files: bool = True,
) -> bool:
    """Remove one torrent, files and all. True when it was there."""
    torrent = named(opener, name)
    if torrent is None:
        return False
    api(
        opener,
        "/api/v2/torrents/delete",
        method="POST",
        form={"hashes": torrent["hash"], "deleteFiles": str(delete_files).lower()},
        what=f"removing {name}",
    )
    return True


def stop(
    opener: urllib.request.OpenerDirector,
    torrent_hash: str,
    *,
    base: str = CLIENT,
) -> None:
    api(
        opener,
        "/api/v2/torrents/stop",
        base=base,
        method="POST",
        form={"hashes": torrent_hash},
        what="stopping the download",
    )


def start(
    opener: urllib.request.OpenerDirector,
    torrent_hash: str,
    *,
    base: str = CLIENT,
) -> None:
    api(
        opener,
        "/api/v2/torrents/start",
        base=base,
        method="POST",
        form={"hashes": torrent_hash},
        what="starting the download",
    )


def recheck(
    opener: urllib.request.OpenerDirector,
    torrent_hash: str,
    *,
    base: str = CLIENT,
) -> None:
    api(
        opener,
        "/api/v2/torrents/recheck",
        base=base,
        method="POST",
        form={"hashes": torrent_hash},
        what="rechecking the data",
    )


def reannounce(
    opener: urllib.request.OpenerDirector,
    torrent_hash: str,
    *,
    base: str = CLIENT,
) -> None:
    """Ask the tracker for peers now, instead of waiting for the interval."""
    api(
        opener,
        "/api/v2/torrents/reannounce",
        base=base,
        method="POST",
        form={"hashes": torrent_hash},
        what="asking the tracker for peers",
    )


def limit_download(
    opener: urllib.request.OpenerDirector, torrent_hash: str, bytes_per_second: int
) -> None:
    api(
        opener,
        "/api/v2/torrents/setDownloadLimit",
        method="POST",
        form={"hashes": torrent_hash, "limit": bytes_per_second},
        what="limiting the download",
    )


def preferences(opener: urllib.request.OpenerDirector) -> dict[str, Any]:
    body = api(opener, "/api/v2/app/preferences", what="qBittorrent preferences")
    if not isinstance(body, dict):
        raise ScenarioError("qBittorrent returned no preferences")
    return body


def set_preferences(
    opener: urllib.request.OpenerDirector, values: dict[str, Any]
) -> None:
    api(
        opener,
        "/api/v2/app/setPreferences",
        method="POST",
        form={"json": json.dumps(values)},
        what="setting qBittorrent preferences",
    )


def save_preferences(opener: urllib.request.OpenerDirector) -> dict[str, Any]:
    """Remember the preferences a scenario changes, once.

    A second ``apply`` must not overwrite the original values with the ones the
    first run set, or ``teardown`` would restore the scenario's own limit.
    """
    if PREFERENCES_FILE.exists():
        return json.loads(PREFERENCES_FILE.read_text(encoding="utf-8"))
    current = preferences(opener)
    saved = {key: current.get(key) for key in PREFERENCE_KEYS}
    SCENARIO_STATE.mkdir(parents=True, exist_ok=True)
    PREFERENCES_FILE.write_text(
        json.dumps(saved, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return saved


def restore_preferences(opener: urllib.request.OpenerDirector) -> None:
    """Put the saved values back, and prove the client took them."""
    if not PREFERENCES_FILE.exists():
        return
    saved = json.loads(PREFERENCES_FILE.read_text(encoding="utf-8"))
    set_preferences(opener, saved)
    current = preferences(opener)
    restored = {key: current.get(key) for key in PREFERENCE_KEYS}
    if restored != saved:
        raise ScenarioError(
            f"the client kept {restored} instead of the saved {saved}"
        )
    PREFERENCES_FILE.unlink()


def wait_torrent(
    opener: urllib.request.OpenerDirector,
    name: str = TORRENT_NAME,
    *,
    predicate: Callable[[dict[str, Any]], bool],
    what: str,
    timeout: float = 120,
    interval: float = 1,
    base: str = CLIENT,
    nudge: bool = False,
) -> dict[str, Any]:
    """Wait for a torrent to reach a state, optionally asking for peers.

    The tracker keeps peers in memory, so a tracker that restarted, or two
    peers that announced before each other, can leave a torrent with nobody to
    talk to until its own announce interval comes round (a minute, and
    qBittorrent backs off to five after a miss). A transfer therefore nudges the
    tracker while it waits.
    """
    deadline = time.monotonic() + timeout
    next_nudge = time.monotonic() + NUDGE_AFTER
    last: dict[str, Any] | None = None
    while time.monotonic() < deadline:
        last = named(opener, name, base=base)
        if last is not None and predicate(last):
            return last
        if nudge and last is not None and time.monotonic() >= next_nudge:
            try:
                reannounce(opener, last["hash"], base=base)
            except ScenarioError:
                pass
            next_nudge = time.monotonic() + NUDGE_AFTER
        time.sleep(interval)
    raise ScenarioError(f"{what} did not happen within {timeout:.0f}s: {last}")


def progress(torrent: dict[str, Any] | None) -> float:
    if torrent is None:
        return 0.0
    return float(torrent.get("progress") or 0)


def state(torrent: dict[str, Any] | None) -> str:
    if torrent is None:
        return "absent"
    return str(torrent.get("state") or "unknown")


# --------------------------------------------------------------------------
# The seeder's file: the 47% is real bytes, not a progress field.
# --------------------------------------------------------------------------


def backup_seed_file() -> None:
    """Keep the whole file once, before any run truncates it."""
    if SEED_BACKUP.exists():
        if SEED_BACKUP.stat().st_size != FULL_SIZE:
            raise ScenarioError(
                f"the seeder backup is {SEED_BACKUP.stat().st_size} bytes, "
                f"not the release's {FULL_SIZE}; restore the lab before applying"
            )
        return
    if not SEED_FILE.is_file():
        raise ScenarioError(f"the seeder has no file at {SEED_FILE}")
    size = SEED_FILE.stat().st_size
    if size != FULL_SIZE:
        raise ScenarioError(
            f"the seeder file is {size} bytes, not the release's {FULL_SIZE}: "
            "the lab is not in its golden state"
        )
    SCENARIO_STATE.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SEED_FILE, SEED_BACKUP)


def truncate_seed_file(target_bytes: int = STUCK_BYTES) -> None:
    """Cut the seeder's file down to a whole number of pieces."""
    if target_bytes % PIECE_LENGTH:
        raise ScenarioError("the truncation must fall on a piece boundary")
    if not SEED_FILE.parent.is_dir():
        raise ScenarioError(f"the seeder has no folder at {SEED_FILE.parent}")
    with open(SEED_FILE, "r+b") as handle:
        handle.truncate(target_bytes)
        handle.flush()
        os.fsync(handle.fileno())


def restore_seed_file() -> None:
    """Put the whole file back, whatever the last run left behind."""
    if SEED_BACKUP.exists():
        if SEED_FILE.exists() and SEED_FILE.stat().st_size == FULL_SIZE:
            return
        SEED_FILE.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SEED_BACKUP, SEED_FILE)
        return
    if not SEED_FILE.exists():
        raise ScenarioError(f"the seeder's file is gone and no backup holds it")
    size = SEED_FILE.stat().st_size
    if size != FULL_SIZE:
        raise ScenarioError(
            f"the seeder file is {size} bytes with no backup to restore from"
        )


CHECKING_STATES = ("checkingUP", "checkingDL", "checkingResumeData", "allocating")


def seeder_reannounce(opener: urllib.request.OpenerDirector) -> None:
    """Put the seeder in front of the tracker before a download starts."""
    torrent = require_named(opener, TORRENT_NAME, base=SEEDER)
    reannounce(opener, torrent["hash"], base=SEEDER)


def seeder_recheck(
    opener: urllib.request.OpenerDirector,
    *,
    expected_progress: float,
    timeout: float = 180,
) -> dict[str, Any]:
    """Recheck the seeder's data and wait until it agrees with the file.

    Waiting for "not checking" is not enough: a recheck takes a moment to
    start, so the first read still shows the state from before the request.
    The file's size decides the percentage the seeder must land on.
    """
    torrent = require_named(opener, TORRENT_NAME, base=SEEDER)
    recheck(opener, torrent["hash"], base=SEEDER)
    settled = wait_torrent(
        opener,
        predicate=lambda item: item.get("state") not in CHECKING_STATES
        and abs(progress(item) - expected_progress) <= 0.001,
        what=f"the seeder rechecking to {expected_progress:.4f}",
        timeout=timeout,
        interval=2,
        base=SEEDER,
    )
    reannounce(opener, settled["hash"], base=SEEDER)
    return settled


# --------------------------------------------------------------------------
# The client's own restart, used by `missingFiles` alone.
# --------------------------------------------------------------------------


def restart_client() -> None:
    """Restart the app's qBittorrent, and nothing else.

    qBittorrent decides `missingFiles` once, when it starts: a torrent whose
    resume data says the data is there but whose files are gone comes up
    stopped with that state. Without the restart a recheck only resets the
    progress and downloads the pieces again.
    """
    environment = os.environ.copy()
    environment["CUPOLA_TESTLAB_STATE_DIR"] = str(STATE_ROOT)
    result = subprocess.run(
        [
            "docker",
            "compose",
            "-p",
            COMPOSE_PROJECT,
            "-f",
            str(COMPOSE_FILE),
            "restart",
            "qbittorrent",
        ],
        cwd=REPO_ROOT,
        env=environment,
        capture_output=True,
        text=True,
        timeout=180,
    )
    if result.returncode != 0:
        raise ScenarioError(
            "restarting qBittorrent failed: " + (result.stderr or "").strip()
        )


def wait_webui(timeout: float = 120) -> urllib.request.OpenerDirector:
    """Wait for the WebUI to answer again and return a fresh session."""
    deadline = time.monotonic() + timeout
    last: str | None = None
    while time.monotonic() < deadline:
        try:
            return opener_for(CLIENT)
        except (ScenarioError, OSError, http.client.HTTPException) as error:
            # A container that is still coming up drops the connection, which
            # is not an error to report, only a moment to wait through.
            last = str(error)
            time.sleep(2)
    raise ScenarioError(f"qBittorrent did not come back: {last}")


def drop_scenario_state() -> None:
    """Leave no scenario bookkeeping behind in the state the lab archives."""
    if SCENARIO_STATE.is_dir() and not any(SCENARIO_STATE.iterdir()):
        SCENARIO_STATE.rmdir()


def move_client_data_away() -> None:
    if CLIENT_DATA_AWAY.exists():
        shutil.rmtree(CLIENT_DATA_AWAY)
    if CLIENT_DATA.exists():
        CLIENT_DATA_AWAY.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(CLIENT_DATA), str(CLIENT_DATA_AWAY))


def restore_client_data() -> None:
    if not CLIENT_DATA_AWAY.exists():
        return
    if CLIENT_DATA.exists():
        shutil.rmtree(CLIENT_DATA)
    CLIENT_DATA.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(CLIENT_DATA_AWAY), str(CLIENT_DATA))


def remove_client_data(timeout: float = 20) -> None:
    """Delete the release's folder, waiting for the client's own deletion.

    A removal with ``deleteFiles`` is carried out by qBittorrent a moment
    later, so the folder can vanish between the check and the removal.
    """
    for folder in (CLIENT_DATA, CLIENT_DATA_AWAY):
        deadline = time.monotonic() + timeout
        while folder.exists() and time.monotonic() < deadline:
            shutil.rmtree(folder, ignore_errors=True)
            if folder.exists():
                time.sleep(0.5)
        if folder.exists():
            raise ScenarioError(f"{folder} could not be removed")


def ensure_absent(
    opener: urllib.request.OpenerDirector,
    name: str = TORRENT_NAME,
) -> None:
    """The acceptance a teardown shares: the torrent and its bytes are gone."""
    if named(opener, name) is not None:
        raise ScenarioError(f"{name} is still in qBittorrent")
    if CLIENT_DATA.exists():
        raise ScenarioError(f"{CLIENT_DATA} is still on disk")
    if CLIENT_DATA_AWAY.exists():
        raise ScenarioError(f"{CLIENT_DATA_AWAY} is still on disk")
