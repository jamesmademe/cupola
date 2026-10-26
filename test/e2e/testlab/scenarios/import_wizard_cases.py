"""The manual import wizard's cases on Radarr (catalogue M-01..M-15).

Each case is a folder of forged files under ``downloads/manual-import/`` and the
movies those files are for. ``apply`` forges the folder and proves what
Radarr's own scan says about it; ``teardown`` takes out of the library whatever
the journey imported and removes the folder, through Radarr's API, so the case
can run again without a snapshot. Every case has movies of its own, so the
order the journeys run in does not matter.

The durations follow the arrs' sample rule (L4): 600 s for a feature, 120-240 s
for a short whose runtime is a few minutes, 20 s for a sample.
"""

from __future__ import annotations

import subprocess
import time
from typing import Callable

import import_lab as lab
from import_lab import Media

from .base import STATE_ROOT, Scenario, ScenarioError

FEATURE = 600


class WizardCase(Scenario):
    """One folder for the wizard, and the movies it may fill."""

    profiles = ("core", "downloads")
    folder = ""
    files: tuple[Media, ...] = ()
    #: (title, year) of every movie the journey may import into.
    movies: tuple[tuple[str, int], ...] = ()
    #: What Radarr's scan must say about the folder before the journey runs.
    expect: Callable[[list[dict]], str | None] = staticmethod(lambda items: None)

    def apply(self) -> None:
        for title, year in self.movies:
            if lab.movie_by_title(title, year).get("hasFile"):
                raise ScenarioError(
                    f"{title} already has a file: tear the case down first"
                )
        lab.forge({self.folder: list(self.files)}, under="downloads")

    def verify(self) -> None:
        names = lab.wizard_files(self.folder)
        missing = [media.name for media in self.files if media.name not in names]
        if missing:
            raise ScenarioError(f"the forge did not write {missing}")
        items = lab.scan("radarr", self.folder)
        problem = self.expect(items)
        if problem:
            raise ScenarioError(f"{problem}: {lab.describe(items)}")

    def teardown(self) -> None:
        for title, year in self.movies:
            lab.delete_movie_file(lab.movie_by_title(title, year)["id"])
        lab.remove_wizard(self.folder)

    def verify_absent(self) -> None:
        if lab.wizard_files(self.folder):
            raise ScenarioError(f"{self.folder} is still in the downloads")
        for title, year in self.movies:
            if lab.movie_by_title(title, year).get("hasFile"):
                raise ScenarioError(f"{title} kept a file after teardown")


def _matched(*titles: str) -> Callable[[list[dict]], str | None]:
    def check(items: list[dict]) -> str | None:
        found = {(item.get("movie") or {}).get("title") for item in items}
        absent = [title for title in titles if title not in found]
        return f"Radarr's scan does not match {absent}" if absent else None

    return check


def _unmatched(count: int) -> Callable[[list[dict]], str | None]:
    def check(items: list[dict]) -> str | None:
        loose = [item for item in items if not item.get("movie")]
        if len(loose) != count:
            return f"Radarr's scan should leave {count} file(s) without a movie"
        return None

    return check


class ImportLocate(WizardCase):
    """M-01: a folder to find by path and to browse into, then scan."""

    name = "import-locate"
    folder = "Spring.2014.1080p.WEB-DL.DDP5.1.H.264-CUPOLA"
    files = (Media(f"{folder}.mkv", seconds=FEATURE),)
    movies = (("Spring", 2014),)
    expect = staticmethod(_matched("Spring"))


class ImportReady(WizardCase):
    """M-02 and M-15: two files Radarr recognises, ready to go in."""

    name = "import-ready"
    folder = "l13-ready"
    files = (
        Media("Sintel.2010.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv", seconds=FEATURE),
        Media(
            "Tears.of.Steel.2012.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv",
            seconds=FEATURE,
        ),
    )
    movies = (("Sintel", 2010), ("Tears of Steel", 2012))
    expect = staticmethod(_matched("Sintel", "Tears of Steel"))


class ImportUnrecognised(WizardCase):
    """M-03: a file whose name names no movie in the library."""

    name = "import-unrecognised"
    folder = "The.Fright.Sprite.2024.1080p.WEB-DL.DDP5.1.H.264-CUPOLA"
    files = (Media(f"{folder}.mkv", seconds=FEATURE),)
    movies = (("Sprite Fright", 2024),)
    expect = staticmethod(_unmatched(1))


def _ensure_remake() -> None:
    """Puts the 1998 remake of Psycho (D47) in the library, as the seed does.

    The seed adds the world's missing movies and nothing else, so a golden
    snapshot taken before the movie was in the world gets it here, from the
    same builder, and every later run finds it already there.
    """
    try:
        lab.movie_by_title("Psycho", 1998)
    except ScenarioError:
        import seed_lab

        seed_lab.seed_radarr_library(seed_lab.load_world(STATE_ROOT))


class ImportAmbiguous(WizardCase):
    """M-04: a file whose name names both Psycho movies, 1960 and 1998.

    Radarr's scan cannot choose, so the file waits for `Which movie?`. The
    journey picks the 1998 movie, and the server must file it under that id.
    """

    name = "import-ambiguous"
    folder = "l13-ambiguous"
    files = (Media("Psycho.mkv", seconds=FEATURE),)
    movies = (("Psycho", 1998),)
    expect = staticmethod(_unmatched(1))

    def apply(self) -> None:
        _ensure_remake()
        super().apply()

    def teardown(self) -> None:
        # The movie record stays; only the file the journey imported goes.
        lab.delete_movie_file(lab.movie_by_title("Psycho", 1998)["id"])
        lab.remove_wizard(self.folder)


class ImportSample(WizardCase):
    """M-08: a feature and its sample in one folder."""

    name = "import-sample"
    folder = "Elephants.Dream.2006.1080p.WEB-DL.DDP5.1.H.264-CUPOLA"
    files = (
        Media(f"{folder}.mkv", seconds=FEATURE),
        Media(f"{folder}.sample.mkv", seconds=20),
    )
    movies = (("Elephants Dream", 2006),)

    @staticmethod
    def expect(items: list[dict]) -> str | None:
        samples = [
            item
            for item in items
            if any(
                "sample" in str(r.get("reason", "")).lower()
                for r in item.get("rejections") or []
            )
        ]
        if len(samples) != 1:
            return "Radarr's scan should call exactly one file a sample"
        return None


class ImportUnknownQuality(WizardCase):
    """M-09: a file whose name says no quality and no language."""

    name = "import-unknown-quality"
    folder = "l13-unknown-quality"
    files = (Media("Coffee Run (2020).mkv", seconds=240),)
    movies = (("Coffee Run", 2020),)
    expect = staticmethod(_matched("Coffee Run"))


class ImportFixMatch(WizardCase):
    """M-14: two files that name nothing, both for the same short."""

    name = "import-fix-match"
    folder = "l13-fix-match"
    files = (
        Media("clip.one.mkv", seconds=180),
        Media("clip.two.mkv", seconds=180),
    )
    movies = (("Charge", 2022),)
    expect = staticmethod(_unmatched(2))


class ImportFailed(WizardCase):
    """M-15: a file the journey scans, and that is gone before the import.

    The journey tears the case down after the scan and before it confirms:
    the teardown removes the file, and Radarr's command then fails with
    ``File doesn't exist``.
    """

    name = "import-failed"
    folder = "Jaws.1975.1080p.BluRay.x264-CUPOLA"
    files = (Media(f"{folder}.mkv", seconds=FEATURE),)
    movies = (("Jaws", 1975),)
    expect = staticmethod(_matched("Jaws"))


# --- Sonarr and Lidarr (L13 phase B) ----------------------------------------
#
# The same wizard on the other two arrs. Each case forges its own folder and
# proves the scan; the teardown takes out what the journey imported, through
# the arr's API. Breaking Bad and Air's Moon Safari are in the golden
# library with no files, so a teardown removes only what a case put there.


def _command_done(service: str, command: dict, *, timeout: float = 120) -> dict:
    """Polls an arr command until it finishes; a failed one is an error."""
    deadline = time.monotonic() + timeout
    while True:
        current = lab.arr(service, f"/command/{command['id']}")
        if current.get("status") in ("completed", "failed", "aborted"):
            if current.get("status") != "completed":
                raise ScenarioError(f"{service} command {command['name']} {current.get('status')}")
            return current
        if time.monotonic() > deadline:
            raise ScenarioError(f"{service} command {command['name']} never finished")
        time.sleep(1)


def _series(title: str) -> dict:
    for series in lab.arr("sonarr", "/series") or []:
        if series.get("title") == title:
            return series
    raise ScenarioError(f"{title} is not in Sonarr's library")


def _episode(series_id: int, season: int, number: int) -> dict:
    for episode in lab.arr("sonarr", f"/episode?seriesId={series_id}") or []:
        if episode.get("seasonNumber") == season and episode.get("episodeNumber") == number:
            return episode
    raise ScenarioError(f"Sonarr holds no episode {season}x{number}")


def _drop_episode_file(episode: dict) -> None:
    file_id = episode.get("episodeFileId") or 0
    if file_id:
        lab.arr("sonarr", f"/episodefile/{file_id}", "DELETE")


def _import_now(folder: str, season: int, number: int) -> None:
    """Imports the file of one episode the way the wizard does, by the API.

    Puts an episode in the library before a case starts, so the case has an
    episode that is already taken.
    """
    for item in lab.scan("sonarr", folder):
        episodes = item.get("episodes") or []
        if any(
            e.get("seasonNumber") == season and e.get("episodeNumber") == number
            for e in episodes
        ):
            command = lab.arr(
                "sonarr",
                "/command",
                "POST",
                {
                    "name": "ManualImport",
                    "importMode": "copy",
                    "files": [
                        {
                            "path": item["path"],
                            "folderName": lab.wizard_path(folder),
                            "seriesId": item["series"]["id"],
                            "seasonNumber": item["seasonNumber"],
                            "episodeIds": [e["id"] for e in episodes],
                            "quality": item["quality"],
                            "languages": item.get("languages") or [],
                            "releaseGroup": item.get("releaseGroup") or "",
                            "indexerFlags": 0,
                            "downloadId": "",
                        }
                    ],
                },
            )
            _command_done("sonarr", command)
            return
    raise ScenarioError(f"Sonarr's scan of {folder} has no {season}x{number}")


class SeriesCase(Scenario):
    """A Sonarr wizard case: a folder, and the episodes the journey may take."""

    profiles = ("core", "downloads")
    folder = ""
    files: tuple[Media, ...] = ()
    series = "Breaking Bad"
    #: (season, episode) the journey may import; their files are taken out.
    episodes: tuple[tuple[int, int], ...] = ()
    #: (season, episode) imported before the journey starts.
    prefilled: tuple[tuple[int, int], ...] = ()

    def expect(self, items: list[dict]) -> str | None:
        return None

    def apply(self) -> None:
        series = _series(self.series)
        for season, number in (*self.episodes, *self.prefilled):
            if _episode(series["id"], season, number).get("hasFile"):
                raise ScenarioError(
                    f"{season}x{number} already has a file: tear the case down first"
                )
        lab.forge({self.folder: list(self.files)}, under="downloads")
        for season, number in self.prefilled:
            _import_now(self.folder, season, number)

    def verify(self) -> None:
        names = lab.wizard_files(self.folder)
        missing = [media.name for media in self.files if media.name not in names]
        if missing:
            raise ScenarioError(f"the forge did not write {missing}")
        items = lab.scan("sonarr", self.folder)
        problem = self.expect(items)
        if problem:
            raise ScenarioError(f"{problem}: {lab.describe(items)}")

    def teardown(self) -> None:
        series = _series(self.series)
        for season, number in (*self.episodes, *self.prefilled):
            _drop_episode_file(_episode(series["id"], season, number))
        lab.remove_wizard(self.folder)

    def verify_absent(self) -> None:
        if lab.wizard_files(self.folder):
            raise ScenarioError(f"{self.folder} is still in the downloads")
        series = _series(self.series)
        for season, number in self.episodes:
            if _episode(series["id"], season, number).get("hasFile"):
                raise ScenarioError(f"{season}x{number} kept a file after teardown")


class SonarrEpisodesReady(SeriesCase):
    """M-01 and M-02 on Sonarr: two episodes named well, ready to go in."""

    name = "import-series-ready"
    folder = "l13-series-ready"
    files = (
        Media("Breaking.Bad.S01E01.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv", seconds=FEATURE),
        Media("Breaking.Bad.S01E02.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv", seconds=FEATURE),
    )
    episodes = ((1, 1), (1, 2))

    def expect(self, items: list[dict]) -> str | None:
        matched = {
            (e.get("seasonNumber"), e.get("episodeNumber"))
            for item in items
            for e in item.get("episodes") or []
        }
        if {(1, 1), (1, 2)} - matched:
            return "Sonarr's scan does not match S01E01 and S01E02"
        return None


class SonarrFixMatch(SeriesCase):
    """M-14 on Sonarr: two files that name no episode, each given one by hand."""

    name = "import-series-fix"
    folder = "l13-series-fix"
    files = (
        Media("clip.one.mkv", seconds=FEATURE),
        Media("clip.two.mkv", seconds=FEATURE),
    )
    episodes = ((1, 3), (1, 4))

    def expect(self, items: list[dict]) -> str | None:
        loose = [item for item in items if not item.get("episodes")]
        if len(loose) != 2:
            return "Sonarr's scan should leave two files without an episode"
        return None


class SonarrSeasonPack(SeriesCase):
    """M-06 on Sonarr: a season with a sample, and an episode already taken."""

    name = "import-season-pack"
    folder = "Breaking.Bad.S01.1080p.WEB-DL.DDP5.1.H.264-CUPOLA"
    files = (
        Media("Breaking.Bad.S01E01.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv", seconds=FEATURE),
        Media("Breaking.Bad.S01E02.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv", seconds=FEATURE),
        Media("Breaking.Bad.S01E03.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv", seconds=FEATURE),
        Media("Breaking.Bad.S01E01.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.sample.mkv", seconds=20),
    )
    episodes = ((1, 1), (1, 2), (1, 3))


# --- Lidarr -----------------------------------------------------------------

ALBUM_TRACKS = (
    (1, "La Femme d’argent"),
    (2, "Sexy Boy"),
    (3, "All I Need"),
)


def _album(artist_name: str, title: str) -> dict:
    artist = next(
        (a for a in lab.arr("lidarr", "/artist") or [] if a.get("artistName") == artist_name),
        None,
    )
    if artist is None:
        raise ScenarioError(f"{artist_name} is not in Lidarr's library")
    for album in lab.arr("lidarr", f"/album?artistId={artist['id']}") or []:
        if album.get("title") == title:
            return album
    raise ScenarioError(f"Lidarr holds no album {title}")


def _drop_track_files(album: dict, codes: tuple[str, ...]) -> None:
    for track in lab.arr("lidarr", f"/track?albumId={album['id']}") or []:
        if str(track.get("trackNumber")) in codes and track.get("trackFileId"):
            lab.arr("lidarr", f"/trackfile/{track['trackFileId']}", "DELETE")


def _write_tracks(folder: str, files: tuple[Media, ...], artist: str, album: str) -> None:
    """Writes the case's FLAC tracks, tagged with their artist and album.

    The forge image hard-codes Daft Punk in its tags, so the Lidarr cases write
    their own tracks with the host's ffmpeg, into the folder the lab mounts as
    the client's downloads. A file with no track number gets no tags at all.
    """
    directory = STATE_ROOT / "downloads" / lab.WIZARD_ROOT / folder
    directory.mkdir(parents=True, exist_ok=True)
    for media in files:
        tags: list[str] = []
        if media.track:
            tags = [
                "-metadata", f"title={media.title}",
                "-metadata", f"artist={artist}",
                "-metadata", f"album={album}",
                "-metadata", f"track={media.track}",
            ]
        subprocess.run(
            [
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
                "-t", str(media.seconds), "-c:a", "flac", *tags,
                str(directory / media.name),
            ],
            check=True,
        )


class LidarrCase(Scenario):
    """A Lidarr wizard case: a folder of tracks, and the album's tracks it may take."""

    profiles = ("core", "downloads")
    folder = ""
    files: tuple[Media, ...] = ()
    artist = "Air"
    album = "Moon Safari"
    #: Lidarr's track numbers (`a1`, `b2`…) the journey may import; their files come out.
    tracks: tuple[str, ...] = ()

    def apply(self) -> None:
        album = _album(self.artist, self.album)
        if any(
            t.get("trackFileId")
            for t in lab.arr("lidarr", f"/track?albumId={album['id']}") or []
            if str(t.get("trackNumber")) in self.tracks
        ):
            raise ScenarioError("a track already has a file: tear the case down first")
        _write_tracks(self.folder, self.files, self.artist, self.album)

    def verify(self) -> None:
        names = lab.wizard_files(self.folder)
        missing = [media.name for media in self.files if media.name not in names]
        if missing:
            raise ScenarioError(f"the forge did not write {missing}")
        items = lab.scan("lidarr", self.folder)
        if not items:
            raise ScenarioError("Lidarr's scan found nothing in the folder")

    def teardown(self) -> None:
        _drop_track_files(_album(self.artist, self.album), self.tracks)
        lab.remove_wizard(self.folder)

    def verify_absent(self) -> None:
        if lab.wizard_files(self.folder):
            raise ScenarioError(f"{self.folder} is still in the downloads")
        album = _album(self.artist, self.album)
        for track in lab.arr("lidarr", f"/track?albumId={album['id']}") or []:
            if str(track.get("trackNumber")) in self.tracks and track.get("trackFileId"):
                raise ScenarioError(f"track {track['trackNumber']} kept a file after teardown")


def _tracks_files(number_list: tuple[int, ...]) -> tuple[Media, ...]:
    return tuple(
        Media(
            f"Air - Moon Safari - {number:02d} - {name}.flac",
            seconds=180,
            track=number,
            title=name,
            album="Moon Safari",
        )
        for number, name in ALBUM_TRACKS
        if number in number_list
    )


class LidarrAlbumReady(LidarrCase):
    """M-01 and M-02 on Lidarr: an album's tracks named well, ready to go in."""

    name = "import-album-ready"
    folder = "l13-album-ready"
    files = _tracks_files((1, 2, 3))
    tracks = ("a1", "a2", "a3")


class LidarrTrackFix(LidarrCase):
    """M-14 on Lidarr: one track whose name says nothing; an artist, an album
    and a track are chosen by hand."""

    name = "import-track-fix"
    folder = "l13-track-fix"
    files = (Media("track.one.flac", seconds=180),)
    tracks = ("a2",)
