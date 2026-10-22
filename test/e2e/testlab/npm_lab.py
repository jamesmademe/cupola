"""Nginx Proxy Manager arranged for the app's catalog rows I-04 to I-08.

NPM is the one service in the lab that issues no API key: the only way in is
an account's email and password exchanged for a JWT at ``POST /api/tokens``.
Everything here speaks that API and nothing else, against the real container
on ``127.0.0.1:8181`` (admin UI) and its published proxy ports 8088 (HTTP) and
8443 (HTTPS).

What ``apply`` leaves behind, all of it named after the lab so ``teardown``
cannot touch the seeded ``cupola.test`` host:

* ``cupola-lab.test`` answers for Radarr (``radarr:7878``), carries the
  expiring certificate and a working ``advanced_config`` extra location. Its
  ``/cupola-testlab`` path is served by nginx itself with the body
  ``advanced-config``, which is how a valid custom block is proven live rather
  than merely stored.
* ``cupola-alt.test`` answers for Dockge (``dockge:5001``) through an access
  list that allows the Docker network and denies the rest. Its
  ``advanced_config`` starts empty so the editor flow (I-05) can write into it.
* one uploaded certificate, provider ``other``, expiring in 14 days. NPM
  computes ``expires_on`` from the PEM on upload, so the amber state the app
  reads is the server's own date, not a date written here.
* a view-only account, ``cupola-viewer@example.com``, whose permission map is
  ``view`` on all six resources, and whose password is generated per lab and
  kept only in ``state/npm-lab.json`` (0600). It is the credential the e2e test
  carries to prove that a refused write is refused by NPM and not by Cupola.

Two NPM facts shape the module, both observed on ``golden-l8``:

* A custom certificate is created in two calls. ``POST /api/nginx/certificates``
  writes the row with ``expires_on`` equal to now; the PEM and key go up as a
  multipart ``POST .../upload``, and only then is ``expires_on`` derived from
  the certificate. Skipping the upload leaves a certificate that is already
  expired.
* ``POST .../renew`` only accepts Let's Encrypt certificates and answers 400
  ``Only Let'sEncrypt certificates can be renewed`` for any other provider.
  The lab has no ACME endpoint and no DNS, so no Let's Encrypt certificate can
  exist here: the renew success path is declared, not simulated.

Nothing in this module prints a token, a password, a private key, or an
audit-log body. NPM's ``/api/audit-log`` returns the full record of a
certificate, private key included, for custom certificates, so responses are
parsed for named fields and never echoed.
"""

from __future__ import annotations

import json
import os
import secrets
import shutil
import socket
import ssl
import subprocess
import time
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from scenarios.base import STATE_ROOT, ScenarioError, credentials, request

BASE = "http://127.0.0.1:8181"
API = f"{BASE}/api"
PROXY_HTTP = "http://127.0.0.1:8088"
PROXY_HTTPS = "https://127.0.0.1:8443"

STATE_FILE = STATE_ROOT / "npm-lab.json"
TLS_DIR = STATE_ROOT / "npm-lab" / "tls"

TOGGLE_DOMAIN = "cupola-lab.test"
ADVANCED_DOMAIN = "cupola-alt.test"
ACCESS_LIST_NAME = "Cupola testlab docker"
CERT_NAME = "Cupola testlab expiring"
VIEWER_EMAIL = "cupola-viewer@example.com"
VIEWER_NAME = "Cupola testlab viewer"
VIEWER_NICK = "Viewer"

# Served by nginx for `cupola-lab.test/cupola-testlab`. `add_header` inside
# `location /` would be overridden by NPM's own proxy.conf, which already sets
# one, so the proof is a separate location that answers without the upstream.
VALID_ADVANCED = (
    "location = /cupola-testlab {\n"
    "    default_type text/plain;\n"
    '    return 200 "advanced-config\\n";\n'
    "}"
)
REFUSED_ADVANCED = "cupola_bogus_directive on;"

CERT_DAYS = 14
CERT_MIN_DAYS = 5
CERT_MAX_DAYS = 21

PROXY_CLIENTS = [
    {"address": "192.168.0.0/16", "directive": "allow"},
    {"address": "all", "directive": "deny"},
]


# ── transport ────────────────────────────────────────────────────────────────


def _check(status: int, what: str) -> None:
    """Never put the body in the message: certificates and audit entries carry
    private keys, and a token lives in the login response."""
    if not 200 <= status < 300:
        raise ScenarioError(f"{what} failed with {status}")


class Api:
    """One admin token, re-minted per command. NPM has no revocation list and
    a day-long token, so holding one for the length of a scenario is fine."""

    def __init__(self, identity: str, secret: str, *, what: str = "admin") -> None:
        status, body = request(
            f"{API}/tokens",
            method="POST",
            payload={"identity": identity, "secret": secret},
        )
        token = body.get("token") if isinstance(body, dict) else None
        if status != 200 or not token:
            raise ScenarioError(f"NPM refused the {what} credential with {status}")
        self.token = str(token)

    def call(
        self,
        path: str,
        *,
        method: str = "GET",
        payload: Any | None = None,
        timeout: float = 60,
    ) -> tuple[int, Any]:
        return request(
            f"{API}{path}",
            method=method,
            payload=payload,
            headers={"Authorization": f"Bearer {self.token}"},
            timeout=timeout,
        )

    def require(
        self,
        path: str,
        *,
        method: str = "GET",
        payload: Any | None = None,
        timeout: float = 60,
        what: str | None = None,
    ) -> Any:
        status, body = self.call(
            path, method=method, payload=payload, timeout=timeout
        )
        _check(status, what or f"NPM {method} {path}")
        return body

    def upload(self, certificate_id: int, cert: Path, key: Path) -> None:
        boundary = f"----cupola{uuid.uuid4().hex}"
        parts: list[str] = []
        for name, path in (("certificate", cert), ("certificate_key", key)):
            parts.append(
                f"--{boundary}\r\n"
                f'Content-Disposition: form-data; name="{name}"; '
                f'filename="{path.name}"\r\n'
                "Content-Type: application/octet-stream\r\n\r\n"
                f"{path.read_text(encoding='utf-8')}\r\n"
            )
        body = ("".join(parts) + f"--{boundary}--\r\n").encode("utf-8")
        call = urllib.request.Request(
            f"{API}/nginx/certificates/{certificate_id}/upload",
            data=body,
            method="POST",
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": f"multipart/form-data; boundary={boundary}",
            },
        )
        try:
            with urllib.request.urlopen(call, timeout=60) as response:
                status = response.status
        except urllib.error.HTTPError as error:
            status = error.code
        _check(status, "NPM certificate upload")


def admin() -> Api:
    env = credentials()
    identity = (
        os.environ.get("CUPOLA_TESTLAB_NPM_USERNAME")
        or env.get("CUPOLA_TESTLAB_NPM_USERNAME")
        or ""
    ).strip()
    secret = (
        os.environ.get("CUPOLA_TESTLAB_NPM_PASSWORD")
        or env.get("CUPOLA_TESTLAB_NPM_PASSWORD")
        or ""
    )
    if not identity or not secret:
        raise ScenarioError(
            "credentials.env has no NPM administrator: run "
            "`python3 test/e2e/testlab/testlab.py seed` first"
        )
    return Api(identity, secret)


# ── state ────────────────────────────────────────────────────────────────────


def load_state() -> dict[str, Any]:
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ScenarioError(f"the npm-lab state is unreadable: {error}") from error


def save_state(state: dict[str, Any]) -> None:
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    temporary = STATE_FILE.with_name(f"{STATE_FILE.name}.tmp")
    temporary.write_text(
        json.dumps(state, indent=2, sort_keys=True), encoding="utf-8"
    )
    os.chmod(temporary, 0o600)
    temporary.replace(STATE_FILE)
    os.chmod(STATE_FILE, 0o600)


def drop_state() -> None:
    if STATE_FILE.exists():
        STATE_FILE.unlink()
    if TLS_DIR.parent.exists():
        shutil.rmtree(TLS_DIR.parent)


# ── read helpers ─────────────────────────────────────────────────────────────


def server_info(api: Api) -> dict[str, Any]:
    status, body = request(f"{API}/")
    _check(status, "NPM health document")
    if not isinstance(body, dict) or str(body.get("status")).upper() != "OK":
        raise ScenarioError("the address answered, but not as an NPM API")
    return body


def hosts(api: Api) -> list[dict[str, Any]]:
    body = api.require("/nginx/proxy-hosts?expand=owner,access_list,certificate")
    return [item for item in body or [] if isinstance(item, dict)]


def host_for(api: Api, domain: str) -> dict[str, Any] | None:
    for item in hosts(api):
        if domain in (item.get("domain_names") or []):
            return item
    return None


def require_host(api: Api, domain: str) -> dict[str, Any]:
    item = host_for(api, domain)
    if item is None:
        raise ScenarioError(f"NPM lists no proxy host for {domain}")
    return item


def certificate_for(api: Api) -> dict[str, Any] | None:
    body = api.require("/nginx/certificates")
    for item in body or []:
        if isinstance(item, dict) and item.get("nice_name") == CERT_NAME:
            return {
                "id": int(item["id"]),
                "provider": str(item.get("provider") or ""),
                "domain": str((item.get("domain_names") or [""])[0]),
                "expiresOn": str(item.get("expires_on") or ""),
            }
    return None


def require_certificate(api: Api) -> dict[str, Any]:
    item = certificate_for(api)
    if item is None:
        raise ScenarioError(f"NPM holds no certificate called {CERT_NAME!r}")
    return item


def access_list_for(api: Api) -> dict[str, Any] | None:
    body = api.require("/nginx/access-lists?expand=clients")
    for item in body or []:
        if isinstance(item, dict) and item.get("name") == ACCESS_LIST_NAME:
            return item
    return None


def require_access_list(api: Api) -> dict[str, Any]:
    item = access_list_for(api)
    if item is None:
        raise ScenarioError(f"NPM lists no access list called {ACCESS_LIST_NAME!r}")
    return item


def viewer_id(api: Api) -> int | None:
    query = urllib.parse.quote(VIEWER_EMAIL)
    body = api.require(f"/users?query={query}")
    for item in body or []:
        if isinstance(item, dict) and item.get("email") == VIEWER_EMAIL:
            return int(item["id"])
    return None


def audit_entries(api: Api) -> list[dict[str, Any]]:
    body = api.require("/audit-log")
    return [item for item in body or [] if isinstance(item, dict)]


def _audit_for(api: Api, domains: set[str]) -> dict[str, Any] | None:
    for entry in audit_entries(api):
        meta = entry.get("meta")
        names = meta.get("domain_names") if isinstance(meta, dict) else None
        if entry.get("object_type") != "proxy-host":
            continue
        if isinstance(names, list) and domains.intersection(
            str(name) for name in names
        ):
            return {
                "id": int(entry.get("id") or 0),
                "objectId": int(entry.get("object_id") or 0),
                "action": str(entry.get("action") or ""),
            }
    return None


def days_until(expires_on: str) -> int | None:
    try:
        expiry = datetime.strptime(expires_on, "%Y-%m-%d %H:%M:%S")
    except (TypeError, ValueError):
        return None
    # NPM writes the certificate's own UTC notAfter, as a naive string.
    return (expiry - datetime.now(timezone.utc).replace(tzinfo=None)).days


# ── the certificate ──────────────────────────────────────────────────────────


def _tls_pair() -> tuple[Path, Path]:
    TLS_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(TLS_DIR.parent, 0o700)
    os.chmod(TLS_DIR, 0o700)
    cert = TLS_DIR / "certificate.pem"
    key = TLS_DIR / "private-key.pem"
    for path in (cert, key):
        if path.exists():
            path.unlink()
    try:
        subprocess.run(
            [
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-days",
                str(CERT_DAYS),
                "-keyout",
                str(key),
                "-out",
                str(cert),
                "-subj",
                f"/CN={TOGGLE_DOMAIN}",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as error:
        raise ScenarioError(
            "openssl is not on PATH, so the lab cannot make the expiring "
            "certificate"
        ) from error
    except subprocess.CalledProcessError as error:
        raise ScenarioError(
            f"openssl refused to make the lab certificate: {error.stderr[-400:]}"
        ) from error
    os.chmod(cert, 0o600)
    os.chmod(key, 0o600)
    return cert, key


def _delete_certificate(api: Api, certificate: dict[str, Any]) -> None:
    api.require(
        f"/nginx/certificates/{certificate['id']}",
        method="DELETE",
        what="NPM certificate delete",
    )


def ensure_certificate(api: Api) -> dict[str, Any]:
    existing = certificate_for(api)
    if existing is not None:
        days = days_until(existing["expiresOn"])
        # Same end state, not the same writes: a certificate inside the amber
        # window is reused, one that has lapsed or is no longer short-dated is
        # replaced with a fresh 14-day pair.
        if days is not None and CERT_MIN_DAYS <= days <= CERT_MAX_DAYS:
            return existing
        _delete_certificate(api, existing)

    cert, key = _tls_pair()
    created = api.require(
        "/nginx/certificates",
        method="POST",
        payload={
            "provider": "other",
            "nice_name": CERT_NAME,
            "domain_names": [TOGGLE_DOMAIN],
        },
        what="NPM certificate create",
    )
    certificate_id = int(created["id"])
    api.upload(certificate_id, cert, key)
    current = certificate_for(api)
    if current is None or current["id"] != certificate_id:
        raise ScenarioError("NPM did not keep the uploaded certificate")
    return current


# ── access list, hosts, account ─────────────────────────────────────────────


def ensure_access_list(api: Api) -> dict[str, Any]:
    payload = {
        "name": ACCESS_LIST_NAME,
        "satisfy_any": False,
        "pass_auth": False,
        "items": [],
        "clients": PROXY_CLIENTS,
    }
    existing = access_list_for(api)
    if existing is None:
        api.require(
            "/nginx/access-lists",
            method="POST",
            payload=payload,
            what="NPM access list create",
        )
    else:
        api.require(
            f"/nginx/access-lists/{existing['id']}",
            method="PUT",
            payload=payload,
            what="NPM access list update",
        )
    return require_access_list(api)


def _host_payload(
    domain: str,
    forward_host: str,
    forward_port: int,
    access_list_id: int,
    certificate_id: int,
    advanced_config: str,
) -> dict[str, Any]:
    return {
        "domain_names": [domain],
        "forward_scheme": "http",
        "forward_host": forward_host,
        "forward_port": forward_port,
        "access_list_id": access_list_id,
        "certificate_id": certificate_id,
        "ssl_forced": False,
        "caching_enabled": False,
        "block_exploits": True,
        "allow_websocket_upgrade": True,
        "http2_support": False,
        "hsts_enabled": False,
        "hsts_subdomains": False,
        "advanced_config": advanced_config,
        "enabled": True,
    }


def ensure_host(
    api: Api,
    domain: str,
    forward_host: str,
    forward_port: int,
    *,
    access_list_id: int = 0,
    certificate_id: int = 0,
    advanced_config: str = "",
) -> dict[str, Any]:
    payload = _host_payload(
        domain,
        forward_host,
        forward_port,
        access_list_id,
        certificate_id,
        advanced_config,
    )
    existing = host_for(api, domain)
    if existing is None:
        api.require(
            "/nginx/proxy-hosts",
            method="POST",
            payload=payload,
            what=f"NPM proxy host create for {domain}",
        )
    else:
        api.require(
            f"/nginx/proxy-hosts/{existing['id']}",
            method="PUT",
            payload=payload,
            what=f"NPM proxy host update for {domain}",
        )
        if not existing.get("enabled"):
            api.require(
                f"/nginx/proxy-hosts/{existing['id']}/enable",
                method="POST",
                what=f"NPM proxy host enable for {domain}",
            )
    return require_host(api, domain)


def ensure_viewer(api: Api, previous: str | None) -> dict[str, Any]:
    password = previous or secrets.token_urlsafe(18)
    existing = viewer_id(api)
    if existing is None:
        api.require(
            "/users",
            method="POST",
            payload={
                "name": VIEWER_NAME,
                "nickname": VIEWER_NICK,
                "email": VIEWER_EMAIL,
                "roles": [],
                "auth": {"type": "password", "secret": password},
            },
            what="NPM user create",
        )
        existing = viewer_id(api)
    if existing is None:
        raise ScenarioError("NPM did not keep the view-only account")

    api.require(
        f"/users/{existing}/permissions",
        method="PUT",
        payload={
            # `all` is the difference between a view-only account that can see
            # the lab's hosts and one whose grid is empty because NPM scopes
            # rows to their owner. Reads are what this account is for.
            "visibility": "all",
            "proxy_hosts": "view",
            "redirection_hosts": "view",
            "dead_hosts": "view",
            "streams": "view",
            "access_lists": "view",
            "certificates": "view",
        },
        what="NPM user permissions",
    )
    api.require(
        f"/users/{existing}/auth",
        method="PUT",
        payload={"type": "password", "secret": password},
        what="NPM user password",
    )
    return {
        "id": existing,
        "email": VIEWER_EMAIL,
        "name": VIEWER_NICK,
        "password": password,
    }


# ── apply, verify, teardown ─────────────────────────────────────────────────


def apply() -> None:
    api = admin()
    info = server_info(api)
    state = load_state()
    previous_password = None
    viewer = state.get("viewer")
    if isinstance(viewer, dict):
        previous_password = viewer.get("password")

    listing = ensure_access_list(api)
    certificate = ensure_certificate(api)
    toggle = ensure_host(
        api,
        TOGGLE_DOMAIN,
        "radarr",
        7878,
        certificate_id=certificate["id"],
        advanced_config=VALID_ADVANCED,
    )
    advanced = ensure_host(
        api,
        ADVANCED_DOMAIN,
        "dockge",
        5001,
        access_list_id=listing["id"],
        advanced_config="",
    )
    account = ensure_viewer(api, previous_password)
    version = info.get("version") or {}

    save_state(
        {
            "server": {
                "url": BASE,
                "api": API,
                "version": f"{int(version.get('major') or 0)}."
                f"{int(version.get('minor') or 0)}."
                f"{int(version.get('revision') or 0)}",
                "revision": int(version.get("revision") or 0),
            },
            "proxy": {"http": PROXY_HTTP, "https": PROXY_HTTPS},
            "advanced": {"valid": VALID_ADVANCED, "refused": REFUSED_ADVANCED},
            "viewer": account,
            "certificate": {
                "id": certificate["id"],
                "provider": certificate["provider"],
                "domain": certificate["domain"],
                "expiresOn": certificate["expiresOn"],
                "niceName": CERT_NAME,
            },
            "accessList": {
                "id": int(listing["id"]),
                "name": ACCESS_LIST_NAME,
                "clients": PROXY_CLIENTS,
            },
            "hosts": {
                "toggle": {
                    "id": int(toggle["id"]),
                    "domain": TOGGLE_DOMAIN,
                    "forward": "radarr:7878",
                },
                "advanced": {
                    "id": int(advanced["id"]),
                    "domain": ADVANCED_DOMAIN,
                    "forward": "dockge:5001",
                },
            },
        }
    )


def _proxy_request(
    url: str,
    host: str,
    *,
    body: str | None = None,
    timeout: float = 15,
) -> tuple[int, bytes]:
    """One request through NPM's published HTTP port, by Host header.

    `body`, when given, is what the response must say. nginx hands new
    connections to a reloaded configuration a moment after NPM returns, so the
    expectation is retried inside a short budget instead of racing the reload.
    """
    deadline = time.monotonic() + 5
    last = "no answer"
    while True:
        call = urllib.request.Request(url, headers={"Host": host})
        client = urllib.request.build_opener()
        try:
            with client.open(call, timeout=timeout) as response:
                status, payload = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, payload = error.code, error.read()
        except (urllib.error.URLError, TimeoutError) as error:
            raise ScenarioError(f"GET {url} did not answer: {error}") from error
        if status == 200 and (body is None or payload.strip() == body.encode()):
            return status, payload
        last = f"{status} {payload[:60]!r}"
        if time.monotonic() >= deadline:
            raise ScenarioError(f"GET {url} answered {last}, not {body!r}")
        time.sleep(0.15)


def _https_request(
    host: str, path: str = "/", *, timeout: float = 20
) -> tuple[int, str]:
    """HTTPS through NPM with the server name in SNI.

    NPM's catch-all 443 server answers `ssl_reject_handshake on`, so a client
    that connects to the IP without SNI is refused before HTTP exists. That is
    the correct behaviour for the app too: it always dials a hostname. The
    certificate is read from the same handshake, so what nginx serves is what
    is asserted, not what the database says it should serve.
    """
    context = ssl._create_unverified_context()
    try:
        with socket.create_connection(("127.0.0.1", 8443), timeout=timeout) as raw:
            with context.wrap_socket(raw, server_hostname=host) as tls:
                der = tls.getpeercert(binary_form=True)
                tls.sendall(
                    f"GET {path} HTTP/1.1\r\nHost: {host}\r\n"
                    "Connection: close\r\n\r\n".encode()
                )
                response = b""
                while True:
                    chunk = tls.recv(8192)
                    if not chunk:
                        break
                    response += chunk
    except (ssl.SSLError, OSError) as error:
        raise ScenarioError(f"HTTPS to {host} did not answer: {error}") from error
    head, _, _ = response.partition(b"\r\n\r\n")
    line = head.split(b"\r\n", 1)[0].decode("iso-8859-1")
    parts = line.split()
    if len(parts) < 2 or not parts[1].isdigit():
        raise ScenarioError(f"HTTPS to {host} answered without a status: {line}")
    try:
        served = subprocess.run(
            ["openssl", "x509", "-inform", "DER", "-noout", "-subject", "-dates"],
            input=der,
            check=True,
            capture_output=True,
        ).stdout.decode("utf-8", errors="replace")
    except (OSError, subprocess.CalledProcessError) as error:
        raise ScenarioError(
            f"could not read the served certificate: {error}"
        ) from error
    return int(parts[1]), served


def verify() -> None:
    state = load_state()
    if not state:
        raise ScenarioError("the npm-lab scenario has no state to verify")

    api = admin()
    info = server_info(api)
    version = info.get("version") or {}
    major = int(version.get("major") or 0)
    minor = int(version.get("minor") or 0)
    if major != 2 or minor < 12:
        raise ScenarioError(
            f"NPM answers version {version.get('major')}.{version.get('minor')}, "
            "not the 2.12 the lab pins"
        )

    listing = require_access_list(api)
    clients = [
        (str(client.get("address")), str(client.get("directive")))
        for client in listing.get("clients") or []
        if isinstance(client, dict)
    ]
    if clients != [
        (PROXY_CLIENTS[0]["address"], PROXY_CLIENTS[0]["directive"]),
        (PROXY_CLIENTS[1]["address"], PROXY_CLIENTS[1]["directive"]),
    ]:
        raise ScenarioError(f"the access list reads {clients}, not the lab's rules")
    if listing.get("satisfy_any") or listing.get("pass_auth"):
        raise ScenarioError("the access list asks for auth or satisfy-any")
    if int(listing.get("proxy_host_count") or 0) < 1:
        raise ScenarioError("the access list is not attached to any host")

    certificate = require_certificate(api)
    if certificate["provider"] != "other":
        raise ScenarioError(
            f"the certificate reads provider {certificate['provider']!r}"
        )
    days = days_until(certificate["expiresOn"])
    if days is None or not CERT_MIN_DAYS <= days <= CERT_MAX_DAYS:
        raise ScenarioError(
            f"the certificate expires in {days} days, outside the lab's "
            f"{CERT_MIN_DAYS}..{CERT_MAX_DAYS} amber window"
        )

    toggle = require_host(api, TOGGLE_DOMAIN)
    if not toggle.get("enabled"):
        raise ScenarioError(f"{TOGGLE_DOMAIN} is disabled")
    if (toggle.get("forward_host"), int(toggle.get("forward_port") or 0)) != (
        "radarr",
        7878,
    ):
        raise ScenarioError(
            f"{TOGGLE_DOMAIN} forwards to "
            f"{toggle.get('forward_host')}:{toggle.get('forward_port')}"
        )
    if toggle.get("advanced_config") != VALID_ADVANCED:
        raise ScenarioError(f"{TOGGLE_DOMAIN} does not carry the valid block")
    if int(toggle.get("certificate_id") or 0) != certificate["id"]:
        raise ScenarioError(f"{TOGGLE_DOMAIN} does not carry the certificate")
    meta = toggle.get("meta") or {}
    if not meta.get("nginx_online"):
        raise ScenarioError(
            f"{TOGGLE_DOMAIN} is not loaded by nginx: {meta.get('nginx_err')}"
        )

    advanced = require_host(api, ADVANCED_DOMAIN)
    if not advanced.get("enabled"):
        raise ScenarioError(f"{ADVANCED_DOMAIN} is disabled")
    if (advanced.get("forward_host"), int(advanced.get("forward_port") or 0)) != (
        "dockge",
        5001,
    ):
        raise ScenarioError(
            f"{ADVANCED_DOMAIN} forwards to "
            f"{advanced.get('forward_host')}:{advanced.get('forward_port')}"
        )
    if int(advanced.get("access_list_id") or 0) != int(listing["id"]):
        raise ScenarioError(f"{ADVANCED_DOMAIN} does not carry the access list")
    if str(advanced.get("advanced_config") or "") != "":
        raise ScenarioError(f"{ADVANCED_DOMAIN} does not start with an empty block")
    if not (advanced.get("meta") or {}).get("nginx_online"):
        raise ScenarioError(f"{ADVANCED_DOMAIN} is not loaded by nginx")

    entry = _audit_for(api, {TOGGLE_DOMAIN, ADVANCED_DOMAIN})
    if entry is None:
        raise ScenarioError("the audit log carries no entry for the lab's hosts")

    _proxy_request(
        f"{PROXY_HTTP}/cupola-testlab", TOGGLE_DOMAIN, body="advanced-config"
    )
    _proxy_request(f"{PROXY_HTTP}/", ADVANCED_DOMAIN)

    status, served = _https_request(TOGGLE_DOMAIN)
    if status != 200:
        raise ScenarioError(f"{TOGGLE_DOMAIN} answered {status} over HTTPS")
    if TOGGLE_DOMAIN not in served:
        raise ScenarioError(
            f"the certificate nginx serves does not name {TOGGLE_DOMAIN}: {served}"
        )

    _verify_viewer(api, state, toggle, certificate)


def _verify_viewer(
    api: Api,
    state: dict[str, Any],
    toggle: dict[str, Any],
    certificate: dict[str, Any],
) -> None:
    viewer = state.get("viewer") or {}
    identity = str(viewer.get("email") or "")
    secret = str(viewer.get("password") or "")
    if not identity or not secret:
        raise ScenarioError("the state carries no view-only account")
    view = Api(identity, secret, what="view-only")

    status, me = view.call("/users/me?expand=permissions")
    if status != 200 or not isinstance(me, dict):
        raise ScenarioError(f"the view-only account answers /users/me with {status}")
    if "admin" in [str(role) for role in me.get("roles") or []]:
        raise ScenarioError("the view-only account is an administrator")
    permissions = me.get("permissions") or {}
    if permissions.get("visibility") != "all":
        raise ScenarioError(
            f"the view-only account's visibility reads "
            f"{permissions.get('visibility')!r}, not 'all'"
        )
    wrong = {
        resource: permissions.get(resource)
        for resource in (
            "proxy_hosts",
            "redirection_hosts",
            "dead_hosts",
            "streams",
            "access_lists",
            "certificates",
        )
        if permissions.get(resource) != "view"
    }
    if wrong:
        raise ScenarioError(f"the view-only account can do more than read: {wrong}")

    status, visible = view.call(
        "/nginx/proxy-hosts?expand=owner,access_list,certificate"
    )
    if status != 200:
        raise ScenarioError(f"the view-only account cannot read hosts: {status}")
    domains = {
        domain
        for item in visible or []
        if isinstance(item, dict)
        for domain in item.get("domain_names") or []
    }
    if not {TOGGLE_DOMAIN, ADVANCED_DOMAIN}.issubset(domains):
        raise ScenarioError(
            "the view-only account cannot see the lab's hosts: "
            f"{sorted(domains)}"
        )
    status, _ = view.call(
        f"/nginx/certificates/{certificate['id']}/renew", method="POST"
    )
    if status != 403:
        raise ScenarioError(f"the view-only account can renew: {status}")
    status, _ = view.call(
        f"/nginx/proxy-hosts/{toggle['id']}/disable", method="POST"
    )
    if status != 403:
        raise ScenarioError(f"the view-only account can disable a host: {status}")
    status, _ = view.call(
        "/nginx/proxy-hosts",
        method="POST",
        payload={
            "domain_names": ["refused.test"],
            "forward_scheme": "http",
            "forward_host": "radarr",
            "forward_port": 7878,
        },
    )
    if status != 403:
        raise ScenarioError(f"the view-only account can create a host: {status}")
    status, _ = view.call("/audit-log")
    if status != 403:
        raise ScenarioError(
            f"the view-only account reads the audit log: {status} "
            "(NPM restricts it to administrators)"
        )
    again = require_host(api, TOGGLE_DOMAIN)
    if not again.get("enabled"):
        raise ScenarioError(f"the refused write left {TOGGLE_DOMAIN} disabled")


def teardown() -> None:
    api = admin()

    for entry in hosts(api):
        if set(entry.get("domain_names") or []) & {TOGGLE_DOMAIN, ADVANCED_DOMAIN}:
            api.require(
                f"/nginx/proxy-hosts/{entry['id']}",
                method="DELETE",
                what=f"NPM proxy host delete for {entry.get('domain_names')}",
            )

    certificate = certificate_for(api)
    if certificate is not None:
        _delete_certificate(api, certificate)

    listing = access_list_for(api)
    if listing is not None:
        api.require(
            f"/nginx/access-lists/{listing['id']}",
            method="DELETE",
            what="NPM access list delete",
        )

    existing = viewer_id(api)
    if existing is not None:
        api.require(
            f"/users/{existing}",
            method="DELETE",
            what="NPM user delete",
        )

    drop_state()


def verify_absent() -> None:
    api = admin()
    for domain in (TOGGLE_DOMAIN, ADVANCED_DOMAIN):
        if host_for(api, domain) is not None:
            raise ScenarioError(f"NPM still serves {domain}")
    if certificate_for(api) is not None:
        raise ScenarioError(f"NPM still holds the certificate {CERT_NAME!r}")
    if access_list_for(api) is not None:
        raise ScenarioError(f"NPM still holds the access list {ACCESS_LIST_NAME!r}")
    if viewer_id(api) is not None:
        raise ScenarioError(f"NPM still holds {VIEWER_EMAIL}")
    if STATE_FILE.exists():
        raise ScenarioError("the npm-lab state file was not removed")
    if TLS_DIR.parent.exists():
        raise ScenarioError("the npm-lab certificate files were not removed")
