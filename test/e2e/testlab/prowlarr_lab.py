"""Prowlarr plumbing shared by the indexer, app and history scenarios.

The lab has one good indexer, ``Cupola testlab``, wired to the local fake
indexer on ``testlab-indexer:8088``, and four applications Prowlarr syncs to.
The scenarios add throwaway indexers and apps beside them and take them out
again; this module holds the calls they share so the three of them cannot
drift apart.

Two facts about Prowlarr 2.3.0 shape everything here, both observed on
``golden-l6``:

* Adding an indexer syncs it to the applications whose ``syncCategories``
  match the indexer's own categories, within a few seconds and without a
  command. The fake indexer advertises Movies only, so Radarr receives it and
  Sonarr, Lidarr and Readarr do not.
* Deleting an indexer does **not** remove the copy the apps hold. Only an
  ``ApplicationIndexerSync`` reconciles them, which is why every teardown here
  ends with that command and a poll of Radarr.

Nothing here prints a credential: the lab's key is the same ``test-key`` every
seeded client already carries.
"""

from __future__ import annotations

import copy
import time
import urllib.parse
from typing import Any

from scenarios.base import ScenarioError, request, require_ok

BASE = "http://127.0.0.1:9696/api/v1"
HEADERS = {"X-Api-Key": "test-key", "Accept": "application/json"}

# The indexer the seed built, and the URL of the local fake indexer.
SEEDED_INDEXER = "Cupola testlab"
LOCAL_INDEXER_URL = "http://testlab-indexer:8088"

# Prowlarr names a synced indexer in an app after its own row.
SYNC_SUFFIX = " (Prowlarr)"
SYNC_COMMAND = "ApplicationIndexerSync"

# The applications Prowlarr syncs to, with their own API root. Only Radarr's
# categories (2000) intersect the fake indexer's, so only Radarr receives it.
APPLICATIONS: dict[str, str] = {
    "Radarr": "http://127.0.0.1:7878/api/v3",
    "Sonarr": "http://127.0.0.1:8989/api/v3",
    "Lidarr": "http://127.0.0.1:8686/api/v1",
    "Readarr": "http://127.0.0.1:8787/api/v1",
}
MOVIE_APP = "Radarr"

FINISHED = ("completed", "failed", "aborted", "cancelled", "orphaned")


def call(
    path: str,
    *,
    method: str = "GET",
    payload: Any | None = None,
    timeout: float = 60.0,
) -> tuple[int, Any]:
    return request(
        f"{BASE}{path}",
        method=method,
        payload=payload,
        headers=HEADERS,
        timeout=timeout,
    )


def require(
    path: str,
    *,
    method: str = "GET",
    payload: Any | None = None,
    timeout: float = 60.0,
) -> Any:
    status, body = call(path, method=method, payload=payload, timeout=timeout)
    require_ok(status, body, f"Prowlarr {method} {path}")
    return body


def _objects(body: Any, what: str) -> list[dict]:
    if not isinstance(body, list):
        raise ScenarioError(f"Prowlarr answered {what} without a list: {body}")
    return [item for item in body if isinstance(item, dict)]


def indexers() -> list[dict]:
    return _objects(require("/indexer"), "/indexer")


def by_name(name: str) -> dict | None:
    for item in indexers():
        if item.get("name") == name:
            return item
    return None


def require_by_name(name: str) -> dict:
    item = by_name(name)
    if item is None:
        raise ScenarioError(f"Prowlarr lists no indexer called {name!r}")
    return item


def seeded() -> dict:
    """The indexer the lab is built on. Never a throwaway one."""
    item = by_name(SEEDED_INDEXER)
    if item is None:
        raise ScenarioError(
            f"the lab has no {SEEDED_INDEXER!r} indexer; reset the golden"
        )
    return item


def summary(item: dict) -> dict:
    """What a scenario promises not to change, and proves it did not."""
    return {
        "id": item.get("id"),
        "name": item.get("name"),
        "enable": bool(item.get("enable")),
        "priority": item.get("priority"),
        "appProfileId": item.get("appProfileId"),
        "tags": list(item.get("tags") or []),
    }


def field_value(item: dict, name: str) -> Any:
    for field in item.get("fields") or []:
        if isinstance(field, dict) and field.get("name") == name:
            return field.get("value")
    return None


def default_app_profile() -> int:
    profiles = _objects(require("/appprofile"), "/appprofile")
    if not profiles:
        raise ScenarioError("Prowlarr has no sync profile to add an indexer with")
    standard = next(
        (item for item in profiles if item.get("name") == "Standard"), profiles[0]
    )
    profile_id = standard.get("id")
    if not isinstance(profile_id, int):
        raise ScenarioError(f"Prowlarr's sync profile has no id: {standard}")
    return profile_id


def create(name: str) -> dict:
    """Add a throwaway Torznab indexer on the local fake indexer."""
    schema = require("/indexer/schema", timeout=120)
    if not isinstance(schema, list):
        raise ScenarioError("Prowlarr answered /indexer/schema without a list")
    definition = next(
        (
            item
            for item in schema
            if isinstance(item, dict)
            and item.get("definitionName") == "Torznab"
            and item.get("name") == "Generic Torznab"
        ),
        None,
    )
    if definition is None:
        raise ScenarioError("Prowlarr offers no Generic Torznab definition")
    replace = {
        "baseUrl": LOCAL_INDEXER_URL,
        "apiPath": "/api",
        "apiKey": "test-key",
    }
    fields = [
        {
            "name": field.get("name"),
            "value": replace.get(field.get("name"), field.get("value")),
        }
        for field in definition.get("fields") or []
        if isinstance(field, dict)
    ]
    payload = {
        "enable": True,
        "name": name,
        "implementation": "Torznab",
        "configContract": "TorznabSettings",
        "protocol": "torrent",
        "priority": 1,
        "appProfileId": default_app_profile(),
        "fields": fields,
        "tags": [],
    }
    status, body = call("/indexer", method="POST", payload=payload)
    if status != 201 or not isinstance(body, dict) or not body.get("id"):
        raise ScenarioError(f"Prowlarr did not add {name!r}: {status} {body}")
    return body


def save(item: dict) -> dict:
    status, body = call(
        f"/indexer/{item['id']}", method="PUT", payload=item, timeout=120
    )
    if status not in (200, 202):
        raise ScenarioError(
            f"Prowlarr did not save indexer {item['id']}: {status} {body}"
        )
    return require(f"/indexer/{item['id']}")


def test_indexer(item: dict) -> None:
    """``Test`` on one indexer: a 2xx is the tracker's own answer."""
    status, body = call("/indexer/test", method="POST", payload=item, timeout=120)
    require_ok(status, body, f"Prowlarr indexer test for {item.get('name')}")


def test_refusal(item: dict, base_url: str) -> list[dict]:
    """The same test against a dead address: 400 and its validation failures.

    Prowlarr answers a failing test with HTTP 400 and a list of
    ``{propertyName, errorMessage, ...}``, which is what the app turns into
    "Test failed" plus the reason.
    """
    probe = copy.deepcopy(item)
    for field in probe.get("fields") or []:
        if isinstance(field, dict) and field.get("name") == "baseUrl":
            field["value"] = base_url
    status, body = call("/indexer/test", method="POST", payload=probe, timeout=120)
    if status != 400:
        raise ScenarioError(
            f"a test against {base_url} answered {status}, not a refusal: {body}"
        )
    failures = [
        failure
        for failure in body if isinstance(failure, dict)
    ] if isinstance(body, list) else []
    if not failures:
        raise ScenarioError(f"the refusal carried no validation failures: {body}")
    return failures


def test_all() -> list[dict]:
    """``Test all indexers``: one report per indexer, valid or not.

    Servarr answers 400 with the same report the moment one indexer is
    invalid, so the report is what is read, not the status.
    """
    status, body = call("/indexer/testall", method="POST", timeout=180)
    report = body if isinstance(body, list) else None
    if status not in (200, 400) or report is None:
        raise ScenarioError(f"Prowlarr testall answered {status}: {body}")
    if not report or not all(
        isinstance(entry, dict) and "isValid" in entry for entry in report
    ):
        raise ScenarioError(f"Prowlarr testall answered without a report: {body}")
    return report


def bulk(ids: list[int], **changes: Any) -> None:
    status, body = call(
        "/indexer/bulk", method="PUT", payload={"ids": list(ids), **changes}
    )
    if status not in (200, 202):
        raise ScenarioError(f"Prowlarr bulk update failed with {status}: {body}")


def bulk_delete(ids: list[int]) -> None:
    status, body = call("/indexer/bulk", method="DELETE", payload={"ids": list(ids)})
    require_ok(status, body, "Prowlarr bulk delete")


def sync_apps(timeout: float = 120.0) -> dict:
    """Run ``ApplicationIndexerSync`` and wait for its real outcome."""
    status, body = call("/command", method="POST", payload={"name": SYNC_COMMAND})
    if status not in (200, 201) or not isinstance(body, dict) or not body.get("id"):
        raise ScenarioError(
            f"Prowlarr did not queue {SYNC_COMMAND}: {status} {body}"
        )
    command = body
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        command = require(f"/command/{body['id']}")
        if str(command.get("status")) in FINISHED:
            break
        time.sleep(1)
    if str(command.get("status")) != "completed":
        raise ScenarioError(
            f"{SYNC_COMMAND} ended {command.get('status')}: "
            f"{command.get('message')} {command.get('exception')}"
        )
    return command


def app_indexer_names(application: str) -> list[str]:
    """The indexers one application holds, by the name it shows."""
    root = APPLICATIONS.get(application)
    if root is None:
        raise ScenarioError(f"unknown application {application!r}")
    status, body = request(
        f"{root}/indexer",
        headers={"X-Api-Key": "test-key", "Accept": "application/json"},
    )
    require_ok(status, body, f"{application} GET /indexer")
    return [
        str(item.get("name"))
        for item in _objects(body, f"{application} /indexer")
    ]


def wait_app(application: str, name: str, *, present: bool, timeout: float = 120.0) -> None:
    """Wait until an app holds (or has dropped) a synced indexer."""
    deadline = time.monotonic() + timeout
    names: list[str] = []
    while time.monotonic() < deadline:
        names = app_indexer_names(application)
        if (name in names) == present:
            return
        time.sleep(2)
    verb = "still lists" if present else "never dropped"
    raise ScenarioError(f"{application} {verb} {name!r}: {names}")


def tags() -> list[dict]:
    return _objects(require("/tag"), "/tag")


def tag_detail() -> list[dict]:
    return _objects(require("/tag/detail"), "/tag/detail")


def tag_by_label(label: str) -> dict | None:
    for item in tags():
        if item.get("label") == label:
            return item
    return None


def create_tag(label: str) -> dict:
    status, body = call("/tag", method="POST", payload={"label": label})
    if status != 201 or not isinstance(body, dict) or not body.get("id"):
        raise ScenarioError(f"Prowlarr did not create tag {label!r}: {status} {body}")
    return body


def delete_tag(tag_id: int) -> None:
    status, body = call(f"/tag/{tag_id}", method="DELETE")
    require_ok(status, body, f"Prowlarr delete tag {tag_id}")


def applications() -> list[dict]:
    return _objects(require("/applications"), "/applications")


def application_by_name(name: str) -> dict | None:
    for item in applications():
        if item.get("name") == name:
            return item
    return None


def require_application(name: str) -> dict:
    item = application_by_name(name)
    if item is None:
        raise ScenarioError(f"Prowlarr lists no application called {name!r}")
    return item


def test_application(item: dict) -> None:
    status, body = call(
        "/applications/test", method="POST", payload=item, timeout=120
    )
    require_ok(status, body, f"Prowlarr application test for {item.get('name')}")


def create_application(payload: dict) -> dict:
    status, body = call("/applications", method="POST", payload=payload, timeout=120)
    if status != 201 or not isinstance(body, dict) or not body.get("id"):
        raise ScenarioError(
            f"Prowlarr did not add application {payload.get('name')!r}: "
            f"{status} {body}"
        )
    return body


def delete_application(app_id: int) -> None:
    status, body = call(f"/applications/{app_id}", method="DELETE")
    require_ok(status, body, f"Prowlarr delete application {app_id}")


def search(indexer_id: int, query: str, *, limit: int = 100) -> list[dict]:
    """One Prowlarr search on one indexer, which is a history row."""
    parameters = urllib.parse.urlencode(
        {
            "query": query,
            "indexerIds": indexer_id,
            "categories": 2000,
            "type": "search",
            "limit": limit,
            "offset": 0,
        }
    )
    return _objects(
        require(f"/search?{parameters}", timeout=180), "/search"
    )


# Prowlarr's ``eventType`` is the numeric ``HistoryEventType``: 1 is a grab,
# 2 an indexer query, 3 an RSS poll. It refuses the names the app sends (see
# ``scenarios/prowlarr_history.py``), so this module only ever sends numbers.
EVENT_GRABBED = 1
EVENT_QUERY = 2
EVENT_RSS = 3


def history(
    *, page: int = 1, page_size: int = 100, event_type: int | None = None
) -> dict:
    parameters = {
        "page": page,
        "pageSize": page_size,
        "sortKey": "date",
        "sortDirection": "descending",
    }
    if event_type:
        parameters["eventType"] = event_type
    body = require(f"/history?{urllib.parse.urlencode(parameters)}")
    if not isinstance(body, dict) or not isinstance(body.get("records"), list):
        raise ScenarioError(f"Prowlarr answered /history without a page: {body}")
    return body


def indexer_history(indexer_id: int, *, limit: int = 30) -> list[dict]:
    parameters = urllib.parse.urlencode({"indexerId": indexer_id, "limit": limit})
    return _objects(require(f"/history/indexer?{parameters}"), "/history/indexer")


def indexer_stats() -> dict:
    body = require("/indexerstats")
    if not isinstance(body, dict):
        raise ScenarioError(f"Prowlarr answered /indexerstats without an object: {body}")
    return body


def indexer_status() -> list[dict]:
    return _objects(require("/indexerstatus"), "/indexerstatus")
