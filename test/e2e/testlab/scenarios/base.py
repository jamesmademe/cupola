"""Shared pieces for the testlab scenarios.

A scenario is a small, idempotent state change on top of the seeded lab. It
talks to the services' own APIs and never writes their databases while the
containers run. ``apply`` brings the state in, ``teardown`` takes it out, and
the two ``verify`` methods are the scenario's own acceptance: a scenario that
cannot prove its state is not done.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[4]
SCRATCH_ROOT = REPO_ROOT / ".ai" / "scratch" / "zz_testlab"
STATE_ROOT = Path(
    os.environ.get("CUPOLA_TESTLAB_STATE_DIR", SCRATCH_ROOT / "state")
).resolve()
CREDENTIALS = STATE_ROOT / "credentials.env"


class ScenarioError(RuntimeError):
    pass


def credentials() -> dict[str, str]:
    values: dict[str, str] = {}
    if not CREDENTIALS.exists():
        return values
    for line in CREDENTIALS.read_text(encoding="utf-8").splitlines():
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
    timeout: float = 15,
) -> tuple[int, Any]:
    data = None
    request_headers = {"Accept": "application/json"}
    if payload is None:
        data = None
    elif isinstance(payload, bytes):
        data = payload
    elif isinstance(payload, str):
        data = payload.encode("utf-8")
    else:
        data = json.dumps(payload).encode("utf-8")
        request_headers["Content-Type"] = "application/json"
    if headers:
        request_headers.update(headers)
    call = urllib.request.Request(
        url, data=data, method=method, headers=request_headers
    )
    client = opener or urllib.request.build_opener()
    try:
        with client.open(call, timeout=timeout) as response:
            body = response.read()
            status = response.status
    except urllib.error.HTTPError as error:
        body = error.read()
        status = error.code
    except (urllib.error.URLError, TimeoutError) as error:
        raise ScenarioError(f"{method} {url} did not answer: {error}") from error
    if not body:
        return status, None
    try:
        return status, json.loads(body)
    except json.JSONDecodeError:
        return status, body.decode("utf-8", errors="replace")


def require_ok(status: int, body: Any, what: str) -> None:
    if not 200 <= status < 300:
        raise ScenarioError(f"{what} failed with {status}: {body}")


class Scenario:
    """One named state on top of the seeded lab."""

    name = ""
    profiles: tuple[str, ...] = ()

    def apply(self) -> None:
        raise NotImplementedError

    def teardown(self) -> None:
        raise NotImplementedError

    def verify(self) -> None:
        raise NotImplementedError

    def verify_absent(self) -> None:
        raise NotImplementedError
