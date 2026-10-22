#!/usr/bin/env python3
"""The main Seerr's world: two household members and every request state.

The lab's Seerr (Compose service `seerr`, 127.0.0.1:5055) already holds the
operator (the API key) and two requester accounts the bootstrap makes. This
script adds what the flows of the catalog read (G-15 to G-23, G-39, G-40):

  1. two local members, **Anna** and **Luca**, with different permissions and
     quotas. Anna may only ask. Luca may also ask for 4K, use the advanced
     options, and has anything he asks approved on the spot. The Jellyfin user
     Seerr imported stays request-only.
  2. seven requests, one per state the catalog reads: waiting, approved and
     processing in Radarr, available (the movie is already in Radarr with a
     file), declined, failed, a series asking for some of its seasons, and a
     4K request waiting for approval.
  3. one open issue with two comments, and Anna's watchlist.
  4. three titles left free for the flows' own requests: a movie to ask for, a
     series to ask a season of, and a movie the approval test sends to Radarr.
     A free title is one with no Seerr media row and no request; the two movies
     are also absent from Radarr. They are picked from candidate lists at every
     run, so a run that stopped halfway still leaves free ones behind.

The world adds no arr to Seerr's settings beyond the Radarr and Sonarr the
bootstrap connects: `testlab_seerr_p5_e2e_test.dart` reads exactly those two.

Everything is done through Seerr's own HTTP API, with the API key; `X-Api-User`
makes a request as a member. Nothing writes the database under a running
container, and every step is idempotent: a second run reads what is there and
only moves it back to the state this file describes. When a test moved a
request on, the seed brings it back: a declined one is declined again, an
approved one is withdrawn and made again (Seerr has no transition back to
waiting), so the id to read is always the one in this file.

The state file, `<state>/seerr-world.json` (0600, never printed, never
committed), is the contract the e2e tests read:

    {
      "seerr": {"url": "http://127.0.0.1:5055", "apiKey": "<operator key>",
                "version": "3.4.1"},
      "generatedAt": "<ISO 8601>",
      "anna": {
        "id": 4, "username": "anna", "email": "anna@example.test",
        "password": "<generated, 0600>",
        "permissions": 32, "permissionNames": ["REQUEST"],
        "quota": {"movie": {"limit": 3, "days": 7, "used": 1,
                            "remaining": 2},
                  "tv":    {"limit": 6, "days": 7, "used": 2,
                            "remaining": 4}}
      },
      "luca": { ... same shape, permissions 12192 ... },
      "people": {"anna": <the anna object>, "luca": <the luca object>},
      "jellyfin": {
        "seerrUserId": 3, "username": "cupola-viewer",
        "jellyfinUserId": "<Jellyfin id>", "permissions": 32,
        "password": {"file": "credentials.env",
                     "key": "CUPOLA_TESTLAB_JELLYFIN_REQUESTER_PASSWORD"}
      },
      "titles": {
        "ask":     {"tmdbId": 329865, "title": "Arrival"},
        "series":  {"tmdbId": 76331, "title": "Succession", "season": 1},
        "approve": {"tmdbId": 545611,
                    "title": "Everything Everywhere All at Once"}
      },
      "requests": {
        "pending":    {<request row>},   # Anna's, waits for the operator
        "processing": {<request row>},   # approved, in Radarr, no file yet
        "available":  {<request row>},   # completed, the movie has a file
        "declined":   {<request row>},
        "failed":     {<request row>},   # the folder it named is not there
        "partial":    {<request row>},   # a series, some of its seasons
        "4k":         {<request row>}    # waits, Luca may ask for 4K
      },
      "issues": [ {<issue row>} ],
      "watchlist": [ {"tmdbId": 238, "mediaType": "movie",
                      "title": "The Godfather"}, ... ],
      "servers": {"radarr": {...}, "sonarr": {...}}
    }

`people` is the same two accounts under the key
`testlab_seerr_flows_e2e_test.dart` reads; both spellings are written from one
object in the same run, so they cannot disagree.

A request row is:

    {
      "id": 23, "status": 2, "statusName": "approved",
      "is4k": false, "mediaType": "movie", "tmdbId": 45745,
      "title": "Sintel", "owner": "luca", "requestedBy": 5,
      "mediaId": 22, "mediaStatus": 3, "mediaStatusName": "processing",
      "seasons": null,
      "server": {"kind": "radarr", "id": 22, "profileId": 1,
                 "rootFolder": "/media/movies", "hasFile": false}
    }

`mediaStatus` is `status4k` for a 4K request, and `status` otherwise. `server`
is what the *arr really holds, read from the *arr's own API; it is absent when
the request never reached one. A failed row carries `failure: {reason}` and,
when the folder was the cause, the `rootFolder` it asked for.

The world has two deliberate limits, both imposed by the lab:

* The failed request is real, but it fails on the destination rather than on a
  server: it is made with a root folder Radarr does not have
  (`/media/movies-4k`), Luca's account has it approved at once, Radarr refuses
  the movie and Seerr marks the request failed. A separate unreachable 4K
  Radarr would have been the other way, and it is not there because Seerr's
  settings must keep exactly the two arrs the P5 test reads.
* A series request that Seerr *approves* makes Sonarr add that series. The
  lab's Sonarr holds exactly the ten seeded series and
  `testlab_arr_sonarr_e2e_test.dart` pins that count, so the series request of
  this world stays waiting for approval. Approving it inside a test would make
  Sonarr hold eleven series.

Usage:
  python3 test/e2e/testlab/seerr_world.py --state-dir .ai/scratch/zz_testlab/state
  python3 test/e2e/testlab/seerr_world.py --state-dir ... --check  # verify only
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = "http://127.0.0.1"
SEERR_URL = f"{ROOT}:5055"
RADARR_URL = f"{ROOT}:7878"
# The lab's Radarr and Sonarr share one key; the seed writes it into Seerr's
# settings, so reading the arrs back uses the same one.
ARR_KEY = "test-key"

# Seerr's permission bits (`server/lib/permissions.ts`), the ones this world uses.
REQUEST = 32
AUTO_APPROVE = 128
AUTO_APPROVE_MOVIE = 256
AUTO_APPROVE_TV = 512
REQUEST_4K = 1024
REQUEST_4K_MOVIE = 2048
REQUEST_ADVANCED = 8192

ANNA_PERMISSIONS = REQUEST
LUCA_PERMISSIONS = (
    REQUEST
    | REQUEST_4K
    | REQUEST_4K_MOVIE
    | REQUEST_ADVANCED
    | AUTO_APPROVE
    | AUTO_APPROVE_MOVIE
    | AUTO_APPROVE_TV
)

PERMISSION_NAMES = {
    REQUEST: "REQUEST",
    AUTO_APPROVE: "AUTO_APPROVE",
    AUTO_APPROVE_MOVIE: "AUTO_APPROVE_MOVIE",
    AUTO_APPROVE_TV: "AUTO_APPROVE_TV",
    REQUEST_4K: "REQUEST_4K",
    REQUEST_4K_MOVIE: "REQUEST_4K_MOVIE",
    REQUEST_ADVANCED: "REQUEST_ADVANCED",
}

# Request status, as `SeerrRequest` in the app decodes it.
PENDING = 1
APPROVED = 2
DECLINED = 3
FAILED = 4
COMPLETED = 5

REQUEST_STATUS_NAMES = {
    PENDING: "pendingApproval",
    APPROVED: "approved",
    DECLINED: "declined",
    FAILED: "failed",
    COMPLETED: "completed",
}

# Media status, as `SeerrMediaAvailability` in the app decodes it (Seerr 3.x,
# where 6 is the blocklist and 7 is deleted).
MEDIA_STATUS_NAMES = {
    1: "unknown",
    2: "pending",
    3: "processing",
    4: "partiallyAvailable",
    5: "available",
    6: "blocklisted",
    7: "deleted",
}

# Issue type and status (`server/constants/issue.ts`).
ISSUE_VIDEO = 1
ISSUE_OPEN = 1

STATE_FILE = "seerr-world.json"

# The world's people. The emails are Seerr's local account keys, so the seed
# finds an existing account instead of making a second one.
ANNA = {
    "key": "anna",
    "username": "anna",
    "email": "anna@example.test",
    "permissions": ANNA_PERMISSIONS,
    "movieQuotaLimit": 3,
    "movieQuotaDays": 7,
    "tvQuotaLimit": 6,
    "tvQuotaDays": 7,
}
LUCA = {
    "key": "luca",
    "username": "luca",
    "email": "luca@example.test",
    "permissions": LUCA_PERMISSIONS,
    "movieQuotaLimit": 20,
    "movieQuotaDays": 7,
    "tvQuotaLimit": 20,
    "tvQuotaDays": 7,
}

# The folder the failed request asks for: the operator typed a 4K library the
# lab's Radarr does not mount, and Radarr refuses the movie for it.
FAILED_ROOT_FOLDER = "/media/movies-4k"

# The titles of the world. Every one is in `state/world.json` except the two
# 4K ones, the failed one and the free ones, which Radarr holds or not.
ALIEN = 348  # Anna asks, the operator has not answered yet
JAWS = 578  # Anna asks, the operator declines
SINTEL = 45745  # Luca asks, approved, in Radarr without a file
BIG_BUCK_BUNNY = 10378  # Luca asks, already in Radarr with a file
NOSFERATU = 653  # Luca asks the 4K copy, it waits
BROOKLYN_NINE_NINE = 48891  # Anna asks two of its eight seasons
INTERSTELLAR = 157336  # Luca asks, approved into a folder Radarr has not

# Titles left free for the flows' own requests. The seed picks the first of
# each list with no Seerr media row (and, for a movie, one Radarr does not
# hold), so a run that stopped halfway leaves the next one free.
ASK_MOVIES = (
    (329865, "Arrival"),
    (438631, "Dune"),
    (872585, "Oppenheimer"),
)
APPROVE_MOVIES = (
    (545611, "Everything Everywhere All at Once"),
    (414906, "The Batman"),
    (509, "Notting Hill"),
)
ASK_SERIES = (
    (76331, "Succession"),
    (136315, "The Bear"),
    (67070, "Fleabag"),
)

# Seerr's media id of Big Buck Bunny, the title the issue is about. The seed
# reads it back from the request it made, so this is a fallback only.
BIG_BUCK_BUNNY_SEERR_MEDIA = 19

ISSUE_MESSAGE = (
    "The last ten minutes play with the sound out of step, on the television "
    "and in the browser alike."
)
ISSUE_REPLY = (
    "Reproduced here too: the audio track is about a second late from 1:12:00."
)

WATCHLIST = (
    (238, "movie", "The Godfather"),
    (95396, "tv", "Severance"),
)


def log(message: str) -> None:
    print(f"[seerr-world] {message}")


def request(
    url: str,
    *,
    method: str = "GET",
    payload: Any | None = None,
    headers: dict[str, str] | None = None,
    timeout: float = 30,
) -> tuple[int, bytes]:
    body: bytes | None
    request_headers = dict(headers or {})
    if payload is None:
        body = None
    elif isinstance(payload, bytes):
        body = payload
    else:
        body = json.dumps(payload).encode()
        request_headers.setdefault("Content-Type", "application/json")
    request_object = urllib.request.Request(
        url, data=body, headers=request_headers, method=method
    )
    try:
        with urllib.request.urlopen(request_object, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        # The body is the useful part of a refusal: Seerr answers with JSON
        # that says what is wrong.
        return error.code, error.read()


def password() -> str:
    return secrets.token_urlsafe(18)


class SeerrError(RuntimeError):
    pass


class World:
    """One run: the state directory, its files, and Seerr's own answers."""

    def __init__(self, state_dir: Path, url: str = SEERR_URL) -> None:
        self.state_dir = state_dir
        self.url = url.rstrip("/")
        self.state_path = state_dir / STATE_FILE
        self.credentials = state_dir / "credentials.env"
        self.seerr_settings = state_dir / "seerr" / "settings.json"
        self.state: dict[str, Any] = self._read_state()
        self._key = ""

    # ------------------------------------------------------------ plumbing

    def _read_state(self) -> dict[str, Any]:
        if not self.state_path.exists():
            return {}
        try:
            value = json.loads(self.state_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}
        return value if isinstance(value, dict) else {}

    def save(self) -> None:
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        payload = json.dumps(self.state, indent=2, sort_keys=True) + "\n"
        temporary = self.state_path.with_suffix(".tmp")
        temporary.write_text(payload, encoding="utf-8")
        os.chmod(temporary, 0o600)
        temporary.replace(self.state_path)
        os.chmod(self.state_path, 0o600)

    def credentials_value(self, key: str) -> str:
        if not self.credentials.exists():
            return ""
        for line in self.credentials.read_text(encoding="utf-8").splitlines():
            if line.startswith("#") or "=" not in line:
                continue
            name, value = line.split("=", 1)
            if name == key:
                return value.strip()
        return ""

    def api_key(self) -> str:
        """The operator's key, from the credentials or Seerr's own settings."""
        if self._key:
            return self._key
        key = self.credentials_value("CUPOLA_TESTLAB_SEERR_API_KEY")
        if not key and self.seerr_settings.exists():
            try:
                settings = json.loads(
                    self.seerr_settings.read_text(encoding="utf-8")
                )
                key = str((settings.get("main") or {}).get("apiKey") or "")
            except (OSError, json.JSONDecodeError):
                key = ""
        if not key:
            raise SeerrError(
                "No Seerr API key: run test/e2e/testlab/bootstrap.sh, or point "
                "--state-dir at the lab's state directory."
            )
        self._key = key
        return key

    def call(
        self,
        path: str,
        *,
        method: str = "GET",
        payload: Any | None = None,
        as_user: int | None = None,
    ) -> tuple[int, Any]:
        headers = {
            "X-Api-Key": self.api_key(),
            "Accept": "application/json",
        }
        if as_user is not None:
            headers["X-Api-User"] = str(as_user)
        try:
            status, body = request(
                f"{self.url}/api/v1{path}", method=method, payload=payload,
                headers=headers,
            )
        except (urllib.error.URLError, TimeoutError) as error:
            raise SeerrError(
                f"{method} {self.url}/api/v1{path} did not answer: {error}"
            ) from error
        if not body:
            return status, None
        try:
            return status, json.loads(body)
        except json.JSONDecodeError:
            return status, body.decode("utf-8", errors="replace")

    def ok(
        self, status: int, body: Any, what: str, allowed=(200, 201, 204)
    ) -> Any:
        if status not in allowed:
            raise SeerrError(f"{what} failed with {status}: {body}")
        return body

    def get(self, path: str, what: str, as_user: int | None = None) -> Any:
        status, body = self.call(path, as_user=as_user)
        return self.ok(status, body, what, allowed=(200,))

    def arr(
        self, url: str, path: str, *, method: str = "GET", payload=None
    ) -> tuple[int, Any]:
        try:
            status, body = request(
                f"{url}/api/v3{path}",
                method=method,
                payload=payload,
                headers={"X-Api-Key": ARR_KEY, "Accept": "application/json"},
            )
        except (urllib.error.URLError, TimeoutError) as error:
            raise SeerrError(
                f"{method} {url}/api/v3{path} did not answer: {error}"
            ) from error
        if not body:
            return status, None
        try:
            return status, json.loads(body)
        except json.JSONDecodeError:
            return status, body.decode("utf-8", errors="replace")

    # --------------------------------------------------------------- users

    def users(self) -> list[dict[str, Any]]:
        listing = self.get("/user?take=500", "reading Seerr's users")
        return [
            entry
            for entry in ((listing or {}).get("results") or [])
            if isinstance(entry, dict)
        ]

    def user_by_email(self, email: str) -> dict[str, Any] | None:
        return next(
            (
                user
                for user in self.users()
                if (user.get("email") or "").lower() == email.lower()
            ),
            None,
        )

    def set_password(self, user_id: int, secret: str) -> None:
        status, body = self.call(
            f"/user/{user_id}/settings/password",
            method="POST",
            payload={"newPassword": secret},
        )
        self.ok(status, body, f"setting the password of user {user_id}")

    def set_permissions(self, user_id: int, permissions: int) -> None:
        status, body = self.call(
            f"/user/{user_id}/settings/permissions",
            method="POST",
            payload={"permissions": permissions},
        )
        self.ok(status, body, f"setting the permissions of user {user_id}")

    def set_quota(self, user_id: int, spec: dict[str, Any]) -> None:
        # The route also writes the username and the email, so both travel with
        # the quotas, unchanged.
        status, body = self.call(
            f"/user/{user_id}/settings/main",
            method="POST",
            payload={
                "username": spec["username"],
                "email": spec["email"],
                "movieQuotaLimit": spec["movieQuotaLimit"],
                "movieQuotaDays": spec["movieQuotaDays"],
                "tvQuotaLimit": spec["tvQuotaLimit"],
                "tvQuotaDays": spec["tvQuotaDays"],
            },
        )
        self.ok(status, body, f"setting the quotas of user {user_id}")

    def secret_for(self, key: str) -> str:
        """A password kept across runs, so a test's sign-in never breaks."""
        stored = self.state.get(key) or {}
        value = stored.get("password")
        if not isinstance(value, str) or not value:
            value = password()
            self.state.setdefault(key, {})["password"] = value
            self.save()
        return value

    def ensure_local(self, spec: dict[str, Any]) -> dict[str, Any]:
        key = spec["key"]
        secret = self.secret_for(key)
        user = self.user_by_email(spec["email"])
        if user is None:
            status, body = self.call(
                "/user",
                method="POST",
                payload={
                    "email": spec["email"],
                    "username": spec["username"],
                    "password": secret,
                },
            )
            self.ok(status, body, f"making {key}'s account")
            user = self.user_by_email(spec["email"])
            if user is None:
                raise SeerrError(f"Seerr did not keep {key}'s account")
            log(f"{key}: local account {user['id']} made")
        else:
            self.set_password(int(user["id"]), secret)
        user_id = int(user["id"])
        self.set_permissions(user_id, spec["permissions"])
        self.set_quota(user_id, spec)
        body = self.get(f"/user/{user_id}", f"reading {key}'s account")
        if int(body.get("permissions") or 0) != spec["permissions"]:
            raise SeerrError(
                f"{key}'s permissions are {body.get('permissions')}, not "
                f"{spec['permissions']}"
            )
        entry = {
            "id": user_id,
            "username": body.get("username") or spec["username"],
            "email": body.get("email") or spec["email"],
            "password": secret,
            "permissions": spec["permissions"],
            "permissionNames": [
                name
                for bit, name in PERMISSION_NAMES.items()
                if spec["permissions"] & bit
            ],
        }
        entry["quota"] = self.quota(user_id)
        return entry

    def quota(self, user_id: int) -> dict[str, Any]:
        """How much of each kind the account has left, as Seerr answers it."""
        body = self.get(f"/user/{user_id}/quota", "reading a quota")
        user = self.get(f"/user/{user_id}", "reading an account")
        result: dict[str, Any] = {}
        for kind, limit_key, days_key in (
            ("movie", "movieQuotaLimit", "movieQuotaDays"),
            ("tv", "tvQuotaLimit", "tvQuotaDays"),
        ):
            used = int(((body or {}).get(kind) or {}).get("used") or 0)
            limit = user.get(limit_key)
            days = user.get(days_key)
            result[kind] = {
                "limit": limit,
                "days": days,
                "used": used,
                "remaining": None if limit is None else int(limit) - used,
                "restricted": bool(((body or {}).get(kind) or {}).get("restricted")),
            }
        return result

    def ensure_imported(self) -> dict[str, Any]:
        """The Jellyfin user Seerr imported, kept request-only.

        Its password is the bootstrap's, generated into `credentials.env`;
        copying it here would be a second home for the same secret, so the
        state file names where it lives instead.
        """
        name = self.credentials_value(
            "CUPOLA_TESTLAB_JELLYFIN_REQUESTER_USERNAME"
        )
        if not name:
            name = "cupola-viewer"
        user = next(
            (
                entry
                for entry in self.users()
                if (entry.get("jellyfinUsername") or "") == name
                or (entry.get("displayName") or "") == name
            ),
            None,
        )
        if user is None:
            raise SeerrError(
                f"Seerr has no imported Jellyfin user {name!r}: the bootstrap's "
                "seed_seerr_requesters makes it before this seed runs"
            )
        user_id = int(user["id"])
        self.set_permissions(user_id, REQUEST)
        body = self.get(f"/user/{user_id}", "reading the imported user")
        if int(body.get("permissions") or 0) != REQUEST:
            raise SeerrError(
                f"the imported user's permissions are {body.get('permissions')}"
            )
        return {
            "seerrUserId": user_id,
            "username": name,
            "jellyfinUserId": body.get("jellyfinUserId"),
            "permissions": REQUEST,
            "permissionNames": ["REQUEST"],
            "password": {
                "file": "credentials.env",
                "key": "CUPOLA_TESTLAB_JELLYFIN_REQUESTER_PASSWORD",
            },
        }

    # -------------------------------------------------------------- servers

    def radarr_servers(self) -> list[dict[str, Any]]:
        servers = self.get("/settings/radarr", "reading Seerr's Radarrs")
        return [entry for entry in (servers or []) if isinstance(entry, dict)]

    def radarr_default(self) -> dict[str, Any]:
        server = next(
            (
                entry
                for entry in self.radarr_servers()
                if not entry.get("is4k") and entry.get("isDefault")
            ),
            None,
        )
        if server is None:
            raise SeerrError("Seerr has no default Radarr for standard requests")
        return server

    def sonarr_servers(self) -> list[dict[str, Any]]:
        servers = self.get("/settings/sonarr", "reading Seerr's Sonarrs")
        return [entry for entry in (servers or []) if isinstance(entry, dict)]

    def sonarr_default(self) -> dict[str, Any]:
        server = next(
            (
                entry
                for entry in self.sonarr_servers()
                if not entry.get("is4k") and entry.get("isDefault")
            ),
            None,
        )
        if server is None:
            raise SeerrError("Seerr has no default Sonarr")
        return server

    # --------------------------------------------------------------- titles

    def media_row(
        self, media_type: str, tmdb_id: int
    ) -> dict[str, Any] | None:
        info = self.media_info(media_type, tmdb_id)
        media = info.get("mediaInfo")
        return media if isinstance(media, dict) else None

    def free_titles(self) -> dict[str, Any]:
        """Three titles nobody asked for, for the flows' own requests.

        A free title has no Seerr media row and no request; a free movie is
        also one Radarr does not hold, so an approval really adds it and a
        decline leaves Radarr untouched. The first of each list that is free
        wins, so a run that stopped halfway is repaired by the next one.
        """

        def free_movie(candidates) -> dict[str, Any]:
            for tmdb_id, expected in candidates:
                if self.rows_for(tmdb_id, "movie", False):
                    continue
                if self.arr_movie(tmdb_id) is not None:
                    continue
                info = self.media_info("movie", tmdb_id)
                if info.get("mediaInfo") is not None:
                    continue
                title = str(info.get("title") or expected)
                if not title:
                    continue
                return {"tmdbId": tmdb_id, "title": title}
            raise SeerrError(
                "Every candidate movie for the flows' own requests is taken: "
                "clear a request and its media row, or add one to "
                "ASK_MOVIES/APPROVE_MOVIES in seerr_world.py."
            )

        def free_series(candidates) -> dict[str, Any]:
            for tmdb_id, expected in candidates:
                if self.rows_for(tmdb_id, "tv", False):
                    continue
                info = self.media_info("tv", tmdb_id)
                if info.get("mediaInfo") is not None:
                    continue
                title = str(info.get("name") or expected)
                seasons = [
                    int(season.get("seasonNumber") or 0)
                    for season in (info.get("seasons") or [])
                    if int(season.get("seasonNumber") or 0) > 0
                ]
                if not title or not seasons:
                    continue
                return {"tmdbId": tmdb_id, "title": title, "season": 1}
            raise SeerrError(
                "Every candidate series for the flows' own requests is taken: "
                "clear a request and its media row, or add one to ASK_SERIES "
                "in seerr_world.py."
            )

        return {
            "ask": free_movie(ASK_MOVIES),
            "series": free_series(ASK_SERIES),
            "approve": free_movie(APPROVE_MOVIES),
        }

    # ------------------------------------------------------------- requests

    def request_rows(self) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        skip = 0
        while True:
            page = self.get(
                f"/request?take=100&skip={skip}", "reading Seerr's requests"
            ) or {}
            results = [
                entry
                for entry in (page.get("results") or [])
                if isinstance(entry, dict)
            ]
            rows.extend(results)
            total = int((page.get("pageInfo") or {}).get("results") or 0)
            skip += len(results)
            if not results or skip >= total:
                return rows

    def rows_for(
        self, tmdb_id: int, media_type: str, is4k: bool
    ) -> list[dict[str, Any]]:
        return [
            row
            for row in self.request_rows()
            if (row.get("media") or {}).get("tmdbId") == tmdb_id
            and (row.get("media") or {}).get("mediaType") == media_type
            and bool(row.get("is4k")) == is4k
        ]

    def request_by_id(self, request_id: int) -> dict[str, Any]:
        return self.get(f"/request/{request_id}", "reading a request")

    def delete_request(self, request_id: int) -> None:
        status, body = self.call(f"/request/{request_id}", method="DELETE")
        self.ok(status, body, f"deleting request {request_id}")

    def set_request_status(self, request_id: int, status_code: int) -> None:
        # Seerr's route takes `approve` and `decline` only: a request cannot be
        # put back to waiting, and a completed one is not a status at all (it
        # is what an approval becomes once the title is already on the server).
        action = "decline" if status_code == DECLINED else "approve"
        status, body = self.call(
            f"/request/{request_id}/{action}", method="POST"
        )
        self.ok(status, body, f"moving request {request_id} to {action}")

    def media_info(self, media_type: str, tmdb_id: int) -> dict[str, Any]:
        path = "movie" if media_type == "movie" else "tv"
        body = self.get(f"/{path}/{tmdb_id}", f"reading {media_type} {tmdb_id}")
        return body if isinstance(body, dict) else {}

    def title_of(self, media_type: str, tmdb_id: int) -> str:
        info = self.media_info(media_type, tmdb_id)
        return str(
            info.get("title") if media_type == "movie" else info.get("name")
        ) or ""

    def create_request(self, spec: dict[str, Any]) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "mediaType": spec["mediaType"],
            "mediaId": spec["tmdbId"],
            "is4k": spec["is4k"],
        }
        if spec.get("seasons"):
            payload["seasons"] = spec["seasons"]
        # An override travels with the creation: an account that auto-approves
        # (Luca) would otherwise send the request to the server before an
        # edit could name the folder.
        payload.update(spec.get("override") or {})
        status, body = self.call(
            "/request", method="POST", payload=payload, as_user=spec["ownerId"]
        )
        if status == 409:
            # Somebody made it between the read and the write: read it again.
            rows = self.rows_for(
                spec["tmdbId"], spec["mediaType"], spec["is4k"]
            )
            if rows:
                return rows[0]
        if status == 202:
            raise SeerrError(
                f"{spec['key']}: Seerr has no season left to request: {body}"
            )
        self.ok(status, body, f"{spec['key']}: asking for {spec['title']}")
        row = self.request_by_id(int(body["id"]))
        log(f"{spec['key']}: {spec['title']} asked for, request {row['id']}")
        return row

    def pick_row(
        self, rows: list[dict[str, Any]], spec: dict[str, Any]
    ) -> dict[str, Any] | None:
        wanted = spec["wanted"]
        for row in rows:
            if int(row.get("status") or 0) == wanted:
                return row
        return rows[0] if rows else None

    def wait_request(
        self, request_id: int, wanted: int, *, seconds: float = 45
    ) -> dict[str, Any]:
        deadline = time.monotonic() + seconds
        row = self.request_by_id(request_id)
        while int(row.get("status") or 0) != wanted and time.monotonic() < deadline:
            time.sleep(1)
            row = self.request_by_id(request_id)
        return row

    def apply_override(
        self, request_id: int, media_type: str, override: dict[str, Any]
    ) -> None:
        """Names the server, profile or folder an approval will be sent with."""
        status, body = self.call(
            f"/request/{request_id}",
            method="PUT",
            payload={"mediaType": media_type, **override},
        )
        self.ok(status, body, f"editing request {request_id}")

    def ensure_request(self, spec: dict[str, Any]) -> dict[str, Any]:
        """One request in one state, made or brought back to it."""
        rows = self.rows_for(spec["tmdbId"], spec["mediaType"], spec["is4k"])
        row = self.pick_row(rows, spec)
        if row is not None and int(
            ((row.get("requestedBy") or {}).get("id") or 0)
        ) != spec["ownerId"]:
            # The operator may have moved it to somebody else: this world's
            # requests belong to its own members.
            self.delete_request(int(row["id"]))
            rows = [entry for entry in rows if entry["id"] != row["id"]]
            row = None
        if row is None:
            row = self.create_request(spec)
            rows = self.rows_for(
                spec["tmdbId"], spec["mediaType"], spec["is4k"]
            )
        request_id = int(row["id"])
        if spec["mediaType"] == "movie":
            # Seerr keeps one request per movie (declined and completed ones
            # excepted), so any other row for the same title is a leftover.
            for extra in rows:
                if int(extra["id"]) != request_id:
                    self.delete_request(int(extra["id"]))
        override = spec.get("override") or {}
        if override and any(
            row.get(field) != value for field, value in override.items()
        ):
            self.apply_override(request_id, spec["mediaType"], override)
            row = self.request_by_id(request_id)
        current = int(row.get("status") or 0)
        if current != spec["wanted"]:
            if spec["wanted"] == PENDING:
                # Seerr takes no `pending` transition back: a request that was
                # approved or failed is withdrawn, and a new one is made, which
                # is the only way a request waits again.
                self.delete_request(request_id)
                row = self.create_request(spec)
                request_id = int(row["id"])
                current = int(row.get("status") or 0)
            else:
                self.set_request_status(request_id, spec["wanted"])
                row = self.wait_request(request_id, spec["wanted"])
                current = int(row.get("status") or 0)
        if current != spec["wanted"]:
            raise SeerrError(
                f"{spec['key']}: request {request_id} reads {current}, not "
                f"{spec['wanted']}"
            )
        return self.request_by_id(request_id)

    def arr_movie(self, tmdb_id: int) -> dict[str, Any] | None:
        status, movies = self.arr(RADARR_URL, "/movie")
        if status != 200 or not isinstance(movies, list):
            raise SeerrError(f"Radarr did not list its movies ({status})")
        return next(
            (
                movie
                for movie in movies
                if isinstance(movie, dict) and movie.get("tmdbId") == tmdb_id
            ),
            None,
        )

    def request_view(
        self,
        key: str,
        owner: str,
        row: dict[str, Any],
        *,
        server: dict[str, Any] | None = None,
        reason: str | None = None,
    ) -> dict[str, Any]:
        media = row.get("media") or {}
        is4k = bool(row.get("is4k"))
        status = int(media.get("status4k") if is4k else media.get("status") or 0)
        seasons = sorted(
            int(season.get("seasonNumber") or 0)
            for season in (row.get("seasons") or [])
            if int(season.get("seasonNumber") or 0) > 0
        )
        view: dict[str, Any] = {
            "id": int(row["id"]),
            "status": int(row.get("status") or 0),
            "statusName": REQUEST_STATUS_NAMES.get(
                int(row.get("status") or 0), "unknown"
            ),
            "is4k": is4k,
            "mediaType": media.get("mediaType"),
            "tmdbId": media.get("tmdbId"),
            "title": self.title_of(
                str(media.get("mediaType") or "movie"),
                int(media.get("tmdbId") or 0),
            ),
            "owner": owner,
            "requestedBy": int(((row.get("requestedBy") or {}).get("id")) or 0),
            "mediaId": int(media.get("id") or 0),
            "mediaStatus": status,
            "mediaStatusName": MEDIA_STATUS_NAMES.get(status, "unknown"),
            "seasons": seasons or None,
        }
        if server is not None:
            view["server"] = server
        if row.get("rootFolder"):
            view["rootFolder"] = row.get("rootFolder")
        if reason is not None:
            view["failure"] = {"reason": reason}
        return view

    # --------------------------------------------------------------- issues

    def issues(self) -> list[dict[str, Any]]:
        listing = self.get(
            "/issue?take=100&sort=modified&filter=all", "reading the issues"
        )
        return [
            entry
            for entry in ((listing or {}).get("results") or [])
            if isinstance(entry, dict)
        ]

    def ensure_issue(
        self, anna_id: int, media_id: int, request_row: dict[str, Any]
    ) -> dict[str, Any]:
        issue = next(
            (
                entry
                for entry in self.issues()
                if (entry.get("createdBy") or {}).get("id") == anna_id
                and (entry.get("media") or {}).get("id") == media_id
                and int(entry.get("issueType") or 0) == ISSUE_VIDEO
            ),
            None,
        )
        if issue is None:
            # Anna may only request, and Seerr wants CREATE_ISSUES to file one:
            # the operator files it on her behalf, which Seerr supports with
            # `userId` and keeps as hers.
            status, body = self.call(
                "/issue",
                method="POST",
                payload={
                    "issueType": ISSUE_VIDEO,
                    "message": ISSUE_MESSAGE,
                    "mediaId": media_id,
                    "userId": anna_id,
                },
            )
            self.ok(status, body, "filing the issue")
            issue = next(
                (
                    entry
                    for entry in self.issues()
                    if (entry.get("createdBy") or {}).get("id") == anna_id
                    and (entry.get("media") or {}).get("id") == media_id
                    and int(entry.get("issueType") or 0) == ISSUE_VIDEO
                ),
                None,
            )
            if issue is None:
                raise SeerrError("Seerr did not keep the issue")
            log(f"issue {issue['id']} filed by Anna on {request_row['title']}")
        issue_id = int(issue["id"])
        if int(issue.get("status") or 0) != ISSUE_OPEN:
            # A test resolved it through the app: the world wants it open.
            status, body = self.call(
                f"/issue/{issue_id}/open", method="POST"
            )
            self.ok(status, body, f"reopening issue {issue_id}")
            log(f"issue {issue_id} reopened")
        if len(issue.get("comments") or []) < 2:
            status, body = self.call(
                f"/issue/{issue_id}/comment",
                method="POST",
                payload={"message": ISSUE_REPLY},
            )
            self.ok(status, body, f"commenting on issue {issue_id}")
        issue = self.get(f"/issue/{issue_id}", "reading the issue")
        return issue

    def issue_view(self, issue: dict[str, Any], names: dict[int, str]) -> dict:
        media = issue.get("media") or {}
        created_by = int(((issue.get("createdBy") or {}).get("id")) or 0)
        comments = []
        for comment in issue.get("comments") or []:
            user_id = int(((comment.get("user") or {}).get("id")) or 0)
            comments.append(
                {
                    "id": int(comment.get("id") or 0),
                    "userId": user_id,
                    "by": names.get(user_id, "someone"),
                    "message": comment.get("message"),
                }
            )
        comments.sort(key=lambda entry: entry["id"])
        return {
            "id": int(issue["id"]),
            "status": int(issue.get("status") or 0),
            "statusName": "open"
            if int(issue.get("status") or 0) == ISSUE_OPEN
            else "resolved",
            "issueType": int(issue.get("issueType") or 0),
            "issueTypeName": "video",
            "createdBy": created_by,
            "media": {
                "id": int(media.get("id") or 0),
                "tmdbId": media.get("tmdbId"),
                "mediaType": media.get("mediaType"),
                "title": self.title_of(
                    str(media.get("mediaType") or "movie"),
                    int(media.get("tmdbId") or 0),
                ),
            },
            "comments": comments,
        }

    # ------------------------------------------------------------ watchlist

    def watchlist(self, user_id: int) -> list[dict[str, Any]]:
        listing = self.get(
            "/discover/watchlist", "reading a watchlist", as_user=user_id
        )
        return [
            entry
            for entry in ((listing or {}).get("results") or [])
            if isinstance(entry, dict)
        ]

    def ensure_watchlist(self, user_id: int) -> list[dict[str, Any]]:
        current = {
            (entry.get("tmdbId"), entry.get("mediaType"))
            for entry in self.watchlist(user_id)
        }
        for tmdb_id, media_type, title in WATCHLIST:
            if (tmdb_id, media_type) in current:
                continue
            status, body = self.call(
                "/watchlist",
                method="POST",
                payload={
                    "tmdbId": tmdb_id,
                    "mediaType": media_type,
                    "title": title,
                },
                as_user=user_id,
            )
            if status == 409:
                # Already there, which is what this wanted anyway.
                continue
            self.ok(status, body, f"putting {title} on the watchlist")
            log(f"watchlist: {title} ({media_type} {tmdb_id})")
        return [
            {
                "tmdbId": int(entry.get("tmdbId") or 0),
                "mediaType": entry.get("mediaType"),
                "title": entry.get("title"),
            }
            for entry in self.watchlist(user_id)
        ]

    # ---------------------------------------------------------------- apply

    def apply(self) -> dict[str, Any]:
        status_body = self.get("/status", "reading Seerr's version")
        version = str((status_body or {}).get("version") or "")
        if not version:
            raise SeerrError("Seerr did not say its version")

        anna = self.ensure_local(ANNA)
        luca = self.ensure_local(LUCA)
        jellyfin = self.ensure_imported()
        if int(jellyfin["seerrUserId"]) in (int(anna["id"]), int(luca["id"])):
            raise SeerrError("the imported Jellyfin user is one of the locals")
        log(
            f"accounts: anna {anna['id']}, luca {luca['id']}, "
            f"jellyfin {jellyfin['seerrUserId']}"
        )

        radarr = self.radarr_default()
        sonarr = self.sonarr_default()

        def movie_server(tmdb_id: int) -> dict[str, Any] | None:
            movie = self.arr_movie(tmdb_id)
            if movie is None:
                return None
            return {
                "kind": "radarr",
                "id": int(movie.get("id") or 0),
                "profileId": int(movie.get("qualityProfileId") or 0),
                "rootFolder": movie.get("rootFolderPath"),
                "hasFile": bool(movie.get("hasFile")),
            }

        # 1. Waiting for the operator.
        pending = self.ensure_request(
            {
                "key": "pending",
                "ownerId": int(anna["id"]),
                "mediaType": "movie",
                "tmdbId": ALIEN,
                "is4k": False,
                "seasons": None,
                "wanted": PENDING,
                "title": "Alien",
            }
        )
        # 2. Approved, in Radarr, no file yet: the approval really landed.
        processing = self.ensure_request(
            {
                "key": "processing",
                "ownerId": int(luca["id"]),
                "mediaType": "movie",
                "tmdbId": SINTEL,
                "is4k": False,
                "seasons": None,
                "wanted": APPROVED,
                "title": "Sintel",
            }
        )
        if movie_server(SINTEL) is None:
            # Seerr's write to Radarr is asynchronous, and a retry asks again.
            self.set_request_status(int(processing["id"]), APPROVED)
        # 3. Available: the movie is already in Radarr with a file, so the
        # approval completes on its own.
        available = self.ensure_request(
            {
                "key": "available",
                "ownerId": int(luca["id"]),
                "mediaType": "movie",
                "tmdbId": BIG_BUCK_BUNNY,
                "is4k": False,
                "seasons": None,
                "wanted": COMPLETED,
                "title": "Big Buck Bunny",
            }
        )
        # 4. Declined by the operator.
        declined = self.ensure_request(
            {
                "key": "declined",
                "ownerId": int(anna["id"]),
                "mediaType": "movie",
                "tmdbId": JAWS,
                "is4k": False,
                "seasons": None,
                "wanted": DECLINED,
                "title": "Jaws",
            }
        )
        # 5. 4K, waiting: Luca may ask for 4K, and 4K is never approved by
        # itself (he has no AUTO_APPROVE_4K on purpose).
        four_k_waiting = self.ensure_request(
            {
                "key": "4k",
                "ownerId": int(luca["id"]),
                "mediaType": "movie",
                "tmdbId": NOSFERATU,
                "is4k": True,
                "seasons": None,
                "wanted": PENDING,
                "title": "Nosferatu",
            }
        )
        # 6. Failed: the operator approved it into a folder Radarr has not, so
        # Radarr refused the movie and Seerr marked the request failed.
        failed = self.ensure_request(
            {
                "key": "failed",
                "ownerId": int(luca["id"]),
                "mediaType": "movie",
                "tmdbId": INTERSTELLAR,
                "is4k": False,
                "seasons": None,
                "wanted": FAILED,
                "title": "Interstellar",
                "override": {
                    "serverId": int(radarr.get("id") or 0),
                    "profileId": int(radarr.get("activeProfileId") or 0),
                    "rootFolder": FAILED_ROOT_FOLDER,
                },
            }
        )
        # 7. A series, some of its seasons: it waits, because approving it
        # would make Sonarr hold an eleventh series (see the module docstring).
        partial = self.ensure_request(
            {
                "key": "partial",
                "ownerId": int(anna["id"]),
                "mediaType": "tv",
                "tmdbId": BROOKLYN_NINE_NINE,
                "is4k": False,
                "seasons": [1, 2],
                "wanted": PENDING,
                "title": "Brooklyn Nine-Nine",
            }
        )

        issue = self.ensure_issue(
            int(anna["id"]),
            int((available.get("media") or {}).get("id")
                or BIG_BUCK_BUNNY_SEERR_MEDIA),
            {"title": "Big Buck Bunny"},
        )
        watchlist = self.ensure_watchlist(int(anna["id"]))
        titles = self.free_titles()

        self.state = {
            "seerr": {
                "url": self.url,
                "apiKey": self.api_key(),
                "version": version,
            },
            "generatedAt": datetime.now(timezone.utc).isoformat(
                timespec="seconds"
            ),
            "anna": anna,
            "luca": luca,
            "people": {"anna": anna, "luca": luca},
            "jellyfin": jellyfin,
            "titles": titles,
            "requests": {
                "pending": self.request_view(
                    "pending", "anna", pending
                ),
                "processing": self.request_view(
                    "processing", "luca", processing,
                    server=movie_server(SINTEL),
                ),
                "available": self.request_view(
                    "available", "luca", available,
                    server=movie_server(BIG_BUCK_BUNNY),
                ),
                "declined": self.request_view(
                    "declined", "anna", declined
                ),
                "failed": self.request_view(
                    "failed", "luca", failed,
                    reason=(
                        f"Radarr has no folder "
                        f"{failed.get('rootFolder') or FAILED_ROOT_FOLDER}, so "
                        "it refused the movie"
                    ),
                ),
                "partial": self.request_view(
                    "partial", "anna", partial
                ),
                "4k": self.request_view(
                    "4k", "luca", four_k_waiting
                ),
            },
            "issues": [
                self.issue_view(
                    issue,
                    {
                        int(anna["id"]): "anna",
                        int(luca["id"]): "luca",
                        1: "operator",
                    },
                )
            ],
            "watchlist": watchlist,
        }
        self.state["servers"] = {
            "radarr": {
                "id": radarr.get("id"),
                "hostname": radarr.get("hostname"),
                "port": radarr.get("port"),
                "profileId": radarr.get("activeProfileId"),
                "rootFolder": radarr.get("activeDirectory"),
            },
            "sonarr": {
                "id": sonarr.get("id"),
                "hostname": sonarr.get("hostname"),
                "port": sonarr.get("port"),
                "profileId": sonarr.get("activeProfileId"),
                "rootFolder": sonarr.get("activeDirectory"),
            },
        }
        # The quotas are read after the requests exist, so `used` is the real
        # figure the app will read.
        self.state["anna"]["quota"] = self.quota(int(anna["id"]))
        self.state["luca"]["quota"] = self.quota(int(luca["id"]))
        self.save()
        log(f"state: {self.state_path} (chmod 600; never commit or paste it)")
        return self.state


def verify(world: World) -> list[str]:
    """Read the world back through Seerr's own API. Writes nothing."""
    checks: list[str] = []

    def ok(line: str) -> None:
        checks.append(line)
        print(f"[ok] {line}")

    status_body = world.get("/status", "reading Seerr's version")
    version = str((status_body or {}).get("version") or "")
    if not version.startswith("3."):
        raise SeerrError(f"Seerr answers version {version}, not a 3.x")
    ok(f"{world.url} is Seerr {version}")

    state = world.state
    if not state:
        raise SeerrError(f"No {world.state_path}: run the seed first")

    names: dict[int, str] = {}
    for key, spec in (("anna", ANNA), ("luca", LUCA)):
        stored = state.get(key) or {}
        user = world.user_by_email(spec["email"])
        if user is None:
            raise SeerrError(f"Seerr has no {key} at {spec['email']}")
        user_id = int(user["id"])
        names[user_id] = key
        if int(user.get("permissions") or 0) != spec["permissions"]:
            raise SeerrError(
                f"{key}'s permissions are {user.get('permissions')}, not "
                f"{spec['permissions']}"
            )
        for field in ("movieQuotaLimit", "movieQuotaDays",
                      "tvQuotaLimit", "tvQuotaDays"):
            if user.get(field) != spec[field]:
                raise SeerrError(
                    f"{key}'s {field} is {user.get(field)}, not {spec[field]}"
                )
        if stored.get("id") != user_id:
            raise SeerrError(
                f"the state file says {key} is user {stored.get('id')}, Seerr "
                f"says {user_id}: run the seed again"
            )
        ok(
            f"{key} is user {user_id}, permissions {spec['permissions']} "
            f"({', '.join(stored.get('permissionNames') or [])}), quota "
            f"{user.get('movieQuotaLimit')}/{user.get('movieQuotaDays')}d "
            f"movies and {user.get('tvQuotaLimit')}/{user.get('tvQuotaDays')}d "
            "series"
        )
    names[1] = "operator"

    jellyfin = state.get("jellyfin") or {}
    imported = next(
        (
            user
            for user in world.users()
            if int(user["id"]) == int(jellyfin.get("seerrUserId") or 0)
        ),
        None,
    )
    if imported is None:
        raise SeerrError("the imported Jellyfin user is missing")
    if int(imported.get("permissions") or 0) != REQUEST:
        raise SeerrError(
            f"the imported user's permissions are {imported.get('permissions')}"
        )
    names[int(imported["id"])] = "jellyfin"
    ok(
        f"the imported Jellyfin user {jellyfin.get('username')} is user "
        f"{imported['id']}, REQUEST alone"
    )

    radarrs = world.radarr_servers()
    sonarrs = world.sonarr_servers()
    if len(radarrs) != 1 or len(sonarrs) != 1:
        raise SeerrError(
            "Seerr's settings hold "
            f"{len(radarrs)} Radarrs and {len(sonarrs)} Sonarrs, not one each: "
            "the P5 test reads exactly those two"
        )
    default = world.radarr_default()
    ok(
        f"it knows one Radarr at {default.get('hostname')}:{default.get('port')} "
        f"({default.get('activeProfileName')}, "
        f"{default.get('activeDirectory')}) and one Sonarr at "
        f"{sonarrs[0].get('hostname')}:{sonarrs[0].get('port')}"
    )

    def one(
        key: str, tmdb_id: int, media_type: str, is4k: bool
    ) -> dict[str, Any]:
        rows = world.rows_for(tmdb_id, media_type, is4k)
        if len(rows) != 1:
            raise SeerrError(
                f"{key}: {len(rows)} requests for {media_type} {tmdb_id} "
                f"(4K {is4k}), wanted exactly 1"
            )
        return rows[0]

    def expect(
        key: str, tmdb_id: int, media_type: str, is4k: bool, wanted: int
    ) -> dict[str, Any]:
        row = one(key, tmdb_id, media_type, is4k)
        if int(row.get("status") or 0) != wanted:
            raise SeerrError(
                f"{key}: request {row['id']} reads {row.get('status')}, not "
                f"{wanted} ({REQUEST_STATUS_NAMES.get(wanted)})"
            )
        return row

    stored = state.get("requests") or {}

    row = expect("pending", ALIEN, "movie", False, PENDING)
    owner = int(((row.get("requestedBy") or {}).get("id")) or 0)
    if owner != int(state["anna"]["id"]):
        raise SeerrError("the pending request is not Anna's")
    if stored.get("pending", {}).get("id") != int(row["id"]):
        raise SeerrError(
            "the state file names another pending request: run the seed again"
        )
    media_status = int((row.get("media") or {}).get("status") or 0)
    if media_status not in (2, 3):
        raise SeerrError(
            f"the pending request's media reads {media_status}, not pending or "
            "processing"
        )
    ok(
        f"pending: {stored['pending']['title']} (tmdb {ALIEN}), request "
        f"{row['id']}, media {MEDIA_STATUS_NAMES.get(media_status)}"
    )

    row = expect("processing", SINTEL, "movie", False, APPROVED)
    owner = int(((row.get("requestedBy") or {}).get("id")) or 0)
    if owner != int(state["luca"]["id"]):
        raise SeerrError("the processing request is not Luca's")
    movie = world.arr_movie(SINTEL)
    if movie is None:
        raise SeerrError(f"Radarr does not hold movie {SINTEL}")
    if int(movie.get("qualityProfileId") or 0) != int(
        default.get("activeProfileId") or 0
    ):
        raise SeerrError(
            f"Radarr holds the processing movie with profile "
            f"{movie.get('qualityProfileId')}, not "
            f"{default.get('activeProfileId')}"
        )
    if movie.get("rootFolderPath") != default.get("activeDirectory"):
        raise SeerrError(
            f"Radarr holds the processing movie in {movie.get('rootFolderPath')}"
        )
    if movie.get("hasFile"):
        raise SeerrError(
            "the processing movie already has a file, so it is not processing"
        )
    ok(
        f"processing: {stored['processing']['title']} (tmdb {SINTEL}), request "
        f"{row['id']}, in Radarr {movie['id']} with profile "
        f"{movie.get('qualityProfileId')} and {movie.get('rootFolderPath')}"
    )

    row = expect("available", BIG_BUCK_BUNNY, "movie", False, COMPLETED)
    media_status = int((row.get("media") or {}).get("status") or 0)
    movie = world.arr_movie(BIG_BUCK_BUNNY)
    if movie is not None and not movie.get("hasFile"):
        raise SeerrError(
            "Big Buck Bunny is in Radarr without a file: the available request "
            "cannot read available (the manual import scenario takes the file "
            "away and puts it back, so run this after its teardown)"
        )
    if media_status != 5:
        raise SeerrError(
            f"the available request's media reads {media_status}, not available"
        )
    ok(
        f"available: {stored['available']['title']} (tmdb "
        f"{BIG_BUCK_BUNNY}), request {row['id']}, completed, "
        f"media available, Radarr has the file"
    )

    row = expect("declined", JAWS, "movie", False, DECLINED)
    owner = int(((row.get("requestedBy") or {}).get("id")) or 0)
    if owner != int(state["anna"]["id"]):
        raise SeerrError("the declined request is not Anna's")
    ok(f"declined: {stored['declined']['title']} (tmdb {JAWS}), request {row['id']}")

    row = expect("failed", INTERSTELLAR, "movie", False, FAILED)
    if row.get("rootFolder") != FAILED_ROOT_FOLDER:
        raise SeerrError(
            f"the failed request names {row.get('rootFolder')}, not "
            f"{FAILED_ROOT_FOLDER}"
        )
    if world.arr_movie(INTERSTELLAR) is not None:
        raise SeerrError(
            "Radarr holds the failed request's movie: the approval did not "
            "fail on its folder"
        )
    ok(
        f"failed: {stored['failed']['title']} (tmdb {INTERSTELLAR}), request "
        f"{row['id']}, approved into {FAILED_ROOT_FOLDER}, which Radarr has "
        "not"
    )

    row = expect("4k", NOSFERATU, "movie", True, PENDING)
    if not row.get("is4k"):
        raise SeerrError("the 4K request is not a 4K one")
    status4k = int((row.get("media") or {}).get("status4k") or 0)
    if status4k not in (2, 3):
        raise SeerrError(
            f"the 4K request's media reads {status4k} in 4K, not pending"
        )
    ok(
        f"4k: {stored['4k']['title']} (tmdb {NOSFERATU}), request {row['id']}, "
        f"waiting, media {MEDIA_STATUS_NAMES.get(status4k)}"
    )

    row = expect("partial", BROOKLYN_NINE_NINE, "tv", False, PENDING)
    owner = int(((row.get("requestedBy") or {}).get("id")) or 0)
    if owner != int(state["anna"]["id"]):
        raise SeerrError("the partial series request is not Anna's")
    seasons = sorted(
        int(season.get("seasonNumber") or 0)
        for season in (row.get("seasons") or [])
    )
    if seasons != [1, 2]:
        raise SeerrError(f"the partial request asks for seasons {seasons}")
    show = world.media_info("tv", BROOKLYN_NINE_NINE)
    total = len(
        [
            season
            for season in (show.get("seasons") or [])
            if int(season.get("seasonNumber") or 0) > 0
        ]
    )
    if total <= len(seasons):
        raise SeerrError(
            f"the series has {total} seasons; a partial request needs more"
        )
    ok(
        f"partial: {stored['partial']['title']} (tmdb "
        f"{BROOKLYN_NINE_NINE}), request {row['id']}, seasons {seasons} of "
        f"{total}, waiting"
    )

    if not state.get("issues"):
        raise SeerrError("the state file has no issue")
    issue = world.get(
        f"/issue/{state['issues'][0]['id']}", "reading the issue"
    )
    if int(issue.get("status") or 0) != ISSUE_OPEN:
        raise SeerrError("the issue is resolved, not open")
    if int(((issue.get("createdBy") or {}).get("id")) or 0) != int(
        state["anna"]["id"]
    ):
        raise SeerrError("the issue is not Anna's")
    comments = issue.get("comments") or []
    if len(comments) < 2:
        raise SeerrError(f"the issue has {len(comments)} comments, not two")
    authors = {
        int(((comment.get("user") or {}).get("id")) or 0)
        for comment in comments
    }
    if int(state["anna"]["id"]) not in authors:
        raise SeerrError("the issue has no comment by Anna")
    ok(
        f"issue {issue['id']} is open, filed by Anna on "
        f"{(issue.get('media') or {}).get('tmdbId')}, "
        f"{len(comments)} comments"
    )

    watchlist = world.watchlist(int(state["anna"]["id"]))
    have = {(entry.get("tmdbId"), entry.get("mediaType")) for entry in watchlist}
    missing = [
        (tmdb_id, media_type)
        for tmdb_id, media_type, _ in WATCHLIST
        if (tmdb_id, media_type) not in have
    ]
    if missing:
        raise SeerrError(f"Anna's watchlist misses {missing}")
    ok(
        "Anna's watchlist holds "
        + ", ".join(
            f"{entry.get('title')} ({entry.get('mediaType')})"
            for entry in watchlist
        )
    )

    titles = state.get("titles") or {}
    for key in ("ask", "series", "approve"):
        if not isinstance(titles.get(key), dict):
            raise SeerrError(f"the state file names no free {key} title")
    for key in ("ask", "approve"):
        tmdb_id = int(titles[key]["tmdbId"])
        if world.rows_for(tmdb_id, "movie", False):
            raise SeerrError(f"the free movie for {key} already has a request")
        if world.media_row("movie", tmdb_id) is not None:
            raise SeerrError(f"the free movie for {key} has a media row")
        if world.arr_movie(tmdb_id) is not None:
            raise SeerrError(f"Radarr already holds the free movie for {key}")
    series = int(titles["series"]["tmdbId"])
    if world.rows_for(series, "tv", False):
        raise SeerrError("the free series already has a request")
    if world.media_row("tv", series) is not None:
        raise SeerrError("the free series has a media row")
    ok(
        f"free for the flows: {titles['ask']['title']}, "
        f"{titles['series']['title']} (season {titles['series'].get('season')}), "
        f"{titles['approve']['title']}"
    )

    return checks


def run(args: argparse.Namespace) -> int:
    state_dir = Path(args.state_dir)
    if args.reset:
        (state_dir / STATE_FILE).unlink(missing_ok=True)
        log("state file removed: the next run generates new passwords")

    world = World(state_dir, args.url)
    if args.check:
        print()
        verify(world)
        return 0

    state_dir.mkdir(parents=True, exist_ok=True)
    world.apply()
    print()
    verify(world)
    print()
    print(f"The main Seerr's world is ready at {world.url}")
    print(
        f"State: {world.state_path} (chmod 600; never commit or paste it)"
    )
    return 0


def seed(state_dir: Path) -> dict[str, Any]:
    """The seed `seed_lab.py` calls, and the scenario's apply."""
    return World(Path(state_dir)).apply()


def verify_only(state_dir: Path) -> list[str]:
    return verify(World(Path(state_dir)))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Seed the main Seerr's world (L7)."
    )
    parser.add_argument(
        "--state-dir",
        default=os.environ.get(
            "CUPOLA_TESTLAB_STATE_DIR", ".ai/scratch/zz_testlab/state"
        ),
        help="the lab's disposable state directory",
    )
    parser.add_argument(
        "--url",
        default=os.environ.get("CUPOLA_TESTLAB_SEERR_URL", SEERR_URL),
        help="where the main Seerr answers on the host",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="forget the generated passwords and make new ones",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="only verify the world, and change nothing",
    )
    arguments = parser.parse_args()
    try:
        return run(arguments)
    except SeerrError as error:
        print(f"[seerr-world] {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
