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

from typing import Callable

import import_lab as lab
from import_lab import Media

from .base import Scenario, ScenarioError

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
