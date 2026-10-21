"""Small deterministic protocol mocks for the macOS Cupola lab.

These are intentionally limited to the two transports for which a generic
vendor container is not available. They are not a replacement for certification
against a real TrueNAS or Unraid host; the response shapes are the contract
fixtures used by Cupola's clients and are suitable for repeatable UI/error
passes.

The TrueNAS mock speaks TLS only, like a TrueNAS that revokes an API key sent
over a cleartext socket, with the self-signed certificate that
test/e2e/testlab/truenas_cert.sh keeps in the lab's state directory. It reads
the certificate for every connection, so one made again is served without a
restart. With `--healthcheck` this file performs a TLS handshake against the
running mock and exits 0 or 1, which is what the Compose healthcheck runs.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import socket
import socketserver
import ssl
import struct
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl
from xml.sax.saxutils import escape


API_KEY = os.environ.get("MOCK_API_KEY", "test-key")
MODE = os.environ.get("MOCK_MODE", "unraid").lower()
TLS_CERT = os.environ.get("MOCK_TLS_CERT", "/certs/truenas.crt")
TLS_KEY = os.environ.get("MOCK_TLS_KEY", "/certs/truenas.key")
TRUENAS_PORT = 8460
INDEXER_PORT = 8088
FORGE_DIR = os.environ.get("MOCK_FORGE_DIR", "/forge")


def json_bytes(value: object) -> bytes:
    return json.dumps(value, separators=(",", ":")).encode("utf-8")


def tls_context() -> ssl.SSLContext:
    """A server context over the certificate as it is on disk right now."""
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(TLS_CERT, TLS_KEY)
    return context


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

    def read_exact(self, size: int) -> bytes | None:
        # A TLS socket returns what is left of one record, which can be fewer
        # bytes than asked for, so every read here loops until it has them all.
        data = bytearray()
        while len(data) < size:
            chunk = self.sock.recv(size - len(data))
            if not chunk:
                return None
            data.extend(chunk)
        return bytes(data)

    def read_frame(self) -> tuple[int, bytes] | None:
        header = self.read_exact(2)
        if header is None:
            return None
        opcode = header[0] & 0x0F
        masked = bool(header[1] & 0x80)
        length = header[1] & 0x7F
        if length == 126:
            extended = self.read_exact(2)
            if extended is None:
                return None
            length = struct.unpack("!H", extended)[0]
        elif length == 127:
            extended = self.read_exact(8)
            if extended is None:
                return None
            length = struct.unpack("!Q", extended)[0]
        mask = b""
        if masked:
            mask = self.read_exact(4)
            if mask is None:
                return None
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
        # The handshake runs here, on the connection's own thread: a client that
        # stalls in it holds only itself. One that refuses the certificate, or
        # connects to look at it and leaves (the healthcheck, the app's
        # certificate probe), ends the connection with an error and nothing
        # more: ssl.SSLError is an OSError, so one clause says it all.
        try:
            connection = tls_context().wrap_socket(self.request, server_side=True)
            with connection:
                self.serve(connection)
        except OSError:
            return

    def serve(self, sock: ssl.SSLSocket) -> None:
        request = b""
        while b"\r\n\r\n" not in request:
            chunk = sock.recv(4096)
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
        sock.sendall(response)
        connection = WebSocketConnection(sock)
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


def bencode(value: object) -> bytes:
    if isinstance(value, int):
        return b"i" + str(value).encode("ascii") + b"e"
    if isinstance(value, str):
        value = value.encode("utf-8")
    if isinstance(value, bytes):
        return str(len(value)).encode("ascii") + b":" + value
    if isinstance(value, list):
        return b"l" + b"".join(bencode(item) for item in value) + b"e"
    if isinstance(value, dict):
        items = []
        for key in sorted(value):
            encoded = key.encode("utf-8") if isinstance(key, str) else key
            items.append(bencode(encoded) + bencode(value[key]))
        return b"d" + b"".join(items) + b"e"
    raise TypeError(f"cannot bencode {type(value).__name__}")


class IndexerHandler(BaseHTTPRequestHandler):
    """Torznab search and a BEP 3 tracker, in one local service.

    Radarr asks for the release; qBittorrent announces here and receives the
    seeder's address. The tracker keeps peers in memory, so a restarted lab
    simply waits for the next announce.
    """

    server_version = "CupolaTestlabIndexer/1.0"
    peers: dict[bytes, dict[tuple[str, int], int]] = {}

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/healthz":
            self._send(200, b"ok", "text/plain")
            return
        if parsed.path == "/api":
            query = dict(parse_qsl(parsed.query, keep_blank_values=True))
            if query.get("t") == "caps":
                self._send(200, self._caps(), "application/xml")
            else:
                self._send(200, self._search(query), "application/xml")
            return
        if parsed.path == "/announce":
            query = dict(
                parse_qsl(
                    parsed.query,
                    keep_blank_values=True,
                    encoding="latin-1",
                )
            )
            self._announce(query)
            return
        if parsed.path.startswith("/torrents/"):
            self._torrent(parsed.path.removeprefix("/torrents/"))
            return
        self.send_error(404)

    def _release(self) -> dict[str, object]:
        path = os.path.join(FORGE_DIR, "release.json")
        try:
            with open(path, encoding="utf-8") as handle:
                value = json.load(handle)
        except (OSError, ValueError):
            return {}
        return value if isinstance(value, dict) else {}

    def _caps(self) -> bytes:
        return b"""<?xml version="1.0" encoding="UTF-8"?>
<caps>
  <server version="1.0" title="Cupola testlab"/>
  <limits max="100" default="100"/>
  <searching>
    <search available="yes" supportedParams="q"/>
    <movie-search available="yes" supportedParams="q,tmdbid,imdbid"/>
  </searching>
  <categories>
    <category id="2000" name="Movies"/>
  </categories>
</caps>
"""

    def _search(self, query: dict[str, str]) -> bytes:
        release = self._release()
        title = str(release.get("title", ""))
        if not title:
            return self._rss([])
        # One release, and every search sees it. Radarr's "Test" button asks
        # with a title of its own choosing; an empty answer would fail the
        # indexer for the wrong reason. The lab never enables RSS, and the only
        # search it triggers is the one for Big Buck Bunny.
        base = "http://testlab-indexer:8088"
        torrent = str(release.get("torrent", ""))
        item = f"""    <item>
      <title>{escape(title)}</title>
      <guid isPermaLink="false">{escape(str(release.get("infohash", "")))}</guid>
      <link>{base}/torrents/{escape(torrent)}</link>
      <enclosure url="{base}/torrents/{escape(torrent)}" length="{release.get("size", 0)}" type="application/x-bittorrent"/>
      <description>Synthetic release for the Cupola import slice.</description>
      <pubDate>Wed, 01 Jan 2025 00:00:00 +0000</pubDate>
      <category>2000</category>
      <torznab:attr name="size" value="{release.get("size", 0)}"/>
      <torznab:attr name="seeders" value="1"/>
      <torznab:attr name="peers" value="2"/>
      <torznab:attr name="category" value="2000"/>
      <torznab:attr name="infohash" value="{escape(str(release.get("infohash", "")))}"/>
    </item>
"""
        return self._rss([item])

    def _rss(self, items: list[str]) -> bytes:
        body = "".join(items)
        return f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:torznab="http://torznab.com/schemas/2015/feed">
  <channel>
    <title>Cupola testlab</title>
    <link>http://testlab-indexer:8088/</link>
    <description>Cupola testlab indexer</description>
{body}  </channel>
</rss>
""".encode("utf-8")

    def _torrent(self, name: str) -> None:
        release = self._release()
        expected = str(release.get("torrent", ""))
        if not expected or name != expected:
            self.send_error(404)
            return
        path = os.path.join(FORGE_DIR, "torrents", expected)
        try:
            with open(path, "rb") as handle:
                body = handle.read()
        except OSError:
            self.send_error(404)
            return
        self._send(200, body, "application/x-bittorrent")

    def _announce(self, query: dict[str, str]) -> None:
        info_hash = (query.get("info_hash") or "").encode("latin-1")
        if not info_hash:
            self.send_error(400)
            return
        try:
            port = int(query.get("port") or 0)
        except ValueError:
            self.send_error(400)
            return
        ip = self.client_address[0]
        event = query.get("event") or ""
        peers = self.peers.setdefault(info_hash, {})
        if event == "stopped":
            peers.pop((ip, port), None)
        else:
            peers[(ip, port)] = int(query.get("left") or 1)
        others = [
            (peer_ip, peer_port)
            for (peer_ip, peer_port) in peers
            if (peer_ip, peer_port) != (ip, port)
        ]
        if query.get("compact", "1") == "1":
            compact = b"".join(
                socket.inet_aton(peer_ip) + struct.pack(">H", peer_port & 0xFFFF)
                for peer_ip, peer_port in others
            )
            payload = (
                b"d8:intervali60e5:peers"
                + str(len(compact)).encode("ascii")
                + b":"
                + compact
                + b"e"
            )
        else:
            payload = bencode(
                {
                    "interval": 60,
                    "peers": [
                        {"ip": peer_ip, "port": peer_port, "peer id": b"-CU0001-"}
                        for peer_ip, peer_port in others
                    ],
                }
            )
        self._send(200, payload, "text/plain")

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return


def healthcheck() -> int:
    """Exit status for the Compose healthcheck: does the mock finish a TLS handshake?"""
    if MODE != "truenas":
        return 1
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    # The certificate is self-signed on purpose and this only asks whether the
    # server answers a handshake, so nothing is verified.
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    try:
        with socket.create_connection(("127.0.0.1", TRUENAS_PORT), timeout=3) as plain:
            with context.wrap_socket(plain):
                return 0
    except OSError:
        return 1


def main() -> None:
    if "--healthcheck" in sys.argv[1:]:
        sys.exit(healthcheck())
    if MODE == "truenas":
        # Fail at start, loudly, when the certificate is not where the lab keeps
        # it: a mock that cannot do TLS is worse than one that is not running,
        # since the app refuses to talk to anything else.
        try:
            tls_context()
        except (ssl.SSLError, OSError) as error:
            sys.exit(
                f"The TrueNAS mock needs a TLS certificate at {TLS_CERT} and its key at "
                f"{TLS_KEY} ({error}). Make them with test/e2e/testlab/truenas_cert.sh."
            )
        server = socketserver.ThreadingTCPServer(("0.0.0.0", TRUENAS_PORT), TrueNasHandler)
    elif MODE == "indexer":
        server = ThreadingHTTPServer(("0.0.0.0", INDEXER_PORT), IndexerHandler)
    else:
        server = ThreadingHTTPServer(("0.0.0.0", 8480), UnraidHandler)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
