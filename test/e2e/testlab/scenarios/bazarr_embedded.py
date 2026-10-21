"""Bazarr and an embedded English subtitle: the forge's own track, extracted by
a real provider, beside the movie that stays wanted for lack of the language.

The chain is real. Radarr's library holds Big Buck Bunny with a file; ffmpeg
muxes the forge's English subtitle into that file with the `eng` tag; Bazarr's
`embeddedsubtitles` provider reads the track and extracts it next to the video.
The Matrix gets a French track instead, so it stays wanted with English
missing. Bazarr counts embedded tracks as existing subtitles
(`general.use_embedded_subs`), which would skip the extraction, so the scenario
turns that setting off while it is applied and puts it back on teardown.

Every file it touches is backed up under `state/backup/bazarr_embedded`, and
every change goes through the services' APIs or their media folders, never
their databases.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import time
import urllib.parse
from pathlib import Path

from .base import STATE_ROOT, Scenario, ScenarioError, request, require_ok

RADARR = "http://127.0.0.1:7878/api/v3"
BAZARR = "http://127.0.0.1:6767/api"
RADARR_HEADERS = {"X-Api-Key": "test-key"}
BAZARR_HEADERS = {"X-API-KEY": "test-key"}

BIG_BUCK_BUNNY_TMDB = 10378
THE_MATRIX_TMDB = 603
BIG_BUCK_BUNNY_FILE = "The.Great.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv"
THE_MATRIX_FILE = "The Matrix (1999).mp4"
THE_MATRIX_WANTED_FILE = "The Matrix (1999).mkv"
FORGE = (
    STATE_ROOT
    / "downloads"
    / "spike"
    / "Big.Buck.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.subs.mkv"
)
BACKUP = STATE_ROOT / "backup" / "bazarr_embedded"
MARKER = BACKUP / "state.json"


def _radarr(path: str, method: str = "GET", payload: dict | None = None) -> object:
    status, body = request(
        f"{RADARR}{path}", method=method, payload=payload, headers=RADARR_HEADERS
    )
    require_ok(status, body, f"Radarr {method} {path}")
    return body


def _movie(tmdb_id: int) -> dict:
    movies = _radarr(f"/movie?tmdbId={tmdb_id}")
    if isinstance(movies, list):
        for movie in movies:
            if isinstance(movie, dict) and movie.get("tmdbId") == tmdb_id:
                return movie
    raise ScenarioError(f"Radarr has no movie with tmdbId {tmdb_id}")


def _host(container_path: str) -> Path:
    """The host path of a container path: /media and /downloads are the state root."""
    return STATE_ROOT / str(container_path).lstrip("/")


def _folder(movie: dict) -> Path:
    return _host(movie["path"])


def _tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise ScenarioError(f"{name} is not on PATH; the scenario needs it for the track")
    return path


def _subtitle_streams(path: Path) -> list[tuple[int, str, str]]:
    """The subtitle streams of a file as (index, language, codec)."""
    if not path.exists():
        raise ScenarioError(f"{path} is missing")
    result = subprocess.run(
        [
            _tool("ffprobe"),
            "-v",
            "error",
            "-select_streams",
            "s",
            "-show_entries",
            "stream=index,codec_name:stream_tags=language",
            "-of",
            "json",
            str(path),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise ScenarioError(f"ffprobe cannot read {path}: {result.stderr.strip()}")
    streams = json.loads(result.stdout or "{}").get("streams") or []
    return [
        (
            int(stream.get("index") or 0),
            str((stream.get("tags") or {}).get("language") or "").lower(),
            str(stream.get("codec_name") or ""),
        )
        for stream in streams
    ]


def _place(target: Path, source: Path) -> None:
    """Put `source` at `target` as a fresh file.

    A new inode matters: Radarr re-reads a movie file when its size changed, and
    an in-place overwrite can leave the mount serving the old size for a moment.
    """
    partial = target.parent / f".{target.name}.cupola"
    shutil.copy2(source, partial)
    os.utime(partial, None)
    os.replace(partial, target)


def _mux(source: Path, subtitle_source: Path, target: Path, language: str) -> None:
    """Write `source` with the first subtitle stream of `subtitle_source` tagged
    `language`, so a file that had no track carries a real, labelled one."""
    with tempfile.TemporaryDirectory() as scratch:
        partial = Path(scratch) / "movie.mkv"
        result = subprocess.run(
            [
                _tool("ffmpeg"),
                "-v",
                "error",
                "-y",
                "-i",
                str(source),
                "-i",
                str(subtitle_source),
                "-map",
                "0:v",
                "-map",
                "0:a",
                "-map",
                "1:s:0",
                "-c",
                "copy",
                "-c:s",
                "srt",
                "-metadata:s:s:0",
                f"language={language}",
                "-metadata:s:s:0",
                f"title={language}",
                str(partial),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise ScenarioError(
                f"ffmpeg cannot mux the subtitle into {target.name}: "
                f"{result.stderr.strip()}"
            )
        if not _subtitle_streams(partial):
            raise ScenarioError(f"ffmpeg wrote {target.name} without a subtitle track")
        target.parent.mkdir(parents=True, exist_ok=True)
        _place(target, partial)


def _bazarr(
    path: str,
    method: str = "GET",
    form: dict | None = None,
    timeout: float = 15,
) -> tuple[int, object]:
    headers = dict(BAZARR_HEADERS)
    payload = None
    if form is not None:
        payload = urllib.parse.urlencode(form)
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    return request(
        f"{BAZARR}{path}", method=method, payload=payload, headers=headers, timeout=timeout
    )


def _bazarr_movie(radarr_id: int) -> dict | None:
    status, body = _bazarr(f"/movies?radarrid[]={radarr_id}")
    require_ok(status, body, f"Bazarr movies {radarr_id}")
    rows = (body or {}).get("data") or []
    for row in rows:
        if row.get("radarrId") == radarr_id:
            return row
    return None


def _bazarr_action(radarr_id: int, action: str, timeout: float = 15) -> None:
    status, body = _bazarr(
        f"/movies?radarrid={radarr_id}&action={action}", method="PATCH", timeout=timeout
    )
    require_ok(status, body, f"Bazarr {action} on movie {radarr_id}")


def _bazarr_settings() -> dict:
    status, body = _bazarr("/system/settings")
    require_ok(status, body, "Bazarr settings")
    if not isinstance(body, dict):
        raise ScenarioError("Bazarr settings did not answer with an object")
    return body


def _set_embedded_subs(value: bool) -> None:
    status, body = _bazarr(
        "/system/settings",
        method="POST",
        form={"settings-general-use_embedded_subs": "true" if value else "false"},
    )
    require_ok(status, body, "Bazarr use_embedded_subs")


def _rescan(
    movie: dict,
    expected_name: str,
    expected_size: int | None = None,
    attempts: int = 3,
) -> None:
    """Ask Radarr to scan the movie again until it reports the file we wrote.

    The scan compares the file's size, and the media mount can answer with the
    previous size for a moment after a write, so a single pass is not enough.
    """
    for _ in range(attempts):
        _radarr(
            "/command",
            method="POST",
            payload={"name": "RescanMovie", "movieId": movie["id"]},
        )
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            current = _radarr(f"/movie/{movie['id']}")
            movie_file = (current or {}).get("movieFile") or {}
            if (current or {}).get("hasFile") and movie_file.get(
                "relativePath"
            ) == expected_name:
                if expected_size is None or movie_file.get("size") == expected_size:
                    return
            time.sleep(2)
    raise ScenarioError(f"Radarr did not rescan {movie['title']} to {expected_name}")


def _history_has_embedded(radarr_id: int) -> bool:
    status, body = _bazarr("/movies/history")
    require_ok(status, body, "Bazarr movie history")
    rows = (body or {}).get("data") or []
    return any(
        row.get("radarrId") == radarr_id and row.get("provider") == "embeddedsubtitles"
        for row in rows
    )


def _await_extracted(radarr_id: int, timeout: float = 90) -> dict:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        movie = _bazarr_movie(radarr_id)
        if movie and not movie.get("missing_subtitles"):
            for subtitle in movie.get("subtitles") or []:
                path = subtitle.get("path")
                if subtitle.get("code2") == "en" and path and _host(path).exists():
                    return movie
        time.sleep(2)
    raise ScenarioError(
        f"Bazarr did not extract the embedded English subtitle for movie {radarr_id}"
    )


def _backup(path: Path) -> None:
    """Keep the seeded file aside, and never mistake a muxed file for it."""
    if not path.exists():
        return
    target = BACKUP / path.name
    if target.exists():
        return
    if _subtitle_streams(path):
        raise ScenarioError(
            f"{path.name} already carries a subtitle track and no backup exists; "
            "reset the lab before applying the scenario"
        )
    shutil.copy2(path, target)


def _delete_extracted(radarr_id: int, folder: Path, video: Path) -> None:
    """Remove the extracted subtitle through Bazarr, then make sure it is gone."""
    expected = folder / f"{video.stem}.en.srt"
    movie = _bazarr_movie(radarr_id)
    for subtitle in (movie or {}).get("subtitles") or []:
        if subtitle.get("code2") != "en" or not subtitle.get("path"):
            continue
        query = urllib.parse.urlencode(
            {
                "radarrid": radarr_id,
                "language": "en",
                "forced": "False",
                "hi": "False",
                "path": subtitle["path"],
            }
        )
        status, body = _bazarr(f"/movies/subtitles?{query}", method="DELETE")
        if status not in (204, 404, 500):
            require_ok(status, body, "Bazarr delete subtitle")
    expected.unlink(missing_ok=True)


class BazarrEmbedded(Scenario):
    name = "bazarr-embedded"
    profiles = ("core", "media")

    def apply(self) -> None:
        if not FORGE.exists():
            raise ScenarioError(f"the forge subtitle file is missing: {FORGE}")
        _tool("ffmpeg")

        big_buck_bunny = _movie(BIG_BUCK_BUNNY_TMDB)
        matrix = _movie(THE_MATRIX_TMDB)
        bunny_folder = _folder(big_buck_bunny)
        matrix_folder = _folder(matrix)
        bunny_path = bunny_folder / BIG_BUCK_BUNNY_FILE
        matrix_path = matrix_folder / THE_MATRIX_FILE
        matrix_wanted = matrix_folder / THE_MATRIX_WANTED_FILE

        BACKUP.mkdir(parents=True, exist_ok=True)
        settings = _bazarr_settings()
        if "embeddedsubtitles" not in (
            settings["general"].get("enabled_providers") or []
        ):
            raise ScenarioError(
                "Bazarr has the embeddedsubtitles provider disabled; "
                "enable it before applying the scenario"
            )
        if not MARKER.exists():
            MARKER.write_text(
                json.dumps(
                    {
                        "use_embedded_subs": bool(
                            settings["general"]["use_embedded_subs"]
                        )
                    }
                ),
                encoding="utf-8",
            )

        if not bunny_path.exists() and not (BACKUP / bunny_path.name).exists():
            raise ScenarioError(
                "Big Buck Bunny has no file in the library; reset the golden"
            )
        _backup(bunny_path)
        _backup(matrix_path)

        _mux(BACKUP / bunny_path.name, FORGE, bunny_path, "eng")
        if not matrix_wanted.exists():
            _mux(BACKUP / matrix_path.name, FORGE, matrix_wanted, "fre")
        matrix_path.unlink(missing_ok=True)

        _rescan(big_buck_bunny, bunny_path.name, bunny_path.stat().st_size)
        _rescan(matrix, matrix_wanted.name, matrix_wanted.stat().st_size)

        _set_embedded_subs(False)

        _bazarr_action(big_buck_bunny["id"], "sync")
        # A subtitle left by an earlier run would hide the extraction.
        (bunny_folder / f"{bunny_path.stem}.en.srt").unlink(missing_ok=True)
        _bazarr_action(big_buck_bunny["id"], "scan-disk")
        _bazarr_action(matrix["id"], "sync")
        _bazarr_action(matrix["id"], "scan-disk")

        _bazarr_action(big_buck_bunny["id"], "search-missing", timeout=120)
        _bazarr_action(matrix["id"], "search-missing", timeout=120)

        _await_extracted(big_buck_bunny["id"])

    def teardown(self) -> None:
        big_buck_bunny = _movie(BIG_BUCK_BUNNY_TMDB)
        matrix = _movie(THE_MATRIX_TMDB)
        bunny_folder = _folder(big_buck_bunny)
        matrix_folder = _folder(matrix)
        bunny_path = bunny_folder / BIG_BUCK_BUNNY_FILE
        matrix_path = matrix_folder / THE_MATRIX_FILE
        matrix_wanted = matrix_folder / THE_MATRIX_WANTED_FILE

        _delete_extracted(big_buck_bunny["id"], bunny_folder, bunny_path)

        if (BACKUP / bunny_path.name).exists():
            _place(bunny_path, BACKUP / bunny_path.name)
            (BACKUP / bunny_path.name).unlink()
        if matrix_wanted.exists():
            matrix_wanted.unlink()
        if (BACKUP / matrix_path.name).exists():
            _place(matrix_path, BACKUP / matrix_path.name)
            (BACKUP / matrix_path.name).unlink()

        if bunny_path.exists():
            _rescan(big_buck_bunny, bunny_path.name, bunny_path.stat().st_size)
        if matrix_path.exists():
            _rescan(matrix, matrix_path.name, matrix_path.stat().st_size)

        if MARKER.exists():
            original = json.loads(MARKER.read_text(encoding="utf-8"))
            _set_embedded_subs(bool(original.get("use_embedded_subs", True)))
            MARKER.unlink()

        for movie in (big_buck_bunny, matrix):
            _bazarr_action(movie["id"], "sync")
            _bazarr_action(movie["id"], "scan-disk")

        if BACKUP.exists() and not any(BACKUP.iterdir()):
            BACKUP.rmdir()

    def verify(self) -> None:
        big_buck_bunny = _movie(BIG_BUCK_BUNNY_TMDB)
        matrix = _movie(THE_MATRIX_TMDB)
        bunny_path = _folder(big_buck_bunny) / BIG_BUCK_BUNNY_FILE
        matrix_wanted = _folder(matrix) / THE_MATRIX_WANTED_FILE

        if not big_buck_bunny.get("hasFile"):
            raise ScenarioError("Radarr lost Big Buck Bunny's file")
        bunny_languages = [language for _, language, _ in _subtitle_streams(bunny_path)]
        if "eng" not in bunny_languages:
            raise ScenarioError(
                f"the library file has no eng subtitle track: {bunny_languages}"
            )

        matrix_languages = [language for _, language, _ in _subtitle_streams(matrix_wanted)]
        if "eng" in matrix_languages or "fre" not in matrix_languages:
            raise ScenarioError(
                f"The Matrix should carry only a French track: {matrix_languages}"
            )

        movie = _bazarr_movie(big_buck_bunny["id"])
        if movie is None:
            raise ScenarioError("Bazarr does not list Big Buck Bunny")
        if movie.get("missing_subtitles"):
            raise ScenarioError(
                f"Bazarr still wants {movie['missing_subtitles']} for Big Buck Bunny"
            )
        extracted = [
            subtitle
            for subtitle in movie.get("subtitles") or []
            if subtitle.get("code2") == "en" and subtitle.get("path")
        ]
        if not extracted:
            raise ScenarioError("Bazarr recorded no extracted English subtitle")
        extracted_path = _host(extracted[0]["path"])
        if not extracted_path.exists() or extracted_path.stat().st_size == 0:
            raise ScenarioError(f"the extracted subtitle is not on disk: {extracted_path}")
        text = extracted_path.read_text(encoding="utf-8", errors="replace")
        if "subtitle from the forge" not in text:
            raise ScenarioError(
                f"the extracted subtitle is not the forge's: {extracted_path}"
            )

        wanted = _bazarr_movie(matrix["id"])
        if wanted is None:
            raise ScenarioError("Bazarr does not list The Matrix")
        if not any(
            subtitle.get("code2") == "en"
            for subtitle in wanted.get("missing_subtitles") or []
        ):
            raise ScenarioError("The Matrix should stay wanted in English")
        if wanted.get("subtitles"):
            raise ScenarioError(
                f"The Matrix should have no subtitle: {wanted['subtitles']}"
            )

        if _bazarr_settings()["general"]["use_embedded_subs"]:
            raise ScenarioError("Bazarr still counts embedded subtitles as existing")
        if not _history_has_embedded(big_buck_bunny["id"]):
            raise ScenarioError(
                "Bazarr's history has no embeddedsubtitles row for Big Buck Bunny"
            )

    def verify_absent(self) -> None:
        big_buck_bunny = _movie(BIG_BUCK_BUNNY_TMDB)
        matrix = _movie(THE_MATRIX_TMDB)
        bunny_path = _folder(big_buck_bunny) / BIG_BUCK_BUNNY_FILE
        matrix_path = _folder(matrix) / THE_MATRIX_FILE
        matrix_wanted = _folder(matrix) / THE_MATRIX_WANTED_FILE

        for path in (bunny_path.parent / f"{bunny_path.stem}.en.srt", matrix_wanted):
            if path.exists():
                raise ScenarioError(f"{path.name} survived the teardown")
        if not bunny_path.exists() or not matrix_path.exists():
            raise ScenarioError("the teardown did not restore the seeded files")
        for path in (bunny_path, matrix_path):
            if _subtitle_streams(path):
                raise ScenarioError(f"{path.name} still carries a subtitle track")

        if (big_buck_bunny.get("movieFile") or {}).get("relativePath") != bunny_path.name:
            raise ScenarioError("Radarr still points Big Buck Bunny at another file")
        if (matrix.get("movieFile") or {}).get("relativePath") != matrix_path.name:
            raise ScenarioError("Radarr still points The Matrix at another file")

        for movie in (big_buck_bunny, matrix):
            row = _bazarr_movie(movie["id"])
            if row is None:
                raise ScenarioError(f"Bazarr does not list {movie['title']}")
            if row.get("subtitles"):
                raise ScenarioError(
                    f"Bazarr still sees subtitles for {movie['title']}: {row['subtitles']}"
                )
            if not any(
                subtitle.get("code2") == "en"
                for subtitle in row.get("missing_subtitles") or []
            ):
                raise ScenarioError(f"{movie['title']} should be wanted in English again")

        if _bazarr_settings()["general"]["use_embedded_subs"]:
            raise ScenarioError(
                "Bazarr's use_embedded_subs is not the lab's false"
            )
        if MARKER.exists():
            raise ScenarioError("the scenario left its marker behind")


SCENARIO = BazarrEmbedded()
