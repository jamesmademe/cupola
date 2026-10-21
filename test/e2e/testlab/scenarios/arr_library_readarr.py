"""Readarr's library reads: the fields the wall reads, the calendar, the queue,
the wanted pages and the history.

Rows A-08, A-09, A-10, A-11 and A-12 of the flow catalogue, on the six authors
L6a writes into Readarr's database. The scenario unmonitors one author, which
takes his book out of ``wanted/missing``, and puts him back on teardown.

A-08 is **partial for Readarr by design**: the author wall draws no status
badge, because Readarr's queue is indexed by book, so an author's badge would
ignore the queue and call a downloading author missing. ``MediaBrowseScaffold``
draws no status chips without a status, so All is the only filter Readarr has.
The scenario proves the library read and the statistics the author's caption
uses (``bookFileCount/bookCount``, missing), and the Wanted tab's own pages,
rather than pretending a chip exists.

The calendar is asked the way the app asks it, with ``includeAuthor``: thirty
days from a local day. The six books are dated 1813 to 1902, so the app's window
is empty and "Nothing scheduled" is the honest state; the historical window
proves the dates the server reports.

``apply`` posts a ``BookSearch`` for the first missing book, which is A-11's
"il command parte". A command is append-only: ``teardown`` restores the author
and cannot erase the command row, which stays as the evidence.
"""

from __future__ import annotations

import json
from datetime import date, datetime, timedelta

from .base import STATE_ROOT, Scenario, ScenarioError, request, require_ok

READARR = "http://127.0.0.1:8787/api/v1"
HEADERS = {"X-Api-Key": "test-key"}
TARGET = "Bram Stoker"
KNOWN_RELEASE = ("Pride and Prejudice", "1813-01-01")
HISTORICAL_START = "1800-01-01"
HISTORICAL_END = "1910-12-31"
BACKUP = STATE_ROOT / "backup" / "arr_library_readarr"
MARKER = BACKUP / "state.json"

COMMAND_STATES = ("queued", "started", "completed", "failed", "aborted")


def _call(
    path: str,
    method: str = "GET",
    payload: object | None = None,
    timeout: float = 30,
) -> tuple[int, object]:
    return request(
        f"{READARR}{path}",
        method=method,
        payload=payload,
        headers=HEADERS,
        timeout=timeout,
    )


def _read(
    path: str,
    method: str = "GET",
    payload: object | None = None,
    timeout: float = 30,
) -> object:
    status, body = _call(path, method, payload, timeout)
    require_ok(status, body, f"Readarr {method} {path}")
    return body


def _envelope(body: object, what: str) -> tuple[int, list[dict]]:
    if not isinstance(body, dict):
        raise ScenarioError(f"{what} did not answer with a page envelope")
    records = body.get("records")
    total = body.get("totalRecords")
    if not isinstance(records, list) or not isinstance(total, int):
        raise ScenarioError(f"{what} answered an envelope without records or total")
    return total, [row for row in records if isinstance(row, dict)]


def _authors() -> list[dict]:
    body = _read("/author")
    if not isinstance(body, list):
        raise ScenarioError("Readarr answered the author list with something else")
    return [item for item in body if isinstance(item, dict)]


def _author_named(name: str) -> dict | None:
    for author in _authors():
        if author.get("authorName") == name:
            return author
    return None


def _put_author(author_id: int, fields: dict) -> dict:
    current = _read(f"/author/{author_id}")
    if not isinstance(current, dict):
        raise ScenarioError(f"Readarr answered author {author_id} with something else")
    current.update(fields)
    updated = _read(f"/author/{author_id}", "PUT", current)
    if not isinstance(updated, dict):
        raise ScenarioError(f"Readarr answered the update of {author_id} with nothing")
    return updated


def _stamp(value: object) -> datetime:
    if not isinstance(value, str) or not value:
        raise ScenarioError(f"a record carries no date: {value!r}")
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _calendar(start: date, end: date) -> list[dict]:
    body = _read(
        "/calendar"
        f"?start={start.isoformat()}&end={end.isoformat()}&includeAuthor=true"
    )
    if not isinstance(body, list):
        raise ScenarioError("Readarr answered the calendar with something else")
    return [row for row in body if isinstance(row, dict)]


def _marker() -> dict:
    if not MARKER.exists():
        return {}
    try:
        value = json.loads(MARKER.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ScenarioError(f"the scenario's marker is unreadable: {error}") from error
    return value if isinstance(value, dict) else {}


def _save(marker: dict) -> None:
    BACKUP.mkdir(parents=True, exist_ok=True)
    MARKER.write_text(json.dumps(marker, indent=2, sort_keys=True) + "\n", encoding="utf-8")


class ArrLibraryReadarr(Scenario):
    name = "arr-library-readarr"
    profiles = ("core",)

    def apply(self) -> None:
        marker = _marker()
        author = _author_named(TARGET)
        if author is None:
            raise ScenarioError(
                f"Readarr has no author named {TARGET!r}. The lab's library is the "
                "six authors of golden-l6 (scenario readarr-library); reset the lab "
                "before applying."
            )
        if "original" not in marker:
            marker["original"] = {"monitored": author.get("monitored")}
            marker["author"] = author["id"]
            _save(marker)
        original = marker["original"]
        _put_author(author["id"], {"monitored": not bool(original.get("monitored"))})

        missing_total, missing = _envelope(
            _read("/wanted/missing?page=1&pageSize=50&includeAuthor=true"),
            "Readarr wanted/missing",
        )
        if missing_total < 1 or not missing:
            raise ScenarioError("Readarr's wanted/missing is empty")
        book_id = missing[0].get("id")
        if not isinstance(book_id, int):
            raise ScenarioError("a wanted book carries no id")
        created = _read("/command", "POST", {"name": "BookSearch", "bookIds": [book_id]})
        if not isinstance(created, dict) or not created.get("id"):
            raise ScenarioError("Readarr did not accept the BookSearch command")
        marker["search"] = {"id": created["id"], "bookId": book_id}
        _save(marker)

    def teardown(self) -> None:
        marker = _marker()
        author_id = marker.get("author")
        original = marker.get("original")
        if isinstance(author_id, int) and isinstance(original, dict):
            _put_author(author_id, original)

    def verify(self) -> None:
        marker = _marker()
        author_id = marker.get("author")
        original = marker.get("original") or {}
        if not isinstance(author_id, int) or not original:
            raise ScenarioError("the scenario has no applied state to verify")

        # A-08, All: the author list and the counts its caption reads.
        authors = _authors()
        if len(authors) < 6:
            raise ScenarioError(
                f"Readarr lists {len(authors)} authors, not the lab's library"
            )
        author_ids = set()
        for author in authors:
            if not isinstance(author.get("id"), int) or not author.get("authorName"):
                raise ScenarioError(f"an author has no id or name: {author!r}")
            author_ids.add(author["id"])
            stats = author.get("statistics")
            if not isinstance(stats, dict):
                raise ScenarioError(
                    f"{author['authorName']} carries no statistics, so its caption "
                    "has no counts"
                )
            for key in ("bookCount", "bookFileCount", "totalBookCount"):
                if not isinstance(stats.get(key), int):
                    raise ScenarioError(
                        f"{author['authorName']}'s statistics carry no {key}"
                    )
        target = _read(f"/author/{author_id}")
        if target.get("monitored") == original.get("monitored"):
            raise ScenarioError(f"{TARGET} is still monitored as before")
        books = _read("/book")
        if not isinstance(books, list) or not books:
            raise ScenarioError("Readarr answered the book list with nothing")
        for book in books:
            if not isinstance(book, dict):
                raise ScenarioError(f"a book is not an object: {book!r}")
            if not isinstance(book.get("id"), int) or not book.get("title"):
                raise ScenarioError(f"a book has no id or title: {book!r}")
            if book.get("authorId") not in author_ids:
                raise ScenarioError(
                    f"{book['title']!r} hangs off an author outside the library"
                )
            _stamp(book.get("releaseDate"))

        # A-08, the state the scenario made: the unmonitored author's book
        # leaves wanted/missing, the others stay.
        own_books = _read(f"/book?authorId={author_id}")
        own_titles = {
            book.get("title") for book in own_books or [] if isinstance(book, dict)
        }
        if not own_titles:
            raise ScenarioError(f"{TARGET} has no book in the library")
        missing_total, missing = _envelope(
            _read("/wanted/missing?page=1&pageSize=50&includeAuthor=true"),
            "Readarr wanted/missing",
        )
        if missing_total < 1 or not missing:
            raise ScenarioError("Readarr's wanted/missing is empty")
        wanted_titles = set()
        for row in missing:
            if not isinstance(row.get("id"), int) or not row.get("title"):
                raise ScenarioError(f"a wanted book has no id or title: {row!r}")
            author = row.get("author")
            if not isinstance(author, dict) or not author.get("authorName"):
                raise ScenarioError(
                    "a wanted book came back without its author: the client asks "
                    "includeAuthor=true"
                )
            wanted_titles.add(row.get("title"))
        still_wanted = own_titles & wanted_titles
        if still_wanted:
            raise ScenarioError(
                f"{TARGET} is unmonitored but still wanted: {sorted(still_wanted)}"
            )

        # A-11, Cutoff unmet: the envelope the app's pill reads.
        cutoff_total, cutoff = _envelope(
            _read("/wanted/cutoff?page=1&pageSize=50&includeAuthor=true"),
            "Readarr wanted/cutoff",
        )
        for row in cutoff:
            if not isinstance(row.get("id"), int) or not row.get("title"):
                raise ScenarioError(f"a cutoff book has no id or title: {row!r}")
        if cutoff_total != len(cutoff):
            raise ScenarioError("the cutoff page reports a total its rows do not match")

        # A-11, the search the Wanted tab starts.
        search = marker.get("search") or {}
        if not isinstance(search.get("id"), int):
            raise ScenarioError("the scenario did not post the BookSearch")
        command = _read(f"/command/{search['id']}")
        if not isinstance(command, dict) or command.get("name") != "BookSearch":
            raise ScenarioError("the BookSearch command is not the one that was posted")
        if (command.get("body") or {}).get("bookIds") != [search.get("bookId")]:
            raise ScenarioError("the BookSearch command carries another book")
        if command.get("status") not in COMMAND_STATES:
            raise ScenarioError(
                f"the BookSearch is in an unknown state: {command.get('status')!r}"
            )

        # A-10, the queue and the client it would come from.
        queue_total, queue = _envelope(
            _read("/queue?page=1&pageSize=50"), "Readarr queue"
        )
        clients = _read("/downloadclient")
        if not isinstance(clients, list):
            raise ScenarioError("Readarr answered the download clients with something else")
        if not clients and queue_total != 0:
            raise ScenarioError("Readarr reports queue rows without a download client")
        for row in queue:
            if not row.get("title"):
                raise ScenarioError(f"a queue row has no title: {row!r}")
            if "trackedDownloadState" not in row:
                raise ScenarioError(
                    f"a queue row carries no trackedDownloadState: {row!r}"
                )

        # A-09, the calendar: the app's window and a window with books in it.
        today = date.today()
        app_start = today
        app_end = today + timedelta(days=30)
        for row in _calendar(app_start, app_end):
            moment = _stamp(row.get("releaseDate")).date()
            if not app_start <= moment <= app_end:
                raise ScenarioError(
                    f"{row.get('title')!r} is dated {moment}, outside the app's window"
                )
        historical = _calendar(
            date.fromisoformat(HISTORICAL_START), date.fromisoformat(HISTORICAL_END)
        )
        if not historical:
            raise ScenarioError("Readarr's calendar is empty for 1800 to 1910")
        titles = set()
        for row in historical:
            moment = _stamp(row.get("releaseDate")).date()
            if not date.fromisoformat(HISTORICAL_START) <= moment <= date.fromisoformat(
                HISTORICAL_END
            ):
                raise ScenarioError(
                    f"{row.get('title')!r} is dated {moment}, outside the window asked"
                )
            if not isinstance(row.get("author"), dict):
                raise ScenarioError(
                    f"{row.get('title')!r} came back without its author: the client "
                    "asks includeAuthor=true"
                )
            titles.add(row.get("title"))
        if KNOWN_RELEASE[0] not in titles:
            raise ScenarioError(
                f"the calendar does not date {KNOWN_RELEASE[0]!r} in its own year"
            )

        # A-12, the history envelope.
        history_total, history = _envelope(
            _read("/history?page=1&pageSize=20&includeAuthor=true"), "Readarr history"
        )
        for row in history:
            if not isinstance(row.get("eventType"), str) or not row.get("eventType"):
                raise ScenarioError(f"a history row has no eventType: {row!r}")
            _stamp(row.get("date"))
        if history_total < len(history):
            raise ScenarioError("the history reports fewer rows than it returned")

    def verify_absent(self) -> None:
        marker = _marker()
        if not marker:
            return
        author_id = marker.get("author")
        original = marker.get("original") or {}
        if isinstance(author_id, int) and original:
            author = _read(f"/author/{author_id}")
            for key, value in original.items():
                if author.get(key) != value:
                    raise ScenarioError(
                        f"{TARGET}'s {key} is {author.get(key)!r}, not the lab's {value!r}"
                    )
        MARKER.unlink(missing_ok=True)
        if BACKUP.exists() and not any(BACKUP.iterdir()):
            BACKUP.rmdir()


SCENARIO = ArrLibraryReadarr()
