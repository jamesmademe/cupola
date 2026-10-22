#!/usr/bin/env python3
"""A real Plex playback session, and the stop that the server may refuse (L8).

The catalog asks for two things of Plex that the app itself cannot make: a
session playing right now (`S-07`, `S-09`), and the `Stop playback` action on
it. This script is the spike for both, and it is deliberately split into what
Plex does allow and what it does not:

  * **making the session.** `GET /:/timeline` with a real `ratingKey`, a
    duration, a position, `state=playing`, a dedicated
    `X-Plex-Client-Identifier` and the owner's token. On this server (1.43.4)
    that alone already lists a row in `/status/sessions`, but the row carries
    **no nested `Session` element**, which is the only id the app's
    `PlexClient.stopSession` sends: a session Plex draws but nobody can
    address. Reading a range of the item's own part (`/library/parts/...`)
    with the same `X-Plex-Session-Identifier` makes the server register the
    stream, and the nested `Session` appears with `bandwidth` and `location`.
    Both halves are measured, not assumed, and the report says which held;
  * **stopping it.** `POST /status/sessions/terminate?sessionId=` is a Plex
    Pass feature and needs the server owner's token. This server is claimed
    with the owner's real account but reports `myPlexSubscription: false`, so
    the spike records the server's own answer instead of pretending the action
    is there. Nothing is written to the plex.tv account: no user, no invite,
    no change of plan. Whether the call works is asked of the server, on the
    lab's own session, and then the session is ended the way the client itself
    ends one: `/:/timeline?state=stopped`, which always works and leaves no
    ghost on the Now playing surfaces.

The report (`<state>/plex-play.json`, no secret in it) is the contract
`testlab_plex_e2e_test.dart` reads for `S-07`: which of the two session shapes
the server produced, and the exact status `/status/sessions/terminate` answered.
Only the spike writes it: `play` and `stop` are the commands a person runs, and
they print their own, shorter report instead of replacing the evidence.

Usage:

    python3 test/e2e/testlab/plex_play.py            # spike, report, clean up
    python3 test/e2e/testlab/plex_play.py play       # leave a session playing
    python3 test/e2e/testlab/plex_play.py stop       # end the one left playing
    python3 test/e2e/testlab/plex_play.py check      # re-read the contract
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRATCH_ROOT = REPO_ROOT / ".ai" / "scratch" / "zz_testlab"

PLEX_URL = os.environ.get("CUPOLA_TESTLAB_PLEX_URL", "http://127.0.0.1:32400")
REPORT_NAME = "plex-play.json"
# One dedicated identity: the lab's own device row, never the app's
# (`plexClientId` in settings) and never a person's client.
CLIENT_ID = "cupola-testlab-play"
SESSION_ID = "cupola-testlab-play-session"
TERMINATE_REASON = "Cupola TestLab: the spike's own session"
PLEX_LIBRARY = "com.plexapp.plugins.library"


class PlayError(RuntimeError):
    """Plex refused a step of the spike."""


def state_root() -> Path:
    return Path(
        os.environ.get("CUPOLA_TESTLAB_STATE_DIR", SCRATCH_ROOT / "state")
    ).resolve()


def credentials(state: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    file = state / "credentials.env"
    if not file.exists():
        return values
    for line in file.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def token(state: Path) -> str:
    """The owner's server token, from the chmod-600 file. Never printed."""
    value = credentials(state).get("CUPOLA_TESTLAB_PLEX_TOKEN", "").strip()
    if not value:
        raise PlayError(
            "the lab credentials have no CUPOLA_TESTLAB_PLEX_TOKEN: run "
            "test/e2e/testlab/bootstrap.sh against a claimed Plex"
        )
    return value


def headers(state: Path, *, session: str | None = None) -> dict[str, str]:
    values = {
        "X-Plex-Token": token(state),
        "Accept": "application/json",
        "X-Plex-Client-Identifier": CLIENT_ID,
        "X-Plex-Product": "Cupola TestLab",
        "X-Plex-Version": "1.0",
        "X-Plex-Device": "Cupola TestLab",
        "X-Plex-Device-Name": "Cupola TestLab",
        "X-Plex-Platform": "macOS",
    }
    if session:
        values["X-Plex-Session-Identifier"] = session
    return values


def call(
    state: Path,
    path: str,
    *,
    method: str = "GET",
    query: dict[str, Any] | None = None,
    session: str | None = None,
    extra: dict[str, str] | None = None,
    timeout: float = 30,
) -> tuple[int, bytes]:
    url = PLEX_URL.rstrip("/") + path
    if query:
        url = f"{url}?{urllib.parse.urlencode(query)}"
    request_headers = headers(state, session=session)
    if extra:
        request_headers.update(extra)
    request = urllib.request.Request(url, headers=request_headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except (urllib.error.URLError, TimeoutError) as error:
        raise PlayError(f"{method} {path} did not answer: {error}") from error


def container(
    state: Path, path: str, *, query: dict[str, Any] | None = None
) -> dict[str, Any]:
    status, body = call(state, path, query=query)
    if not 200 <= status < 300:
        raise PlayError(f"GET {path} answered {status}")
    try:
        return json.loads(body)["MediaContainer"]
    except (json.JSONDecodeError, KeyError, TypeError) as error:
        raise PlayError(f"GET {path} did not answer a MediaContainer") from error


# ---------------------------------------------------------------------------
# The item to play
# ---------------------------------------------------------------------------


def movie_section(state: Path) -> str:
    """The Films section's key, read rather than assumed."""
    answer = container(state, "/library/sections")
    for entry in answer.get("Directory", []):
        if isinstance(entry, dict) and str(entry.get("type") or "") == "movie":
            return str(entry.get("key") or "")
    raise PlayError(
        "the server has no movie section: run test/e2e/testlab/plex_media.py "
        "first"
    )


def pick_item(state: Path) -> dict[str, Any]:
    """A real movie long enough for a session, with a part to read.

    The Films library, the longest item, and only items that carry a
    `/library/parts/...` key: a session whose part cannot be read is not a
    stream, and the spike is about the stream.
    """
    section = movie_section(state)
    answer = container(state, f"/library/sections/{section}/all", query={"type": 1})
    candidates: list[tuple[int, dict[str, Any], dict[str, Any]]] = []
    for entry in answer.get("Metadata", []):
        if not isinstance(entry, dict):
            continue
        parts = [
            part
            for media in entry.get("Media", [])
            if isinstance(media, dict)
            for part in media.get("Part", [])
            if isinstance(part, dict) and part.get("key")
        ]
        if not parts:
            continue
        candidates.append((int(entry.get("duration") or 0), entry, parts[0]))
    if not candidates:
        raise PlayError(
            "the Films library holds no movie with a media part: run "
            "test/e2e/testlab/plex_media.py first"
        )
    duration, entry, part = max(candidates, key=lambda row: row[0])
    return {"item": entry, "part": part, "duration": duration}


# ---------------------------------------------------------------------------
# The session
# ---------------------------------------------------------------------------


def sessions(state: Path) -> list[dict[str, Any]]:
    answer = container(state, "/status/sessions")
    return [
        entry for entry in answer.get("Metadata", []) if isinstance(entry, dict)
    ]


def own_sessions(state: Path) -> list[dict[str, Any]]:
    return [
        entry
        for entry in sessions(state)
        if str((entry.get("Player") or {}).get("machineIdentifier") or "")
        == CLIENT_ID
    ]


def describe(entry: dict[str, Any]) -> dict[str, Any]:
    """One session, as the app reads it and as the spike reports it."""
    player = entry.get("Player") or {}
    nested = entry.get("Session")
    return {
        "ratingKey": str(entry.get("ratingKey") or ""),
        "title": str(entry.get("title") or ""),
        "type": str(entry.get("type") or ""),
        "sessionKey": str(entry.get("sessionKey") or ""),
        "sessionId": str(nested.get("id") or "") if isinstance(nested, dict) else "",
        "bandwidth": nested.get("bandwidth") if isinstance(nested, dict) else None,
        "location": nested.get("location") if isinstance(nested, dict) else None,
        "state": str(player.get("state") or ""),
        "viewOffset": entry.get("viewOffset"),
        "duration": entry.get("duration"),
        "machineIdentifier": str(player.get("machineIdentifier") or ""),
        "product": str(player.get("product") or ""),
    }


def timeline(
    state: Path, rating_key: str, *, state_name: str, time_ms: int, duration: int
) -> int:
    status, _ = call(
        state,
        "/:/timeline",
        query={
            "ratingKey": rating_key,
            "key": f"/library/metadata/{rating_key}",
            "state": state_name,
            "time": time_ms,
            "duration": duration,
            "identifier": PLEX_LIBRARY,
        },
        session=SESSION_ID,
    )
    return status


def read_part(state: Path, part: dict[str, Any]) -> int:
    """Read a slice of the item's own part, the way a player buffers.

    This is what turns the timeline row into a stream the server registers:
    the nested `Session` element (its id, bandwidth and location) appears only
    after the part has been served. A range keeps it to half a megabyte.
    """
    status, _ = call(
        state,
        str(part["key"]),
        session=SESSION_ID,
        extra={"Range": "bytes=0-524287"},
    )
    return status


def end_session(state: Path, rating_key: str, duration: int, time_ms: int) -> None:
    """`state=stopped`: how a client ends its own session, always allowed."""
    timeline(
        state,
        rating_key,
        state_name="stopped",
        time_ms=time_ms,
        duration=duration,
    )


def wait_for_session(
    state: Path, rating_key: str, *, timeout: float = 10
) -> dict[str, Any] | None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for entry in own_sessions(state):
            if str(entry.get("ratingKey") or "") == rating_key:
                return describe(entry)
        time.sleep(0.5)
    return None


def terminate(state: Path, session_id: str) -> dict[str, Any]:
    """`POST /status/sessions/terminate`, and the server's own answer.

    401 is Plex Pass (or a token that is not the owner's), 403 is an empty
    session id, 404 is a session id the server does not know. The spike records
    the code and the body rather than translating it.
    """
    status, body = call(
        state,
        "/status/sessions/terminate",
        method="POST",
        query={"sessionId": session_id, "reason": TERMINATE_REASON},
    )
    text = body.decode("utf-8", errors="replace").strip()
    return {
        "status": status,
        "allowed": 200 <= status < 300,
        "body": text[:300],
        "meaning": _terminate_meaning(status),
    }


def _terminate_meaning(status: int) -> str:
    if 200 <= status < 300:
        return "the server stopped the stream"
    if status == 401:
        return (
            "Plex Pass: the docs put the feature here, and a server without "
            "it answers 401 whatever the token"
        )
    if status == 403:
        return "the sessionId was empty, or the token may not do this"
    if status == 404:
        return "the server does not know that session id"
    return f"the server refused with {status}"


# ---------------------------------------------------------------------------
# The spike
# ---------------------------------------------------------------------------


def server_sheet(state: Path) -> dict[str, Any]:
    answer = container(state, "/")
    # `myPlexUsername` is the real account's address and is deliberately not
    # read here: the lab never records an identity it does not own.
    return {
        "version": str(answer.get("version") or ""),
        "machineIdentifier": str(answer.get("machineIdentifier") or ""),
        "plexPass": bool(answer.get("myPlexSubscription")),
    }


def play(state: Path) -> dict[str, Any]:
    """Make the session, both halves, and report what the server produced."""
    chosen = pick_item(state)
    item = chosen["item"]
    duration = int(item.get("duration") or chosen["duration"] or 0)
    if duration <= 0:
        raise PlayError(f"{item.get('title')} has no duration to report")
    rating_key = str(item["ratingKey"])
    position = duration // 5

    # A session left by an earlier run would answer as two rows.
    for stale in own_sessions(state):
        stale_key = str(stale.get("ratingKey") or "")
        if stale_key:
            end_session(
                state,
                stale_key,
                int(stale.get("duration") or duration),
                int(stale.get("viewOffset") or 0),
            )
    time.sleep(0.5)

    status = timeline(
        state,
        rating_key,
        state_name="playing",
        time_ms=position,
        duration=duration,
    )
    if not 200 <= status < 300:
        raise PlayError(f"/:/timeline answered {status}")
    timeline_only = wait_for_session(state, rating_key, timeout=5)

    part_status = read_part(state, chosen["part"])
    consuming = wait_for_session(state, rating_key, timeout=10)
    if consuming is None:
        raise PlayError(
            "/status/sessions never listed the session, with or without a "
            "client that reads the part"
        )

    return {
        "item": {
            "ratingKey": rating_key,
            "title": str(item.get("title") or ""),
            "type": str(item.get("type") or ""),
            "duration": duration,
            "position": position,
            "part": str(chosen["part"].get("key") or ""),
        },
        "timelineOnly": timeline_only,
        "consuming": consuming,
        "partStatus": part_status,
    }


def spike(state: Path) -> dict[str, Any]:
    """The whole spike: play, ask for the stop, then end the session."""
    sheet = server_sheet(state)
    report: dict[str, Any] = {
        "plex": {"url": PLEX_URL, **sheet},
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    played = play(state)
    report.update(played)
    session_id = str((played["consuming"] or {}).get("sessionId") or "")
    report["terminate"] = (
        terminate(state, session_id)
        if session_id
        else {
            "status": None,
            "allowed": False,
            "body": "",
            "meaning": (
                "no nested Session id: the app's stopSession has nothing to "
                "send, so the call cannot even be attempted"
            ),
        }
    )
    # Always leave the lab with nobody playing, whichever answer came back.
    end_session(
        state,
        played["item"]["ratingKey"],
        played["item"]["duration"],
        played["item"]["position"],
    )
    stopped = wait_for_absence(state, played["item"]["ratingKey"], timeout=10)
    report["after"] = {
        "sessions": [describe(entry) for entry in own_sessions(state)],
        "ended": stopped,
        "endedBy": "timeline state=stopped",
    }
    report["stopped"] = report["after"]["ended"]
    return report


def wait_for_absence(state: Path, rating_key: str, *, timeout: float = 10) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not any(
            str(entry.get("ratingKey") or "") == rating_key
            for entry in own_sessions(state)
        ):
            return True
        time.sleep(0.5)
    return False


def write_report(state: Path, report: dict[str, Any]) -> Path:
    path = state / REPORT_NAME
    path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    os.chmod(path, 0o644)
    return path


def play_and_report(state: Path) -> dict[str, Any]:
    """`play`: one session left playing, for the app's Now playing surfaces.

    The report is the same contract `spike` writes, minus the terminate step.
    """
    report: dict[str, Any] = {
        "plex": {"url": PLEX_URL, **server_sheet(state)},
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    report.update(play(state))
    report["terminate"] = None
    report["after"] = {"sessions": [describe(entry) for entry in own_sessions(state)]}
    report["stopped"] = False
    return report


def stop(state: Path) -> dict[str, Any]:
    """`stop`: end whatever this identity left playing, then report it."""
    report: dict[str, Any] = {
        "plex": {"url": PLEX_URL, **server_sheet(state)},
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    left = own_sessions(state)
    for entry in left:
        rating_key = str(entry.get("ratingKey") or "")
        if not rating_key:
            continue
        end_session(
            state,
            rating_key,
            int(entry.get("duration") or 0),
            int(entry.get("viewOffset") or 0),
        )
    ended = not own_sessions(state)
    report["item"] = {
        "ratingKey": str(left[0].get("ratingKey") or "") if left else "",
        "title": str(left[0].get("title") or "") if left else "",
    }
    report["after"] = {
        "sessions": [describe(entry) for entry in own_sessions(state)],
        "ended": ended,
        "endedBy": "timeline state=stopped",
    }
    report["stopped"] = ended
    return report


def verify_only(state: Path) -> list[str]:
    """What the spike's contract should say, read from the server."""
    problems: list[str] = []
    path = state / REPORT_NAME
    if not path.exists():
        return [f"no {REPORT_NAME}: run test/e2e/testlab/plex_play.py"]
    report = json.loads(path.read_text(encoding="utf-8"))
    sheet = server_sheet(state)
    if report.get("plex", {}).get("plexPass") != sheet["plexPass"]:
        problems.append(
            "the report's Plex Pass flag no longer matches the server's"
        )
    if sheet["plexPass"] is False and (report.get("terminate") or {}).get(
        "allowed"
    ):
        problems.append("the report says a stop was allowed on a server with no Plex Pass")
    if not report.get("stopped"):
        problems.append("the spike's session was left playing")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(
        description="A Plex playback session, its stop, and the evidence (L8)."
    )
    parser.add_argument(
        "action",
        nargs="?",
        choices=("spike", "play", "stop", "check"),
        default="spike",
        help="spike (default: play, ask to stop, clean up), play, stop, check",
    )
    parser.add_argument(
        "--state-dir",
        default=os.environ.get(
            "CUPOLA_TESTLAB_STATE_DIR", str(state_root())
        ),
        help="the lab's disposable state directory",
    )
    arguments = parser.parse_args()
    state = Path(arguments.state_dir).resolve()
    try:
        if arguments.action == "check":
            problems = verify_only(state)
            if problems:
                raise PlayError("; ".join(problems))
            print(json.dumps({"plex-play": "verified"}, indent=2))
            return 0
        if arguments.action == "stop":
            report = stop(state)
        elif arguments.action == "play":
            report = play_and_report(state)
        else:
            report = spike(state)
        if arguments.action == "spike":
            # Only the spike owns the contract: `play` and `stop` are the
            # commands a person runs, and they must not replace the evidence
            # with their own, shorter report.
            write_report(state, report)
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0
    except PlayError as error:
        print(f"[plex-play] {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
