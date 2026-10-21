#!/usr/bin/env python3
"""A local Usenet server for the testlab: enough RFC 3977 for SABnzbd and NZBGet.

The download chain of the lab never touches the internet (testlab plan,
principle 3). Torrents have their local seeder; Usenet gets this process: it
speaks the reader commands the two clients actually send, and it serves yEnc
articles for a small NZB that the scenario builds from a deterministic test
file. Nothing here posts, so every connection is a reader.

It runs on the host, on 127.0.0.1, because the lab owns the host and not the
other way round: the containers reach it at ``host.docker.internal`` (verified
on OrbStack for both clients). It is started by the scenarios, detached, and
stopped by their teardown; the pid and the manifest live in the testlab state
directory, never in the repository.

The same process also answers a tiny HTTP surface, because a client cannot read
the host filesystem: ``GET /nzb/<key>.nzb`` is what ``mode=addurl`` and
NZBGet's ``append`` fetch, ``GET /payload/<key>`` is the file the articles
carry (the test compares the download against it), and ``GET /health`` says the
server is up.

Run it by hand for a protocol check:

    python3 test/e2e/testlab/nntp_server.py --self-test --state-dir <dir>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import signal
import socket
import socketserver
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import zlib
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

HOST = "127.0.0.1"
NNTP_PORT = 1119
HTTP_PORT = 1120
GROUP = "alt.binaries.test"
PART_SIZE = 64 * 1024
LINE_LENGTH = 128
# How long a slow article waits before its body. A slow file is cut into many
# small articles, so the wait happens between articles, not inside one: the
# client can stop the job at the next boundary (a second or two), which a
# dribbled article would not allow. The file lasts parts * this long.
SLOW_ARTICLE_DELAY = 3.0
STATE_SUBDIR = "usenet"


class NntpError(RuntimeError):
    pass


# ---------------------------------------------------------------------------
# The catalogue: files, their parts, and the articles that carry them.


@dataclass(frozen=True)
class FileSpec:
    """One file the server can serve, and the parts it is cut into."""

    key: str
    name: str
    size: int
    part_size: int = PART_SIZE
    # 1-based part numbers the server answers 430 for. A missing article is a
    # real failure for the client, not a broken scenario: it is how the lab
    # shows a download that cannot be repaired.
    missing_parts: tuple[int, ...] = ()
    # A slow file dribbles its body one line at a time, so a job stays
    # "Downloading" while a second job waits "Queued" behind it. Nothing is
    # simulated: the bytes are the real ones, they simply arrive slowly.
    slow: bool = False

    @property
    def parts(self) -> int:
        return max(1, (self.size + self.part_size - 1) // self.part_size)

    def part_bounds(self, number: int) -> tuple[int, int]:
        start = (number - 1) * self.part_size
        return start, min(start + self.part_size, self.size)

    def message_id(self, number: int) -> str:
        return f"cupola.{self.key}.{number}@testlab.local"

    def subject(self, number: int) -> str:
        return f"{self.name} yEnc ({number}/{self.parts})"


def payload_for(key: str, size: int) -> bytes:
    """A deterministic file for [key], so a run is repeatable byte for byte.

    The bytes are not a video and are not meant to be one: the client only has
    to fetch them, decode the yEnc and write them back unchanged.
    """
    seed = hashlib.sha256(f"cupola-testlab-usenet:{key}".encode()).digest()
    block = bytearray()
    counter = 0
    while len(block) < min(size, 1 << 20):
        block.extend(hashlib.sha256(seed + counter.to_bytes(4, "big")).digest())
        counter += 1
    return (bytes(block) * (size // len(block) + 1))[:size]


def yenc_part(
    data: bytes,
    *,
    spec: FileSpec,
    number: int,
    full_crc: int,
) -> str:
    """The yEnc text for one part, headers included, as CRLF-free lines."""
    start, end = spec.part_bounds(number)
    lines = [
        f"=ybegin part={number} total={spec.parts} line={LINE_LENGTH} "
        f"size={spec.size} name={spec.name}",
        f"=ypart begin={start + 1} end={end}",
    ]
    assert end > start
    encoded: list[str] = []
    line: list[str] = []
    for byte in data:
        value = (byte + 42) & 0xFF
        if value in (0x00, 0x0A, 0x0D, 0x3D):
            token = "=" + chr((value + 64) & 0xFF)
        else:
            token = chr(value)
        line.append(token)
        if len(line) >= LINE_LENGTH:
            encoded.append("".join(line))
            line = []
    if line:
        encoded.append("".join(line))
    lines.extend(encoded)
    trailer = f"=yend size={len(data)} part={number} pcrc32={_crc32(data):08x}"
    if number == spec.parts:
        trailer += f" crc32={full_crc:08x}"
    lines.append(trailer)
    return "\r\n".join(lines)


def _crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


@dataclass
class Article:
    message_id: str
    headers: list[str]
    body: str
    present: bool
    slow: bool = False


@dataclass
class Library:
    files: list[FileSpec]
    group: str = GROUP
    _cache: dict[str, Article] = field(default_factory=dict, repr=False)

    def spec(self, key: str) -> FileSpec | None:
        for item in self.files:
            if item.key == key:
                return item
        return None

    def payload(self, key: str) -> bytes:
        spec = self.spec(key)
        if spec is None:
            raise NntpError(f"no file called {key}")
        return payload_for(key, spec.size)

    def article(self, message_id: str) -> Article | None:
        normalised = message_id.strip().strip("<>")
        if normalised in self._cache:
            return self._cache[normalised]
        for spec in self.files:
            for number in range(1, spec.parts + 1):
                if spec.message_id(number) != normalised:
                    continue
                article = self._build(spec, number)
                self._cache[normalised] = article
                return article
        return None

    def _build(self, spec: FileSpec, number: int) -> Article:
        present = number not in spec.missing_parts
        if not present:
            return Article(
                message_id=spec.message_id(number),
                headers=[],
                body="",
                present=False,
            )
        data = self.payload(spec.key)
        start, end = spec.part_bounds(number)
        part = data[start:end]
        full_crc = _crc32(data)
        headers = [
            f"Message-ID: <{spec.message_id(number)}>",
            f"Newsgroups: {self.group}",
            f"Subject: {spec.subject(number)}",
            "From: cupola@testlab.local",
            "Date: Wed, 21 Oct 2026 12:00:00 +0000",
            "X-Newsreader: Cupola testlab",
        ]
        return Article(
            message_id=spec.message_id(number),
            headers=headers,
            body=yenc_part(part, spec=spec, number=number, full_crc=full_crc),
            present=True,
            slow=spec.slow,
        )

    def nzb(self, key: str) -> bytes:
        spec = self.spec(key)
        if spec is None:
            raise NntpError(f"no file called {key}")
        segments = []
        for number in range(1, spec.parts + 1):
            start, end = spec.part_bounds(number)
            segments.append(
                f'      <segment bytes="{end - start}" '
                f'number="{number}">{spec.message_id(number)}</segment>'
            )
        document = "\n".join(
            [
                '<?xml version="1.0" encoding="UTF-8"?>',
                '<!DOCTYPE nzb PUBLIC "-//newzBin//DTD NZB 1.1//EN" '
                '"http://www.newzbin.com/DTD/nzb/nzb-1.1.dtd">',
                '<nzb xmlns="http://www.newzbin.com/DTD/2003/nzb">',
                "  <head>",
                f'    <meta type="title">{spec.name}</meta>',
                "  </head>",
                f'  <file poster="cupola@testlab.local" date="1700000000" '
                f'subject="{spec.subject(1)}">',
                "    <groups>",
                f"      <group>{self.group}</group>",
                "    </groups>",
                "    <segments>",
                *segments,
                "    </segments>",
                "  </file>",
                "</nzb>",
                "",
            ]
        )
        return document.encode("utf-8")


# ---------------------------------------------------------------------------
# The protocol.


class NntpHandler(socketserver.StreamRequestHandler):
    greeting = "200 cupola-testlab NNTP service ready, posting prohibited"

    def handle(self) -> None:
        self._send(self.greeting)
        while True:
            line = self.rfile.readline()
            if not line:
                return
            command = line.decode("utf-8", errors="replace").strip()
            if not command:
                continue
            verb, _, rest = command.partition(" ")
            verb = verb.upper()
            try:
                if not self._dispatch(verb, rest.strip()):
                    return
            except (BrokenPipeError, ConnectionResetError):
                return

    def _dispatch(self, verb: str, argument: str) -> bool:
        if verb == "QUIT":
            self._send("205 closing connection")
            return False
        if verb == "CAPABILITIES":
            self._send("101 Capability list:")
            self._send("VERSION 2")
            self._send("READER")
            self._send("AUTHINFO USER")
            self._send(".")
            return True
        if verb == "MODE" and argument.upper() == "READER":
            self._send("200 Reader mode, posting prohibited")
            return True
        if verb == "AUTHINFO":
            # The lab accepts any credentials on purpose: the point of the
            # scenario is the article path, not the password policy, and the
            # NZBGet entry keeps the user's own username untouched.
            self._send(
                "281 Authentication accepted"
                if argument.upper().startswith("PASS")
                else "381 Password required"
            )
            return True
        if verb == "DATE":
            self._send("111 " + time.strftime("%Y%m%d%H%M%S", time.gmtime()))
            return True
        if verb == "GROUP":
            self._send(f"211 {self._count()} 1 {self._count()} {argument or GROUP}")
            return True
        if verb == "LIST":
            self._send("215 list of newsgroups follows")
            self._send(f"{GROUP} {self._count()} 1 y")
            self._send(".")
            return True
        if verb in ("ARTICLE", "HEAD", "BODY", "STAT"):
            return self._article(verb, argument)
        self._send(f"500 command not recognized: {verb}")
        return True

    @property
    def library(self) -> Library:
        return self.server.library  # type: ignore[attr-defined]

    def _count(self) -> int:
        return sum(spec.parts for spec in self.library.files)

    def _article(self, verb: str, argument: str) -> bool:
        if not argument:
            self._send("501 a message id is required")
            return True
        article = self.library.article(argument)
        if article is None or not article.present:
            self._send("430 no such article")
            return True
        message_id = f"<{article.message_id}>"
        if verb == "STAT":
            self._send(f"223 0 {message_id} article exists")
            return True
        if verb == "HEAD":
            self._send(f"221 0 {message_id} headers follow")
            self._send_lines(article.headers)
            return True
        if article.slow:
            time.sleep(SLOW_ARTICLE_DELAY)
        if verb == "BODY":
            self._send(f"222 0 {message_id} body follows")
            self._send_lines(article.body.split("\r\n"))
            return True
        self._send(f"220 0 {message_id} article follows")
        self._send_lines(article.headers + [""] + article.body.split("\r\n"))
        return True

    def _send(self, line: str) -> None:
        self.wfile.write(line.encode("latin-1", errors="replace") + b"\r\n")
        self.wfile.flush()

    def _send_lines(self, lines: list[str]) -> None:
        """Write a multi-line block with dot stuffing, then the terminator."""
        buffer = bytearray()
        for line in lines:
            if line.startswith("."):
                line = "." + line
            # yEnc is bytes, not text: latin-1 keeps 0x80..0xFF as one byte
            # each, where UTF-8 would expand them and break every CRC.
            buffer.extend(line.encode("latin-1", errors="replace"))
            buffer.extend(b"\r\n")
        buffer.extend(b".\r\n")
        self.wfile.write(bytes(buffer))
        self.wfile.flush()


class NntpServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


# ---------------------------------------------------------------------------
# The HTTP surface: the NZB the clients fetch, and the payload they carry.


class HttpHandler(BaseHTTPRequestHandler):
    server_version = "CupolaTestlabNntp/1.0"

    @property
    def library(self) -> Library:
        return self.server.library  # type: ignore[attr-defined]

    def log_message(self, format: str, *args: Any) -> None:
        # The path is safe; no secret ever travels on this surface.
        sys.stderr.write("[nntp-http] %s\n" % (format % args))

    def do_GET(self) -> None:  # noqa: N802 - the HTTP verb is the name
        path = self.path.split("?", 1)[0]
        if path == "/health":
            self._answer(
                200,
                json.dumps(
                    {
                        "ok": True,
                        "group": self.library.group,
                        "files": [
                            {
                                "key": spec.key,
                                "name": spec.name,
                                "size": spec.size,
                                "parts": spec.parts,
                            }
                            for spec in self.library.files
                        ],
                    }
                ).encode("utf-8"),
                "application/json",
            )
            return
        if path.startswith("/nzb/"):
            key = path.removeprefix("/nzb/").removesuffix(".nzb")
            try:
                body = self.library.nzb(key)
            except NntpError:
                self._answer(404, b"no such nzb", "text/plain")
                return
            self._answer(200, body, "application/x-nzb")
            return
        if path.startswith("/payload/"):
            key = path.removeprefix("/payload/")
            try:
                body = self.library.payload(key)
            except NntpError:
                self._answer(404, b"no such file", "text/plain")
                return
            self._answer(200, body, "application/octet-stream")
            return
        self._answer(404, b"not found", "text/plain")

    def _answer(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


# ---------------------------------------------------------------------------
# The manifest, the process, and its lifecycle.


def state_paths(state_dir: str | os.PathLike[str]) -> dict[str, Path]:
    root = Path(state_dir) / STATE_SUBDIR
    return {
        "root": root,
        "manifest": root / "manifest.json",
        "pid": root / "nntp.pid",
        "log": root / "nntp.log",
    }


def write_manifest(
    state_dir: str | os.PathLike[str],
    files: list[FileSpec],
    *,
    port: int = NNTP_PORT,
    http_port: int = HTTP_PORT,
) -> dict[str, Any]:
    paths = state_paths(state_dir)
    paths["root"].mkdir(parents=True, exist_ok=True)
    manifest = {
        "group": GROUP,
        "port": port,
        "httpPort": http_port,
        "files": [
            {
                "key": spec.key,
                "name": spec.name,
                "size": spec.size,
                "partSize": spec.part_size,
                "missingParts": list(spec.missing_parts),
                "slow": spec.slow,
            }
            for spec in files
        ],
    }
    paths["manifest"].write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def read_manifest(state_dir: str | os.PathLike[str]) -> dict[str, Any]:
    path = state_paths(state_dir)["manifest"]
    if not path.exists():
        raise NntpError(f"the Usenet manifest is missing at {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def library_from_manifest(manifest: dict[str, Any]) -> Library:
    return Library(
        group=manifest.get("group", GROUP),
        files=[
            FileSpec(
                key=item["key"],
                name=item["name"],
                size=int(item["size"]),
                part_size=int(item.get("partSize", PART_SIZE)),
                missing_parts=tuple(int(n) for n in item.get("missingParts", [])),
                slow=bool(item.get("slow", False)),
            )
            for item in manifest.get("files", [])
        ],
    )


def _healthy(http_port: int) -> bool:
    try:
        with urllib.request.urlopen(
            f"http://{HOST}:{http_port}/health", timeout=1.5
        ) as answer:
            return answer.status == 200
    except (urllib.error.URLError, OSError):
        return False


def running(state_dir: str | os.PathLike[str]) -> bool:
    paths = state_paths(state_dir)
    if not paths["pid"].exists():
        return False
    try:
        pid = int(paths["pid"].read_text(encoding="utf-8").strip())
        os.kill(pid, 0)
    except (ValueError, OSError):
        return False
    try:
        return _healthy(read_manifest(state_dir)["httpPort"])
    except NntpError:
        return False


def ensure(state_dir: str | os.PathLike[str], timeout: float = 25) -> dict[str, Any]:
    """Start the server if it is not up, and prove it answers. Idempotent."""
    manifest = read_manifest(state_dir)
    if running(state_dir):
        return manifest
    paths = state_paths(state_dir)
    paths["root"].mkdir(parents=True, exist_ok=True)
    log = paths["log"].open("ab")
    process = subprocess.Popen(
        [
            sys.executable,
            str(Path(__file__).resolve()),
            "--state-dir",
            str(state_dir),
        ],
        stdout=log,
        stderr=log,
        start_new_session=True,
    )
    paths["pid"].write_text(str(process.pid), encoding="utf-8")
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if _healthy(int(manifest["httpPort"])):
            return manifest
        if process.poll() is not None:
            raise NntpError(
                "the Usenet server exited while starting; see "
                f"{paths['log']}"
            )
        time.sleep(0.15)
    raise NntpError(f"the Usenet server did not answer on {manifest['httpPort']}")


def stop(state_dir: str | os.PathLike[str]) -> bool:
    """Stop the server started by [ensure], if any. Idempotent."""
    paths = state_paths(state_dir)
    if not paths["pid"].exists():
        return False
    try:
        pid = int(paths["pid"].read_text(encoding="utf-8").strip())
    except ValueError:
        paths["pid"].unlink(missing_ok=True)
        return False
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    for _ in range(40):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.1)
    else:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    paths["pid"].unlink(missing_ok=True)
    return True


def serve(state_dir: str | os.PathLike[str]) -> None:
    manifest = read_manifest(state_dir)
    library = library_from_manifest(manifest)
    nntp = NntpServer((HOST, int(manifest["port"])), NntpHandler)
    nntp.library = library  # type: ignore[attr-defined]
    http = ThreadingHTTPServer((HOST, int(manifest["httpPort"])), HttpHandler)
    http.library = library  # type: ignore[attr-defined]
    threading.Thread(target=http.serve_forever, daemon=True).start()
    print(
        f"[nntp] {len(library.files)} files, nntp {HOST}:{manifest['port']}, "
        f"http {HOST}:{manifest['httpPort']}",
        flush=True,
    )
    try:
        nntp.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        nntp.server_close()
        http.shutdown()


# ---------------------------------------------------------------------------
# A protocol check that needs neither client.


def self_test(state_dir: str | os.PathLike[str]) -> dict[str, Any]:
    """Read every part back over a real socket and decode it."""
    manifest = read_manifest(state_dir)
    library = library_from_manifest(manifest)
    nntp = NntpServer((HOST, 0), NntpHandler)
    nntp.library = library  # type: ignore[attr-defined]
    threading.Thread(target=nntp.serve_forever, daemon=True).start()
    port = nntp.server_address[1]
    checks: list[str] = []
    try:
        for spec in library.files:
            if spec.slow:
                # A slow file dribbles its body on purpose; reading it here
                # would only prove that waiting works. Its headers are enough.
                _self_test_headers(port, library, spec)
                checks.append(f"{spec.key}: {spec.parts} parts, slow, headers read")
                continue
            decoded = _self_test_file(port, library, spec)
            if spec.missing_parts:
                checks.append(f"{spec.key}: {spec.parts} parts, missing honoured")
                continue
            expected = library.payload(spec.key)
            if decoded != expected:
                raise NntpError(f"{spec.key} decoded to the wrong bytes")
            checks.append(f"{spec.key}: {spec.parts} parts, {len(decoded)} bytes")
    finally:
        nntp.shutdown()
        nntp.server_close()
    return {"checks": checks}


def _self_test_file(port: int, library: Library, spec: FileSpec) -> bytes:
    with socket.create_connection((HOST, port), timeout=10) as sock:
        stream = sock.makefile("rwb")

        def send(command: str) -> None:
            stream.write(command.encode() + b"\r\n")
            stream.flush()

        def read_line() -> str:
            # latin-1 on purpose: the body is yEnc bytes, not UTF-8 text.
            return stream.readline().decode("latin-1").rstrip("\r\n")

        def read_block() -> list[str]:
            lines: list[str] = []
            while True:
                line = read_line()
                if line == ".":
                    return lines
                lines.append(line[1:] if line.startswith("..") else line)

        greeting = read_line()
        if not greeting.startswith("200"):
            raise NntpError(f"bad greeting: {greeting}")
        send("CAPABILITIES")
        if not read_line().startswith("101"):
            raise NntpError("CAPABILITIES was refused")
        capabilities = read_block()
        if "VERSION 2" not in capabilities:
            raise NntpError("the capability list never ended")
        send("AUTHINFO USER reader")
        if not read_line().startswith("381"):
            raise NntpError("AUTHINFO USER was refused")
        send("AUTHINFO PASS reader")
        if not read_line().startswith("281"):
            raise NntpError("AUTHINFO PASS was refused")
        send("DATE")
        if not read_line().startswith("111"):
            raise NntpError("DATE was refused")
        send(f"GROUP {library.group}")
        if not read_line().startswith("211"):
            raise NntpError("GROUP was refused")
        decoded = bytearray()
        for number in range(1, spec.parts + 1):
            message_id = f"<{spec.message_id(number)}>"
            send(f"STAT {message_id}")
            answer = read_line()
            if number in spec.missing_parts:
                if not answer.startswith("430"):
                    raise NntpError(f"part {number} should be missing: {answer}")
                continue
            if not answer.startswith("223"):
                raise NntpError(f"STAT {message_id} answered {answer}")
            send(f"BODY {message_id}")
            if not read_line().startswith("222"):
                raise NntpError(f"BODY {message_id} was refused")
            decoded.extend(_decode_yenc(read_block()))
            send(f"HEAD {message_id}")
            if not read_line().startswith("221"):
                raise NntpError(f"HEAD {message_id} was refused")
            read_block()
        send("QUIT")
        if not read_line().startswith("205"):
            raise NntpError("QUIT was refused")
        return bytes(decoded)


def _self_test_headers(port: int, library: Library, spec: FileSpec) -> None:
    with socket.create_connection((HOST, port), timeout=10) as sock:
        stream = sock.makefile("rwb")
        stream.readline()
        message_id = f"<{spec.message_id(1)}>"
        stream.write(f"STAT {message_id}\r\n".encode())
        stream.flush()
        if not stream.readline().startswith(b"223"):
            raise NntpError(f"STAT {message_id} was refused")
        stream.write(f"HEAD {message_id}\r\n".encode())
        stream.flush()
        if not stream.readline().startswith(b"221"):
            raise NntpError(f"HEAD {message_id} was refused")
        while stream.readline() not in (b".\r\n", b""):
            continue
        stream.write(b"QUIT\r\n")
        stream.flush()
        if not stream.readline().startswith(b"205"):
            raise NntpError("QUIT was refused")


def _decode_yenc(lines: list[str]) -> bytes:
    body: list[str] = []
    inside = False
    for line in lines:
        if line.startswith("=ybegin"):
            inside = True
            continue
        if line.startswith("=ypart"):
            continue
        if line.startswith("=yend"):
            break
        if inside:
            body.append(line)
    data = bytearray()
    for line in body:
        index = 0
        while index < len(line):
            char = line[index]
            if char == "=":
                data.append((ord(line[index + 1]) - 64 - 42) & 0xFF)
                index += 2
            else:
                data.append((ord(char) - 42) & 0xFF)
                index += 1
    return bytes(data)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", required=True)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="read the manifest back over a socket and exit",
    )
    arguments = parser.parse_args(argv)
    if arguments.self_test:
        print(json.dumps(self_test(arguments.state_dir), indent=2))
        return 0
    serve(arguments.state_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
