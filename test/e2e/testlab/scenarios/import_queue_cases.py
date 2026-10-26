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

from .base import Scenario, ScenarioError, credentials


class QueueCase(Scenario):
    profiles = ("core", "downloads")
    #: The arr whose queue the case runs through.
    service = "radarr"
    #: The size the release claims per file: the arrs judge it against the
    #: quality definition and the runtime, and the forged files are tiny.
    claimed_size = 5_000_000
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
        if lab.queue_of(self.service, self._download_id() or "-"):
            raise ScenarioError(f"{self.release} is already in Radarr's queue")
        if self.upgrades:
            self._profile(allow=True)
        lab.forge({self.release: list(self.files)}, under="seed-data")
        lab.seed_release(self.release)
        lab.push_release(
            self.service,
            self.release,
            size=len(self.files) * self.claimed_size,
        )
        lab.wait_settled(self.service, self._download_id())

    def verify(self) -> None:
        records = lab.queue_of(self.service, self._download_id())
        if not records:
            raise ScenarioError(f"{self.release} is not in Radarr's queue")
        words = " | ".join(lab.messages_of(records[0]))
        if self.says not in words:
            raise ScenarioError(f"Radarr says {words!r}, not {self.says!r}")

    def teardown(self) -> None:
        download_id = self._download_id()
        if download_id:
            lab.remove_from_queue(self.service, download_id)
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


# --- Sonarr (L13 phase C) -----------------------------------------------------
#
# The client and the indexer Sonarr needs are put in by the case and taken out
# by its teardown (D49), so the golden library keeps neither. The client's
# password is the lab's own, read from the credentials file: Radarr returns its
# secrets masked, so a copy would not carry it.

CLIENT_NAME = "qBittorrent (testlab)"
INDEXER_NAME = "Cupola testlab"
INDEXER_URL = "http://testlab-indexer:8088/"


def _set_fields(item: dict, values: dict) -> None:
    for field in item["fields"]:
        if field["name"] in values:
            field["value"] = values[field["name"]]


def _wire_sonarr() -> None:
    secrets = credentials()
    clients = lab.arr("sonarr", "/downloadclient") or []
    if not any(client.get("name") == CLIENT_NAME for client in clients):
        schema = next(
            item
            for item in lab.arr("sonarr", "/downloadclient/schema") or []
            if item.get("implementation") == "QBittorrent"
        )
        _set_fields(
            schema,
            {
                "host": "qbittorrent",
                "port": 8080,
                "useSsl": False,
                "urlBase": "",
                "username": secrets.get("CUPOLA_TESTLAB_QBITTORRENT_USERNAME", "admin"),
                "password": secrets.get("CUPOLA_TESTLAB_QBITTORRENT_PASSWORD", ""),
                "tvCategory": "tv-sonarr",
                "tvImportedCategory": "",
                "recentTvPriority": 0,
                "olderTvPriority": 0,
                "initialState": 0,
                "sequentialOrder": False,
                "firstAndLast": False,
                "contentLayout": 0,
            },
        )
        schema.update({"name": CLIENT_NAME, "enable": True, "priority": 1})
        lab.arr("sonarr", "/downloadclient?forceSave=true", "POST", schema)
    indexers = lab.arr("sonarr", "/indexer") or []
    if not any(indexer.get("name") == INDEXER_NAME for indexer in indexers):
        schema = next(
            item
            for item in lab.arr("sonarr", "/indexer/schema") or []
            if item.get("implementation") == "Torznab"
        )
        _set_fields(
            schema,
            {"baseUrl": INDEXER_URL, "apiPath": "/api", "categories": [5000]},
        )
        schema.update(
            {
                "name": INDEXER_NAME,
                "enableRss": False,
                "enableAutomaticSearch": False,
                "enableInteractiveSearch": False,
            }
        )
        lab.arr("sonarr", "/indexer?forceSave=true", "POST", schema)


def _unwire_sonarr() -> None:
    for item in lab.arr("sonarr", "/downloadclient") or []:
        if item.get("name") == CLIENT_NAME:
            lab.arr("sonarr", f"/downloadclient/{item['id']}", "DELETE")
    for item in lab.arr("sonarr", "/indexer") or []:
        if item.get("name") == INDEXER_NAME:
            lab.arr("sonarr", f"/indexer/{item['id']}", "DELETE")


class SonarrQueueCase(QueueCase):
    """A release through Sonarr's queue, with the client and indexer it needs."""

    service = "sonarr"
    # A credible episode (L13 phase 0): Sonarr refuses 4.8 MB for a 58 minute one.
    claimed_size = 3_000_000_000

    def apply(self) -> None:
        _wire_sonarr()
        super().apply()

    #: (season, episode) of Breaking Bad the case imports: their files come out.
    imported: tuple[tuple[int, int], ...] = ()

    def teardown(self) -> None:
        super().teardown()
        series = next(
            item
            for item in lab.arr("sonarr", "/series") or []
            if item.get("title") == "Breaking Bad"
        )
        for season, number in self.imported:
            episodes = lab.arr("sonarr", f"/episode?seriesId={series['id']}") or []
            episode = next(
                item
                for item in episodes
                if item.get("seasonNumber") == season
                and item.get("episodeNumber") == number
            )
            if episode.get("episodeFileId"):
                lab.arr("sonarr", f"/episodefile/{episode['episodeFileId']}", "DELETE")
        _unwire_sonarr()


class SonarrEpisodeNamesDontMatch(SonarrQueueCase):
    """M-11 on Sonarr: a grab for S01E01 whose file is S01E03.

    Sonarr says the episode is not in the grabbed release and waits for a
    person: `Add it anyway` on the file reads it as S1 E3, from its name.
    """

    name = "import-sonarr-episode"
    release = "Breaking.Bad.S01E01.1080p.WEB-DL.DDP5.1.H.264-CUPOLA"
    imported = ((1, 3),)
    files = (
        Media("Breaking.Bad.S01E03.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv", seconds=600),
    )
    says = "Episode 1x03 was not found in the grabbed release"


class SonarrSampleOnly(SonarrQueueCase):
    """M-13 on Sonarr: a release holding only a sample."""

    name = "import-sonarr-sample-only"
    release = "Breaking.Bad.S02E01.1080p.WEB-DL.DDP5.1.H.264-CUPOLA"
    files = (
        Media("Breaking.Bad.S02E01.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.sample.mkv", seconds=20),
    )
    says = "Sample"
