"""The blocked imports on Radarr's queue (catalogue M-07, M-11), from the L13
phase 0 recipes.

Each case forges a release with its own torrent, seeds it, hands it to Radarr
through ``release/push`` and waits until Radarr's own download handling has
decided and stopped changing its mind. What it decides is the case:

- ``import-not-upgrade``: a release named 2160p whose file is 480p, for a movie
  that has the 1080p of S1. Radarr says ``Not an upgrade for existing movie
  file`` and waits for a person (``importPending`` with a warning).
- ``import-sample-only``: a release holding only a sample. Radarr says
  ``Sample`` and waits the same way.

These cases change what a teardown cannot put back by itself (a grab in
Radarr's history blocks the next one; ``Add it anyway`` replaces the movie's
file), so their journeys start from the ``l13-golden`` snapshot. The teardown
still removes what the case added, so the lab is usable after it.
"""

from __future__ import annotations

import import_lab as lab
from import_lab import Media

from .base import Scenario, ScenarioError


class QueueCase(Scenario):
    profiles = ("core", "downloads")
    release = ""
    files: tuple[Media, ...] = ()
    movie: tuple[str, int] = ("", 0)
    #: Words Radarr's queue record must hold once it settles.
    says = ""
    upgrades = False

    def _download_id(self) -> str:
        return lab.infohash_of(self.release)

    def _profile(self, *, allow: bool) -> None:
        """The movie's profile upgrades up to WEB 2160p, or does not."""
        movie = lab.movie_by_title(*self.movie)
        pid = movie["qualityProfileId"]
        profile = lab.arr("radarr", f"/qualityprofile/{pid}")
        profile["upgradeAllowed"] = allow
        if allow:
            for item in profile["items"]:
                if item.get("name") == "WEB 2160p":
                    profile["cutoff"] = item["id"]
        lab.arr("radarr", f"/qualityprofile/{pid}", "PUT", profile)

    def apply(self) -> None:
        if lab.queue_of("radarr", self._download_id() or "-"):
            raise ScenarioError(f"{self.release} is already in Radarr's queue")
        if self.upgrades:
            self._profile(allow=True)
        lab.forge({self.release: list(self.files)}, under="seed-data")
        lab.seed_release(self.release)
        lab.push_release(
            "radarr",
            self.release,
            size=sum(1 for _ in self.files) * 5_000_000,
        )
        lab.wait_settled("radarr", self._download_id())

    def verify(self) -> None:
        records = lab.queue_of("radarr", self._download_id())
        if not records:
            raise ScenarioError(f"{self.release} is not in Radarr's queue")
        words = " | ".join(lab.messages_of(records[0]))
        if self.says not in words:
            raise ScenarioError(f"Radarr says {words!r}, not {self.says!r}")

    def teardown(self) -> None:
        download_id = self._download_id()
        if download_id:
            lab.remove_from_queue("radarr", download_id)
        lab.unseed(self.release)
        if self.upgrades:
            self._profile(allow=False)

    def verify_absent(self) -> None:
        if (lab.testlab.STATE_ROOT / "seed-data" / self.release).exists():
            raise ScenarioError(f"{self.release} is still in the seeder's data")


class ImportNotUpgrade(QueueCase):
    name = "import-not-upgrade"
    release = "Big.Buck.Bunny.2008.2160p.WEB-DL.DDP5.1.H.265-CUPOLA"
    files = (Media("Big.Buck.Bunny.2008.480p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv", "854x480", 120),)
    movie = ("Big Buck Bunny", 2008)
    says = "Not an upgrade for existing movie file"
    upgrades = True


class ImportSampleOnly(QueueCase):
    name = "import-sample-only"
    release = "Elephants.Dream.2006.1080p.WEB-DL.DDP5.1.H.264-CUPOLA"
    files = (
        Media("Elephants.Dream.2006.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.sample.mkv", seconds=20),
    )
    movie = ("Elephants Dream", 2006)
    says = "Sample"
