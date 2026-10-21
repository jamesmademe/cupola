"""Shared pieces for the two Usenet scenarios.

The lab's Usenet chain is one host process (``nntp_server``) and two clients:
SABnzbd, which is configured through its own HTTP API, and NZBGet, whose news
server is a line of ``nzbget.conf`` that the daemon re-reads on ``reload``. Both
clients reach the server at ``host.docker.internal``, the address the containers
use for the Mac they run on.

Nothing here holds a secret: the SABnzbd entry is created without credentials,
and the NZBGet edit touches only the five non-secret news-server fields, whose
original values are saved so the teardown can put them back. The two clients are
driven over their real APIs, exactly as the app drives them.
"""

from __future__ import annotations

import base64
import http.client
import json
import re
import shutil
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable, Iterable, TypeVar

import nntp_server  # noqa: E402

from scenarios.base import STATE_ROOT, ScenarioError, credentials  # noqa: E402

NNTP_PORT = nntp_server.NNTP_PORT
SAB_URL = "http://127.0.0.1:8082"
SAB_API_KEY = "test-key"
SAB_SERVER_NAME = "cupola-testlab-nntp"
NZBGET_URL = "http://127.0.0.1:6789/jsonrpc"
NZBGET_CONF = STATE_ROOT / "nzbget" / "nzbget.conf"
SAB_COMPLETE = STATE_ROOT / "sabnzbd" / "Downloads" / "complete"
NZBGET_COMPLETE = STATE_ROOT / "downloads" / "completed"

# The jobs both scenarios leave behind, one per catalog state.
COMPLETE = "Cupola.Testlab.Usenet.Complete"
MISSING = "Cupola.Testlab.Usenet.Missing"
SLOW = "Cupola.Testlab.Usenet.Slow"
WAITING = "Cupola.Testlab.Usenet.Waiting"
PAUSED = "Cupola.Testlab.Usenet.Paused"
# The seed's own NZBGet specimen. It holds a fake article that the lab server
# answers 430 for, so with one connection it keeps taking turns away from the
# scenario's jobs. The scenario pauses it and puts it back.
SEED_SPECIMEN = "cupola-nzbget-test"
# The two jobs the e2e adds and removes itself: one to prove the add path and
# one to prove the delete path. The scenario never leaves them behind.
ADDED = "Cupola.Testlab.Usenet.Added"
THROWAWAY = "Cupola.Testlab.Usenet.Throwaway"
JOB_NAMES = (COMPLETE, MISSING, SLOW, WAITING, PAUSED, ADDED, THROWAWAY)

# The NZBGet news-server fields the scenario changes, and nothing else. The
# username and password stay untouched, so no credential is ever read, stored
# or written by the scenario.
NZBGET_FIELDS = (
    "Server1.Host",
    "Server1.Port",
    "Server1.Encryption",
    "Server1.Connections",
    "Server1.JoinGroup",
)


def usenet_dir() -> Path:
    return STATE_ROOT / "usenet"


def scenario_state(name: str) -> Path:
    return usenet_dir() / f"{name}.json"


def read_state(name: str) -> dict[str, Any]:
    path = scenario_state(name)
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def write_state(name: str, payload: dict[str, Any]) -> None:
    usenet_dir().mkdir(parents=True, exist_ok=True)
    path = scenario_state(name)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    path.chmod(0o600)


def drop_state(name: str) -> None:
    scenario_state(name).unlink(missing_ok=True)
    # When the last scenario lets go, the server's manifest and log go too:
    # the next apply writes a fresh one, and nothing of the run is left in the
    # lab's state directory.
    if not [
        path for path in usenet_dir().glob("*.json") if path.name != "manifest.json"
    ]:
        for leftover in ("manifest.json", "nntp.log", "nntp.pid"):
            (usenet_dir() / leftover).unlink(missing_ok=True)
        try:
            usenet_dir().rmdir()
        except OSError:
            pass


def library_files() -> list[nntp_server.FileSpec]:
    """The files the scenarios serve, one per state they need.

    ``Complete`` and ``Paused`` carry a real 192 KiB file. ``Missing`` answers
    430 for every article, which is the client's own failure path and not a
    broken server. ``Slow`` is cut into many small articles with a pause
    before each, so the job stays downloading and can still be stopped at an
    article boundary. ``Waiting`` sits behind it in a client that runs one
    job per connection. ``Added`` and ``Throwaway`` are the two the e2e adds
    and removes itself.
    """
    return [
        nntp_server.FileSpec(
            COMPLETE, "Cupola.Testlab.Usenet.mkv", 3 * 64 * 1024
        ),
        nntp_server.FileSpec(
            MISSING,
            "Cupola.Testlab.Usenet.Missing.mkv",
            2 * 64 * 1024,
            missing_parts=(1, 2),
        ),
        # Many small articles: the pause between them is what keeps the job
        # downloading, and the client can stop it at the next article.
        nntp_server.FileSpec(
            SLOW,
            "Cupola.Testlab.Usenet.Slow.mkv",
            64 * 1024,
            part_size=512,
            slow=True,
        ),
        nntp_server.FileSpec(
            WAITING, "Cupola.Testlab.Usenet.Waiting.mkv", 3 * 64 * 1024
        ),
        nntp_server.FileSpec(
            PAUSED, "Cupola.Testlab.Usenet.Paused.mkv", 3 * 64 * 1024
        ),
        nntp_server.FileSpec(ADDED, "Cupola.Testlab.Usenet.Added.mkv", 64 * 1024),
        nntp_server.FileSpec(
            THROWAWAY, "Cupola.Testlab.Usenet.Throwaway.mkv", 64 * 1024
        ),
    ]


def ensure_server() -> dict[str, Any]:
    manifest = nntp_server.write_manifest(STATE_ROOT, library_files())
    return nntp_server.ensure(STATE_ROOT)


def stop_server() -> None:
    nntp_server.stop(STATE_ROOT)


def nzb_url(key: str) -> str:
    """The URL a client inside a container fetches the NZB from."""
    return f"http://host.docker.internal:{nntp_server.HTTP_PORT}/nzb/{key}.nzb"


T = TypeVar("T")


def wait_for(
    read: Callable[[], T],
    predicate: Callable[[T], bool],
    *,
    what: str,
    timeout: float = 90,
    interval: float = 0.5,
) -> T:
    deadline = time.monotonic() + timeout
    last: T | None = None
    while time.monotonic() < deadline:
        last = read()
        if predicate(last):
            return last
        time.sleep(interval)
    raise ScenarioError(f"timed out waiting for {what}: last read {last!r}")


# ---------------------------------------------------------------------------
# SABnzbd


class Sabnzbd:
    """The SABnzbd HTTP API, as the app calls it."""

    def call(self, mode: str, **extra: Any) -> dict[str, Any]:
        query = urllib.parse.urlencode(
            {"mode": mode, "output": "json", "apikey": SAB_API_KEY, **extra}
        )
        try:
            with urllib.request.urlopen(
                f"{SAB_URL}/api?{query}", timeout=20
            ) as answer:
                body = json.loads(answer.read())
        except (urllib.error.URLError, OSError) as error:
            raise ScenarioError(f"SABnzbd did not answer: {error}") from error
        if body.get("status") is False:
            raise ScenarioError(f"SABnzbd refused {mode}: {body.get('error')}")
        return body

    def queue(self) -> dict[str, Any]:
        return self.call("queue", start=0, limit=100)["queue"]

    def slots(self) -> list[dict[str, Any]]:
        return list(self.queue().get("slots") or [])

    def history(self) -> list[dict[str, Any]]:
        history = self.call("history", start=0, limit=100)["history"]
        return list(history.get("slots") or [])

    def servers(self) -> list[dict[str, Any]]:
        config = self.call("get_config", section="servers").get("config") or {}
        return list(config.get("servers") or [])

    def add(self, key: str) -> str:
        answer = self.call("addurl", name=nzb_url(key))
        ids = answer.get("nzo_ids") or []
        if not ids:
            raise ScenarioError(f"SABnzbd did not accept the NZB for {key}")
        return str(ids[0])

    def pause(self, nzo_id: str) -> None:
        self.call("queue", name="pause", value=nzo_id)

    def resume(self, nzo_id: str) -> None:
        self.call("queue", name="resume", value=nzo_id)

    def delete(self, nzo_id: str, *, delete_files: bool = True) -> None:
        self.call(
            "queue",
            name="delete",
            value=nzo_id,
            **({"del_files": 1} if delete_files else {}),
        )

    def delete_history(self, nzo_id: str, *, delete_files: bool = True) -> None:
        self.call(
            "history",
            name="delete",
            value=nzo_id,
            archive=0,
            **({"del_files": 1} if delete_files else {}),
        )

    def configure_server(self) -> None:
        """Create or update the lab's news server entry. Idempotent."""
        self.call(
            "set_config",
            section="servers",
            name=SAB_SERVER_NAME,
            host="host.docker.internal",
            port=nntp_server.NNTP_PORT,
            connections=2,
            ssl=0,
            enable=1,
            priority=0,
        )

    def remove_server(self) -> None:
        if any(server.get("name") == SAB_SERVER_NAME for server in self.servers()):
            self.call("del_config", section="servers", keyword=SAB_SERVER_NAME)

    def server(self) -> dict[str, Any]:
        for entry in self.servers():
            if entry.get("name") == SAB_SERVER_NAME:
                return entry
        raise ScenarioError("SABnzbd has no lab news server")

    def slot(self, name: str) -> dict[str, Any] | None:
        for entry in self.slots():
            if str(entry.get("filename") or entry.get("name")) == name:
                return entry
        return None

    def history_item(self, name: str) -> dict[str, Any] | None:
        for entry in self.history():
            if str(entry.get("name")) == name:
                return entry
        return None

    def clean(self, names: Iterable[str] = JOB_NAMES) -> None:
        """Remove every job the scenarios own, and prove it is gone.

        SABnzbd cancels a job at once, but asking twice costs nothing and a
        job that reappears between the read and the delete is caught.
        """
        wanted = set(names)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            slots = [
                entry
                for entry in self.slots()
                if str(entry.get("filename") or entry.get("name")) in wanted
            ]
            history = [
                entry for entry in self.history() if str(entry.get("name")) in wanted
            ]
            if not slots and not history:
                return
            for entry in slots:
                self.delete(str(entry.get("nzo_id")), delete_files=True)
            for entry in history:
                self.delete_history(str(entry.get("nzo_id")), delete_files=True)
            time.sleep(0.5)
        raise ScenarioError("SABnzbd kept a job the scenario owns")


# ---------------------------------------------------------------------------
# NZBGet


class Nzbget:
    """The NZBGet JSON-RPC API, plus the one config edit it cannot do itself."""

    def __init__(self) -> None:
        values = credentials()
        user = values.get("CUPOLA_TESTLAB_NZBGET_USERNAME", "nzbget")
        password = values.get("CUPOLA_TESTLAB_NZBGET_PASSWORD", "")
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        self._auth = f"Basic {token}"

    def call(self, method: str, params: list[Any] | None = None) -> Any:
        payload = json.dumps(
            {"jsonrpc": "2.0", "method": method, "params": params or [], "id": 1}
        ).encode()
        # ``reload`` drops the control connection while the daemon re-reads its
        # config, so a call made right after it can be refused at the socket
        # before the request is even read. Retry those, never a JSON-RPC error.
        for attempt in range(8):
            request = urllib.request.Request(
                NZBGET_URL,
                data=payload,
                headers={
                    "Authorization": self._auth,
                    "Content-Type": "application/json",
                },
            )
            try:
                with urllib.request.urlopen(request, timeout=30) as answer:
                    body = json.loads(answer.read())
                break
            except (urllib.error.URLError, http.client.HTTPException, OSError) as error:
                if attempt == 7:
                    raise ScenarioError(
                        f"NZBGet did not answer: {error}"
                    ) from error
                time.sleep(0.5)
        if body.get("error"):
            raise ScenarioError(f"NZBGet refused {method}: {body['error']}")
        return body.get("result")

    def config(self) -> dict[str, str]:
        return {item["Name"]: item["Value"] for item in self.call("config") or []}

    def groups(self) -> list[dict[str, Any]]:
        return list(self.call("listgroups", [0]) or [])

    def history(self) -> list[dict[str, Any]]:
        return list(self.call("history", [False]) or [])

    def append(self, key: str) -> int:
        # The name must end in .nzb: NZBGet hands anything without a known
        # extension to the scan scripts instead of queueing it.
        nzb_id = self.call(
            "append",
            [
                f"{key}.nzb",
                nzb_url(key),
                "",
                0,
                False,
                False,
                "",
                0,
                "FORCE",
            ],
        )
        if not isinstance(nzb_id, int) or nzb_id <= 0:
            raise ScenarioError(f"NZBGet did not accept the NZB for {key}")
        return nzb_id

    def edit(self, command: str, nzb_id: int) -> bool:
        return bool(self.call("editqueue", [command, 0, "", [nzb_id]]))

    def reload(self) -> None:
        """Ask the daemon to re-read its config.

        ``reload`` answers at once and applies the file in the background, so
        the caller has to wait for the daemon to report the change, not for the
        call to return.
        """
        self.call("reload")

    def group(self, name: str) -> dict[str, Any] | None:
        for entry in self.groups():
            if entry.get("NZBName") == name:
                return entry
        return None

    def history_item(self, name: str) -> dict[str, Any] | None:
        for entry in self.history():
            # A deleted entry can stay visible with a DELETED status; it is
            # not the job the scenario just added. ``Deleted`` itself is not
            # that signal: NZBGet sets it on a failed job whose partial files
            # it cleaned up.
            if entry.get("Name") != name:
                continue
            if str(entry.get("Status", "")).startswith("DELETED"):
                continue
            return entry
        return None

    def clean(self, names: Iterable[str] = JOB_NAMES) -> None:
        """Remove every job the scenarios own, and prove it is gone.

        ``GroupDelete`` on a group that is downloading takes effect at the
        next article, so the loop asks again until the queue agrees; two
        groups with one name would otherwise shadow each other.
        """
        wanted = set(names)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            groups = [
                entry for entry in self.groups() if entry.get("NZBName") in wanted
            ]
            history = [
                entry
                for entry in self.history() + list(self.call("history", [True]) or [])
                if entry.get("Name") in wanted
            ]
            if not groups and not history:
                return
            for entry in groups:
                self.edit("GroupDelete", int(entry["NZBID"]))
            for entry in history:
                # Final, not the hide that HistoryDelete performs: a hidden
                # entry would still be counted by the next run's own reads.
                self.edit("HistoryFinalDelete", int(entry["NZBID"]))
            time.sleep(0.5)
        raise ScenarioError("NZBGet kept a job the scenario owns")

    def pause_seed(self) -> bool:
        """Stop the seed's specimen so it cannot take the connection."""
        group = self.group(SEED_SPECIMEN)
        if group is None or group.get("Status") == "PAUSED":
            return False
        return self.edit("GroupPause", int(group["NZBID"]))

    def resume_seed(self) -> None:
        group = self.group(SEED_SPECIMEN)
        if group is not None and group.get("Status") == "PAUSED":
            self.edit("GroupResume", int(group["NZBID"]))

    def read_fields(self) -> dict[str, str]:
        text = NZBGET_CONF.read_text(encoding="utf-8")
        found: dict[str, str] = {}
        for field in NZBGET_FIELDS:
            match = re.search(rf"^{re.escape(field)}=(.*)$", text, re.MULTILINE)
            if match is None:
                raise ScenarioError(f"NZBGet's config has no {field}")
            found[field] = match.group(1)
        return found

    def write_fields(self, values: dict[str, str]) -> None:
        """Change the news-server lines and make the daemon re-read the file.

        ``saveconfig`` is not usable here: it rewrites the file from the options
        it is handed and drops everything else. The daemon re-reads its config
        on ``reload``, which is the path the web UI uses for external edits.
        """
        text = NZBGET_CONF.read_text(encoding="utf-8")
        for field, value in values.items():
            pattern = re.compile(rf"^{re.escape(field)}=.*$", re.MULTILINE)
            if pattern.search(text) is None:
                raise ScenarioError(f"NZBGet's config has no {field}")
            text = pattern.sub(f"{field}={value}", text, count=1)
        temporary = NZBGET_CONF.with_suffix(".conf.testlab")
        temporary.write_text(text, encoding="utf-8")
        temporary.replace(NZBGET_CONF)
        self.reload()
        # ``reload`` restarts the daemon, and the old process answers the
        # config call with the new values before it goes away. Wait out the
        # restart, then wait for the new process to agree: a job added during
        # that window is queued but its URL fetch dies with the old process.
        time.sleep(3)
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            current = self.config()
            if all(current.get(field) == value for field, value in values.items()):
                return
            time.sleep(0.3)
        raise ScenarioError(
            "NZBGet did not pick up the news server change: "
            + ", ".join(f"{field}={self.config().get(field)!r}" for field in values)
        )

    def point_at_lab(self, original: dict[str, str] | None = None) -> dict[str, str]:
        """Point Server1 at the lab, and hand back what it was before.

        ``original`` is what a previous apply saved: a second apply must not
        mistake the lab's own values for the lab's starting point.
        """
        original = original or self.read_fields()
        self.write_fields(
            {
                "Server1.Host": "host.docker.internal",
                "Server1.Port": str(nntp_server.NNTP_PORT),
                "Server1.Encryption": "no",
                # One connection on purpose: NZBGet runs as many jobs as it has
                # free connections, so a single one is what makes the job
                # behind the slow one read "Queued".
                "Server1.Connections": "1",
                "Server1.JoinGroup": "no",
            }
        )
        return original


# ---------------------------------------------------------------------------
# Files the clients wrote, removed from the host's bind mounts.


def verify_download(client: str, name: str, filename: str, size: int) -> None:
    """Prove a completed job wrote exactly the bytes the articles carried."""
    root = SAB_COMPLETE if client == "sabnzbd" else NZBGET_COMPLETE
    path = root / name / filename
    if not path.exists():
        raise ScenarioError(f"{client} left no file at {path}")
    if path.read_bytes() != nntp_server.payload_for(name, size):
        raise ScenarioError(f"{client} wrote a different file at {path}")


def remove_download(name: str) -> None:
    for root in (SAB_COMPLETE, NZBGET_COMPLETE):
        for child in root.glob(f"{name}*"):
            if child.is_dir():
                shutil.rmtree(child, ignore_errors=True)
            else:
                child.unlink(missing_ok=True)
