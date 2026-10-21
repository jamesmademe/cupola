"""A-08, A-09, A-11 and A-12 on Radarr, from the fields the server answers.

The library chips are not a filter the app invents: each one reads a field
Radarr already carries (``hasFile``, ``monitored``, the queue, ``wanted/cutoff``)
and the app's rules for turning those fields into a chip live in
``lib/core/widgets/media_browse_scaffold.dart`` and
``lib/features/movies/domain/radarr_status.dart``. The scenario proves the
fields and the rules on the seeded library, and adds the one state the golden
library does not have: a title below its cutoff.

That state is made the way a person makes it: a cloned quality profile (from
``HD-1080p``, upgrade allowed) assigned to ``Fight Club``, whose file is an
``SDTV`` one. ``wanted/cutoff`` then lists exactly that movie, the Cutoff unmet
chip has a member, and the wanted tab's cutoff pill is not empty. ``teardown``
puts the movie's profile back and drops the clone.

Calendar, wanted and history are read as the app reads them: the calendar over
a date window, ``wanted/missing`` and ``wanted/cutoff`` with their envelope
totals, and history with the L5 grab and import the lab already carries.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any

import arr_probe as probe

from .base import Scenario, ScenarioError

NAME = "arr-library-radarr"
PROFILE_NAME = "Cupola testlab cutoff"
PROFILE_SOURCE = 4  # HD-1080p: its cutoff is Bluray-1080p, so an SDTV file is below it
BELOW_CUTOFF_TMDB = 550  # Fight Club, whose seeded file is an SDTV one
AVAILABLE_TMDB = 550
UNMONITORED_TMDB = 348  # Alien, seeded unmonitored
MISSING_TMDB = 1153576  # Street Fighter, released and monitored with no file
CALENDAR_TMDB = 1400940  # Clayface, in cinemas today
WANTED_PAGE = (
    "?page=1&pageSize=200&sortKey=airDateUtc&sortDirection=descending"
    "&includeSeries=true"
)
HISTORY_PAGE = (
    "?page=1&pageSize=200&sortKey=date&sortDirection=descending&includeMovie=true"
)


def _movie(tmdb_id: int) -> dict[str, Any]:
    movie = probe.find_movie(probe.RADARR, tmdb_id)
    if movie is None:
        raise ScenarioError(f"Radarr does not hold TMDB id {tmdb_id}")
    return movie


def _expected_on_disk(movie: dict[str, Any]) -> bool:
    """The app's ``RadarrMovie.isExpectedOnDisk`` over the raw payload."""
    verdict = movie.get("isAvailable")
    if isinstance(verdict, bool):
        return verdict
    return str(movie.get("status") or "").lower() in ("released", "incinemas")


def _library_readings() -> dict[str, Any]:
    """The library as the chips read it, with the app's own rules."""
    movies = probe.movies(probe.RADARR)
    queue_ids = {int(record["movieId"]) for record in probe.queue_records(probe.RADARR)
                 if isinstance(record.get("movieId"), int)}
    cutoff_ids = {
        int(record["id"])
        for record in probe.page(
            probe.RADARR, f"/wanted/cutoff{WANTED_PAGE}", "reading the cutoff list"
        ).get("records", [])
        if isinstance(record.get("id"), int)
    }
    return {
        "all": len(movies),
        "available": sum(1 for movie in movies if movie.get("hasFile")),
        "missing": sum(
            1
            for movie in movies
            if not movie.get("hasFile") and _expected_on_disk(movie)
        ),
        "unreleased": sum(
            1
            for movie in movies
            if not movie.get("hasFile") and not _expected_on_disk(movie)
        ),
        "unmonitored": sum(1 for movie in movies if not movie.get("monitored")),
        "inQueue": len(queue_ids),
        "cutoffUnmet": len(cutoff_ids),
        "queueIds": sorted(queue_ids),
        "cutoffIds": sorted(cutoff_ids),
        "titles": {int(movie["tmdbId"]): movie.get("title") for movie in movies},
    }


class ArrLibraryRadarr(Scenario):
    name = NAME
    profiles = ("core",)

    def apply(self) -> None:
        values: dict[str, Any] = {}
        profile_id, profile_created = probe.ensure_profile(
            probe.RADARR, PROFILE_SOURCE, PROFILE_NAME, upgradeAllowed=True
        )
        values["profileId"] = profile_id
        values["profileCreated"] = profile_created

        movie = _movie(BELOW_CUTOFF_TMDB)
        values["originalProfileId"] = movie.get("qualityProfileId")
        values["originalMonitored"] = movie.get("monitored")
        if movie.get("qualityProfileId") != profile_id:
            movie["qualityProfileId"] = profile_id
            probe.write(
                probe.RADARR,
                f"/movie/{movie['id']}",
                "PUT",
                movie,
                "putting the movie on the cutoff profile",
            )
            probe.wait_until(
                lambda: _movie(BELOW_CUTOFF_TMDB),
                lambda record: record.get("qualityProfileId") == profile_id,
                what="Radarr keeping the cutoff profile",
                timeout=60,
            )

        cutoff = probe.wait_until(
            lambda: probe.page(
                probe.RADARR, f"/wanted/cutoff{WANTED_PAGE}", "reading the cutoff list"
            ),
            lambda page: any(
                isinstance(record, dict)
                and record.get("tmdbId") == BELOW_CUTOFF_TMDB
                for record in page.get("records", [])
            ),
            what="the cutoff list naming the movie",
            timeout=60,
        )
        values["cutoffTotal"] = cutoff.get("totalRecords")
        values["cutoffTitles"] = [
            record.get("title")
            for record in cutoff.get("records", [])
            if isinstance(record, dict)
        ]

        # A-08: the chips over the library, and their members.
        values["library"] = _library_readings()
        if values["library"]["all"] < 40:
            raise ScenarioError(
                f"the library reads {values['library']['all']} movies, not the seeded 42"
            )
        if not _movie(AVAILABLE_TMDB).get("hasFile"):
            raise ScenarioError("the seeded movie with a file has none")
        if _movie(UNMONITORED_TMDB).get("monitored") is not False:
            raise ScenarioError("the seeded unmonitored movie is monitored")
        missing = _movie(MISSING_TMDB)
        if missing.get("hasFile") or not missing.get("monitored"):
            raise ScenarioError("the seeded missing movie is not missing")

        # A-09: the calendar over a window that holds the two seeded releases.
        today = date.today()
        start = today - timedelta(days=7)
        end = today + timedelta(days=45)
        rows = probe.get(
            probe.RADARR,
            f"/calendar?start={start.isoformat()}&end={end.isoformat()}",
            "reading the calendar",
        )
        values["calendarWindow"] = [start.isoformat(), end.isoformat()]
        values["calendar"] = [
            {
                "tmdbId": row.get("tmdbId"),
                "title": row.get("title"),
                "inCinemas": row.get("inCinemas"),
                "digitalRelease": row.get("digitalRelease"),
                "physicalRelease": row.get("physicalRelease"),
            }
            for row in rows
            if isinstance(row, dict)
        ]
        clayface = next(
            (
                row
                for row in values["calendar"]
                if row["tmdbId"] == CALENDAR_TMDB
            ),
            None,
        )
        if clayface is None:
            raise ScenarioError(
                "the calendar does not hold the movie opening today: "
                f"{values['calendar']}"
            )
        for row in values["calendar"]:
            dates = [
                value
                for value in (
                    row["inCinemas"],
                    row["digitalRelease"],
                    row["physicalRelease"],
                )
                if value
            ]
            if not dates:
                raise ScenarioError(f"the calendar row {row['title']!r} has no date")
            if not any(
                start.isoformat() <= str(value)[:10] <= end.isoformat()
                for value in dates
            ):
                raise ScenarioError(
                    f"the calendar row {row['title']!r} falls outside the window"
                )

        # A-11: wanted, both lists, with their totals.
        missing_page = probe.page(
            probe.RADARR, f"/wanted/missing{WANTED_PAGE}", "reading the missing list"
        )
        values["missingTotal"] = missing_page.get("totalRecords")
        values["missingTitles"] = [
            record.get("title")
            for record in missing_page.get("records", [])
            if isinstance(record, dict)
        ]
        if not values["missingTotal"] or values["missingTotal"] < 20:
            raise ScenarioError(
                f"the missing list reads {values['missingTotal']} records"
            )
        if not any(
            isinstance(record, dict) and record.get("tmdbId") == MISSING_TMDB
            for record in missing_page.get("records", [])
        ):
            raise ScenarioError("the missing list does not name the missing movie")

        search_target = next(
            (
                record
                for record in missing_page.get("records", [])
                if isinstance(record, dict)
                and record.get("title") != "Big Buck Bunny"
            ),
            None,
        )
        if search_target is None:
            raise ScenarioError("the missing list has nothing to search for")
        command = probe.command(
            probe.RADARR,
            {"name": "MoviesSearch", "movieIds": [search_target["id"]]},
            "searching the missing movie",
        )
        settled = probe.wait_command(
            probe.RADARR, int(command["id"]), what="the wanted search"
        )
        values["wantedSearchStatus"] = settled.get("status")
        values["wantedSearchMessage"] = settled.get("message")
        values["wantedSearchTitle"] = search_target.get("title")

        # A-12: history, with the L5 grab and the import it produced.
        history = probe.page(
            probe.RADARR, f"/history{HISTORY_PAGE}", "reading the history"
        )
        records = [
            record for record in history.get("records", []) if isinstance(record, dict)
        ]
        values["historyTotal"] = history.get("totalRecords")
        values["historyGrabbed"] = any(
            record.get("eventType") == "grabbed" for record in records
        )
        values["historyImported"] = any(
            record.get("eventType") == "downloadFolderImported"
            for record in records
        )
        values["historyL5"] = any(
            record.get("eventType") == "grabbed"
            and "CUPOLA" in str(record.get("sourceTitle") or "")
            for record in records
        )
        if not values["historyL5"]:
            raise ScenarioError(
                "the history does not carry the L5 grab of the forged release"
            )
        if not values["historyImported"]:
            raise ScenarioError("the history carries no import")
        probe.save_state(NAME, values)

    def verify(self) -> None:
        values = probe.load_state(NAME)
        library = _library_readings()
        saved = values["library"]
        for key in ("all", "available", "missing", "unreleased", "unmonitored"):
            if library[key] != saved[key]:
                raise ScenarioError(
                    f"the library's {key} reads {library[key]}, not {saved[key]}"
                )
        if library["cutoffUnmet"] < 1:
            raise ScenarioError("the cutoff chip has no member")
        if _movie(BELOW_CUTOFF_TMDB).get("qualityProfileId") != values["profileId"]:
            raise ScenarioError("the below-cutoff movie left its profile")
        if int(_movie(BELOW_CUTOFF_TMDB)["id"]) not in library["cutoffIds"]:
            raise ScenarioError(
                "the movie below its cutoff is not in wanted/cutoff"
            )

        cutoff_page = probe.page(
            probe.RADARR, f"/wanted/cutoff{WANTED_PAGE}", "reading the cutoff list"
        )
        if not any(
            isinstance(record, dict) and record.get("tmdbId") == BELOW_CUTOFF_TMDB
            for record in cutoff_page.get("records", [])
        ):
            raise ScenarioError("wanted/cutoff does not name the movie")

        rows = probe.get(
            probe.RADARR,
            f"/calendar?start={values['calendarWindow'][0]}"
            f"&end={values['calendarWindow'][1]}",
            "reading the calendar",
        )
        today = date.today().isoformat()
        if not any(
            isinstance(row, dict)
            and row.get("tmdbId") == CALENDAR_TMDB
            and str(row.get("inCinemas") or "")[:10] == today
            for row in rows
        ):
            raise ScenarioError(
                "the calendar does not hold the movie opening today"
            )

        missing_page = probe.page(
            probe.RADARR, f"/wanted/missing{WANTED_PAGE}", "reading the missing list"
        )
        if missing_page.get("totalRecords") != values["missingTotal"]:
            raise ScenarioError(
                "the missing total reads "
                f"{missing_page.get('totalRecords')}, not {values['missingTotal']}"
            )
        if values.get("wantedSearchStatus") != "completed":
            raise ScenarioError(
                f"the wanted search settled as {values.get('wantedSearchStatus')!r}"
            )

        history = probe.page(
            probe.RADARR, f"/history{HISTORY_PAGE}", "reading the history"
        )
        records = [
            record for record in history.get("records", []) if isinstance(record, dict)
        ]
        if not any(
            record.get("eventType") == "grabbed"
            and "CUPOLA" in str(record.get("sourceTitle") or "")
            for record in records
        ):
            raise ScenarioError("the history lost the L5 grab")
        if not any(
            record.get("eventType") == "downloadFolderImported"
            for record in records
        ):
            raise ScenarioError("the history lost the import")

    def teardown(self) -> None:
        values: dict[str, Any] | None = None
        try:
            values = probe.load_state(NAME)
        except ScenarioError:
            values = None
        movie = probe.find_movie(probe.RADARR, BELOW_CUTOFF_TMDB)
        if movie is not None and values is not None:
            original = values.get("originalProfileId")
            monitored = values.get("originalMonitored")
            if movie.get("qualityProfileId") != original or (
                monitored is not None and movie.get("monitored") != monitored
            ):
                movie["qualityProfileId"] = original
                if monitored is not None:
                    movie["monitored"] = monitored
                probe.write(
                    probe.RADARR,
                    f"/movie/{movie['id']}",
                    "PUT",
                    movie,
                    "putting the movie's profile and monitoring back",
                )
                probe.wait_until(
                    lambda: _movie(BELOW_CUTOFF_TMDB),
                    lambda record: record.get("qualityProfileId") == original,
                    what="Radarr keeping the original profile",
                    timeout=60,
                )
        profile = probe.find_profile(probe.RADARR, PROFILE_NAME)
        if profile is not None:
            probe.delete_profile(probe.RADARR, int(profile["id"]))
        probe.clear_state(NAME)

    def verify_absent(self) -> None:
        if probe.find_profile(probe.RADARR, PROFILE_NAME) is not None:
            raise ScenarioError(f"the cloned profile {PROFILE_NAME!r} is still there")
        movie = _movie(BELOW_CUTOFF_TMDB)
        profiles = {int(item["id"]) for item in probe.quality_profiles(probe.RADARR)}
        if movie.get("qualityProfileId") not in profiles:
            raise ScenarioError(
                "the movie points at profile "
                f"{movie.get('qualityProfileId')}, which no longer exists"
            )
        page = probe.page(
            probe.RADARR, f"/wanted/cutoff{WANTED_PAGE}", "reading the cutoff list"
        )
        if page.get("totalRecords"):
            raise ScenarioError(
                f"wanted/cutoff still lists {page.get('totalRecords')} records"
            )


SCENARIO = ArrLibraryRadarr()
