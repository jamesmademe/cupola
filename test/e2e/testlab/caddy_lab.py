"""The lab's edge: a Caddy in front of three services, each origin with a
certificate of its own, and a rotation on command.

The edge is the one place the app meets a certificate that is nobody else's: it
reads the fingerprint, pins it, and the pin is what lets the connection
through. When the lab throws the internal CA away and starts the Caddy again,
the pin the person trusted must stop working and the new one must work.

Three origins, one port each: Radarr, Dockge and TrueNAS, the three the plan
names. Every origin has a name of its own (``radarr.localhost`` and friends):
a certificate belongs to a name, and the client sends that name as SNI. The pin
the app keeps is host, port and fingerprint, so the name can be a loopback one
and the three certificates stay three.

The Caddy is a container of the lab's Compose project, started and stopped by
the ``caddy-edge`` scenario. Its configuration is written here, into the lab's
state, and the CA that issues lives there too: nothing of it belongs to the
repository.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import socket
import ssl
import subprocess
import sys
import time
from pathlib import Path
from typing import NamedTuple

REPO_ROOT = Path(__file__).resolve().parents[3]
STATE_ROOT = Path(
    os.environ.get("CUPOLA_TESTLAB_STATE_DIR", REPO_ROOT / ".ai/scratch/zz_testlab/state")
).resolve()
CADDY_DIR = STATE_ROOT / "caddy"
CADDYFILE = CADDY_DIR / "Caddyfile"
DATA_DIR = CADDY_DIR / "data"
CONFIG_DIR = CADDY_DIR / "config"
COMPOSE_FILE = REPO_ROOT / "docker-compose.testlab.yml"
PROJECT = os.environ.get("CUPOLA_TESTLAB_PROJECT", "cupola-testlab")
# The edge's own profile, and the lab's: the services the edge stands in
# front of live in theirs, and Compose refuses a dependency it cannot see.
PROFILES = ("core", "downloads", "media", "infra", "protocol-mocks", "edge")


class Origin(NamedTuple):
    """One origin of the edge: a name, a port, and the service behind it."""

    key: str
    host: str
    port: int
    upstream: str
    tls_upstream: bool


ORIGINS: dict[str, Origin] = {
    "radarr": Origin("radarr", "radarr.localhost", 8445, "radarr:7878", False),
    "dockge": Origin("dockge", "dockge.localhost", 8446, "dockge:5001", False),
    "truenas": Origin(
        "truenas", "truenas.localhost", 8447, "truenas-mock:8460", True
    ),
}


def caddyfile() -> str:
    """The edge's configuration.

    ``auto_https disable_redirects`` and not ``auto_https off``: with the
    latter Caddy skips the TLS automation altogether ("all servers have
    automatic HTTPS disabled and no domains need certificates, skipping TLS
    automation setup"), never asks its internal CA for a certificate, and
    answers every handshake with an internal error, because there is no
    certificate to offer. The redirect is the only thing worth dropping.

    A site with no name would have the same fate: a certificate belongs to a
    name, and a site without one leaves the CA nothing to issue.
    """

    blocks = []
    for origin in ORIGINS.values():
        if origin.tls_upstream:
            # The TrueNAS simulator speaks TLS of its own: the edge trusts it
            # because the lab made it, and the app never sees it.
            block = (
                f"{origin.host}:{origin.port} {{\n"
                "\ttls internal\n"
                f"\treverse_proxy https://{origin.upstream} {{\n"
                "\t\ttransport http {\n"
                "\t\t\ttls_insecure_skip_verify\n"
                "\t\t}\n"
                "\t}\n"
                "}\n"
            )
        else:
            block = (
                f"{origin.host}:{origin.port} {{\n"
                "\ttls internal\n"
                f"\treverse_proxy {origin.upstream}\n"
                "}\n"
            )
        blocks.append(block)
    header = (
        "{\n"
        "\tadmin off\n"
        "\tpersist_config off\n"
        "\tauto_https disable_redirects\n"
        "}\n\n"
    )
    return header + "\n".join(blocks)


def write_config() -> Path:
    """Write the configuration the container reads, and the state it needs."""

    CADDY_DIR.mkdir(parents=True, exist_ok=True)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CADDYFILE.write_text(caddyfile(), encoding="utf-8")
    # The configuration names where the certificates live: it is the edge's
    # own material, and it stays in the lab's state.
    CADDYFILE.chmod(0o600)
    return CADDYFILE


def _compose(*args: str) -> list[str]:
    command = ["docker", "compose", "-p", PROJECT, "-f", str(COMPOSE_FILE)]
    for profile in PROFILES:
        command.extend(["--profile", profile])
    command.extend(args)
    return command


def _run(*args: str, check: bool = True, timeout: float = 300) -> str:
    environment = os.environ.copy()
    environment["CUPOLA_TESTLAB_STATE_DIR"] = str(STATE_ROOT)
    result = subprocess.run(
        _compose(*args),
        cwd=REPO_ROOT,
        env=environment,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(f"docker compose {' '.join(args)} failed: {detail}")
    return result.stdout


def up() -> dict[str, str]:
    """Write the configuration, start the Caddy and wait for the origins."""

    write_config()
    # The configuration is a bind mount read once at start: a container left
    # over from an earlier run would keep the old sites in memory, so the
    # edge is recreated every time the configuration is written.
    _run("up", "-d", "--wait", "--force-recreate", "caddy", timeout=600)
    return fingerprints()


def down() -> None:
    """Stop the edge and take its container away."""

    _run("stop", "caddy", check=False)
    _run("rm", "-sf", "caddy", check=False)


def fingerprint(origin: str) -> str:
    """The SHA-256 of the certificate the origin presents, as lowercase hex.

    The app's own format: the hash of the DER, the same text the trust prompt
    shows and the same text a pin keeps.
    """

    target = ORIGINS[origin]
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", target.port), timeout=5) as raw:
        # The name is what the client sends as SNI, and the certificate the
        # edge answers with belongs to it.
        with context.wrap_socket(raw, server_hostname=target.host) as tls:
            der = tls.getpeercert(binary_form=True)
    return hashlib.sha256(der).hexdigest()


def fingerprints(timeout: float = 60) -> dict[str, str]:
    """The fingerprint of every origin, once the edge answers on all of them."""

    deadline = time.monotonic() + timeout
    pending = dict(ORIGINS)
    values: dict[str, str] = {}
    while pending and time.monotonic() < deadline:
        for key in list(pending):
            try:
                values[key] = fingerprint(key)
            except (OSError, ssl.SSLError):
                continue
            del pending[key]
        if pending:
            time.sleep(0.5)
    if pending:
        raise RuntimeError(f"the edge does not answer on {sorted(pending)}")
    return values


def rotate() -> dict[str, str]:
    """A new CA and a new Caddy: the fingerprints change, the old pins do not.

    The internal CA and the certificates it signed live in the data directory:
    throwing them away is the rotation. The directory itself stays, so the
    bind mount the container sees never changes under its feet.
    """

    down()
    if DATA_DIR.exists():
        for entry in DATA_DIR.iterdir():
            if entry.is_dir():
                shutil.rmtree(entry)
            else:
                entry.unlink()
    return up()


def status() -> dict[str, object]:
    """What the edge is doing, origin by origin."""

    answer: dict[str, object] = {"running": False, "origins": {}}
    try:
        answer["running"] = "caddy" in _run("ps", "--services", "--filter", "status=running")
    except (RuntimeError, subprocess.SubprocessError):
        answer["running"] = False
    origins: dict[str, object] = {}
    for key in ORIGINS:
        try:
            origins[key] = fingerprint(key)
        except (OSError, ssl.SSLError) as error:
            origins[key] = f"no certificate: {error}"
    answer["origins"] = origins
    return answer


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="The lab's edge (Caddy).")
    parser.add_argument("--write-config", action="store_true")
    parser.add_argument("--up", action="store_true")
    parser.add_argument("--down", action="store_true")
    parser.add_argument("--rotate", action="store_true")
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--fingerprint", choices=sorted(ORIGINS))
    arguments = parser.parse_args()
    if arguments.write_config:
        print(json.dumps({"config": str(write_config())}))
    elif arguments.up:
        print(json.dumps(up()))
    elif arguments.down:
        down()
        print(json.dumps({"down": True}))
    elif arguments.rotate:
        print(json.dumps(rotate()))
    elif arguments.status:
        print(json.dumps(status()))
    elif arguments.fingerprint:
        print(
            json.dumps(
                {
                    "origin": arguments.fingerprint,
                    "fingerprint": fingerprint(arguments.fingerprint),
                }
            )
        )
    else:
        parser.print_help()
        sys.exit(2)
