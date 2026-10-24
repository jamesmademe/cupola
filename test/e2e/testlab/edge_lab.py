"""The lab's edge: a self-signed origin in front of a service, with a
certificate the lab can rotate.

The edge is the one place the app meets a certificate of its own, so it is
where the pin earns its keep: the app reads the fingerprint, pins it, and when
the lab makes a new certificate the old pin must stop working. It is a process
of the host, like the gateway: the certificate and the port are enough for the
app, the lab and the test to meet it.
"""

from __future__ import annotations

import hashlib
import http.client
import json
import os
import socket
import socketserver
import ssl
import subprocess
import process_ownership
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
STATE_ROOT = Path(
    os.environ.get("CUPOLA_TESTLAB_STATE_DIR", REPO_ROOT / ".ai/scratch/zz_testlab/state")
).resolve()
EDGE_DIR = STATE_ROOT / "edge"
CERT = EDGE_DIR / "cert.pem"
KEY = EDGE_DIR / "key.pem"
PID_FILE = EDGE_DIR / "edge.pid"
PORT = int(os.environ.get("CUPOLA_TESTLAB_EDGE_PORT", "8444"))
UPSTREAM = ("127.0.0.1", 7878)
UPSTREAM_KEY = "test-key"
MARKER = "edge_lab.py"


def _name(port: int) -> str:
    return f"edge:{port}"


def _pid_file(port: int) -> Path:
    if port == PORT:
        return PID_FILE
    return EDGE_DIR / f"edge-{port}.pid"


def write_certificate() -> None:
    """Make a self-signed certificate for the edge, valid for two days."""

    EDGE_DIR.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-keyout",
            str(KEY),
            "-out",
            str(CERT),
            "-days",
            "2",
            "-subj",
            "/CN=radarr.test",
            "-addext",
            "subjectAltName=DNS:radarr.test,IP:127.0.0.1",
        ],
        capture_output=True,
        check=True,
    )
    CERT.chmod(0o644)
    KEY.chmod(0o600)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args: object) -> None:
        """Quiet: the lab's own log has the story."""

    def do_GET(self) -> None:  # noqa: N802 (http.server's naming)
        self._forward("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._forward("POST")

    def _forward(self, method: str) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        connection = http.client.HTTPConnection(*UPSTREAM, timeout=10)
        headers = {
            "X-Api-Key": UPSTREAM_KEY,
            "Accept": self.headers.get("Accept", "application/json"),
        }
        if body:
            headers["Content-Type"] = self.headers.get(
                "Content-Type", "application/json"
            )
        try:
            connection.request(method, self.path, body=body, headers=headers)
            answer = connection.getresponse()
            payload = answer.read()
            self.send_response(answer.status)
            self.send_header(
                "Content-Type", answer.getheader("Content-Type", "application/json")
            )
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except OSError:
            self.send_response(502)
            self.send_header("Content-Length", "0")
            self.end_headers()
        finally:
            connection.close()


def serve(port: int = PORT) -> None:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(CERT, KEY)
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


def listening(port: int = PORT) -> bool:
    with socket.socket() as sock:
        sock.settimeout(0.5)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def fingerprint(port: int = PORT) -> str:
    """The SHA-256 of the certificate the edge presents, as lowercase hex."""

    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", port), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname=None) as tls:
            der = tls.getpeercert(binary_form=True)
    return hashlib.sha256(der).hexdigest()


def _spawn(port: int) -> int:
    process = subprocess.Popen(
        [__import__("sys").executable, str(Path(__file__).resolve()), "--serve", "--port", str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    EDGE_DIR.mkdir(parents=True, exist_ok=True)
    _pid_file(port).write_text(str(process.pid), encoding="utf-8")
    return process.pid


def up(port: int = PORT, owner: str = "edge-lab") -> None:
    """Make a certificate, start the edge and wait for it.

    A listening edge is never restarted unless this owner already holds it:
    the process may belong to another scenario, or to no lab at all.
    """
    held = process_ownership.record(_name(port))
    if listening(port):
        if held is not None and held.get("owner") == owner:
            return
        if held is not None:
            raise RuntimeError(
                f"the edge on {port} belongs to {held.get('owner')}; "
                "tear that scenario down first"
            )
        raise RuntimeError(
            f"the edge on {port} was not started by the testlab; "
            "stop it before applying this scenario"
        )
    # A record can outlive its process (a crash, a reset). Clear only a
    # matching process; anything else is left alone.
    process_ownership.stop(
        _name(port),
        marker=MARKER,
        port=port,
        legacy_pid_file=_pid_file(port),
    )
    write_certificate()
    pid = _spawn(port)
    process_ownership.claim(_name(port), pid, port, owner, MARKER)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        try:
            if fingerprint(port):
                return
        except (OSError, ssl.SSLError):
            pass
        time.sleep(0.3)
    process_ownership.stop(
        _name(port), marker=MARKER, port=port, owner=owner
    )
    raise RuntimeError("the edge did not present a certificate")


def stop(port: int = PORT, owner: str | None = None) -> None:
    """Stop the edge this owner started, and nothing else.

    Idempotent: no record, a dead process and a second teardown are all a
    success. A record owned by another scenario is left in place.
    """
    process_ownership.stop(
        _name(port),
        marker=MARKER,
        port=port,
        owner=owner,
        # A legacy PID file has no owner: only an unowned stop may use it.
        legacy_pid_file=_pid_file(port) if owner is None else None,
    )
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if not listening(port):
            return
        time.sleep(0.2)


def rotate(port: int = PORT) -> str:
    """A new certificate and a new edge; answers the new fingerprint."""

    held = process_ownership.record(_name(port))
    if held is not None and held.get("owner") not in (None, "edge-lab"):
        raise RuntimeError(
            f"the edge on {port} belongs to {held.get('owner')}; cannot rotate it"
        )
    stop(port, owner="edge-lab")
    up(port, owner="edge-lab")
    return fingerprint(port)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="The lab's edge.")
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--rotate", action="store_true")
    parser.add_argument("--fingerprint", action="store_true")
    parser.add_argument("--port", type=int, default=PORT)
    arguments = parser.parse_args()
    if arguments.serve:
        serve(arguments.port)
    elif arguments.rotate:
        print(json.dumps({"fingerprint": rotate(arguments.port)}))
    elif arguments.fingerprint:
        print(json.dumps({"fingerprint": fingerprint(arguments.port)}))
