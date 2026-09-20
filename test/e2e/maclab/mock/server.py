"""Small deterministic protocol mocks for the macOS Cupola lab.

These are intentionally limited to the two transports for which a generic
vendor container is not available. They are not a replacement for certification
against a real TrueNAS or Unraid host; the response shapes are the contract
fixtures used by Cupola's clients and are suitable for repeatable UI/error
passes.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import socket
import socketserver
import struct
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


API_KEY = os.environ.get("MOCK_API_KEY", "test-key")
MODE = os.environ.get("MOCK_MODE", "unraid").lower()


def json_bytes(value: object) -> bytes:
    return json.dumps(value, separators=(",", ":")).encode("utf-8")


def truenas_result(method: str, params: list[object]) -> object:
    if method == "auth.login_with_api_key":
        return bool(params and params[0] == API_KEY)
    if method == "core.ping":
        return "pong"
    if method == "system.version":
        return {"version": "25.10.2.1", "hostname": "cupola-truenas-mock"}
    if method == "system.info":
        return {
            "version": "25.10.2.1",
            "hostname": "cupola-truenas-mock",
            "uptime_seconds": 86400,
            "cores": 8,
            "physmem": 17179869184,
            "loadavg": [0.1, 0.2, 0.3],
            "model": "Cupola TrueNAS fixture",
        }
    if method == "core.get_methods":
        return []
    if method == "core.get_jobs":
        return []
    if method in {"system.general.config", "system.advanced.config", "mail.config"}:
        return {}
    if method == "update.check_available":
        return {"status": "UNAVAILABLE"}
    if method in {"pool.query", "pool.dataset.query", "sharing.smb.query", "sharing.nfs.query", "iscsi.target.query", "user.query", "group.query", "service.query", "app.query", "virt.instance.query", "alert.list", "reporting.realtime.stats"}:
        return []
    if method == "pool.get_disks":
        return []
    if method in {"pool.dataset.get_instance", "sharing.smb.get_instance", "sharing.nfs.get_instance", "user.get_instance", "group.get_instance"}:
        return {}
    if method.endswith(".create") or method.endswith(".update") or method.endswith(".delete"):
        return True
    if method.startswith("app.") or method.startswith("virt.instance."):
        return True
    if method.startswith("service.") or method.startswith("alert."):
        return True
    return {}


class WebSocketConnection:
    def __init__(self, sock: socket.socket):
        self.sock = sock

    def send_text(self, value: str) -> None:
        payload = value.encode("utf-8")
        length = len(payload)
        if length < 126:
            header = bytes([0x81, length])
        elif length < 65536:
            header = bytes([0x81, 126]) + struct.pack("!H", length)
        else:
            header = bytes([0x81, 127]) + struct.pack("!Q", length)
        self.sock.sendall(header + payload)

    def read_frame(self) -> tuple[int, bytes] | None:
        header = self.sock.recv(2)
        if len(header) < 2:
            return None
        opcode = header[0] & 0x0F
        masked = bool(header[1] & 0x80)
        length = header[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", self.sock.recv(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self.sock.recv(8))[0]
        mask = self.sock.recv(4) if masked else b""
        data = bytearray()
        while len(data) < length:
            chunk = self.sock.recv(length - len(data))
            if not chunk:
                return None
            data.extend(chunk)
        if masked:
            for index in range(length):
                data[index] ^= mask[index % 4]
        return opcode, bytes(data)


class TrueNasHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        request = b""
        while b"\r\n\r\n" not in request:
            chunk = self.request.recv(4096)
            if not chunk:
                return
            request += chunk
        headers = request.decode("latin1").split("\r\n")
        key = next(
            (line.split(":", 1)[1].strip() for line in headers if line.lower().startswith("sec-websocket-key:")),
            "",
        )
        if not key:
            return
        accept = base64.b64encode(
            hashlib.sha1(
                (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")
            ).digest()
        ).decode("ascii")
        response = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        ).encode("latin1")
        self.request.sendall(response)
        connection = WebSocketConnection(self.request)
        while True:
            frame = connection.read_frame()
            if frame is None:
                return
            opcode, payload = frame
            if opcode == 0x8:
                return
            if opcode != 0x1:
                continue
            try:
                message = json.loads(payload.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if not isinstance(message, dict) or "id" not in message:
                continue
            params = message.get("params", [])
            if not isinstance(params, list):
                params = []
            result = truenas_result(str(message.get("method", "")), params)
            connection.send_text(json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": result}))


class UnraidHandler(BaseHTTPRequestHandler):
    server_version = "CupolaUnraidMock/1.0"

    def do_GET(self) -> None:  # noqa: N802 - healthcheck endpoint
        if self.path == "/graphql":
            self.send_response(200)
            self.end_headers()
            return
        self.send_error(404)

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path != "/graphql":
            self.send_error(404)
            return
        if self.headers.get("x-api-key") != API_KEY:
            self.send_response(401)
            self.end_headers()
            return
        try:
            size = int(self.headers.get("content-length", "0"))
            payload = json.loads(self.rfile.read(size))
        except (ValueError, json.JSONDecodeError):
            self.send_error(400)
            return
        query = str(payload.get("query", ""))
        data: dict[str, object] = {}
        if "info" in query:
            data["info"] = {"os": {"distro": "Unraid", "release": "7.0.0-mock", "uptime": 86400}}
        if "array" in query:
            data["array"] = {
                "state": "STARTED",
                "capacity": {"kilobytes": {"free": 8000000, "used": 2000000, "total": 10000000}},
                "disks": [{"name": "disk1", "status": "DISK_OK", "temp": 34}],
            }
        if "dockerContainers" in query:
            data["dockerContainers"] = [{"id": "mock-1", "names": ["cupola-lab"], "state": "running", "status": "Up", "autoStart": True}]
        if "me" in query:
            data["me"] = {"roles": ["ADMIN"], "permissions": [{"resource": "VM", "actions": ["START", "STOP"]}]}
        if "vms" in query:
            data["vms"] = {"domains": [{"id": "vm-1", "name": "cupola-vm", "state": "RUNNING"}]}
        if "notifications" in query:
            data["notifications"] = {
                "overview": {"unread": {"info": 0, "warning": 1, "alert": 0, "total": 1}, "archive": {"info": 0, "warning": 0, "alert": 0, "total": 0}},
                "list": [{"id": "notice-1", "title": "Lab notice", "subject": "Fixture", "description": "Deterministic Unraid mock", "importance": "WARNING", "link": "", "type": "SYSTEM", "timestamp": 1700000000, "formattedTimestamp": "2023-11-14 22:13"}],
            }
        if "shares" in query:
            data["shares"] = [{"id": "share-1", "name": "media", "used": 1000, "size": 10000, "cache": "", "comment": "Lab share", "luksStatus": "NOT_ENCRYPTED"}]
        if "archiveNotification" in query:
            data["archiveNotification"] = {"id": "notice-1", "title": "Lab notice", "subject": "Fixture", "description": "Archived", "importance": "INFO", "link": "", "type": "SYSTEM", "timestamp": 1700000000, "formattedTimestamp": "2023-11-14 22:13"}
        if "mutation" in query and "archiveNotification" not in query:
            data["vm"] = {"start": True, "stop": True, "pause": True, "resume": True, "restart": True, "shutdown": True}
        self._send_json({"data": data})

    def _send_json(self, payload: object) -> None:
        body = json_bytes(payload)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> None:
    if MODE == "truenas":
        server = socketserver.ThreadingTCPServer(("0.0.0.0", 8460), TrueNasHandler)
    else:
        server = ThreadingHTTPServer(("0.0.0.0", 8480), UnraidHandler)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
