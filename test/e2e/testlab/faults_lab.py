"""The lab's fault classes, and the second address that means "out of home".

Every service sits behind the Toxiproxy the control plane already keeps, so a
fault is a toxic on the proxy the app talks to and the away address is a second
listener on the same upstream that can be switched off on its own. The direct
port of each service stays free for the transport harness, which must not
depend on the fault layer.
"""

from __future__ import annotations

import socket
import time
from typing import Any

import testlab
from scenarios.base import Scenario, ScenarioError

#: Radarr is the service the fault classes are proved on: it answers a plain
#: GET, so every class is visible as a different failure and not as a quirk.
SERVICE = "radarr"


def fault(mode: str, milliseconds: int | None = None) -> dict[str, Any]:
    """Apply one of the lab's fault classes to the service's proxy."""

    return testlab.fault(SERVICE, mode, milliseconds)


def clear() -> dict[str, Any]:
    """Take the fault away and let the service answer again."""

    return testlab.fault(SERVICE, "clear")


def proxy_port(service: str = SERVICE) -> int:
    """The host port of the proxy in front of the service."""

    return int(testlab.PROXIES[service][2])


def away_name(service: str = SERVICE) -> str:
    return f"{service}-away"


#: Away addresses that do not sit on the next port after the proxy's. The
#: qBittorrent proxy moved onto the WebUI's port (8080), and the next one is the
#: seeder's published port, so its away address keeps the port it had.
AWAY_PORTS = {"qbittorrent": 28081}


def away_port(service: str = SERVICE) -> int:
    """The host port of the away address: the next one after the proxy's."""

    return AWAY_PORTS.get(service, proxy_port(service) + 1)


def ensure_away(service: str = SERVICE) -> dict[str, Any]:
    """Create the away listener on the same upstream, if it is not there."""

    name = away_name(service)
    for record in testlab.proxy_records():
        if record.get("name") == name:
            return {"name": name, "listen": away_port(service)}
    upstream_host, upstream_port, _ = testlab.PROXIES[service]
    return testlab.toxiproxy(
        "POST",
        "/proxies",
        {
            "name": name,
            "listen": f"0.0.0.0:{away_port(service)}",
            "upstream": f"{upstream_host}:{upstream_port}",
            "enabled": True,
        },
    )


def away(service: str, on: bool) -> dict[str, Any]:
    """Switch the away address on or off."""

    ensure_away(service)
    return testlab.toxiproxy(
        "POST", f"/proxies/{away_name(service)}", {"enabled": bool(on)}
    )


def away_listening(service: str = SERVICE) -> bool:
    for record in testlab.proxy_records():
        if record.get("name") == away_name(service):
            return bool(record.get("enabled"))
    return False


def probe_proxy(
    service: str = SERVICE, timeout: float = 8.0, port: int | None = None
) -> tuple[bool, float]:
    """Ask a listener for the service; answers (it answered, how long it took).

    A fault closes the connection before a status line arrives, so the answer
    is whether an HTTP status line came back at all, not whether the socket
    stayed open. [port] asks another listener, the away address for one.
    """

    start = time.monotonic()
    try:
        with socket.create_connection(
            ("127.0.0.1", port or proxy_port(service)), timeout=timeout
        ) as sock:
            sock.settimeout(timeout)
            sock.sendall(
                b"GET /api/v3/system/status HTTP/1.1\r\n"
                b"Host: radarr\r\nConnection: close\r\n\r\n"
            )
            # The first chunk is the answer. Reading to EOF would make a
            # keep-alive server (qBittorrent) look silent: it sends a complete
            # status line and then waits for the next request, not a close.
            data = sock.recv(4096)
    except OSError:
        return False, time.monotonic() - start
    return data.startswith(b"HTTP/"), time.monotonic() - start


def proxy_toxics(service: str = SERVICE) -> list[dict[str, Any]]:
    record = testlab.toxiproxy("GET", f"/proxies/{service}")
    toxics = record.get("toxics")
    return list(toxics) if isinstance(toxics, list) else []


class FaultScenario(Scenario):
    """One fault class on the service's proxy, with the lab's own proof.

    The toxic's presence is the deterministic fact; the socket's behaviour is
    the one the app reads. A scenario that cannot show both is not done.
    """

    profiles = ("core",)
    mode = "down"
    milliseconds: int | None = None

    def apply(self) -> None:
        fault(self.mode, self.milliseconds)

    def teardown(self) -> None:
        clear()

    def verify(self) -> None:
        toxics = proxy_toxics()
        if not any(toxic.get("name", "").startswith("testlab-") for toxic in toxics):
            raise ScenarioError("the fault is not on the proxy")
        answered, elapsed = probe_proxy()
        if self.mode == "slow":
            delay = (self.milliseconds or 2000) / 1000
            if not answered:
                raise ScenarioError("the slow service did not answer at all")
            if elapsed < delay * 0.8:
                raise ScenarioError(
                    f"the slow service answered in {elapsed:.2f}s, not {delay:.2f}s"
                )
            return
        if self.mode == "flap":
            outcomes = [probe_proxy()[0] for _ in range(6)]
            if all(outcomes):
                raise ScenarioError("the flapping link answered every time")
            if not any(outcomes):
                raise ScenarioError("the flapping link never answered")
            return
        if answered:
            raise ScenarioError("the service still answered")

    def verify_absent(self) -> None:
        if proxy_toxics():
            raise ScenarioError("a toxic is still on the proxy")
        answered, _ = probe_proxy()
        if not answered:
            raise ScenarioError("the service does not answer without the fault")
