"""A-01, A-04, A-06 and A-07 on Radarr, on disposable state only.

The four rows of the flow catalogue the app performs on a movie: add it with a
chosen quality profile, root folder, monitoring and tag; search for it; change
its profile and monitoring; remove it with its files and an import list
exclusion. Everything here is a title the scenario owns: ``tmdbId`` 999001 in
``/media/movies4k``, a cloned quality profile, a tag, and a second root folder.
Nothing in the seeded library is edited, so ``teardown`` takes the whole state
out and the library reads as it did.

The flow is proven once inside ``apply`` (add, search, change, remove, read the
404 and the missing folder), and then the movie is added again so that the
``testlab_arr_radarr_e2e_test.dart`` run that follows has a live title to act
on with the app's own calls. The evidence of the first pass is kept in
``state/scenario-state/arr-actions-radarr.json`` and re-read by ``verify``.

The file the removal deletes is the forged release's own mkv, dropped into the
movie's folder and taken in by ``RescanMovie``: a movie with no file would make
``deleteFiles`` prove nothing.
"""

from __future__ import annotations

import shutil
import time
from typing import Any

import arr_probe as probe

from .base import STATE_ROOT, Scenario, ScenarioError

NAME = "arr-actions-radarr"
TMDB_ID = 999001
PROFILE_NAME = "Cupola testlab 1080p"
PROFILE_SOURCE = 4  # HD-1080p
CHANGED_PROFILE = 3  # HD-720p, the profile A-04 changes to and back
TAG_LABEL = "cupola-testlab"
ROOT_PATH = "/media/movies4k"
SEED_FILE = (
    STATE_ROOT
    / "seed-data"
    / "The.Great.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA"
    / "The.Great.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA.mkv"
)


def _movie_payload(profile_id: int, tag_id: int) -> dict[str, Any]:
    """The minimum Radarr needs to add a movie it already knows by TMDB id."""
    return {
        "title": "Cupola testlab movie",
        "tmdbId": TMDB_ID,
        "year": 2026,
        "qualityProfileId": profile_id,
        "rootFolderPath": ROOT_PATH,
        "monitored": True,
        "minimumAvailability": "released",
        "addOptions": {"searchForMovie": False},
        "images": [],
        "tags": [tag_id],
    }


def _host_path(container_path: str):
    """A path inside the container as the same path under the lab's state."""
    return STATE_ROOT / container_path.lstrip("/")


def _require_movie() -> dict[str, Any]:
    movie = probe.find_movie(probe.RADARR, TMDB_ID)
    if movie is None:
        raise ScenarioError(f"Radarr does not hold TMDB id {TMDB_ID}")
    return movie


def _reread_until(predicate, *, what: str) -> dict[str, Any]:
    return probe.wait_until(
        _require_movie, predicate, what=what, timeout=60, interval=1
    )


def _drop_a_file(movie: dict[str, Any]) -> None:
    """Put the forged release in the movie's folder and let Radarr scan it."""
    if not SEED_FILE.is_file():
        raise ScenarioError(f"the forged release is not at {SEED_FILE}")
    folder = _host_path(movie["path"])
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SEED_FILE, folder / SEED_FILE.name)
    probe.command(
        probe.RADARR,
        {"name": "RescanMovie", "movieIds": [movie["id"]]},
        "starting a movie rescan",
    )
    _reread_until(
        lambda item: bool(item.get("hasFile")),
        what="Radarr taking the dropped file in",
    )


def _wait_for_folder_gone(folder, *, timeout: float = 90) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not folder.exists():
            return True
        time.sleep(2)
    return not folder.exists()


class ArrActionsRadarr(Scenario):
    name = NAME
    profiles = ("core", "downloads")

    def apply(self) -> None:
        values: dict[str, Any] = {}
        # A run that stopped half way leaves the movie behind; the add below
        # would then be a duplicate, so the scenario starts from no movie.
        leftover = probe.find_movie(probe.RADARR, TMDB_ID)
        if leftover is not None:
            probe.call(
                probe.RADARR,
                f"/movie/{leftover['id']}?deleteFiles=true&addImportExclusion=false",
                method="DELETE",
            )
        host_created = probe.host_dir(probe.MOVIES_4K)
        root_id, root_created = probe.ensure_root_folder(probe.RADARR, ROOT_PATH)
        profile_id, profile_created = probe.ensure_profile(
            probe.RADARR, PROFILE_SOURCE, PROFILE_NAME
        )
        tag_id, tag_created = probe.ensure_tag(probe.RADARR, TAG_LABEL)
        values.update(
            {
                "hostCreated": host_created,
                "rootFolderId": root_id,
                "rootFolderCreated": root_created,
                "profileId": profile_id,
                "profileCreated": profile_created,
                "tagId": tag_id,
                "tagCreated": tag_created,
            }
        )

        # A-01: the add, read back by TMDB id.
        created = probe.write(
            probe.RADARR,
            "/movie",
            "POST",
            _movie_payload(profile_id, tag_id),
            "adding the disposable movie",
        )
        movie_id = int(created["id"])
        movie = _reread_until(
            lambda item: item.get("id") == movie_id
            and item.get("qualityProfileId") == profile_id,
            what="Radarr taking the movie in",
        )
        values["movieId"] = movie_id
        values["moviePath"] = movie["path"]

        # A-06: the automatic search, and what the service says it did.
        search = probe.command(
            probe.RADARR,
            {"name": "MoviesSearch", "movieIds": [movie_id]},
            "starting a movie search",
        )
        settled = probe.wait_command(
            probe.RADARR, int(search["id"]), what="the movie search"
        )
        if settled.get("status") != "completed":
            raise ScenarioError(
                "the movie search did not complete: " f"{settled.get('status')}"
            )
        values["searchStatus"] = settled.get("status")
        values["searchMessage"] = settled.get("message")

        # A-04: a profile change and a monitoring change, both read back.
        item = _require_movie()
        item["qualityProfileId"] = CHANGED_PROFILE
        item["monitored"] = False
        probe.write(
            probe.RADARR,
            f"/movie/{movie_id}",
            "PUT",
            item,
            "changing the movie's profile and monitoring",
        )
        changed = _reread_until(
            lambda record: record.get("qualityProfileId") == CHANGED_PROFILE
            and record.get("monitored") is False,
            what="Radarr keeping the changed profile and monitoring",
        )
        values["changedProfileId"] = changed["qualityProfileId"]
        values["changedMonitored"] = changed["monitored"]

        item = _require_movie()
        item["qualityProfileId"] = profile_id
        item["monitored"] = True
        probe.write(
            probe.RADARR,
            f"/movie/{movie_id}",
            "PUT",
            item,
            "putting the movie's profile and monitoring back",
        )
        restored = _reread_until(
            lambda record: record.get("qualityProfileId") == profile_id
            and record.get("monitored") is True,
            what="Radarr keeping the restored profile and monitoring",
        )
        values["restoredProfileId"] = restored["qualityProfileId"]
        values["restoredMonitored"] = restored["monitored"]

        # A-07: a removal with its files and an import list exclusion.
        movie = _require_movie()
        folder = _host_path(movie["path"])
        _drop_a_file(movie)
        status, body = probe.call(
            probe.RADARR,
            f"/movie/{movie_id}?deleteFiles=true&addImportExclusion=true",
            method="DELETE",
        )
        if not 200 <= status < 300:
            raise ScenarioError(f"removing the movie failed with {status}: {body}")
        status, body = probe.call(probe.RADARR, f"/movie/{movie_id}")
        if status != 404:
            raise ScenarioError(
                f"the removed movie answers {status} instead of 404"
            )
        values["removedStatus"] = status
        values["folderGone"] = _wait_for_folder_gone(folder)
        # Radarr writes the exclusion a moment after the delete answers, so
        # the read that proves it has to wait for it rather than race it.
        try:
            probe.wait_until(
                lambda: probe.import_exclusions(probe.RADARR),
                lambda exclusions: any(
                    exclusion.get("tmdbId") == TMDB_ID for exclusion in exclusions
                ),
                what="the removal's import list exclusion",
                timeout=45,
                interval=2,
            )
        except ScenarioError:
            values["exclusionSeen"] = False
        else:
            values["exclusionSeen"] = True
        if not values["exclusionSeen"]:
            raise ScenarioError(
                "the removal added no import list exclusion for the movie"
            )
        probe.delete_import_exclusion(probe.RADARR, tmdb_id=TMDB_ID)

        # The live state the e2e acts on: the movie is back, the rest stays.
        created = probe.write(
            probe.RADARR,
            "/movie",
            "POST",
            _movie_payload(profile_id, tag_id),
            "adding the disposable movie again",
        )
        values["movieId"] = int(created["id"])
        movie = _reread_until(
            lambda item: item.get("id") == values["movieId"]
            and item.get("qualityProfileId") == profile_id,
            what="Radarr taking the movie in again",
        )
        values["moviePath"] = movie["path"]
        probe.save_state(NAME, values)

    def verify(self) -> None:
        values = probe.load_state(NAME)
        movie = _require_movie()
        if movie.get("id") != values["movieId"]:
            raise ScenarioError(
                f"the movie reads id {movie.get('id')}, not {values['movieId']}"
            )
        if movie.get("qualityProfileId") != values["profileId"]:
            raise ScenarioError(
                "the movie reads profile "
                f"{movie.get('qualityProfileId')}, not {values['profileId']}"
            )
        if movie.get("rootFolderPath") != ROOT_PATH:
            raise ScenarioError(
                f"the movie reads root {movie.get('rootFolderPath')!r}"
            )
        if movie.get("monitored") is not True:
            raise ScenarioError("the movie is not monitored")
        if values["tagId"] not in (movie.get("tags") or []):
            raise ScenarioError(
                f"the movie carries tags {movie.get('tags')}, not {values['tagId']}"
            )
        if movie.get("hasFile"):
            raise ScenarioError("the disposable movie has a file")
        if not str(movie.get("path", "")).startswith(f"{ROOT_PATH}/"):
            raise ScenarioError(f"the movie lives at {movie.get('path')!r}")

        profiles = probe.quality_profiles(probe.RADARR)
        if not any(item.get("name") == PROFILE_NAME for item in profiles):
            raise ScenarioError(f"the cloned profile {PROFILE_NAME!r} is gone")
        tags = probe.get(probe.RADARR, "/tag", "reading the tags")
        if not any(item.get("label") == TAG_LABEL for item in tags):
            raise ScenarioError(f"the tag {TAG_LABEL!r} is gone")
        folders = probe.get(probe.RADARR, "/rootfolder", "reading the root folders")
        if not any(item.get("path") == ROOT_PATH for item in folders):
            raise ScenarioError(f"the root folder {ROOT_PATH} is gone")

        if values.get("searchStatus") != "completed":
            raise ScenarioError(
                f"the search settled as {values.get('searchStatus')!r}"
            )
        if values.get("changedProfileId") != CHANGED_PROFILE:
            raise ScenarioError("the profile change was never read back")
        if values.get("changedMonitored") is not False:
            raise ScenarioError("the monitoring change was never read back")
        if values.get("restoredProfileId") != values["profileId"]:
            raise ScenarioError("the profile was not put back")
        if values.get("removedStatus") != 404:
            raise ScenarioError("the removal never answered 404")
        if not values.get("folderGone"):
            raise ScenarioError("the removed movie's folder is still on disk")
        if not values.get("exclusionSeen"):
            raise ScenarioError("the removal added no import list exclusion")

    def teardown(self) -> None:
        movie = probe.find_movie(probe.RADARR, TMDB_ID)
        if movie is not None:
            status, body = probe.call(
                probe.RADARR,
                f"/movie/{movie['id']}?deleteFiles=true&addImportExclusion=false",
                method="DELETE",
            )
            if not 200 <= status < 300:
                raise ScenarioError(
                    f"removing the disposable movie failed with {status}: {body}"
                )
        probe.delete_import_exclusion(probe.RADARR, tmdb_id=TMDB_ID)
        probe.delete_tag(probe.RADARR, TAG_LABEL)
        profile = probe.find_profile(probe.RADARR, PROFILE_NAME)
        if profile is not None:
            probe.delete_profile(probe.RADARR, int(profile["id"]))
        probe.delete_root_folder(probe.RADARR, ROOT_PATH)
        probe.remove_host_dir(probe.MOVIES_4K)
        probe.clear_state(NAME)

    def verify_absent(self) -> None:
        if probe.find_movie(probe.RADARR, TMDB_ID) is not None:
            raise ScenarioError("the disposable movie is still in Radarr")
        if probe.find_profile(probe.RADARR, PROFILE_NAME) is not None:
            raise ScenarioError(f"the cloned profile {PROFILE_NAME!r} is still there")
        tags = probe.get(probe.RADARR, "/tag", "reading the tags")
        if any(item.get("label") == TAG_LABEL for item in tags):
            raise ScenarioError(f"the tag {TAG_LABEL!r} is still there")
        folders = probe.get(probe.RADARR, "/rootfolder", "reading the root folders")
        if any(item.get("path") == ROOT_PATH for item in folders):
            raise ScenarioError(f"the root folder {ROOT_PATH} is still there")
        if any(
            exclusion.get("tmdbId") == TMDB_ID
            for exclusion in probe.import_exclusions(probe.RADARR)
        ):
            raise ScenarioError("the import list exclusion is still there")
        if probe.MOVIES_4K.exists():
            raise ScenarioError(f"{probe.MOVIES_4K} is still on disk")


SCENARIO = ArrActionsRadarr()
