"""A-08, A-09, A-11 and A-12 on Sonarr, from the fields the server answers.

Sonarr's chips read the same three facts Radarr's do (``monitored``, the file
counts in ``statistics``, the queue) plus ``wanted/cutoff``, and the app's rules
are ``lib/features/series/domain/sonarr_status.dart``: a series with aired
episodes and no files is Missing, a series with some is Partial (Available),
and Unmonitored is orthogonal to both.

The golden library has no episode files at all, so Available and Cutoff unmet
have no member here and the scenario says so instead of inventing one: the lab
seeds Sonarr without an indexer or a download client (the seed's own choice),
which is what would put a file or a queue entry in. What the scenario does add
is the Unmonitored state, by unmonitoring ``Parks and Recreation`` and putting
it back, and it proves the change the way the server reports it: the series
flag flips and ``wanted/missing`` drops by exactly that series' aired episodes.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any

import arr_probe as probe

from .base import Scenario, ScenarioError

NAME = "arr-library-sonarr"
UNMONITORED_TVDB = 84912  # Parks and Recreation
MISSING_PAGE = (
    "?page=1&pageSize=200&sortKey=airDateUtc&sortDirection=descending"
    "&includeSeries=true"
)
CUTOFF_PAGE = (
    "?page=1&pageSize=200&sortKey=airDateUtc&sortDirection=descending"
    "&includeSeries=true&includeEpisodeFile=true"
)
HISTORY_PAGE = (
    "?page=1&pageSize=200&sortKey=date&sortDirection=descending"
    "&includeSeries=true&includeEpisode=true"
)


def _series(tvdb_id: int) -> dict[str, Any]:
    item = probe.find_series(probe.SONARR, tvdb_id)
    if item is None:
        raise ScenarioError(f"Sonarr does not hold TVDB id {tvdb_id}")
    return item


def _statistics(item: dict[str, Any]) -> tuple[int | None, int | None]:
    statistics = item.get("statistics")
    if not isinstance(statistics, dict):
        return None, None
    files = statistics.get("episodeFileCount")
    aired = statistics.get("episodeCount")
    return (
        files if isinstance(files, int) else None,
        aired if isinstance(aired, int) else None,
    )


def _availability(item: dict[str, Any]) -> str:
    """The app's ``sonarrSeriesAvailability`` over the raw payload."""
    files, aired = _statistics(item)
    if files is None or aired is None:
        return "unknown"
    if aired <= 0:
        return "available" if files > 0 else "unavailable"
    if files <= 0:
        return "missing"
    return "available" if files >= aired else "partial"


def _missing_total() -> int:
    page = probe.page(probe.SONARR, f"/wanted/missing{MISSING_PAGE}", "the missing list")
    total = page.get("totalRecords")
    return int(total) if isinstance(total, int) else 0


def _library_readings() -> dict[str, Any]:
    library = probe.series(probe.SONARR)
    queue_ids = {
        int(record["seriesId"])
        for record in probe.queue_records(probe.SONARR)
        if isinstance(record.get("seriesId"), int)
    }
    return {
        "all": len(library),
        "available": sum(
            1 for item in library if _availability(item) in ("available", "partial")
        ),
        "missing": sum(
            1
            for item in library
            if item.get("monitored") is True and _availability(item) == "missing"
        ),
        "unreleased": sum(
            1 for item in library if _availability(item) == "unavailable"
        ),
        "unmonitored": sum(1 for item in library if item.get("monitored") is not True),
        "inQueue": len(queue_ids),
        "withFiles": sum(1 for item in library if (_statistics(item)[0] or 0) > 0),
        "titles": sorted(str(item.get("title")) for item in library),
    }


class ArrLibrarySonarr(Scenario):
    name = NAME
    profiles = ("core",)

    def apply(self) -> None:
        values: dict[str, Any] = {}
        series = _series(UNMONITORED_TVDB)
        values["seriesId"] = int(series["id"])
        values["originalMonitored"] = series.get("monitored")
        files, aired = _statistics(series)
        values["seriesFiles"] = files
        values["seriesAired"] = aired
        values["missingBefore"] = _missing_total()

        if series.get("monitored") is not False:
            series["monitored"] = False
            probe.write(
                probe.SONARR,
                f"/series/{series['id']}",
                "PUT",
                series,
                "unmonitoring the series",
            )
            probe.wait_until(
                lambda: _series(UNMONITORED_TVDB),
                lambda item: item.get("monitored") is False,
                what="Sonarr keeping the series unmonitored",
                timeout=60,
            )
        values["missingAfter"] = probe.wait_until(
            _missing_total,
            lambda total: total == values["missingBefore"] - (aired or 0),
            what="the missing list dropping the unmonitored series' episodes",
            timeout=90,
            interval=2,
        )

        # A-08: the chips over the library, with the app's rules.
        values["library"] = _library_readings()
        if values["library"]["all"] < 8:
            raise ScenarioError(
                f"the library reads {values['library']['all']} series, not the seeded 10"
            )
        if values["library"]["unmonitored"] < 1:
            raise ScenarioError("the unmonitored chip has no member")
        if values["library"]["withFiles"] != 0:
            raise ScenarioError(
                "the lab's Sonarr holds episode files; Available and Cutoff unmet "
                "would then need their own state"
            )
        clients = probe.get(probe.SONARR, "/downloadclient", "reading the download clients")
        values["downloadClients"] = len(clients or [])
        if values["downloadClients"] != 0:
            raise ScenarioError(
                "Sonarr has a download client, so its queue should be read as a state"
            )

        # A-09: the calendar over the next thirty days, as the app asks for it.
        today = date.today()
        end = today + timedelta(days=30)
        rows = probe.get(
            probe.SONARR,
            f"/calendar?start={today.isoformat()}&end={end.isoformat()}"
            "&includeSeries=true&includeEpisodeFile=true",
            "reading the calendar",
        )
        values["calendarWindow"] = [today.isoformat(), end.isoformat()]
        values["calendar"] = [
            {
                "id": row.get("id"),
                "series": (row.get("series") or {}).get("title"),
                "seasonNumber": row.get("seasonNumber"),
                "episodeNumber": row.get("episodeNumber"),
                "airDate": row.get("airDate"),
            }
            for row in rows
            if isinstance(row, dict)
        ]
        if not values["calendar"]:
            raise ScenarioError("the next thirty days are empty on Sonarr")
        for row in values["calendar"]:
            if not row["series"] or not row["airDate"]:
                raise ScenarioError(f"the calendar row {row!r} names no episode")
            if not today.isoformat() <= str(row["airDate"])[:10] <= end.isoformat():
                raise ScenarioError(
                    f"the calendar row {row['series']!r} falls outside the window"
                )
        first = values["calendar"][0]
        episode = probe.get(
            probe.SONARR, f"/episode/{first['id']}", "reading the calendar's episode"
        )
        if episode.get("airDate") != first["airDate"]:
            raise ScenarioError(
                "the calendar's air date "
                f"{first['airDate']!r} is not the episode's {episode.get('airDate')!r}"
            )
        values["calendarChecked"] = int(first["id"])

        # A-11: wanted, both lists, and a search from the missing one.
        missing_page = probe.page(
            probe.SONARR, f"/wanted/missing{MISSING_PAGE}", "reading the missing list"
        )
        values["missingTotal"] = missing_page.get("totalRecords")
        cutoff_page = probe.page(
            probe.SONARR, f"/wanted/cutoff{CUTOFF_PAGE}", "reading the cutoff list"
        )
        values["cutoffTotal"] = cutoff_page.get("totalRecords")
        if not values["missingTotal"]:
            raise ScenarioError("the missing list is empty")
        if values["cutoffTotal"] != 0:
            raise ScenarioError(
                f"wanted/cutoff lists {values['cutoffTotal']} records with no files"
            )
        target = next(
            (
                record
                for record in missing_page.get("records", [])
                if isinstance(record, dict)
                and isinstance((record.get("series") or {}).get("id"), int)
            ),
            None,
        )
        if target is None:
            raise ScenarioError("the missing list names no series")
        series_id = int(target["series"]["id"])
        command = probe.command(
            probe.SONARR,
            {"name": "SeasonSearch", "seriesId": series_id, "seasonNumber": 1},
            "searching a missing season",
        )
        settled = probe.wait_command(
            probe.SONARR, int(command["id"]), what="the wanted season search"
        )
        values["wantedSearchStatus"] = settled.get("status")
        values["wantedSearchMessage"] = settled.get("message")
        values["wantedSearchSeries"] = target["series"].get("title")

        # A-12: history, which the seeded lab already carries.
        history = probe.page(
            probe.SONARR, f"/history{HISTORY_PAGE}", "reading the history"
        )
        records = [
            record for record in history.get("records", []) if isinstance(record, dict)
        ]
        values["historyTotal"] = history.get("totalRecords")
        values["historyEvents"] = sorted(
            {str(record.get("eventType")) for record in records}
        )
        if not values["historyTotal"]:
            raise ScenarioError("the history is empty")
        if not any(
            isinstance(record.get("series"), dict) and record["series"].get("title")
            for record in records
        ):
            raise ScenarioError("the history rows carry no series")
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
        series = _series(UNMONITORED_TVDB)
        if series.get("monitored") is not False:
            raise ScenarioError("the unmonitored series is monitored again")
        if _missing_total() != values["missingAfter"]:
            raise ScenarioError(
                f"the missing total reads {_missing_total()}, "
                f"not {values['missingAfter']}"
            )
        if values["missingBefore"] - values["missingAfter"] != (
            values["seriesAired"] or 0
        ):
            raise ScenarioError(
                "the missing list did not drop exactly the series' episodes: "
                f"{values['missingBefore']} then {values['missingAfter']}"
            )
        cutoff_page = probe.page(
            probe.SONARR, f"/wanted/cutoff{CUTOFF_PAGE}", "reading the cutoff list"
        )
        if cutoff_page.get("totalRecords") != 0:
            raise ScenarioError("wanted/cutoff has a member")
        rows = probe.get(
            probe.SONARR,
            f"/calendar?start={values['calendarWindow'][0]}"
            f"&end={values['calendarWindow'][1]}"
            "&includeSeries=true&includeEpisodeFile=true",
            "reading the calendar",
        )
        if not any(
            isinstance(row, dict) and row.get("id") == values["calendarChecked"]
            for row in rows
        ):
            raise ScenarioError("the calendar lost the episode it was checked on")
        if values.get("wantedSearchStatus") != "completed":
            raise ScenarioError(
                f"the wanted search settled as {values.get('wantedSearchStatus')!r}"
            )
        history = probe.page(
            probe.SONARR, f"/history{HISTORY_PAGE}", "reading the history"
        )
        if not history.get("totalRecords"):
            raise ScenarioError("the history is empty")

    def teardown(self) -> None:
        try:
            values: dict[str, Any] | None = probe.load_state(NAME)
        except ScenarioError:
            values = None
        series = probe.find_series(probe.SONARR, UNMONITORED_TVDB)
        if series is not None and series.get("monitored") is not True:
            series["monitored"] = True
            probe.write(
                probe.SONARR,
                f"/series/{series['id']}",
                "PUT",
                series,
                "monitoring the series again",
            )
            probe.wait_until(
                lambda: _series(UNMONITORED_TVDB),
                lambda item: item.get("monitored") is True,
                what="Sonarr keeping the series monitored again",
                timeout=60,
            )
            if values is not None and values.get("missingAfter"):
                # A lower bound rather than the exact total the apply read: the
                # e2e that follows this scenario removes its own disposable
                # series, which legitimately takes episodes off the same list.
                probe.wait_until(
                    _missing_total,
                    lambda total: total >= values["missingAfter"],
                    what="the missing list coming back to its unmonitored total",
                    timeout=90,
                    interval=2,
                )
        probe.clear_state(NAME)

    def verify_absent(self) -> None:
        series = _series(UNMONITORED_TVDB)
        if series.get("monitored") is not True:
            raise ScenarioError("the series is still unmonitored")
        library = _library_readings()
        if library["unmonitored"] != 0:
            raise ScenarioError(
                f"the library reads {library['unmonitored']} unmonitored series"
            )


SCENARIO = ArrLibrarySonarr()
