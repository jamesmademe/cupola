#!/usr/bin/env python3
"""Forge one synthetic release for the Radarr import slice.

The release is a real MKV (a test pattern at 1 fps with silent audio, long
enough and heavy enough that Radarr does not call it a sample), placed in a
folder whose name cannot be matched to the movie in Radarr's library. A real
private torrent carries it to the local tracker, so the app's qBittorrent
fetches it over BitTorrent rather than copying a file.

The script is idempotent: a release that is already on disk is left alone,
which is what a snapshot restore expects.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Any

# The indexer's title matches the movie, so Radarr grabs the release; the
# folder and file inside name a film that is not in the library, so Radarr
# refuses to import it by itself and the queue waits for a person.
RELEASE_TITLE = "Big.Buck.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA"
FOLDER = "The.Great.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA"
TORRENT = "the-great-bunny.torrent"


def bencode(value: Any) -> bytes:
    if isinstance(value, bool):
        raise TypeError("bencode has no boolean type")
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
            encoded_key = key.encode("utf-8") if isinstance(key, str) else key
            items.append(bencode(encoded_key) + bencode(value[key]))
        return b"d" + b"".join(items) + b"e"
    raise TypeError(f"cannot bencode {type(value).__name__}")


def bdecode(data: bytes) -> Any:
    def parse(position: int) -> tuple[Any, int]:
        marker = data[position : position + 1]
        if marker == b"d":
            result: dict[bytes, Any] = {}
            position += 1
            while data[position : position + 1] != b"e":
                key, position = parse(position)
                value, position = parse(position)
                result[key] = value
            return result, position + 1
        if marker == b"l":
            values: list[Any] = []
            position += 1
            while data[position : position + 1] != b"e":
                value, position = parse(position)
                values.append(value)
            return values, position + 1
        if marker == b"i":
            end = data.index(b"e", position)
            return int(data[position + 1 : end]), end + 1
        if marker.isdigit():
            colon = data.index(b":", position)
            length = int(data[position:colon])
            start = colon + 1
            return data[start : start + length], start + length
        raise ValueError(f"not bencode at {position}: {marker!r}")

    value, end = parse(0)
    if end != len(data):
        raise ValueError("trailing bytes after bencode value")
    return value


def infohash(torrent: Path) -> str:
    decoded = bdecode(torrent.read_bytes())
    info = decoded[b"info"]
    return hashlib.sha1(bencode(info)).hexdigest()


def run(command: list[str]) -> None:
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(
            f"{command[0]} failed with {result.returncode}"
        )


def make_media(
    target: Path,
    size: str,
    bitrate: str,
    *,
    duration: int = 120,
    subtitles: bool = False,
) -> None:
    if target.is_file() and target.stat().st_size > 20_480:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    subtitle_input: list[str] = []
    subtitle_output: list[str] = []
    if subtitles:
        srt = target.with_suffix(".srt")
        srt.write_text(
            "1\n00:00:00,000 --> 00:00:20,000\nA subtitle from the forge.\n",
            encoding="utf-8",
        )
        subtitle_input = ["-i", str(srt)]
        subtitle_output = [
            "-map",
            "0:v",
            "-map",
            "1:a",
            "-map",
            "2:s",
            "-c:s",
            "srt",
        ]
    run(
        [
            "ffmpeg",
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "lavfi",
            "-i",
            f"testsrc2=size={size}:rate=1",
            "-f",
            "lavfi",
            "-i",
            "anullsrc=channel_layout=stereo:sample_rate=48000",
            *subtitle_input,
            "-t",
            str(duration),
            *subtitle_output,
            "-c:v",
            "libx264",
            "-preset",
            "ultrafast",
            "-b:v",
            bitrate,
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-b:a",
            "32k",
            "-shortest",
            str(target),
        ]
    )
    if target.stat().st_size <= 20_480:
        raise SystemExit(
            f"{target.name} is {target.stat().st_size} bytes, below the "
            "subtitle and sample thresholds"
        )


def make_music(
    target: Path,
    *,
    title: str,
    track: int,
    album: str,
    duration: int,
) -> None:
    if target.is_file() and target.stat().st_size > 20_480:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    run(
        [
            "ffmpeg",
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "lavfi",
            "-i",
            "anullsrc=channel_layout=stereo:sample_rate=44100",
            "-t",
            str(duration),
            "-c:a",
            "flac",
            "-metadata",
            f"title={title}",
            "-metadata",
            "artist=Daft Punk",
            "-metadata",
            f"album={album}",
            "-metadata",
            f"track={track}",
            str(target),
        ]
    )


def lidarr_tracks() -> list[dict[str, Any]]:
    """The album Lidarr knows, with MusicBrainz's titles and durations.

    The forge reads them from Lidarr rather than inventing a second music
    catalogue: the file's length is the track's length, which is what Lidarr
    compares when it imports.
    """
    headers = {"X-Api-Key": "test-key", "Accept": "application/json"}
    try:
        with urllib.request.urlopen(
            urllib.request.Request(
                "http://lidarr:8686/api/v1/album?artistId=1", headers=headers
            ),
            timeout=10,
        ) as answer:
            albums = json.load(answer)
        discovery = next(
            (
                album
                for album in albums
                if isinstance(album, dict) and album.get("title") == "Discovery"
            ),
            None,
        )
        if discovery is None:
            return []
        with urllib.request.urlopen(
            urllib.request.Request(
                f"http://lidarr:8686/api/v1/track?albumId={discovery['id']}",
                headers=headers,
            ),
            timeout=10,
        ) as answer:
            tracks = json.load(answer)
        return [track for track in tracks if isinstance(track, dict)]
    except (OSError, ValueError):
        return []


def make_spike(spike_dir: Path) -> list[str]:
    """The files the spike asks the three arrs to parse.

    The short file without `sample` in its name is the one that matters: it is
    how the arrs' duration-based sample detection is tested rather than the
    name. The rar files are not archives, only names the arrs must refuse.
    """
    shutil.rmtree(spike_dir, ignore_errors=True)
    spike_dir.mkdir(parents=True, exist_ok=True)
    files = {
        "1080p": (
            "Big.Buck.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
            "1920x1080",
            "300k",
            120,
            False,
        ),
        "2160p": (
            "Big.Buck.Bunny.2008.2160p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
            "3840x2160",
            "500k",
            120,
            False,
        ),
        "480p": (
            "Big.Buck.Bunny.2008.480p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
            "854x480",
            "150k",
            120,
            False,
        ),
        "sample": (
            "Big.Buck.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.sample.mkv",
            "1920x1080",
            "300k",
            20,
            False,
        ),
        "short": (
            "Big.Buck.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.short.mkv",
            "1920x1080",
            "300k",
            20,
            False,
        ),
        "subs": (
            "Big.Buck.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.subs.mkv",
            "1920x1080",
            "300k",
            120,
            True,
        ),
        "episode": (
            "Breaking.Bad.S01E02.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
            "1920x1080",
            "300k",
            600,
            False,
        ),
        "multi": (
            "Breaking.Bad.S01E01E02.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
            "1920x1080",
            "300k",
            600,
            False,
        ),
        "unreadable": (
            "Unreadable.Name.2024.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
            "1920x1080",
            "300k",
            120,
            False,
        ),
    }
    for name, (file_name, size, bitrate, duration, subtitles) in files.items():
        make_media(
            spike_dir / file_name,
            size,
            bitrate,
            duration=duration,
            subtitles=subtitles,
        )
        print(f"[forge] spike {name}: {file_name}")
    tracks = lidarr_tracks()
    for track in tracks:
        number = int(track.get("trackNumber") or 0)
        title = str(track.get("title") or f"Track {number}")
        duration = int((track.get("duration") or 0) / 1000)
        if duration <= 0:
            duration = 180
        target = spike_dir / f"Daft Punk - Discovery - {number:02d} - {title}.flac"
        make_music(
            target,
            title=title,
            track=number,
            album="Discovery",
            duration=duration,
        )
        print(f"[forge] spike music: {target.name}")
    if not tracks:
        make_music(
            spike_dir / "Daft Punk - Discovery - 01 - One More Time.flac",
            title="One More Time",
            track=1,
            album="Discovery",
            duration=320,
        )
    for name in ("archive.rar", "archive.password.rar"):
        source = spike_dir / files["1080p"][0]
        target = spike_dir / name
        if not target.exists():
            target.write_bytes(source.read_bytes())
        print(f"[forge] spike archive: {name}")
    return sorted(path.name for path in spike_dir.iterdir())


def forge(
    output_dir: Path,
    seed_dir: Path,
    tracker_url: str,
) -> dict[str, Any]:
    release_dir = seed_dir / FOLDER
    media = release_dir / f"{FOLDER}.mkv"
    make_media(media, "1920x1080", "300k")
    torrent = output_dir / "torrents" / TORRENT
    torrent.parent.mkdir(parents=True, exist_ok=True)
    if not torrent.is_file():
        run(
            [
                "mktorrent",
                "-a",
                tracker_url,
                "-o",
                str(torrent),
                "-l",
                "16",
                "-p",
                str(release_dir),
            ]
        )
    record = {
        "title": RELEASE_TITLE,
        "folder": FOLDER,
        "file": media.name,
        "size": media.stat().st_size,
        "infohash": infohash(torrent),
        "torrent": TORRENT,
        "tracker": tracker_url,
    }
    (output_dir / "release.json").write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default="/forge")
    parser.add_argument("--seed-dir", default="/seed-data")
    parser.add_argument(
        "--tracker-url", default="http://testlab-indexer:8088/announce"
    )
    parser.add_argument("--spike-dir", default="/downloads/spike")
    arguments = parser.parse_args()
    record = forge(
        Path(arguments.output_dir),
        Path(arguments.seed_dir),
        arguments.tracker_url,
    )
    record["spike"] = make_spike(Path(arguments.spike_dir))
    (Path(arguments.output_dir) / "release.json").write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(record, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
