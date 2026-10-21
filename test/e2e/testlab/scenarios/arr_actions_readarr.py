"""Readarr's writes on the seeded library: profile, monitoring, the searches.

Rows A-04 and A-06 of the flow catalogue, on one of the six authors L6a writes
straight into Readarr's database. The scenario changes the author, reads the
record back, posts the two searches the app's author page and Wanted tab post,
and puts the author back on teardown.

Two rows of the catalogue are declared rather than written, and the reasons are
in the lab, not in the client:

* A-03, adding an author: Readarr says authors are added in Readarr itself, and
  the app offers no action. Nothing to write.
* A-07, removing an author: the client has ``deleteAuthor``
  (``readarr_service.dart``), but Readarr's metadata host is unreachable
  offline, so ``POST /author`` answers 500 and ``GET /author/lookup`` answers
  503: the lab cannot create a throwaway author. Deleting one of the six
  seeded authors would lose a record that only stopping the container and
  rewriting ``readarr.db`` could bring back, which the lab rules forbid. The
  e2e test holds the evidence for both answers.
"""

from __future__ import annotations

import json

from .base import STATE_ROOT, Scenario, ScenarioError, request, require_ok

READARR = "http://127.0.0.1:8787/api/v1"
HEADERS = {"X-Api-Key": "test-key"}
TARGET = "Jules Verne"
BACKUP = STATE_ROOT / "backup" / "arr_actions_readarr"
MARKER = BACKUP / "state.json"

COMMAND_STATES = ("queued", "started", "completed", "failed", "aborted")


def _call(
    path: str,
    method: str = "GET",
    payload: object | None = None,
    timeout: float = 30,
) -> tuple[int, object]:
    return request(
        f"{READARR}{path}",
        method=method,
        payload=payload,
        headers=HEADERS,
        timeout=timeout,
    )


def _read(
    path: str,
    method: str = "GET",
    payload: object | None = None,
    timeout: float = 30,
) -> object:
    status, body = _call(path, method, payload, timeout)
    require_ok(status, body, f"Readarr {method} {path}")
    return body


def _authors() -> list[dict]:
    body = _read("/author")
    if not isinstance(body, list):
        raise ScenarioError("Readarr answered the author list with something else")
    return [item for item in body if isinstance(item, dict)]


def _author_named(name: str) -> dict | None:
    for author in _authors():
        if author.get("authorName") == name:
            return author
    return None


def _require_author(name: str) -> dict:
    author = _author_named(name)
    if author is None:
        raise ScenarioError(
            f"Readarr has no author named {name!r}. The lab's library is the six "
            "authors of golden-l6 (scenario readarr-library); reset the lab "
            "before applying this scenario."
        )
    return author


def _put_author(author_id: int, fields: dict) -> dict:
    """Read the record whole and put it back whole, as the client does."""
    current = _read(f"/author/{author_id}")
    if not isinstance(current, dict):
        raise ScenarioError(f"Readarr answered author {author_id} with something else")
    current.update(fields)
    updated = _read(f"/author/{author_id}", "PUT", current)
    if not isinstance(updated, dict):
        raise ScenarioError(f"Readarr answered the update of {author_id} with nothing")
    return updated


def _quality_profiles() -> list[dict]:
    body = _read("/qualityprofile")
    if not isinstance(body, list):
        raise ScenarioError("Readarr answered the quality profiles with something else")
    return [item for item in body if isinstance(item, dict)]


def _other_profile(profiles: list[dict], current: object) -> int:
    for profile in profiles:
        if isinstance(profile.get("id"), int) and profile["id"] != current:
            return profile["id"]
    raise ScenarioError("Readarr has a single quality profile, so nothing can change")


def _post_command(payload: dict) -> dict:
    created = _read("/command", "POST", payload)
    if not isinstance(created, dict) or not created.get("id"):
        raise ScenarioError(f"Readarr did not accept the {payload.get('name')} command")
    return created


def _command(command_id: int) -> dict:
    command = _read(f"/command/{command_id}")
    if not isinstance(command, dict):
        raise ScenarioError(f"Readarr answered command {command_id} with something else")
    return command


def _marker() -> dict:
    if not MARKER.exists():
        return {}
    try:
        value = json.loads(MARKER.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ScenarioError(f"the scenario's marker is unreadable: {error}") from error
    return value if isinstance(value, dict) else {}


def _save(marker: dict) -> None:
    BACKUP.mkdir(parents=True, exist_ok=True)
    MARKER.write_text(json.dumps(marker, indent=2, sort_keys=True) + "\n", encoding="utf-8")


class ArrActionsReadarr(Scenario):
    name = "arr-actions-readarr"
    profiles = ("core",)

    def apply(self) -> None:
        marker = _marker()
        author = _require_author(TARGET)
        if "original" not in marker:
            marker["original"] = {
                key: author.get(key)
                for key in ("qualityProfileId", "monitored", "monitorNewItems")
            }
            marker["author"] = author["id"]
            _save(marker)
        original = marker["original"]
        applied = {
            "qualityProfileId": _other_profile(
                _quality_profiles(), original.get("qualityProfileId")
            ),
            "monitored": not bool(original.get("monitored")),
        }
        marker["applied"] = applied
        _save(marker)
        _put_author(author["id"], applied)

        books = _read(f"/book?authorId={author['id']}")
        book_ids = [
            book["id"]
            for book in books or []
            if isinstance(book, dict) and isinstance(book.get("id"), int)
        ]
        if not book_ids:
            raise ScenarioError(f"Readarr's {TARGET} has no book to search")
        searches = []
        for payload in (
            {"name": "AuthorSearch", "authorId": author["id"]},
            {"name": "BookSearch", "bookIds": [book_ids[0]]},
        ):
            command = _post_command(payload)
            searches.append({"id": command["id"], "payload": payload})
        marker["searches"] = searches
        _save(marker)

    def teardown(self) -> None:
        marker = _marker()
        author_id = marker.get("author")
        original = marker.get("original")
        if isinstance(author_id, int) and isinstance(original, dict):
            _put_author(author_id, original)

    def verify(self) -> None:
        marker = _marker()
        author_id = marker.get("author")
        applied = marker.get("applied") or {}
        if not isinstance(author_id, int) or not applied:
            raise ScenarioError("the scenario has no applied state to verify")
        author = _read(f"/author/{author_id}")
        for key, value in applied.items():
            if author.get(key) != value:
                raise ScenarioError(
                    f"Readarr kept {key}={author.get(key)!r} instead of {value!r}"
                )
        original = marker.get("original") or {}
        for key in ("metadataProfileId", "monitorNewItems"):
            if key in original and author.get(key) != original[key]:
                raise ScenarioError(
                    f"the profile change moved {key} to {author.get(key)!r}"
                )

        searches = marker.get("searches") or []
        if len(searches) != 2:
            raise ScenarioError("the scenario did not post both searches")
        for search in searches:
            payload = search.get("payload") or {}
            command = _command(int(search["id"]))
            if command.get("name") != payload.get("name"):
                raise ScenarioError(
                    f"command {search['id']} is {command.get('name')!r}, "
                    f"not {payload.get('name')!r}"
                )
            body = command.get("body") or {}
            for key, value in payload.items():
                if key == "name":
                    continue
                if body.get(key) != value:
                    raise ScenarioError(
                        f"command {search['id']} carries {key}={body.get(key)!r}, "
                        f"not {value!r}"
                    )
            if command.get("status") not in COMMAND_STATES:
                raise ScenarioError(
                    f"command {search['id']} is in an unknown state: "
                    f"{command.get('status')!r}"
                )

        if _author_named(TARGET) is None:
            raise ScenarioError(f"Readarr lost {TARGET}")

    def verify_absent(self) -> None:
        marker = _marker()
        if not marker:
            return
        author_id = marker.get("author")
        original = marker.get("original") or {}
        if isinstance(author_id, int) and original:
            author = _read(f"/author/{author_id}")
            for key, value in original.items():
                if author.get(key) != value:
                    raise ScenarioError(
                        f"{TARGET}'s {key} is {author.get(key)!r}, not the lab's {value!r}"
                    )
        MARKER.unlink(missing_ok=True)
        if BACKUP.exists() and not any(BACKUP.iterdir()):
            BACKUP.rmdir()


SCENARIO = ArrActionsReadarr()
