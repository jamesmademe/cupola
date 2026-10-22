#!/usr/bin/env python3
"""Sara's Seerr: the second server P9 needs, set up and seeded from scratch.

The household has one Seerr, the lab's main one, which the operator holds the
key of. P9 is the other arrangement: a friend's server, where the operator
signs in with a local account of his own that may only request. This script
brings that second server (Compose service `seerr-sara`, 127.0.0.1:5056) from
an empty container to the state the P9 test expects, and does it again on
every run without changing what it already set up:

  1. a Jellyfin admin of its own (`sara`) on the lab's Jellyfin, so the second
     Seerr's admin is the friend and not the household's operator;
  2. the first-setup routes (public settings, media-server sign-in, Jellyfin
     settings, initialize, main settings), which the bootstrap runs for the
     main Seerr the same way;
  3. Radarr and Sonarr, with the lab's `test-key`, the `Any` profile and the
     media folder, so an approved request could reach them;
  4. the operator's local account with REQUEST alone, and one Jellyfin user
     Seerr imports (the lab's viewer) with REQUEST alone as well;
  5. one pending request of the operator's, for a movie Radarr does not have,
     so the P9 test reads a real request instead of a fixture.

The credentials it generates are written once and reused, in
`<state>/seerr-sara.json` (0600, inside the disposable state directory). They
are never printed. That file is the truth the e2e test signs in with; the API
key is not copied there, it stays in the container's own settings.json.

Usage:
  python3 test/e2e/testlab/seerr_sara.py --state-dir .ai/scratch/zz_testlab/state
  python3 test/e2e/testlab/seerr_sara.py --check    # verify, write nothing new
"""

from __future__ import annotations

import argparse
import http.cookiejar
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


ROOT = "http://127.0.0.1"
SARA_URL = f"{ROOT}:5056"
JELLYFIN_URL = f"{ROOT}:8096"
# Inside the Compose network, where Sara's Seerr reaches them: the same names
# the main Seerr's settings carry.
RADARR_HOST = "radarr"
RADARR_PORT = 7878
SONARR_HOST = "sonarr"
SONARR_PORT = 8989
JELLYFIN_HOST = "jellyfin"
JELLYFIN_PORT = 8096
MEDIA_SERVER_TYPE_JELLYFIN = 2
REQUEST_ONLY = 32
ADMIN = 2

# The Jellyfin administrator the lab makes in bootstrap.sh. It only exists to
# create the friend's user; Seerr then keeps a key of its own.
JELLYFIN_ADMIN = os.environ.get("CUPOLA_TESTLAB_JELLYFIN_ADMIN", "cupola-admin")
JELLYFIN_ADMIN_PASSWORD = os.environ.get(
    "CUPOLA_TESTLAB_JELLYFIN_PASSWORD", "cupola-pass"
)

# Who lives on the second server.
FRIEND = os.environ.get("CUPOLA_TESTLAB_SEERR_SARA_ADMIN", "sara")
FRIEND_EMAIL = os.environ.get("CUPOLA_TESTLAB_SEERR_SARA_ADMIN_EMAIL", "sara@example.test")
OPERATOR = "matt"
OPERATOR_EMAIL = "matt@example.net"
IMPORTED = os.environ.get(
    "CUPOLA_TESTLAB_JELLYFIN_REQUESTER_USERNAME", "cupola-viewer"
)

# Movies TMDB knows, in the order the seed prefers them. The first one the
# lab's Radarr does not have becomes the pending request; the P9 test reads
# the id this script writes, never one of these numbers.
CANDIDATES = (155, 27205, 13, 238, 680, 129, 120, 424)

STATE_FILE = "seerr-sara.json"


def log(message: str) -> None:
    print(f"[seerr-sara] {message}")


def warn(label: str, error: Exception) -> None:
    print(f"[seerr-sara] warning {label}: {type(error).__name__}: {error}")


def request(
    url: str,
    *,
    method: str = "GET",
    payload: Any | None = None,
    headers: dict[str, str] | None = None,
    opener: urllib.request.OpenerDirector | None = None,
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
    client = opener or urllib.request.build_opener()
    try:
        with client.open(request_object, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        # The body is the useful part of a refusal: Seerr and Jellyfin both
        # answer with JSON that says what is wrong.
        return error.code, error.read()


def json_request(
    url: str,
    *,
    method: str = "GET",
    payload: Any | None = None,
    headers: dict[str, str] | None = None,
    opener: urllib.request.OpenerDirector | None = None,
) -> Any:
    _, body = request(
        url,
        method=method,
        payload=payload,
        headers=headers,
        opener=opener,
    )
    return json.loads(body) if body else None


def password() -> str:
    return secrets.token_urlsafe(18)


def wait_http(url: str, seconds: int) -> None:
    deadline = time.time() + seconds
    last = ""
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=3) as response:
                if response.status < 500:
                    return
        except (urllib.error.URLError, OSError) as error:
            last = str(error)
        time.sleep(1)
    raise SystemExit(f"{url} did not answer within {seconds}s ({last})")


class Lab:
    """One run: the state directory, the files it reads and writes."""

    def __init__(self, state_dir: Path, url: str) -> None:
        self.state_dir = state_dir
        self.url = url.rstrip("/")
        self.state_path = state_dir / STATE_FILE
        self.seerr_settings = state_dir / "seerr-sara" / "settings.json"
        self.state = self._read_state()
        self._jellyfin_headers: dict[str, str] | None = None

    # The state file is the lab's truth about accounts and ids. It is created
    # once; a run only adds what is missing, so passwords never change under
    # a test that already knows them.
    def _read_state(self) -> dict[str, Any]:
        if not self.state_path.exists():
            return {}
        return json.loads(self.state_path.read_text(encoding="utf-8"))

    def save(self) -> None:
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        payload = json.dumps(self.state, indent=2, sort_keys=True) + "\n"
        temporary = self.state_path.with_suffix(".tmp")
        temporary.write_text(payload, encoding="utf-8")
        os.chmod(temporary, 0o600)
        temporary.replace(self.state_path)

    def secret(self, section: str, field: str) -> str:
        stored = self.state.get(section) or {}
        value = stored.get(field)
        if not isinstance(value, str) or not value:
            value = password()
            self.state.setdefault(section, {})[field] = value
            self.save()
        return value

    # ---------------------------------------------------------------- Seerr

    def api_key(self) -> str:
        """The key Seerr generated for its admin, from its own settings."""
        deadline = time.time() + 20
        while time.time() < deadline:
            try:
                settings = json.loads(
                    self.seerr_settings.read_text(encoding="utf-8")
                )
                key = (settings.get("main") or {}).get("apiKey")
                if isinstance(key, str) and key:
                    return key
            except (OSError, json.JSONDecodeError):
                pass
            time.sleep(0.5)
        raise SystemExit(
            f"No API key in {self.seerr_settings}: was the second Seerr initialized?"
        )

    def key_headers(self) -> dict[str, str]:
        return {
            "X-Api-Key": self.api_key(),
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

    def public(self) -> dict[str, Any]:
        return json_request(f"{self.url}/api/v1/settings/public") or {}

    def wait_for_seerr(self, seconds: int) -> None:
        wait_http(f"{self.url}/api/v1/status", seconds)
        wait_http(f"{JELLYFIN_URL}/System/Info/Public", seconds)

    def initialize(self) -> None:
        """The first-setup routes, when the server has never been set up."""
        if self.public().get("initialized") is True:
            return
        log("first setup: Sara's Jellyfin admin, then the media server")
        friend_password = self.secret("admin", "jellyfinPassword")
        self.jellyfin_user(FRIEND, friend_password, admin=True)

        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(jar)
        )
        status, body = request(
            f"{self.url}/api/v1/auth/jellyfin",
            method="POST",
            payload={
                "username": FRIEND,
                "password": friend_password,
                "hostname": JELLYFIN_HOST,
                "port": JELLYFIN_PORT,
                "useSsl": False,
                "urlBase": "",
                "email": FRIEND_EMAIL,
                "serverType": MEDIA_SERVER_TYPE_JELLYFIN,
            },
            opener=opener,
        )
        if status not in (200, 201):
            raise SystemExit(
                f"Seerr refused Sara's Jellyfin sign-in ({status}): "
                f"{body.decode(errors='replace')}"
            )
        log(f"Seerr: {FRIEND} is its admin, signed in through Jellyfin")

        # The sign-in already wrote ip, port and its own Jellyfin key. Only
        # the address the app opens is left: the lab's Jellyfin on the host.
        for path, payload in (
            (
                "/api/v1/settings/jellyfin",
                {"externalHostname": JELLYFIN_URL},
            ),
            ("/api/v1/settings/initialize", {}),
            # The route merges, so this sets the locale and leaves the rest.
            ("/api/v1/settings/main", {"locale": "en"}),
        ):
            status, body = request(
                f"{self.url}{path}",
                method="POST",
                payload=payload,
                opener=opener,
            )
            if status not in (200, 201):
                raise SystemExit(
                    f"Seerr refused {path} ({status}): "
                    f"{body.decode(errors='replace')}"
                )

    def ensure_arrs(self) -> dict[str, Any]:
        """Radarr and Sonarr as Seerr's settings hold them, once."""
        configured: dict[str, Any] = {}
        for kind, port in (("radarr", RADARR_PORT), ("sonarr", SONARR_PORT)):
            servers = json_request(
                f"{self.url}/api/v1/settings/{kind}", headers=self.key_headers()
            )
            servers = [entry for entry in (servers or []) if isinstance(entry, dict)]
            if not servers:
                directory = "/media/movies" if kind == "radarr" else "/media/series"
                payload: dict[str, Any] = {
                    "name": kind.capitalize(),
                    "hostname": RADARR_HOST if kind == "radarr" else SONARR_HOST,
                    "port": port,
                    "apiKey": "test-key",
                    "useSsl": False,
                    "baseUrl": "",
                    "activeProfileId": 1,
                    "activeProfileName": "Any",
                    "activeDirectory": directory,
                    "is4k": False,
                    "minimumAvailability": "released",
                    "isDefault": True,
                    "externalUrl": "",
                    "syncEnabled": True,
                }
                if kind == "sonarr":
                    payload["enableSeasonFolders"] = True
                status, body = request(
                    f"{self.url}/api/v1/settings/{kind}",
                    method="POST",
                    payload=payload,
                    headers=self.key_headers(),
                )
                if status not in (200, 201):
                    raise SystemExit(
                        f"Seerr refused its {kind} settings ({status}): "
                        f"{body.decode(errors='replace')}"
                    )
                log(f"Seerr: {kind.capitalize()} at {payload['hostname']}:{port}")
                servers = json_request(
                    f"{self.url}/api/v1/settings/{kind}",
                    headers=self.key_headers(),
                ) or []
            server = servers[0]
            configured[kind] = {
                "id": server.get("id"),
                "hostname": server.get("hostname"),
                "port": server.get("port"),
                "profile": server.get("activeProfileName"),
                "directory": server.get("activeDirectory"),
            }
        return configured

    def users(self) -> list[dict[str, Any]]:
        listing = json_request(
            f"{self.url}/api/v1/user?take=500", headers=self.key_headers()
        )
        return [entry for entry in ((listing or {}).get("results") or [])
                if isinstance(entry, dict)]

    def user_by_email(self, email: str) -> dict[str, Any] | None:
        return next(
            (
                user
                for user in self.users()
                if (user.get("email") or "").lower() == email.lower()
            ),
            None,
        )

    def request_only(self, user_id: int) -> None:
        status, body = request(
            f"{self.url}/api/v1/user/{user_id}/settings/permissions",
            method="POST",
            payload={"permissions": REQUEST_ONLY},
            headers=self.key_headers(),
        )
        if status not in (200, 201):
            raise SystemExit(
                f"Seerr refused the permissions of user {user_id} ({status}): "
                f"{body.decode(errors='replace')}"
            )

    def ensure_operator(self) -> dict[str, Any]:
        """The operator's local account, REQUEST alone, password set again."""
        mail = OPERATOR_EMAIL
        secret = self.secret("operator", "password")
        user = self.user_by_email(mail)
        if user is None:
            status, body = request(
                f"{self.url}/api/v1/user",
                method="POST",
                payload={
                    "email": mail,
                    "username": OPERATOR,
                    "password": secret,
                },
                headers=self.key_headers(),
            )
            if status not in (200, 201):
                raise SystemExit(
                    f"Seerr refused the operator account ({status}): "
                    f"{body.decode(errors='replace')}"
                )
            user = json.loads(body)
            log("Seerr: the operator's local account")
        else:
            status, body = request(
                f"{self.url}/api/v1/user/{user['id']}/settings/password",
                method="POST",
                payload={"newPassword": secret},
                headers=self.key_headers(),
            )
            if status not in (200, 201, 204):
                raise SystemExit(
                    f"Seerr refused the operator password ({status}): "
                    f"{body.decode(errors='replace')}"
                )
        self.request_only(int(user["id"]))
        return {
            "email": mail,
            "password": secret,
            "userId": int(user["id"]),
            "permissions": REQUEST_ONLY,
        }

    def ensure_imported(self) -> dict[str, Any] | None:
        """One Jellyfin user Seerr imported, so the server has a real second
        account as an imported one, not only local accounts."""
        jellyfin_id = self.jellyfin_user_id(IMPORTED)
        if jellyfin_id is None:
            log(f"Jellyfin has no {IMPORTED}: no imported user seeded")
            return None
        known = next(
            (
                user
                for user in self.users()
                if (user.get("jellyfinUserId") or "").lower()
                == jellyfin_id.lower()
            ),
            None,
        )
        if known is None:
            status, body = request(
                f"{self.url}/api/v1/user/import-from-jellyfin",
                method="POST",
                payload={"jellyfinUserIds": [jellyfin_id]},
                headers=self.key_headers(),
            )
            if status not in (200, 201):
                raise SystemExit(
                    f"Seerr refused the Jellyfin import ({status}): "
                    f"{body.decode(errors='replace')}"
                )
            imported = json.loads(body)
            known = (
                imported[0]
                if isinstance(imported, list) and imported
                else next(
                    (
                        user
                        for user in self.users()
                        if (user.get("jellyfinUserId") or "").lower()
                        == jellyfin_id.lower()
                    ),
                    None,
                )
            )
            log(f"Seerr: {IMPORTED} imported from Jellyfin")
        if known is None:
            return None
        self.request_only(int(known["id"]))
        return {
            "jellyfinUsername": IMPORTED,
            "seerrUserId": int(known["id"]),
            "permissions": REQUEST_ONLY,
        }

    def operator_session(self) -> urllib.request.OpenerDirector:
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(jar)
        )
        status, body = request(
            f"{self.url}/api/v1/auth/local",
            method="POST",
            payload={
                "email": OPERATOR_EMAIL,
                "password": self.state["operator"]["password"],
            },
            opener=opener,
        )
        if status != 200:
            raise SystemExit(
                f"The operator cannot sign in to Sara's Seerr ({status}): "
                f"{body.decode(errors='replace')}"
            )
        return opener

    def radarr_movies(self) -> list[int]:
        status, body = request(
            f"{ROOT}:7878/api/v3/movie", headers={"X-Api-Key": "test-key"}
        )
        if status != 200:
            raise SystemExit(f"Radarr did not answer ({status})")
        return [
            movie["tmdbId"]
            for movie in json.loads(body)
            if isinstance(movie, dict) and movie.get("tmdbId")
        ]

    def known_title(self, tmdb_id: int) -> str:
        status, body = request(
            f"{self.url}/api/v1/movie/{tmdb_id}", headers=self.key_headers()
        )
        if status != 200:
            raise SystemExit(
                f"Seerr does not know movie {tmdb_id} ({status}): "
                f"{body.decode(errors='replace')}"
            )
        return json.loads(body).get("title") or ""

    def pick_title(self) -> tuple[int, str]:
        """A movie Seerr knows and Radarr does not have, with its title."""
        taken = set(self.radarr_movies())
        for tmdb_id in CANDIDATES:
            if tmdb_id in taken:
                continue
            title = self.known_title(tmdb_id)
            if title:
                return tmdb_id, title
        raise SystemExit(
            "Every candidate movie is already in Radarr: add one to "
            "seerr_sara.py's CANDIDATES."
        )

    def request_list(self, opener: urllib.request.OpenerDirector) -> list[dict[str, Any]]:
        listing = json_request(
            f"{self.url}/api/v1/request?take=100&skip=0&filter=all",
            opener=opener,
        )
        return [
            entry
            for entry in ((listing or {}).get("results") or [])
            if isinstance(entry, dict)
        ]

    def ensure_request(self) -> dict[str, Any]:
        """The operator's pending request, for a movie Radarr does not have."""
        tmdb_id, title = self.pick_title()
        opener = self.operator_session()
        me = json_request(f"{self.url}/api/v1/auth/me", opener=opener) or {}
        operator_id = int(me["id"])

        # The title this seed asked for last time, when Radarr has since
        # gained it: that request is the seed's own, so the seed takes it
        # back rather than leaving two on a server P9 expects one on.
        previous = (self.state.get("request") or {}).get("tmdbId")
        if isinstance(previous, int) and previous != tmdb_id:
            for entry in self.request_list(opener):
                if (entry.get("media") or {}).get("tmdbId") == previous:
                    request(
                        f"{self.url}/api/v1/request/{entry['id']}",
                        method="DELETE",
                        headers=self.key_headers(),
                    )
                    log(f"Seerr: the seed's earlier request ({previous}) withdrawn")

        existing = next(
            (
                entry
                for entry in self.request_list(opener)
                if (entry.get("media") or {}).get("tmdbId") == tmdb_id
                and (entry.get("media") or {}).get("mediaType") == "movie"
            ),
            None,
        )
        if existing is not None and existing.get("status") != 1:
            # Somebody approved or declined it since the last run: the P9
            # test needs it waiting, so the seed takes it back.
            request(
                f"{self.url}/api/v1/request/{existing['id']}",
                method="DELETE",
                headers=self.key_headers(),
            )
            existing = None
            log("Seerr: the operator's earlier request withdrawn, it moved on")

        if existing is None:
            status, body = request(
                f"{self.url}/api/v1/request",
                method="POST",
                payload={"mediaType": "movie", "mediaId": tmdb_id},
                opener=opener,
            )
            if status not in (200, 201):
                raise SystemExit(
                    f"Seerr refused the operator's request ({status}): "
                    f"{body.decode(errors='replace')}"
                )
            existing = json.loads(body)
            log(f"Seerr: the operator asked for {title} ({tmdb_id}), pending")

        return {
            "id": int(existing["id"]),
            "tmdbId": tmdb_id,
            "mediaType": "movie",
            "title": title,
            "status": "pendingApproval",
            "requestedBy": operator_id,
        }

    # ------------------------------------------------------------- Jellyfin

    def jellyfin_headers(self) -> dict[str, str]:
        """The lab admin's token, asked for once: Jellyfin keeps one session
        per device, and a second sign-in on the same DeviceId retires the
        first token."""
        if self._jellyfin_headers is not None:
            return self._jellyfin_headers
        _, body = request(
            f"{JELLYFIN_URL}/Users/AuthenticateByName",
            method="POST",
            payload={
                "Username": JELLYFIN_ADMIN,
                "Pw": JELLYFIN_ADMIN_PASSWORD,
                "App": "Cupola",
                "AppVersion": "1.0",
                "DeviceId": "cupola-testlab-seerr-sara",
                "Device": "Cupola TestLab",
            },
            headers={
                "Authorization": (
                    'MediaBrowser Client="Cupola", Device="Cupola TestLab", '
                    'DeviceId="cupola-testlab-seerr-sara", Version="1.0"'
                )
            },
        )
        token = (json.loads(body) or {}).get("AccessToken")
        if not token:
            raise SystemExit("The lab's Jellyfin admin did not answer with a token")
        self._jellyfin_headers = {
            "Authorization": (
                'MediaBrowser Client="Cupola", Device="Cupola TestLab", '
                'DeviceId="cupola-testlab-seerr-sara", Version="1.0", '
                f'Token="{token}"'
            ),
            "Accept": "application/json",
            "Content-Type": "application/json",
        }
        return self._jellyfin_headers

    def jellyfin_users(self) -> list[dict[str, Any]]:
        users = json_request(f"{JELLYFIN_URL}/Users", headers=self.jellyfin_headers())
        return [user for user in (users or []) if isinstance(user, dict)]

    def jellyfin_user_id(self, name: str) -> str | None:
        user = next(
            (entry for entry in self.jellyfin_users() if entry.get("Name") == name),
            None,
        )
        return None if user is None else str(user["Id"])

    def jellyfin_user(self, name: str, secret: str, *, admin: bool) -> str:
        """A Jellyfin user of the lab, with its password and its policy."""
        headers = self.jellyfin_headers()
        user = next(
            (entry for entry in self.jellyfin_users() if entry.get("Name") == name),
            None,
        )
        if user is None:
            status, body = request(
                f"{JELLYFIN_URL}/Users/New",
                method="POST",
                payload={"Name": name, "Password": secret},
                headers=headers,
            )
            if status not in (200, 201):
                raise SystemExit(
                    f"Jellyfin refused the user {name} ({status}): "
                    f"{body.decode(errors='replace')}"
                )
            user = json.loads(body)
            log(f"Jellyfin: {name} made")
        user_id = str(user["Id"])

        status, body = request(
            f"{JELLYFIN_URL}/Users/{user_id}/Password",
            method="POST",
            payload={"NewPw": secret},
            headers=headers,
        )
        if status not in (200, 204):
            raise SystemExit(
                f"Jellyfin refused the password of {name} ({status}): "
                f"{body.decode(errors='replace')}"
            )

        current = json_request(f"{JELLYFIN_URL}/Users/{user_id}", headers=headers) or {}
        policy = dict(current.get("Policy") or {})
        policy["IsAdministrator"] = admin
        if admin:
            policy["EnableAllFolders"] = True
            policy["EnabledFolders"] = []
        status, body = request(
            f"{JELLYFIN_URL}/Users/{user_id}/Policy",
            method="POST",
            payload=policy,
            headers=headers,
        )
        if status not in (200, 204):
            raise SystemExit(
                f"Jellyfin refused the policy of {name} ({status}): "
                f"{body.decode(errors='replace')}"
            )
        return user_id


def verify(lab: Lab, state: dict[str, Any]) -> list[str]:
    """What the P9 test will read, read here first. No secrets in the lines."""
    checks: list[str] = []

    def ok(line: str) -> None:
        checks.append(line)
        print(f"[ok] {line}")

    status = json_request(f"{lab.url}/api/v1/status") or {}
    ok(f"{lab.url} is Seerr {status.get('version')}")

    public = lab.public()
    if public.get("initialized") is not True:
        raise SystemExit("The second Seerr is not initialized")
    ok(
        "initialized on "
        f"{'Jellyfin' if public.get('mediaServerType') == MEDIA_SERVER_TYPE_JELLYFIN else public.get('mediaServerType')}"
    )

    admin = json_request(f"{lab.url}/api/v1/auth/me", headers=lab.key_headers()) or {}
    if (admin.get("permissions") or 0) & ADMIN != ADMIN:
        raise SystemExit("The key's user is not an admin")
    ok(f"its admin is user {admin.get('id')} ({admin.get('jellyfinUsername')}), with the key")

    for kind in ("radarr", "sonarr"):
        servers = json_request(
            f"{lab.url}/api/v1/settings/{kind}", headers=lab.key_headers()
        ) or []
        if not servers:
            raise SystemExit(f"Seerr knows no {kind}")
        server = servers[0]
        ok(
            f"it knows {kind.capitalize()} at "
            f"{server.get('hostname')}:{server.get('port')} "
            f"({server.get('activeProfileName')}, {server.get('activeDirectory')})"
        )

    operator = state["operator"]
    opener = lab.operator_session()
    me = json_request(f"{lab.url}/api/v1/auth/me", opener=opener) or {}
    if me.get("id") != operator["userId"]:
        raise SystemExit("The operator signed in as somebody else")
    if me.get("permissions") != REQUEST_ONLY:
        raise SystemExit(
            f"The operator's permissions are {me.get('permissions')}, not REQUEST"
        )
    ok(
        f"the operator's local account {operator['email']} signs in as user "
        f"{me.get('id')}, REQUEST alone"
    )

    wanted = state["request"]
    found = [
        entry
        for entry in lab.request_list(opener)
        if (entry.get("media") or {}).get("tmdbId") == wanted["tmdbId"]
    ]
    if len(found) != 1:
        raise SystemExit(
            f"the operator's requests for {wanted['title']}: {len(found)}, wanted 1"
        )
    row = found[0]
    if row.get("status") != 1:
        raise SystemExit(f"the operator's request is {row.get('status')}, not pending")
    if (row.get("requestedBy") or {}).get("id") != operator["userId"]:
        raise SystemExit("the pending request is somebody else's")
    ok(
        f"the operator's pending request: {wanted['title']} "
        f"(tmdb {wanted['tmdbId']}), request {row.get('id')}"
    )

    imported = state.get("imported")
    if imported:
        users = {user.get("id"): user for user in lab.users()}
        user = users.get(imported["seerrUserId"])
        if user is None or user.get("permissions") != REQUEST_ONLY:
            raise SystemExit("The imported Jellyfin user is missing or not REQUEST")
        ok(
            f"the imported Jellyfin user {imported['jellyfinUsername']} is user "
            f"{imported['seerrUserId']}, REQUEST alone"
        )

    # The request must not be in Radarr: a pending request has not been
    # approved, and 155 in a queue would mean the seed asked something else.
    if wanted["tmdbId"] in lab.radarr_movies():
        raise SystemExit("The pending request's movie is in Radarr already")
    ok(f"Radarr does not have {wanted['title']} yet, so the request waits")

    return checks


def run(args: argparse.Namespace) -> int:
    state_dir = Path(args.state_dir)
    state_dir.mkdir(parents=True, exist_ok=True)
    if args.reset:
        (state_dir / STATE_FILE).unlink(missing_ok=True)
        log("state file removed: the next run generates new passwords")

    lab = Lab(state_dir, args.url)
    lab.wait_for_seerr(args.wait)

    if args.check:
        if not lab.state:
            raise SystemExit(f"No {lab.state_path}: run the seed first")
        verify(lab, lab.state)
        return 0

    lab.initialize()

    # The state file holds what each step made, so a rerun reads it back
    # instead of guessing. It is written as soon as an account exists.
    lab.state["url"] = lab.url
    lab.state["mediaServer"] = "jellyfin"
    lab.state.setdefault("admin", {}).update(
        {"jellyfinUsername": FRIEND, "email": FRIEND_EMAIL}
    )
    lab.state["operator"] = lab.ensure_operator()
    lab.state["arrs"] = lab.ensure_arrs()
    imported = lab.ensure_imported()
    if imported is not None:
        lab.state["imported"] = imported
    lab.state["request"] = lab.ensure_request()
    lab.save()

    verify(lab, lab.state)

    print()
    print(f"Sara's Seerr is ready at {lab.url}")
    print(f"State: {lab.state_path} (chmod 600; never commit or paste it)")
    print("The operator holds a local account on it, REQUEST alone.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Set up and seed the second Seerr P9 needs (Sara's)."
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
        default=os.environ.get("CUPOLA_TESTLAB_SEERR_SARA_URL", SARA_URL),
        help="where the second Seerr answers on the host",
    )
    parser.add_argument(
        "--wait",
        type=int,
        default=120,
        help="seconds to wait for the containers to answer",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="forget the generated passwords and make new ones",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="only verify what is there, and change nothing",
    )
    return run(parser.parse_args())


if __name__ == "__main__":
    sys.exit(main())
