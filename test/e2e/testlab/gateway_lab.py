"""A gateway in front of a service, for the answers the app must recognise.

One process plays every part a gateway can take: Cloudflare Access (its login
redirect, and its refusal of a request without the service token), a proxy's own
password, required custom headers, a sign-in page Cupola cannot complete, and a
service that answers in someone else's place. The part is on the path, so the
same server can be all of them at once.

The server is a process of the host: the app, the lab and the test all reach it
on 127.0.0.1, and the scenario starts and stops it.
"""

from __future__ import annotations

import base64
import json
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

STATE_ROOT = Path(
    os.environ.get("CUPOLA_TESTLAB_STATE_DIR", ".ai/scratch/zz_testlab/state")
).resolve()
PID_FILE = STATE_ROOT / "gateway-lab.pid"
PORT = int(os.environ.get("CUPOLA_TESTLAB_GATEWAY_PORT", "8466"))
TOKEN_ID = "cupola-testlab-client-id"
TOKEN_SECRET = "cupola-testlab-client-secret"
BASIC_USER = "cupola"
BASIC_PASSWORD = "cupola-gateway-pass"
CUSTOM_HEADER = "X-Cupola-Lab"
CUSTOM_VALUE = "cupola-lab-value"

WEB_PAGE = (
    b"<!doctype html><html><body><form><input type=password name=password>"
    b"<button>Sign in</button></form></body></html>"
)
OTHER_APP = b"<!doctype html><html><body><div id=app>Another application</div></body></html>"


def basic_header() -> str:
    raw = base64.b64encode(f"{BASIC_USER}:{BASIC_PASSWORD}".encode()).decode()
    return f"Basic {raw}"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args: object) -> None:
        """Quiet: the lab's own log has the story."""

    def do_GET(self) -> None:  # noqa: N802 (http.server's naming)
        self._answer()

    def do_POST(self) -> None:  # noqa: N802
        self._answer()

    def _mode(self) -> str:
        return self.path.strip("/").split("/")[0] or "service"

    def _answer(self) -> None:
        mode = self._mode()
        if mode == "cf-refused":
            # The token was sent and Access refused it anyway: the challenge
            # names the Access team domain, which is how the app tells this
            # refusal from the service's own.
            body = b'{"error":"access denied: invalid service token"}'
            self.send_response(403)
            self.send_header(
                "WWW-Authenticate",
                'Bearer realm="myteam.cloudflareaccess.com"',
            )
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if mode == "cf":
            if not self.headers.get("CF-Access-Client-Id"):
                self.send_response(302)
                self.send_header(
                    "Location",
                    f"https://myteam.cloudflareaccess.com/cdn-cgi/access/login/127.0.0.1:{PORT}",
                )
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self._json({"ok": True, "mode": mode})
            return
        if mode == "basic":
            if self.headers.get("Authorization") != basic_header():
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="Cupola lab"')
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self._json({"ok": True, "mode": mode})
            return
        if mode == "headers":
            if self.headers.get(CUSTOM_HEADER) != CUSTOM_VALUE:
                self.send_response(403)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self._json({"ok": True, "mode": mode})
            return
        if mode == "signin":
            self._bytes(WEB_PAGE, "text/html; charset=utf-8")
            return
        if mode == "other":
            self._bytes(OTHER_APP, "text/html; charset=utf-8")
            return
        self._json({"ok": True, "mode": mode})

    def _json(self, payload: dict[str, object]) -> None:
        self._bytes(json.dumps(payload).encode(), "application/json")

    def _bytes(self, body: bytes, content_type: str) -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def serve(port: int = PORT) -> None:
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.serve_forever()


def listening(port: int = PORT) -> bool:
    with socket.socket() as sock:
        sock.settimeout(0.5)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def start(port: int = PORT) -> int:
    """Start the gateway and wait for its port."""

    if listening(port):
        stop()
    process = subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), "--serve", "--port", str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(process.pid), encoding="utf-8")
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if listening(port):
            return process.pid
        time.sleep(0.2)
    raise RuntimeError("the gateway did not open its port")


def stop() -> None:
    if not PID_FILE.exists():
        return
    try:
        pid = int(PID_FILE.read_text(encoding="utf-8").strip())
        os.kill(pid, signal.SIGTERM)
    except (ProcessLookupError, ValueError):
        pass
    finally:
        PID_FILE.unlink(missing_ok=True)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if not listening():
            return
        time.sleep(0.2)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """A redirect is an answer here, not a place to go."""

    def redirect_request(self, *args: object, **kwargs: object) -> None:
        return None


def ask(
    mode: str, headers: dict[str, str] | None = None, timeout: float = 5.0
) -> tuple[int, str]:
    """Ask one of the gateway's parts; answers (status, body)."""

    request = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/{mode}", headers=headers or {}
    )
    opener = urllib.request.build_opener(_NoRedirect)
    try:
        with opener.open(request, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8", "replace")
    except urllib.error.URLError as error:
        return 0, str(error)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="The lab's gateway.")
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--port", type=int, default=PORT)
    arguments = parser.parse_args()
    if arguments.serve:
        serve(arguments.port)
    else:
        print(json.dumps({"port": arguments.port, "listening": listening(arguments.port)}))
