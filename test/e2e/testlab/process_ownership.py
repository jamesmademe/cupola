"""Which host process the lab started, and who may stop it.

The control API keeps the scenario objects in memory, but a teardown may be a
separate CLI invocation. Ownership therefore lives in a small file beside the
state, not in an instance attribute: one process starts the edge or the
gateway, another can stop exactly that process, and neither touches a server
the lab did not start.
"""

from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import time
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
STATE_ROOT = Path(
    os.environ.get(
        "CUPOLA_TESTLAB_STATE_DIR", REPO_ROOT / ".ai/scratch/zz_testlab/state"
    )
)
if not STATE_ROOT.is_absolute():
    STATE_ROOT = REPO_ROOT / STATE_ROOT
STATE_ROOT = STATE_ROOT.resolve()

#: Beside the state root, not inside it: a snapshot restores the lab's data,
#: not the identity of a process that was running when the snapshot was made.
OWNERSHIP_FILE = STATE_ROOT.parent / "processes.json"


def _load() -> dict[str, Any]:
    if not OWNERSHIP_FILE.exists():
        return {}
    try:
        payload = json.loads(OWNERSHIP_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise RuntimeError(
            f"the lab's process ownership file is unreadable: {OWNERSHIP_FILE}: "
            f"{error}"
        ) from error
    return payload if isinstance(payload, dict) else {}


def _save(records: dict[str, Any]) -> None:
    OWNERSHIP_FILE.parent.mkdir(parents=True, exist_ok=True)
    temporary = OWNERSHIP_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(records, indent=2, sort_keys=True) + "\n")
    temporary.replace(OWNERSHIP_FILE)


def record(name: str) -> dict[str, Any] | None:
    return _load().get(name)


def claim(name: str, pid: int, port: int, owner: str, marker: str) -> None:
    records = _load()
    records[name] = {
        "pid": pid,
        "port": port,
        "owner": owner,
        "marker": marker,
        "startedAt": time.time(),
    }
    _save(records)


def release(name: str, owner: str | None = None) -> None:
    records = _load()
    held = records.get(name)
    if held is None:
        return
    if owner is not None and held.get("owner") != owner:
        return
    records.pop(name, None)
    _save(records)


def describe(pid: int) -> str:
    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "command="],
        text=True,
        capture_output=True,
        timeout=10,
    )
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except (ProcessLookupError, PermissionError):
        return False
    return True


def _belongs(name: str, pid: int, port: int, marker: str) -> bool:
    command = describe(pid)
    if not command:
        return False
    # The port as a whole number: `--port 846` must not match `--port 8466`.
    return marker in command and re.search(rf"--port {port}(?!\d)", command) is not None


def stop(
    name: str,
    *,
    marker: str,
    port: int,
    owner: str | None = None,
    legacy_pid_file: Path | None = None,
) -> bool:
    """Stop the process the lab owns, or leave every other process alone.

    Returns whether a process was stopped or a stale record was cleared. A
    record owned by someone else, or a live PID whose command is no longer the
    lab's server, is never signalled.
    """
    held = record(name)
    if held is not None:
        if owner is not None and held.get("owner") != owner:
            return False
        pid = int(held.get("pid") or 0)
        if pid and alive(pid):
            if not _belongs(name, pid, int(held.get("port") or port), marker):
                # The PID was reused by somebody else. Drop the claim and do
                # not touch the process.
                release(name)
                return False
            os.kill(pid, signal.SIGTERM)
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and alive(pid):
                time.sleep(0.2)
            if alive(pid):
                # Still ours: a server that ignored the polite signal.
                if _belongs(name, pid, int(held.get("port") or port), marker):
                    os.kill(pid, signal.SIGKILL)
        release(name)
        return True

    if owner is not None or legacy_pid_file is None or not legacy_pid_file.exists():
        return False
    try:
        pid = int(legacy_pid_file.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        legacy_pid_file.unlink(missing_ok=True)
        return False
    try:
        if pid and alive(pid) and _belongs(name, pid, port, marker):
            os.kill(pid, signal.SIGTERM)
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and alive(pid):
                time.sleep(0.2)
            if alive(pid) and _belongs(name, pid, port, marker):
                os.kill(pid, signal.SIGKILL)
            return True
    finally:
        legacy_pid_file.unlink(missing_ok=True)
    return False
