#!/usr/bin/env python3
"""Control plane for the disposable Cupola testlab.

The lab is a Compose project on OrbStack. This command is the only supported
way to move it between states: bring profiles up, seed, snapshot, reset,
apply a scenario, inject a fault, and check that the whole thing is healthy.

Two rules shape the code:

* The host owns Docker. Nothing here runs the Docker socket inside a
  container; Dockge talks to its own ``docker:dind`` sidecar.
* State is data, not a rebuild. A snapshot archives the bind-mounted state
  directories while the containers are stopped, and a reset restores them
  byte for byte before starting anything again.

The same commands are exposed on 127.0.0.1 for the journeys, which run inside
the app sandbox and cannot start processes. The token lives in the chmod-600
credentials file and is never printed.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import http.server
import importlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Iterable

TESTLAB_DIR = Path(__file__).resolve().parent
REPO_ROOT = TESTLAB_DIR.parents[2]
COMPOSE_FILE = REPO_ROOT / "docker-compose.testlab.yml"
SCRATCH_ROOT = REPO_ROOT / ".ai" / "scratch" / "zz_testlab"
STATE_ROOT = Path(
    os.environ.get("CUPOLA_TESTLAB_STATE_DIR", SCRATCH_ROOT / "state")
).resolve()
SNAPSHOT_ROOT = SCRATCH_ROOT / "snapshots"
CREDENTIALS = STATE_ROOT / "credentials.env"
PORTS_FILE = SCRATCH_ROOT / "ports.json"
PROJECT = os.environ.get("CUPOLA_TESTLAB_PROJECT", "cupola-testlab")
PROFILES = ("core", "downloads", "media", "infra", "protocol-mocks")
TOXIPROXY_URL = os.environ.get(
    "CUPOLA_TESTLAB_TOXIPROXY_URL", "http://127.0.0.1:8474"
)

# The app talks to the proxy ports; the direct ports stay for the transport
# harness, which must not depend on the fault layer.
PROXIES: dict[str, tuple[str, int, int]] = {
    "seerr": ("seerr", 5055, 25055),
    "radarr": ("radarr", 7878, 27878),
    "sonarr": ("sonarr", 8989, 28989),
    "lidarr": ("lidarr", 8686, 28686),
    "readarr": ("readarr", 8787, 28787),
    "prowlarr": ("prowlarr", 9696, 29696),
    "bazarr": ("bazarr", 6767, 26767),
    "qbittorrent": ("qbittorrent", 8080, 28080),
    "transmission": ("transmission", 9091, 29091),
    "sabnzbd": ("sabnzbd", 8080, 28082),
    "nzbget": ("nzbget", 6789, 26789),
    "jellyfin": ("jellyfin", 8096, 28096),
    "plex": ("plex", 32400, 23240),
    "dockge": ("dockge", 5001, 25001),
    "npm": ("nginx-proxy-manager", 81, 28181),
    "truenas": ("truenas-mock", 8460, 28460),
    "unraid": ("unraid-mock", 8480, 28480),
}

FAULT_MODES = ("down", "timeout", "slow", "flap", "clear")


class LabError(RuntimeError):
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


def control_token() -> str:
    return credentials().get("CUPOLA_TESTLAB_CONTROL_TOKEN", "")


def compose_command(
    *args: str, profiles: Iterable[str] = PROFILES
) -> list[str]:
    command = ["docker", "compose", "-p", PROJECT, "-f", str(COMPOSE_FILE)]
    for profile in profiles:
        command.extend(["--profile", profile])
    command.extend(args)
    return command


def run(
    command: list[str],
    *,
    check: bool = True,
    capture: bool = False,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment["CUPOLA_TESTLAB_STATE_DIR"] = str(STATE_ROOT)
    result = subprocess.run(
        command,
        cwd=REPO_ROOT,
        env=environment,
        text=True,
        capture_output=capture,
        timeout=timeout,
    )
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise LabError(
            f"{' '.join(command[:4])} failed with {result.returncode}: {detail}"
        )
    return result


def ensure_docker() -> None:
    context = run(["docker", "context", "show"], capture=True).stdout.strip()
    if context != "orbstack":
        raise LabError(
            "the testlab requires the OrbStack Docker context "
            f"(current: {context})"
        )


def ensure_state() -> None:
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    SCRATCH_ROOT.mkdir(parents=True, exist_ok=True)


def compose_up(extra_profiles: Iterable[str] = ()) -> None:
    ensure_docker()
    ensure_state()
    profiles = tuple(dict.fromkeys((*PROFILES, *extra_profiles)))
    command = compose_command("up", "-d", "--wait", profiles=profiles)
    print("[testlab] starting the containers", file=sys.stderr)
    run(command, capture=True, timeout=600)
    ensure_proxies()
    seeder_warm()


def compose_down() -> None:
    ensure_docker()
    print("[testlab] stopping the containers", file=sys.stderr)
    run(compose_command("down", "--remove-orphans"), capture=True, timeout=300)


def ps_records() -> list[dict[str, Any]]:
    result = run(
        compose_command("ps", "--format", "json"),
        capture=True,
        check=False,
    )
    records: list[dict[str, Any]] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return records


def lab_status() -> dict[str, Any]:
    records = ps_records()
    containers = []
    for record in records:
        containers.append(
            {
                "service": record.get("Service") or record.get("Name"),
                "name": record.get("Name"),
                "state": record.get("State"),
                "health": record.get("Health") or "",
            }
        )
    proxies = []
    try:
        proxies = proxy_records()
    except LabError:
        proxies = []
    return {
        "project": PROJECT,
        "stateRoot": str(STATE_ROOT),
        "containers": sorted(
            containers, key=lambda item: str(item.get("service") or "")
        ),
        "proxies": sorted(
            (proxy.get("name") for proxy in proxies if proxy.get("name"))
        ),
        "snapshots": sorted(
            path.name for path in SNAPSHOT_ROOT.glob("*") if path.is_dir()
        )
        if SNAPSHOT_ROOT.exists()
        else [],
    }


def wait_for_toxiproxy(timeout: float = 30) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            toxiproxy("GET", "/version")
            return
        except LabError:
            time.sleep(0.5)
    raise LabError(f"toxiproxy did not answer at {TOXIPROXY_URL}")


def toxiproxy(
    method: str, path: str, payload: dict[str, Any] | None = None
) -> dict[str, Any]:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        f"{TOXIPROXY_URL}{path}", data=data, method=method, headers=headers
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            body = response.read()
    except (urllib.error.URLError, TimeoutError) as error:
        raise LabError(f"toxiproxy is not reachable: {error}") from error
    if not body:
        return {}
    try:
        return json.loads(body)
    except json.JSONDecodeError as error:
        raise LabError(f"toxiproxy answered with invalid JSON: {error}") from error


def proxy_records() -> list[dict[str, Any]]:
    """Toxiproxy answers ``/proxies`` with a map keyed by proxy name."""
    body = toxiproxy("GET", "/proxies")
    if isinstance(body, dict):
        if isinstance(body.get("proxies"), list):
            return list(body["proxies"])
        return [value for value in body.values() if isinstance(value, dict)]
    if isinstance(body, list):
        return list(body)
    return []


def ensure_proxies() -> None:
    wait_for_toxiproxy()
    existing = {proxy["name"]: proxy for proxy in proxy_records()}
    for name, (upstream, port, listen_port) in PROXIES.items():
        desired_upstream = f"{upstream}:{port}"
        desired_listen = f"0.0.0.0:{listen_port}"
        current = existing.get(name)
        if current is not None:
            if (
                current.get("upstream") == desired_upstream
                and current.get("listen") == desired_listen
            ):
                continue
            toxiproxy("DELETE", f"/proxies/{name}")
        toxiproxy(
            "POST",
            "/proxies",
            {
                "name": name,
                "listen": desired_listen,
                "upstream": desired_upstream,
                "enabled": True,
            },
        )
    PORTS_FILE.write_text(
        json.dumps(
            {name: spec[2] for name, spec in PROXIES.items()},
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def clear_toxics(name: str) -> None:
    proxy = toxiproxy("GET", f"/proxies/{name}")
    for toxic in proxy.get("toxics", []):
        toxiproxy("DELETE", f"/proxies/{name}/toxics/{toxic['name']}")


def seeder_warm() -> None:
    """Make the local seeder announce to the tracker before it is needed.

    qBittorrent persists the last tracker error in its resume data. A golden
    snapshot can therefore carry a `Host not found` from the first start, when
    the indexer was not up yet, and wait out its retry interval while a
    download sits at zero. Reannouncing after the indexer is healthy clears it;
    if it does not, one restart of the seeder does.
    """
    import http.cookiejar
    import urllib.parse

    env = credentials()
    user = env.get("CUPOLA_TESTLAB_QBITTORRENT_USERNAME", "admin")
    password = env.get("CUPOLA_TESTLAB_QBITTORRENT_PASSWORD", "")
    if not password:
        return

    def announce() -> bool:
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(jar)
        )
        try:
            form = urllib.parse.urlencode(
                {"username": user, "password": password}
            ).encode()
            login = urllib.request.Request(
                "http://127.0.0.1:8081/api/v2/auth/login",
                data=form,
                headers={
                    "Content-Type": "application/x-www-form-urlencoded"
                },
            )
            opener.open(login, timeout=5).read()
            info = json.load(
                opener.open(
                    "http://127.0.0.1:8081/api/v2/torrents/info", timeout=5
                )
            )
            hashes = "|".join(
                str(item.get("hash")) for item in info if item.get("hash")
            )
            if not hashes:
                return True
            reannounce = urllib.request.Request(
                "http://127.0.0.1:8081/api/v2/torrents/reannounce",
                data=urllib.parse.urlencode({"hashes": hashes}).encode(),
                headers={
                    "Content-Type": "application/x-www-form-urlencoded"
                },
            )
            opener.open(reannounce, timeout=5).read()
            time.sleep(2)
            for item in info:
                hash_value = item.get("hash")
                if not hash_value:
                    continue
                trackers = json.load(
                    opener.open(
                        "http://127.0.0.1:8081/api/v2/torrents/trackers"
                        f"?hash={hash_value}",
                        timeout=5,
                    )
                )
                for tracker in trackers:
                    if "testlab-indexer" in str(tracker.get("url")):
                        if tracker.get("status") != 2:
                            return False
            return True
        except (OSError, ValueError):
            return False

    if announce():
        return
    run(
        compose_command("restart", "qbittorrent-seed"),
        capture=True,
        timeout=60,
    )
    time.sleep(3)
    announce()


def fault(service: str, mode: str, milliseconds: int | None = None) -> dict[str, Any]:
    if service not in PROXIES:
        raise LabError(
            f"unknown service {service!r}; choose one of "
            + ", ".join(sorted(PROXIES))
        )
    if mode not in FAULT_MODES:
        raise LabError(f"unknown fault {mode!r}; choose one of {FAULT_MODES}")
    wait_for_toxiproxy()
    if mode == "down":
        # A disabled Toxiproxy listener still accepts the TCP connection and
        # closes it before the headers, which reads as an unreadable answer.
        # A reset is what a dead host looks like at the socket, and it is the
        # state the app paints red.
        toxiproxy("POST", f"/proxies/{service}", {"enabled": True})
        clear_toxics(service)
        toxiproxy(
            "POST",
            f"/proxies/{service}/toxics",
            {
                "name": "testlab-down",
                "type": "reset_peer",
                "stream": "downstream",
                "toxicity": 1.0,
                "attributes": {"timeout": 0},
            },
        )
        return {"service": service, "fault": "down"}
    if mode == "clear":
        toxiproxy("POST", f"/proxies/{service}", {"enabled": True})
        clear_toxics(service)
        return {"service": service, "fault": "clear"}
    if mode == "slow":
        delay = milliseconds if milliseconds and milliseconds > 0 else 1500
        clear_toxics(service)
        toxiproxy(
            "POST",
            f"/proxies/{service}/toxics",
            {
                "name": "testlab-latency",
                "type": "latency",
                "stream": "downstream",
                "toxicity": 1.0,
                "attributes": {"latency": delay},
            },
        )
        return {"service": service, "fault": "slow", "milliseconds": delay}
    if mode == "timeout":
        clear_toxics(service)
        toxiproxy(
            "POST",
            f"/proxies/{service}/toxics",
            {
                "name": "testlab-timeout",
                "type": "timeout",
                "stream": "downstream",
                "toxicity": 1.0,
                "attributes": {"timeout": 0},
            },
        )
        return {"service": service, "fault": "timeout"}
    # A flap is not a background daemon: half the connections time out, which
    # is what an intermittent link reads like at the socket, and it is
    # repeatable without a process this command would have to keep alive.
    clear_toxics(service)
    toxiproxy(
        "POST",
        f"/proxies/{service}/toxics",
        {
            "name": "testlab-flap",
            "type": "timeout",
            "stream": "downstream",
            "toxicity": 0.5,
            "attributes": {"timeout": 0},
        },
    )
    return {"service": service, "fault": "flap"}


def hash_tree(root: Path, *, ignore: Iterable[str] = ("dind",)) -> dict[str, str]:
    ignored = set(ignore)
    digests: dict[str, str] = {}
    if not root.exists():
        return digests
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if relative.parts and relative.parts[0] in ignored:
            continue
        if not path.is_file():
            continue
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        digests[str(relative)] = digest.hexdigest()
    return digests


def copy_state(destination: Path) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(
        STATE_ROOT,
        destination,
        ignore=shutil.ignore_patterns("dind"),
        symlinks=True,
    )


def verify_restored(snapshot: Path) -> None:
    expected = hash_tree(snapshot)
    actual = hash_tree(STATE_ROOT)
    if expected != actual:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        changed = sorted(
            key
            for key in set(expected) & set(actual)
            if expected[key] != actual[key]
        )
        raise LabError(
            "restored state differs from the snapshot: "
            f"missing={missing[:3]} extra={extra[:3]} changed={changed[:3]}"
        )


def snapshot(name: str, force: bool = False) -> dict[str, Any]:
    if not name or "/" in name or name in (".", ".."):
        raise LabError("snapshot needs a simple name")
    target = SNAPSHOT_ROOT / name
    if target.exists() and not force:
        raise LabError(f"snapshot {name!r} exists; pass --force to replace it")
    compose_down()
    copy_state(target)
    compose_up()
    return {
        "snapshot": name,
        "files": len(hash_tree(target)),
        "stateRoot": str(STATE_ROOT),
    }


def reset(name: str = "golden") -> dict[str, Any]:
    source = SNAPSHOT_ROOT / name
    if not source.is_dir():
        raise LabError(f"snapshot {name!r} does not exist")
    compose_down()
    for child in STATE_ROOT.iterdir():
        if child.name == "dind":
            continue
        if child.is_dir():
            shutil.rmtree(child)
        else:
            child.unlink()
    shutil.copytree(source, STATE_ROOT, dirs_exist_ok=True, symlinks=True)
    verify_restored(source)
    compose_up()
    return {
        "snapshot": name,
        "files": len(hash_tree(source)),
        "stateRoot": str(STATE_ROOT),
    }


def scenario_module(name: str) -> Any:
    module_name = name.replace("-", "_")
    if not module_name.replace("_", "").isalnum():
        raise LabError("scenario needs a simple module name")
    sys.path.insert(0, str(TESTLAB_DIR))
    return importlib.import_module(f"scenarios.{module_name}")


def scenario_apply(name: str) -> dict[str, Any]:
    module = scenario_module(name)
    instance = module.SCENARIO
    compose_up(getattr(instance, "profiles", ()))
    instance.apply()
    instance.verify()
    return {"scenario": name, "applied": True}


def scenario_teardown(name: str) -> dict[str, Any]:
    module = scenario_module(name)
    instance = module.SCENARIO
    instance.teardown()
    instance.verify_absent()
    return {"scenario": name, "tornDown": True}


def scenario_list() -> dict[str, Any]:
    directory = TESTLAB_DIR / "scenarios"
    names = sorted(
        path.stem
        for path in directory.glob("*.py")
        if path.stem not in ("__init__", "base")
    )
    return {"scenarios": names}


def export_world() -> dict[str, Any]:
    ensure_state()
    result = run(
        [
            "dart",
            "run",
            "tool/testlab/export_world.dart",
            "--output",
            str(STATE_ROOT / "world.json"),
        ],
        capture=True,
        timeout=300,
    )
    if result.stdout:
        sys.stderr.write(result.stdout)
    return {"world": str(STATE_ROOT / "world.json")}


def forge() -> dict[str, Any]:
    ensure_docker()
    ensure_state()
    run(
        compose_command(
            "run",
            "--rm",
            "--build",
            "testlab-forge",
            profiles=(*PROFILES, "forge"),
        ),
        capture=True,
        timeout=600,
    )
    return {"forged": True}


def seed() -> dict[str, Any]:
    ensure_state()
    export_world()
    forge()
    result = run(
        [
            sys.executable,
            str(TESTLAB_DIR / "seed_lab.py"),
            "--state-dir",
            str(STATE_ROOT),
        ],
        capture=True,
        timeout=600,
    )
    if result.stdout:
        sys.stderr.write(result.stdout)
    return {"seeded": True, "stateRoot": str(STATE_ROOT)}


def spike() -> dict[str, Any]:
    forge()
    from spike_media import run as run_spike

    return run_spike()


def doctor() -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        checks.append({"check": name, "ok": ok, "detail": detail})

    try:
        context = run(["docker", "context", "show"], capture=True).stdout.strip()
        check("docker context is orbstack", context == "orbstack", context)
    except LabError as error:
        check("docker context is orbstack", False, str(error))
    check("compose file exists", COMPOSE_FILE.is_file(), str(COMPOSE_FILE))
    check("state root exists", STATE_ROOT.is_dir(), str(STATE_ROOT))
    if CREDENTIALS.exists():
        mode = CREDENTIALS.stat().st_mode & 0o777
        check("credentials are chmod 600", mode == 0o600, oct(mode))
        check("control token exists", bool(control_token()))
    else:
        check("credentials are chmod 600", False, "credentials.env is missing")
        check("control token exists", False, "credentials.env is missing")
    records = ps_records()
    unhealthy = [
        record
        for record in records
        if (record.get("Health") or "").lower() not in ("", "healthy")
        or (record.get("State") or "").lower() != "running"
    ]
    check(
        "every container is running and healthy",
        bool(records) and not unhealthy,
        f"{len(records)} containers, {len(unhealthy)} not healthy",
    )
    try:
        proxies = proxy_records()
        missing = sorted(set(PROXIES) - {proxy["name"] for proxy in proxies})
        check("every proxy exists", not missing, ",".join(missing))
    except LabError as error:
        check("every proxy exists", False, str(error))
    try:
        with urllib.request.urlopen(
            "http://127.0.0.1:8188/healthz", timeout=3
        ) as answer:
            check("the indexer answers", answer.status == 200)
    except (urllib.error.URLError, TimeoutError) as error:
        check("the indexer answers", False, str(error))
    world = STATE_ROOT / "world.json"
    if world.is_file():
        try:
            document = json.loads(world.read_text(encoding="utf-8"))
            titles = document.get("titles")
            check(
                "the world is exported",
                isinstance(titles, list) and len(titles) > 0,
                f"{len(titles) if isinstance(titles, list) else 0} titles",
            )
        except (OSError, ValueError) as error:
            check("the world is exported", False, str(error))
    else:
        check("the world is exported", False, str(world))
    return {"ok": all(item["ok"] for item in checks), "checks": checks}


def dispatch(command: str, arguments: list[str]) -> dict[str, Any]:
    """Run one whitelisted command for the local control API."""
    if command == "status":
        return lab_status()
    if command == "up":
        compose_up(arguments)
        ensure_proxies()
        return {"up": True, "profiles": list(arguments)}
    if command == "down":
        compose_down()
        return {"down": True}
    if command == "seed":
        return seed()
    if command == "snapshot":
        if not arguments:
            raise LabError("snapshot needs a name")
        return snapshot(arguments[0], force="--force" in arguments)
    if command == "reset":
        return reset(arguments[0] if arguments else "golden")
    if command == "scenario":
        if not arguments:
            raise LabError("scenario needs list, apply or teardown")
        action = arguments[0]
        if action == "list":
            return scenario_list()
        if action in ("apply", "teardown") and len(arguments) > 1:
            if action == "apply":
                return scenario_apply(arguments[1])
            return scenario_teardown(arguments[1])
        raise LabError("usage: scenario list|apply <name>|teardown <name>")
    if command == "fault":
        if len(arguments) < 2:
            raise LabError("usage: fault <service> down|timeout|slow <ms>|flap|clear")
        milliseconds = None
        if len(arguments) > 2:
            try:
                milliseconds = int(arguments[2])
            except ValueError as error:
                raise LabError("slow needs milliseconds") from error
        return fault(arguments[0], arguments[1], milliseconds)
    if command == "doctor":
        return doctor()
    if command == "spike":
        return spike()
    if command == "proxies":
        ensure_proxies()
        return {"proxies": list(PROXIES), "portsFile": str(PORTS_FILE)}
    raise LabError(f"command {command!r} is not available over the control API")


class ControlHandler(http.server.BaseHTTPRequestHandler):
    server_version = "CupolaTestlab/1.0"

    def log_message(self, format: str, *args: Any) -> None:
        # The request path is safe; query strings never carry the token.
        sys.stderr.write("[testlab] %s\n" % (format % args))

    def _authorised(self) -> bool:
        expected = control_token()
        if not expected:
            self._answer(503, {"error": "the control token is missing"})
            return False
        header = self.headers.get("Authorization", "")
        presented = header.removeprefix("Bearer ").strip()
        if not hmac.compare_digest(presented, expected):
            self._answer(401, {"error": "unauthorised"})
            return False
        return True

    def _answer(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 - the HTTP verb is the name
        if self.path == "/health":
            self._answer(200, {"ok": True})
            return
        if self.path == "/status":
            if self._authorised():
                self._answer(200, dispatch("status", []))
            return
        self._answer(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802 - the HTTP verb is the name
        if self.path != "/command":
            self._answer(404, {"error": "not found"})
            return
        if not self._authorised():
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 65536:
            self._answer(400, {"error": "a small JSON body is required"})
            return
        try:
            body = json.loads(self.rfile.read(length))
            command = str(body["command"])
            arguments = [str(item) for item in body.get("arguments", [])]
        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
            self._answer(400, {"error": "expected {command, arguments}"})
            return
        try:
            self._answer(200, dispatch(command, arguments))
        except LabError as error:
            self._answer(400, {"error": str(error)})


def serve(port: int) -> None:
    token = control_token()
    if not token:
        raise LabError(
            "the control token is missing; run test/e2e/testlab/bootstrap.sh"
        )
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), ControlHandler)
    print(f"[testlab] control API on http://127.0.0.1:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Control plane for the disposable Cupola testlab."
    )
    commands = parser.add_subparsers(dest="command", required=True)

    up = commands.add_parser("up", help="start the lab and its proxies")
    up.add_argument("--profile", action="append", default=[])

    commands.add_parser("down", help="stop the lab, keeping its state")
    commands.add_parser("status", help="print containers and proxies")
    commands.add_parser("seed", help="run the deterministic seed")
    commands.add_parser("doctor", help="check the lab end to end")
    commands.add_parser("proxies", help="create or repair the toxiproxy proxies")
    commands.add_parser("spike", help="parse the forge's files through the arrs")

    snapshot_parser = commands.add_parser("snapshot", help="archive the state")
    snapshot_parser.add_argument("name")
    snapshot_parser.add_argument("--force", action="store_true")

    reset_parser = commands.add_parser("reset", help="restore a snapshot")
    reset_parser.add_argument("name", nargs="?", default="golden")

    scenario = commands.add_parser("scenario", help="apply a scenario")
    scenario.add_argument("action", choices=("list", "apply", "teardown"))
    scenario.add_argument("name", nargs="?")

    fault_parser = commands.add_parser("fault", help="inject a service fault")
    fault_parser.add_argument("service")
    fault_parser.add_argument("mode", choices=FAULT_MODES)
    fault_parser.add_argument("milliseconds", nargs="?", type=int)

    serve_parser = commands.add_parser("serve", help="run the local control API")
    serve_parser.add_argument("--port", type=int, default=8799)

    commands.add_parser(
        "app-config", help="configure the app for a profile (arrives in L11)"
    )
    commands.add_parser(
        "play", help="start a playback session (arrives in L8)"
    )
    commands.add_parser(
        "journeys", help="run the UI journeys (arrives in L12)"
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_args(list(argv or sys.argv[1:]))
    try:
        if arguments.command == "up":
            compose_up(arguments.profile)
            ensure_proxies()
            print(json.dumps(lab_status(), indent=2))
        elif arguments.command == "down":
            compose_down()
            print(json.dumps({"down": True}))
        elif arguments.command == "status":
            print(json.dumps(lab_status(), indent=2))
        elif arguments.command == "seed":
            print(json.dumps(seed(), indent=2))
        elif arguments.command == "doctor":
            report = doctor()
            for item in report["checks"]:
                mark = "ok" if item["ok"] else "FAIL"
                print(f"[{mark}] {item['check']} {item['detail']}".rstrip())
            return 0 if report["ok"] else 1
        elif arguments.command == "proxies":
            ensure_proxies()
            print(json.dumps({"proxies": list(PROXIES)}, indent=2))
        elif arguments.command == "spike":
            report = spike()
            for item in report["checks"]:
                mark = "ok" if item["ok"] else "FAIL"
                print(f"[{mark}] {item['check']} {item['detail']}".rstrip())
            print(json.dumps(report, indent=2))
            return 0 if report["ok"] else 1
        elif arguments.command == "snapshot":
            print(json.dumps(snapshot(arguments.name, arguments.force), indent=2))
        elif arguments.command == "reset":
            print(json.dumps(reset(arguments.name), indent=2))
        elif arguments.command == "scenario":
            if arguments.action == "list":
                print(json.dumps(scenario_list(), indent=2))
            elif not arguments.name:
                raise LabError("scenario needs a name")
            elif arguments.action == "apply":
                print(json.dumps(scenario_apply(arguments.name), indent=2))
            else:
                print(json.dumps(scenario_teardown(arguments.name), indent=2))
        elif arguments.command == "fault":
            print(
                json.dumps(
                    fault(
                        arguments.service,
                        arguments.mode,
                        arguments.milliseconds,
                    ),
                    indent=2,
                )
            )
        elif arguments.command == "serve":
            serve(arguments.port)
        elif arguments.command == "app-config":
            raise LabError("app-config arrives in L11")
        elif arguments.command == "play":
            raise LabError("play arrives in L8")
        elif arguments.command == "journeys":
            raise LabError("journeys arrives in L12")
    except LabError as error:
        print(f"testlab: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
