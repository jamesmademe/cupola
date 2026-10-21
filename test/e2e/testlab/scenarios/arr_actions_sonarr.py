"""A-02, A-04, A-06 and A-07 on Sonarr, on a disposable series only.

The series is ``Firefly`` (TVDB 78874): a real lookup, so the add posts back
what Sonarr's metadata proxy answered, exactly as ``SonarrService.addSeries``
does. If the lookup cannot answer (the lab's metadata host is outside the
containers), the scenario posts the minimum Sonarr needs and says so in its
state file, rather than pretending a lookup happened.

``apply`` proves the whole cycle once (add with ``firstSeason`` monitoring and
its seasons read back, the three searches, a season unmonitored and a series
type changed and put back, then a removal with an import list exclusion, the
404 and the folder gone) and then adds the series again for the e2e run that
follows. The library is never touched: ``teardown`` removes the series, the
root folder and the exclusion.

Two declared limits, both the lab's: Sonarr has no download client and no
indexer (the seed leaves them out), so its searches complete with no report and
its queue is empty; and the series has no episode file, so ``deleteFiles`` has
no file to delete here. Sonarr creates no folder for a series with no episodes,
so the scenario makes the folder itself, as a person's disk would have one, and
the removal is what takes it away.
"""

from __future__ import annotations

from typing import Any

import arr_probe as probe

from .base import STATE_ROOT, Scenario, ScenarioError

NAME = "arr-actions-sonarr"
TVDB_ID = 78874
TITLE = "Firefly"
YEAR = 2002
PROFILE_NAME = "Cupola testlab 1080p"
PROFILE_SOURCE = 4  # HD-1080p
CHANGED_PROFILE = 3  # HD-720p, the profile A-04 changes to and back
ROOT_PATH = "/media/tv-anime"
LOOKUP = f"/series/lookup?term=tvdb%3A{TVDB_ID}"


def _lookup() -> dict[str, Any] | None:
    status, body = probe.call(probe.SONARR, LOOKUP)
    if not 200 <= status < 300 or not isinstance(body, list):
        return None
    for item in body:
        if isinstance(item, dict) and item.get("tvdbId") == TVDB_ID:
            return item
    return None


def _direct_payload() -> dict[str, Any]:
    """What Sonarr needs when its metadata proxy does not answer."""
    return {
        "title": TITLE,
        "year": YEAR,
        "tvdbId": TVDB_ID,
        "images": [],
        "seasons": [{"seasonNumber": 1, "monitored": True}],
    }


def _add_payload(row: dict[str, Any], profile_id: int) -> dict[str, Any]:
    payload = dict(row)
    payload.update(
        {
            "qualityProfileId": profile_id,
            "rootFolderPath": ROOT_PATH,
            "monitored": True,
            "seasonFolder": True,
            "seriesType": "standard",
            "addOptions": {
                "monitor": "firstSeason",
                "searchForMissingEpisodes": False,
                "searchForCutoffUnmetEpisodes": False,
            },
            "images": payload.get("images") or [],
            "tags": [],
        }
    )
    return payload


def _require_series() -> dict[str, Any]:
    series = probe.find_series(probe.SONARR, TVDB_ID)
    if series is None:
        raise ScenarioError(f"Sonarr does not hold TVDB id {TVDB_ID}")
    return series


def _reread_until(predicate, *, what: str, timeout: float = 180) -> dict[str, Any]:
    return probe.wait_until(
        _require_series, predicate, what=what, timeout=timeout, interval=1
    )


def _wait_gone(*, timeout: float = 90) -> None:
    """Wait until Sonarr no longer holds the series.

    Sonarr answers a delete before the row is gone, and an add of the same TVDB
    id in that window is refused as a duplicate: the two calls have to be
    sequenced by the service's own answer, not by ours.
    """
    probe.wait_until(
        lambda: probe.find_series(probe.SONARR, TVDB_ID),
        lambda item: item is None,
        what="the removed series leaving Sonarr",
        timeout=timeout,
        interval=1,
    )


def _put_until(
    series_id: int,
    build,
    predicate,
    *,
    what: str,
    attempts: int = 3,
    timeout: float = 45,
) -> dict[str, Any]:
    """PUT the series and read it back, retrying a write that was overwritten.

    Sonarr writes a series update asynchronously and an add, a refresh or a
    second update that is still in flight can land after it. A person's change
    is not lost on the server's schedule, so the scenario sends it again until
    the service reads it back.
    """
    last: ScenarioError | None = None
    for _ in range(attempts):
        series = _require_series()
        probe.write(
            probe.SONARR,
            f"/series/{series_id}",
            "PUT",
            build(series),
            what,
        )
        try:
            return probe.wait_until(
                _require_series,
                predicate,
                what=what,
                timeout=timeout,
                interval=1,
            )
        except ScenarioError as error:
            last = error
    raise last if last is not None else ScenarioError(what)


def _add(row: dict[str, Any], profile_id: int) -> int:
    """Add the series, waiting out a delete that has not landed yet."""
    payload = _add_payload(row, profile_id)
    for attempt in range(3):
        status, body = probe.call(probe.SONARR, "/series", "POST", payload)
        if 200 <= status < 300:
            return int(body["id"])
        if status == 400 and attempt < 2:
            _wait_gone()
            continue
        raise ScenarioError(f"adding the series failed with {status}: {body}")
    raise ScenarioError("the series could not be added")


def _season_flags(series: dict[str, Any]) -> dict[int, bool]:
    return {
        int(season["seasonNumber"]): bool(season.get("monitored"))
        for season in series.get("seasons") or []
        if isinstance(season, dict)
    }


def _host_path(container_path: str):
    """A path inside the container as the same path under the lab's state."""
    return STATE_ROOT / container_path.lstrip("/")


def _ensure_series_folder(series: dict[str, Any]):
    """Make the series' folder, which Sonarr does not create on an add.

    A series added with no episodes has nothing to write yet, so the folder on
    disk is the person's own; the removal with ``deleteFiles`` is what takes it
    away, and that is the half of A-07 this scenario proves here.
    """
    folder = _host_path(series["path"])
    folder.mkdir(parents=True, exist_ok=True)
    return folder


class ArrActionsSonarr(Scenario):
    name = NAME
    profiles = ("core",)

    def apply(self) -> None:
        values: dict[str, Any] = {}
        # A run that stopped half way leaves the series behind; the add below
        # would then be a duplicate, so the scenario starts from no series.
        leftover = probe.find_series(probe.SONARR, TVDB_ID)
        if leftover is not None:
            probe.call(
                probe.SONARR,
                f"/series/{leftover['id']}?deleteFiles=true"
                "&addImportListExclusion=false",
                method="DELETE",
            )
            _wait_gone()
        host_created = probe.host_dir(probe.TV_ANIME)
        root_id, root_created = probe.ensure_root_folder(probe.SONARR, ROOT_PATH)
        profile_id, profile_created = probe.ensure_profile(
            probe.SONARR, PROFILE_SOURCE, PROFILE_NAME
        )
        values.update(
            {
                "hostCreated": host_created,
                "rootFolderId": root_id,
                "rootFolderCreated": root_created,
                "profileId": profile_id,
                "profileCreated": profile_created,
            }
        )

        # A-02: the lookup, then the add, read back by TVDB id.
        row = _lookup()
        values["lookup"] = "tvdb" if row is not None else "direct"
        series_id = _add(row if row is not None else _direct_payload(), profile_id)
        series = _reread_until(
            lambda item: item.get("id") == series_id
            and item.get("qualityProfileId") == profile_id
            and _season_flags(item).get(1) is True,
            what="Sonarr taking the series in with its first season monitored",
        )
        values["seriesId"] = series_id
        values["seriesPath"] = series["path"]
        values["seasonsMonitored"] = {
            str(number): monitored
            for number, monitored in _season_flags(series).items()
        }
        values["seriesType"] = series.get("seriesType")

        # A-06: the three searches the app can start for a series.
        for label, payload in (
            ("SeriesSearch", {"name": "SeriesSearch", "seriesId": series_id}),
            (
                "SeasonSearch",
                {"name": "SeasonSearch", "seriesId": series_id, "seasonNumber": 1},
            ),
        ):
            command = probe.command(
                probe.SONARR, payload, f"starting {label}"
            )
            settled = probe.wait_command(
                probe.SONARR, int(command["id"]), what=label
            )
            values[f"{label}Status"] = settled.get("status")
            values[f"{label}Message"] = settled.get("message")
        # Sonarr fetches the episode list after the add answers, so the rows
        # arrive a moment later.
        episodes = probe.wait_until(
            lambda: probe.get(
                probe.SONARR,
                f"/episode?seriesId={series_id}&seasonNumber=1",
                "reading the series' episodes",
            ),
            lambda rows: bool(rows),
            what="Sonarr listing the series' episodes",
            timeout=90,
            interval=2,
        )
        episode_id = int(episodes[0]["id"])
        command = probe.command(
            probe.SONARR,
            {"name": "EpisodeSearch", "episodeIds": [episode_id]},
            "starting an episode search",
        )
        settled = probe.wait_command(
            probe.SONARR, int(command["id"]), what="EpisodeSearch"
        )
        values["EpisodeSearchStatus"] = settled.get("status")
        values["EpisodeSearchMessage"] = settled.get("message")

        # A-04: a profile change, a season unmonitored, a series type changed,
        # each read back, then put back the way the add left them.
        def changed_body(series: dict[str, Any]) -> dict[str, Any]:
            body = dict(series)
            body["qualityProfileId"] = CHANGED_PROFILE
            body["monitored"] = False
            body["seriesType"] = "anime"
            body["seasons"] = [
                {
                    **season,
                    "monitored": (
                        False
                        if season.get("seasonNumber") == 1
                        else season.get("monitored")
                    ),
                }
                for season in series.get("seasons") or []
            ]
            return body

        changed = _put_until(
            series_id,
            changed_body,
            lambda item: item.get("qualityProfileId") == CHANGED_PROFILE
            and item.get("monitored") is False
            and item.get("seriesType") == "anime"
            and _season_flags(item).get(1) is False,
            what="Sonarr keeping the changed profile, monitoring and type",
        )
        values["changedProfileId"] = changed["qualityProfileId"]
        values["changedMonitored"] = changed["monitored"]
        values["changedSeriesType"] = changed["seriesType"]
        values["changedSeasonMonitored"] = _season_flags(changed).get(1)

        def restored_body(series: dict[str, Any]) -> dict[str, Any]:
            body = dict(series)
            body["qualityProfileId"] = profile_id
            body["monitored"] = True
            body["seriesType"] = "standard"
            body["seasons"] = [
                {
                    **season,
                    "monitored": (
                        True
                        if season.get("seasonNumber") == 1
                        else season.get("monitored")
                    ),
                }
                for season in series.get("seasons") or []
            ]
            return body

        restored = _put_until(
            series_id,
            restored_body,
            lambda item: item.get("qualityProfileId") == profile_id
            and item.get("monitored") is True
            and item.get("seriesType") == "standard"
            and _season_flags(item).get(1) is True,
            what="Sonarr keeping the restored profile, monitoring and type",
        )
        values["restoredProfileId"] = restored["qualityProfileId"]
        values["restoredSeriesType"] = restored["seriesType"]
        values["restoredSeasonMonitored"] = _season_flags(restored).get(1)

        # A-07: a removal with its folder and an import list exclusion.
        series = _require_series()
        folder = _ensure_series_folder(series)
        status, body = probe.call(
            probe.SONARR,
            f"/series/{series_id}?deleteFiles=true&addImportListExclusion=true",
            method="DELETE",
        )
        if not 200 <= status < 300:
            raise ScenarioError(f"removing the series failed with {status}: {body}")
        status, body = probe.call(probe.SONARR, f"/series/{series_id}")
        if status != 404:
            raise ScenarioError(
                f"the removed series answers {status} instead of 404"
            )
        values["removedStatus"] = status
        probe.wait_until(
            lambda: folder.exists(),
            lambda exists: not exists,
            what="the removed series' folder leaving the disk",
            timeout=60,
            interval=2,
        )
        values["folderGone"] = not folder.exists()
        _wait_gone()
        try:
            probe.wait_until(
                lambda: probe.import_exclusions(probe.SONARR),
                lambda exclusions: any(
                    exclusion.get("tvdbId") == TVDB_ID for exclusion in exclusions
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
                "the removal added no import list exclusion for the series"
            )
        probe.delete_import_exclusion(probe.SONARR, tvdb_id=TVDB_ID)

        # The live state the e2e acts on. The delete above answers before the
        # row is gone, so the re-add waits for the service to agree.
        _wait_gone()
        values["seriesId"] = _add(
            row if row is not None else _direct_payload(), profile_id
        )
        series = _reread_until(
            lambda item: item.get("id") == values["seriesId"]
            and item.get("qualityProfileId") == profile_id
            and _season_flags(item).get(1) is True,
            what="Sonarr taking the series in again",
        )
        values["seriesPath"] = series["path"]
        values["seasonsMonitored"] = {
            str(number): monitored
            for number, monitored in _season_flags(series).items()
        }
        values["seriesType"] = series.get("seriesType")
        # The folder the e2e's removal takes away (Sonarr creates none).
        _ensure_series_folder(series)
        probe.save_state(NAME, values)

    def verify(self) -> None:
        values = probe.load_state(NAME)
        series = _require_series()
        if series.get("id") != values["seriesId"]:
            raise ScenarioError(
                f"the series reads id {series.get('id')}, not {values['seriesId']}"
            )
        if series.get("qualityProfileId") != values["profileId"]:
            raise ScenarioError(
                "the series reads profile "
                f"{series.get('qualityProfileId')}, not {values['profileId']}"
            )
        if series.get("rootFolderPath") != ROOT_PATH:
            raise ScenarioError(
                f"the series reads root {series.get('rootFolderPath')!r}"
            )
        if series.get("monitored") is not True:
            raise ScenarioError("the series is not monitored")
        if series.get("seriesType") != "standard":
            raise ScenarioError(
                f"the series reads type {series.get('seriesType')!r}"
            )
        seasons = _season_flags(series)
        if seasons.get(1) is not True:
            raise ScenarioError(f"the seasons read {seasons}, season 1 is not monitored")
        if any(monitored for number, monitored in seasons.items() if number != 1):
            raise ScenarioError(
                f"the seasons read {seasons}, more than the first is monitored"
            )
        if values.get("lookup") not in ("tvdb", "direct"):
            raise ScenarioError(f"the add path reads {values.get('lookup')!r}")

        for label in ("SeriesSearch", "SeasonSearch", "EpisodeSearch"):
            if values.get(f"{label}Status") != "completed":
                raise ScenarioError(
                    f"{label} settled as {values.get(f'{label}Status')!r}"
                )
        if values.get("changedProfileId") != CHANGED_PROFILE:
            raise ScenarioError("the profile change was never read back")
        if values.get("changedMonitored") is not False:
            raise ScenarioError("the series monitoring change was never read back")
        if values.get("changedSeriesType") != "anime":
            raise ScenarioError("the series type change was never read back")
        if values.get("changedSeasonMonitored") is not False:
            raise ScenarioError("the season monitoring change was never read back")
        if values.get("restoredProfileId") != values["profileId"]:
            raise ScenarioError("the profile was not put back")
        if values.get("restoredSeriesType") != "standard":
            raise ScenarioError("the series type was not put back")
        if values.get("restoredSeasonMonitored") is not True:
            raise ScenarioError("the season monitoring was not put back")
        if values.get("removedStatus") != 404:
            raise ScenarioError("the removal never answered 404")
        if not values.get("folderGone"):
            raise ScenarioError("the removed series' folder is still on disk")
        if not values.get("exclusionSeen"):
            raise ScenarioError("the removal added no import list exclusion")

        profiles = probe.quality_profiles(probe.SONARR)
        if not any(item.get("name") == PROFILE_NAME for item in profiles):
            raise ScenarioError(f"the cloned profile {PROFILE_NAME!r} is gone")
        folders = probe.get(probe.SONARR, "/rootfolder", "reading the root folders")
        if not any(item.get("path") == ROOT_PATH for item in folders):
            raise ScenarioError(f"the root folder {ROOT_PATH} is gone")

    def teardown(self) -> None:
        series = probe.find_series(probe.SONARR, TVDB_ID)
        if series is not None:
            status, body = probe.call(
                probe.SONARR,
                f"/series/{series['id']}?deleteFiles=true&addImportListExclusion=false",
                method="DELETE",
            )
            if not 200 <= status < 300:
                raise ScenarioError(
                    f"removing the disposable series failed with {status}: {body}"
                )
        probe.delete_import_exclusion(probe.SONARR, tvdb_id=TVDB_ID)
        profile = probe.find_profile(probe.SONARR, PROFILE_NAME)
        if profile is not None:
            probe.delete_profile(probe.SONARR, int(profile["id"]))
        probe.delete_root_folder(probe.SONARR, ROOT_PATH)
        probe.remove_host_dir(probe.TV_ANIME)
        probe.clear_state(NAME)

    def verify_absent(self) -> None:
        if probe.find_series(probe.SONARR, TVDB_ID) is not None:
            raise ScenarioError("the disposable series is still in Sonarr")
        if probe.find_profile(probe.SONARR, PROFILE_NAME) is not None:
            raise ScenarioError(f"the cloned profile {PROFILE_NAME!r} is still there")
        folders = probe.get(probe.SONARR, "/rootfolder", "reading the root folders")
        if any(item.get("path") == ROOT_PATH for item in folders):
            raise ScenarioError(f"the root folder {ROOT_PATH} is still there")
        if any(
            exclusion.get("tvdbId") == TVDB_ID
            for exclusion in probe.import_exclusions(probe.SONARR)
        ):
            raise ScenarioError("the import list exclusion is still there")
        if probe.TV_ANIME.exists():
            raise ScenarioError(f"{probe.TV_ANIME} is still on disk")


SCENARIO = ArrActionsSonarr()
