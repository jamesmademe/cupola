#!/usr/bin/env python3
"""Dockge con stack veri nel ``docker:dind`` isolato del lab.

Dockge non ha una REST API: tutto passa da Socket.IO v4, e i comandi sono
avvolti in una busta ``agent`` (``emit("agent", endpoint, evento, ...args)``,
ack come ultimo argomento), la stessa forma che usa
``lib/features/dockge/data/dockge_client.dart``. Questo modulo è il client del
lab per quel protocollo, non un secondo client dell'app: serve a preparare lo
stato e a rileggerlo dal server, e non tocca mai la libreria dell'app.

Cosa fa, in breve:

* ``ensure_image()`` copia l'immagine minima dal Docker del Mac al volume del
  dind (``docker save`` | ``docker exec -i … docker load``) e la ritarghetta
  ``cupola-lab/base:1``. Da lì in poi il dind non scarica niente: i compose
  portano ``pull_policy: never``, quindi anche ``Update`` (che è
  ``docker compose pull``) risponde ``Skipped``.
* ``session()`` apre un socket, fa login e restituisce un [Dockge]; ogni comando
  ha il suo ack e gli eventi spinti (``stackList``, ``terminalWrite``) restano
  in memoria per la rilettura.
* ``probe_runtime()`` dice se il dind riesce a creare container.

Il limite del dind attuale (evidenza in ``dind_stacks/README.md``): il suo
``/var/lib/docker`` è un bind mount dello stato sul Mac, e overlayfs non riesce
a scriverci l'upperdir. Il kernel monta lo snapshot in sola lettura e ogni
``docker run`` fallisce con ``mount callback failed``, seguito dal passo che non
è riuscito a scrivere (``mkdir …/dev/shm: read-only file system``,
``symlink …/etc/mtab: file exists``: cambia a ogni tentativo).

Quindi uno stack resta ``Inactive``: ``Start`` e ``Deploy``, gli unici due che
creano un container, rispondono ``Failed to …``; ``Stop``, ``Restart``,
``Update`` e ``Down`` rispondono come no-op, perché non c'è niente da fermare.
Lo scenario misura il fatto e lo scrive nel marcatore; l'e2e verifica il ramo
che vale davvero.

Le credenziali stanno solo in ``$CUPOLA_TESTLAB_STATE_DIR/credentials.env``
(0600): qui si leggono e non si stampano mai, token compresi.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import subprocess
import sys
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, AsyncIterator, Iterable

import websockets

TESTLAB_DIR = Path(__file__).resolve().parent
REPO_ROOT = TESTLAB_DIR.parents[2]
SCRATCH_ROOT = REPO_ROOT / ".ai" / "scratch" / "zz_testlab"
STATE_ROOT = Path(
    os.environ.get("CUPOLA_TESTLAB_STATE_DIR", SCRATCH_ROOT / "state")
).resolve()
CREDENTIALS = STATE_ROOT / "credentials.env"
STACKS_DIR = TESTLAB_DIR / "dind_stacks"
MARKER = STATE_ROOT / "backup" / "dockge_lab" / "state.json"

URL = os.environ.get("CUPOLA_TESTLAB_DOCKGE_URL", "http://127.0.0.1:5001")

# The offline crate. `cupola-lab/base:1` is `alpine/socat:1.8.0.3` retagged: an
# Alpine with /bin/sh and nothing else to download. It is the smallest image the
# Mac already has that carries a shell, and copying it into the dind needs no
# network at all.
BASE_IMAGE = "cupola-lab/base:1"
SOURCE_IMAGE = "alpine/socat:1.8.0.3"
DIND_SERVICE = "docker-dind"

LOG_STACK = "cupola-log"
IDLE_STACK = "cupola-idle"
CRASH_STACK = "cupola-crash"
STACKS = (LOG_STACK, IDLE_STACK, CRASH_STACK)

# Dockge's integer stack statuses (`common/util-common.ts`), the five the app's
# `DockgeStackStatus` mirrors.
UNKNOWN = 0
CREATED_FILE = 1
CREATED_STACK = 2
RUNNING = 3
EXITED = 4
STATUS_LABEL = {
    UNKNOWN: "Unknown",
    CREATED_FILE: "Inactive",
    CREATED_STACK: "Inactive",
    RUNNING: "Running",
    EXITED: "Stopped",
}


# Cursor moves, colours and screen resets Docker Compose and Dockge put around
# terminal output; the raw frame keeps them, a person's reading does not.
_ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


# How long a stack list is given to settle before it is read: Dockge does not
# await `sendStackList()`, so the frame for a command can follow its own ack.
_LIST_SETTLE = 0.3


class DockgeLabError(RuntimeError):
    """The lab could not do what was asked."""


class DockgeRefused(DockgeLabError):
    """Dockge answered ``{ok: false}``: a refusal, not a lab fault."""

    def __init__(self, event: str, message: str) -> None:
        super().__init__(message)
        self.event = event
        self.message = message


def credentials() -> dict[str, str]:
    values: dict[str, str] = {}
    if not CREDENTIALS.exists():
        return values
    for line in CREDENTIALS.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key] = value
    return values


def _login_credentials() -> tuple[str, str]:
    values = credentials()
    username = values.get("CUPOLA_TESTLAB_DOCKGE_USERNAME", "")
    password = values.get("CUPOLA_TESTLAB_DOCKGE_PASSWORD", "")
    if not username or not password:
        raise DockgeLabError(
            f"{CREDENTIALS} carries no Dockge username and password"
        )
    return username, password


def compose_for(name: str) -> str:
    """The compose text this lab owns for [name], byte for byte."""
    if name not in STACKS:
        raise DockgeLabError(f"{name!r} is not one of the lab's stacks")
    path = STACKS_DIR / f"{name}.yaml"
    if not path.exists():
        raise DockgeLabError(f"{path} is missing")
    return path.read_text(encoding="utf-8")


# ---- The dind -----------------------------------------------------------


def _run(command: list[str], **kwargs: Any) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def dind_container() -> str:
    """The compose container running ``docker:dind``, found by its label."""
    override = os.environ.get("CUPOLA_TESTLAB_DIND_CONTAINER", "").strip()
    if override:
        return override
    listed = _run(
        [
            "docker",
            "ps",
            "--filter",
            f"label=com.docker.compose.service={DIND_SERVICE}",
            "--format",
            "{{.Names}}",
        ]
    )
    names = [line for line in listed.stdout.splitlines() if line.strip()]
    if not names:
        raise DockgeLabError(
            "no docker:dind container is running; bring the lab up first"
        )
    return names[0].strip()


def _dind(args: Iterable[str], *, stdin: Any = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["docker", "exec", "-i", dind_container(), "docker", *args],
        capture_output=True,
        text=True,
        stdin=stdin,
    )


def _dind_or_fail(args: list[str]) -> str:
    result = _dind(args)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip().splitlines()
        raise DockgeLabError(
            f"docker {' '.join(args)} in the dind failed: "
            f"{detail[-1] if detail else result.returncode}"
        )
    return result.stdout.strip()


def dind_image_id(image: str = BASE_IMAGE) -> str | None:
    result = _dind(["image", "inspect", "--format", "{{.Id}}", image])
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def ensure_image() -> dict[str, Any]:
    """Make sure the crate image is in the dind's volume, without a network.

    Idempotent: an image already there is left alone. The caller records what
    this run added (``loaded``, ``sourceLoaded``) so the teardown can take out
    exactly that and leave the dind as it found it.
    """
    if dind_image_id():
        return {"image": BASE_IMAGE, "loaded": False, "id": dind_image_id()}

    if _run(["docker", "image", "inspect", SOURCE_IMAGE]).returncode != 0:
        raise DockgeLabError(
            f"the Mac has no {SOURCE_IMAGE} image to copy into the dind"
        )

    # `docker load` writes the source's own tag too, so remember whether that
    # tag was already the dind's: the teardown takes out only what it added.
    source_was_there = dind_image_id(SOURCE_IMAGE) is not None

    save = subprocess.Popen(
        ["docker", "save", SOURCE_IMAGE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        load = _dind(["load"], stdin=save.stdout)
    finally:
        if save.stdout is not None:
            save.stdout.close()
        save_error = (
            save.stderr.read().decode("utf-8", "replace") if save.stderr else ""
        )
        save.wait()
    if save.returncode != 0:
        raise DockgeLabError(
            f"docker save {SOURCE_IMAGE} failed: {save_error.strip()}"
        )
    if load.returncode != 0:
        raise DockgeLabError(f"docker load in the dind failed: {load.stderr.strip()}")
    _dind_or_fail(["tag", SOURCE_IMAGE, BASE_IMAGE])
    return {
        "image": BASE_IMAGE,
        "loaded": True,
        "source": SOURCE_IMAGE,
        "sourceLoaded": not source_was_there,
        "id": dind_image_id(),
    }


def remove_image(image: str = BASE_IMAGE) -> None:
    """Take the crate image out again, so the dind is left as it was found."""
    _dind(["image", "rm", "--force", image])


def probe_runtime() -> dict[str, Any]:
    """Whether this dind can create a container at all, with the evidence."""
    if dind_image_id() is None:
        return {"available": False, "evidence": f"{BASE_IMAGE} is not in the dind"}
    result = _dind(["run", "--rm", "--entrypoint", "/bin/true", BASE_IMAGE])
    if result.returncode == 0:
        return {"available": True, "evidence": "docker run exited 0"}
    lines = [line.strip() for line in result.stderr.splitlines() if line.strip()]
    # Docker ends with "Run 'docker run --help' for more information": the
    # daemon's own sentence is the one that says why.
    detail = next(
        (line for line in lines if "Error response from daemon" in line),
        lines[0] if lines else f"docker run exited {result.returncode}",
    )
    return {"available": False, "evidence": detail.removeprefix("docker: ")}


def dind_containers(project: str | None = None) -> list[str]:
    """Container names in the dind, optionally only one compose project's."""
    args = ["ps", "-a", "--format", "{{.Names}}"]
    if project:
        args[2:2] = ["--filter", f"label=com.docker.compose.project={project}"]
    return [line for line in _dind_or_fail(args).splitlines() if line.strip()]


def dind_projects() -> list[str]:
    """The compose projects the dind's daemon knows, running or not."""
    raw = _dind_or_fail(["compose", "ls", "--all", "--format", "json"]).strip()
    if not raw:
        return []
    try:
        listed = json.loads(raw)
    except json.JSONDecodeError as error:
        raise DockgeLabError(f"docker compose ls answered unreadable JSON: {error}") from error
    return sorted(
        str(row.get("Name")) for row in listed if isinstance(row, dict) and row.get("Name")
    )


# ---- The socket ---------------------------------------------------------


class TerminalChunk:
    """One ``terminalWrite`` frame: which terminal said it, and what."""

    __slots__ = ("terminal", "data")

    def __init__(self, terminal: str, data: str) -> None:
        self.terminal = terminal
        self.data = data

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"TerminalChunk({self.terminal!r}, {self.data!r})"

    @property
    def text(self) -> str:
        """The chunk as a person reads it: no cursor moves, no colours.

        ``data`` stays exactly the frame the server sent; this is the view a
        marker and an assertion use, because Dockge's compose output arrives
        with ANSI control sequences around every word.
        """
        return _ANSI.sub("", self.data).replace("\r", "").strip()


class Dockge:
    """One authenticated Socket.IO connection to Dockge, as the app has it."""

    def __init__(self, websocket: Any) -> None:
        self._ws = websocket
        self._acks: dict[int, asyncio.Future] = {}
        self._counter = 0
        self._send_lock = asyncio.Lock()
        self._reader: asyncio.Task | None = None
        self._list_event = asyncio.Event()
        self.stacks: dict[str, dict] = {}
        self.agents: dict[str, Any] = {}
        self.output: list[TerminalChunk] = []
        self.info: dict[str, Any] = {}
        self.notes: list[str] = []

    # -- protocol ---------------------------------------------------------

    async def _send(self, frame: str) -> None:
        async with self._send_lock:
            await self._ws.send(frame)

    async def _handle(self, frame: str) -> None:
        if frame == "2":
            await self._send("3")
            return
        if frame.startswith("43"):
            rest = frame[2:]
            index = 0
            while index < len(rest) and rest[index].isdigit():
                index += 1
            try:
                payload = json.loads(rest[index:]) if rest[index:] else None
            except json.JSONDecodeError:
                payload = None
            if isinstance(payload, list) and len(payload) == 1:
                payload = payload[0]
            future = self._acks.pop(int(rest[:index] or -1), None)
            if future is not None and not future.done():
                future.set_result(payload)
            return
        if not frame.startswith("42"):
            return
        try:
            packet = json.loads(frame[2:])
        except json.JSONDecodeError:
            self.notes.append(f"unreadable event frame: {frame[:80]}")
            return
        if not isinstance(packet, list) or not packet:
            return
        name, args = packet[0], packet[1:]
        if name == "agent":
            # Dockge wraps everything aimed at an agent, pushes included:
            # `emit("agent", "stackList", {...})` is how the list arrives.
            if len(args) < 2:
                return
            name, args = args[0], args[1:]
        if name == "stackList" and args and isinstance(args[0], dict):
            payload = args[0].get("stackList")
            if isinstance(payload, dict):
                self.stacks = payload
                self._list_event.set()
        elif name == "terminalWrite" and len(args) >= 2:
            self.output.append(TerminalChunk(str(args[0]), str(args[1])))
        elif name == "agentList" and args and isinstance(args[0], dict):
            self.agents = args[0].get("agentList") or {}
        elif name == "info" and args and isinstance(args[0], dict):
            self.info.update(args[0])

    async def _read(self) -> None:
        try:
            async for frame in self._ws:
                await self._handle(frame)
        except asyncio.CancelledError:  # pragma: no cover - normal close
            raise
        except Exception as error:  # noqa: BLE001 - a closed socket ends the read
            self.notes.append(f"the read loop stopped: {error}")

    def listen(self) -> None:
        """Start reading frames, so pushes and acks land in this object."""
        self._reader = asyncio.create_task(self._read())

    async def close(self) -> None:
        if self._reader is not None:
            self._reader.cancel()
            self._reader = None
        for future in self._acks.values():
            if not future.done():
                future.cancel()
        self._acks.clear()

    async def call(
        self, event: str, *args: Any, timeout: float = 45.0
    ) -> Any:
        """Emit with an ack and return the ack's payload."""
        self._counter += 1
        ack_id = self._counter
        future: asyncio.Future = asyncio.get_running_loop().create_future()
        self._acks[ack_id] = future
        packet = json.dumps([event, *args], separators=(",", ":"))
        await self._send(f"42{ack_id}{packet}")
        try:
            return await asyncio.wait_for(future, timeout)
        except TimeoutError as error:
            self._acks.pop(ack_id, None)
            raise DockgeLabError(f"Dockge did not answer {event}") from error

    async def agent(self, event: str, *args: Any, timeout: float = 45.0) -> dict:
        """A command aimed at the agent, refusing ``{ok: false}`` the way the app does."""
        answer = await self.call("agent", "", event, *args, timeout=timeout)
        if not isinstance(answer, dict) or answer.get("ok") is not True:
            message = (
                answer.get("msg")
                if isinstance(answer, dict)
                else f"unexpected answer: {answer!r}"
            )
            raise DockgeRefused(event, str(message or f"{event} was refused"))
        return answer

    # -- reads ------------------------------------------------------------

    async def refresh(self, timeout: float = 15.0) -> dict[str, dict]:
        """Ask for the stack list and wait for the push it produces."""
        self._list_event.clear()
        await self.agent("requestStackList")
        try:
            await asyncio.wait_for(self._list_event.wait(), timeout)
        except TimeoutError as error:
            raise DockgeLabError(
                "Dockge acknowledged requestStackList but published no list"
            ) from error
        # A push computed *before* this request can still land after it: Dockge
        # starts `sendStackList()` without awaiting it, so a save or a delete
        # answers before its own list has been built. The first frame to arrive
        # can therefore carry the state from before the command. Let the round
        # trip settle and answer with the newest list, not the first.
        await asyncio.sleep(_LIST_SETTLE)
        return self.stacks

    async def stack(self, name: str) -> dict:
        answer = await self.agent("getStack", name)
        stack = answer.get("stack")
        if not isinstance(stack, dict):
            raise DockgeLabError(f"getStack {name} answered without a stack")
        return stack

    async def services(self, name: str) -> dict:
        answer = await self.agent("serviceStatusList", name)
        listed = answer.get("serviceStatusList")
        return listed if isinstance(listed, dict) else {}

    async def wait_status(
        self, name: str, codes: Iterable[int] = (RUNNING,), timeout: float = 40.0
    ) -> int:
        wanted = set(codes)
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        status = self.status(name)
        while status not in wanted:
            if loop.time() > deadline:
                raise DockgeLabError(
                    f"{name} stayed {STATUS_LABEL.get(status, status)}, "
                    f"not {sorted(wanted)}"
                )
            await asyncio.sleep(0.5)
            await self.refresh()
            status = self.status(name)
        return status

    def status(self, name: str) -> int:
        row = self.stacks.get(name)
        if not isinstance(row, dict):
            return UNKNOWN
        try:
            return int(row.get("status", UNKNOWN))
        except (TypeError, ValueError):
            return UNKNOWN

    def names(self) -> list[str]:
        return sorted(self.stacks)

    # -- lifecycle --------------------------------------------------------

    async def save(self, name: str, compose: str, *, is_add: bool, env: str = "") -> dict:
        return await self.agent("saveStack", name, compose, env, is_add)

    async def deploy(self, name: str, compose: str, *, is_add: bool, env: str = "") -> dict:
        return await self.agent(
            "deployStack", name, compose, env, is_add, timeout=180.0
        )

    async def start(self, name: str) -> dict:
        return await self.agent("startStack", name, timeout=180.0)

    async def stop(self, name: str) -> dict:
        return await self.agent("stopStack", name, timeout=180.0)

    async def restart(self, name: str) -> dict:
        return await self.agent("restartStack", name, timeout=180.0)

    async def update(self, name: str) -> dict:
        return await self.agent("updateStack", name, timeout=180.0)

    async def down(self, name: str) -> dict:
        return await self.agent("downStack", name, timeout=180.0)

    async def delete(self, name: str) -> dict:
        return await self.agent("deleteStack", name, timeout=180.0)

    async def join_combined(self, name: str) -> dict:
        """Join a stack's combined log the way the app's client does."""
        answer = await self.agent("terminalJoin", f"combined--{name}")
        return answer

    def chunks(self, terminal: str | None = None, *, since: int = 0) -> list[TerminalChunk]:
        collected = self.output[since:]
        if terminal is None:
            return collected
        return [chunk for chunk in collected if chunk.terminal == terminal]


def _socket_url(url: str) -> str:
    parsed = url.replace("https://", "wss://").replace("http://", "ws://")
    return f"{parsed.rstrip('/')}/socket.io/?EIO=4&transport=websocket"


@asynccontextmanager
async def session(url: str | None = None) -> AsyncIterator[Dockge]:
    """A logged-in Dockge connection, closed on the way out."""
    username, password = _login_credentials()
    target = _socket_url(url or URL)
    try:
        websocket = await websockets.connect(target, max_size=None)
    except (OSError, websockets.WebSocketException) as error:
        raise DockgeLabError(f"{target} did not answer: {error}") from error
    dockge: Dockge | None = None
    try:
        opened = await websocket.recv()
        if not isinstance(opened, str) or not opened.startswith("0"):
            raise DockgeLabError(f"unexpected Engine.IO opening: {opened!r}")
        await websocket.send("40")
        while True:
            frame = await websocket.recv()
            if isinstance(frame, str) and frame.startswith("40"):
                break
            if isinstance(frame, str) and frame.startswith("44"):
                raise DockgeLabError(f"Dockge refused the namespace: {frame[:120]}")
        dockge = Dockge(websocket)
        dockge.listen()
        answer = await dockge.call(
            "login", {"username": username, "password": password}
        )
        if not isinstance(answer, dict) or answer.get("ok") is not True:
            message = (
                answer.get("msg")
                if isinstance(answer, dict)
                else "unexpected login answer"
            )
            if isinstance(answer, dict) and answer.get("tokenRequired"):
                message = "this Dockge login wants two-factor authentication"
            # The ack carries a JWT on success; on failure only the reason leaves.
            raise DockgeLabError(f"Dockge refused the lab's login: {message}")
        yield dockge
    finally:
        if dockge is not None:
            await dockge.close()
        await websocket.close()


# ---- The marker ---------------------------------------------------------


def load_marker() -> dict:
    if not MARKER.exists():
        return {}
    try:
        return json.loads(MARKER.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise DockgeLabError(f"{MARKER} is unreadable: {error}") from error


def save_marker(marker: dict) -> None:
    MARKER.parent.mkdir(parents=True, exist_ok=True)
    MARKER.write_text(json.dumps(marker, indent=2, sort_keys=True), encoding="utf-8")


def forget_marker() -> None:
    if MARKER.exists():
        MARKER.unlink()
    if MARKER.parent.is_dir() and not any(MARKER.parent.iterdir()):
        MARKER.parent.rmdir()


# ---- The command line ---------------------------------------------------


async def _status() -> dict[str, Any]:
    async with session() as dockge:
        stacks = await dockge.refresh()
        detail = {}
        for name in dockge.names():
            row = stacks[name]
            detail[name] = {
                "status": row.get("status"),
                "label": STATUS_LABEL.get(int(row.get("status", UNKNOWN)), "?"),
                "composeFileName": row.get("composeFileName"),
            }
        return {
            "url": URL,
            "version": dockge.info.get("version"),
            "stacks": detail,
            "marker": load_marker(),
        }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "command",
        nargs="?",
        default="status",
        choices=("status", "probe", "image"),
    )
    arguments = parser.parse_args(argv)
    try:
        if arguments.command == "status":
            payload = asyncio.run(_status())
        elif arguments.command == "probe":
            payload = probe_runtime()
        else:
            payload = ensure_image()
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0
    except DockgeLabError as error:
        print(f"dockge_lab: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
