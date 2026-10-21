#!/usr/bin/env python3
"""Seed Readarr's six authors and their books straight into its database.

Readarr resolves authors and books through its public metadata host, and the
testlab is offline by design: every lookup fails, so its API cannot add an
author (testlab plan, decision 4).  The records are written into ``readarr.db``
with the container stopped, in one transaction, and read back through the API
afterwards.  A row already present by foreign id or by name is left alone, so a
second run changes nothing and does not restart anything.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import shutil
import sqlite3
import subprocess
import time
import unicodedata
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRATCH_ROOT = REPO_ROOT / ".ai" / "scratch" / "zz_testlab"
CONTAINER = "cupola-testlab-readarr-1"
BASE = "http://127.0.0.1:8787/api/v1"
API_KEY = "test-key"
ROOT_FOLDER = "/media/books"
BACKUP_NAME = "readarr.db.bak-readarr-seed"

AUTHOR_METADATA_COLUMNS = {
    "ForeignAuthorId",
    "TitleSlug",
    "Name",
    "Overview",
    "Disambiguation",
    "Gender",
    "Hometown",
    "Born",
    "Died",
    "Status",
    "Images",
    "Links",
    "Genres",
    "Ratings",
    "Aliases",
    "SortName",
    "NameLastFirst",
    "SortNameLastFirst",
}
AUTHOR_COLUMNS = {
    "CleanName",
    "Path",
    "Monitored",
    "LastInfoSync",
    "QualityProfileId",
    "Tags",
    "Added",
    "AddOptions",
    "MetadataProfileId",
    "AuthorMetadataId",
    "MonitorNewItems",
}
BOOK_COLUMNS = {
    "AuthorMetadataId",
    "ForeignBookId",
    "TitleSlug",
    "Title",
    "ReleaseDate",
    "Links",
    "Genres",
    "Ratings",
    "CleanTitle",
    "Monitored",
    "AnyEditionOk",
    "LastInfoSync",
    "Added",
    "AddOptions",
    "RelatedBooks",
}
EDITION_COLUMNS = {
    "BookId",
    "ForeignEditionId",
    "Title",
    "TitleSlug",
    "Language",
    "Format",
    "IsEbook",
    "ReleaseDate",
    "Images",
    "Links",
    "Ratings",
    "Monitored",
    "ManualAdd",
}

RATINGS = json.dumps({"votes": 0, "value": 0})
AUTHOR_ADD_OPTIONS = json.dumps(
    {
        "monitor": "all",
        "booksToMonitor": [],
        "monitored": True,
        "searchForMissingBooks": False,
    }
)
BOOK_ADD_OPTIONS = json.dumps({"addType": "automatic", "searchForNewBook": False})


class SeedError(RuntimeError):
    pass


def state_root() -> Path:
    return Path(
        os.environ.get("CUPOLA_TESTLAB_STATE_DIR", SCRATCH_ROOT / "state")
    ).resolve()


def world(state: Path) -> dict[str, Any]:
    path = state / "world.json"
    if not path.exists():
        raise SeedError(f"{path} is missing: run the lab export first")
    data = json.loads(path.read_text(encoding="utf-8"))
    authors = data.get("authors")
    if not isinstance(authors, list) or not authors:
        raise SeedError(f"{path} carries no authors")
    return data


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%fZ")


def _ascii(text: str) -> str:
    return (
        unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    )


def _slug(text: str) -> str:
    value = re.sub(r"[^a-z0-9]+", "-", _ascii(text).lower()).strip("-")
    return value or "unknown"


def _clean(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", _ascii(text).lower())


def _last_first(name: str) -> str:
    head, _, last = name.rpartition(" ")
    return f"{last}, {head}" if head else name


def _release_date(year: int) -> str:
    return f"{year:04d}-01-01 00:00:00Z"


def api(path: str, timeout: float = 15) -> Any:
    call = urllib.request.Request(
        f"{BASE}{path}",
        headers={"X-Api-Key": API_KEY, "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(call, timeout=timeout) as response:
            return json.loads(response.read() or b"null")
    except urllib.error.HTTPError as error:
        raise SeedError(f"GET {path} answered {error.code}") from error
    except (
        urllib.error.URLError,
        http.client.HTTPException,
        ConnectionError,
        TimeoutError,
        json.JSONDecodeError,
    ) as error:
        raise SeedError(f"GET {path} did not answer: {error}") from error


def api_authors() -> list[dict[str, Any]]:
    body = api("/author")
    if not isinstance(body, list):
        raise SeedError("Readarr answered the author list with something else")
    return body


def api_books() -> list[dict[str, Any]]:
    body = api("/book")
    if not isinstance(body, list):
        raise SeedError("Readarr answered the book list with something else")
    return body


def expected(state: Path) -> list[dict[str, Any]]:
    authors = world(state)["authors"]
    seen_books: set[str] = set()
    for author in authors:
        for book in author.get("books") or []:
            foreign = book["foreignBookId"]
            if foreign in seen_books:
                raise SeedError(f"{foreign} is listed twice in the world")
            seen_books.add(foreign)
    return authors


def verify(state: Path | None = None) -> dict[str, int]:
    """Prove the six authors and their six books through Readarr's API."""
    authors = expected(state or state_root())
    listed_authors = api_authors()
    listed_books = api_books()

    by_name = {item.get("authorName"): item for item in listed_authors}
    missing_authors = [
        author["name"] for author in authors if author["name"] not in by_name
    ]
    if missing_authors:
        raise SeedError(f"authors missing from Readarr: {', '.join(missing_authors)}")

    author_ids = {by_name[author["name"]]["id"] for author in authors}
    titles = {book["title"] for author in authors for book in author["books"]}
    by_title = {item.get("title"): item for item in listed_books}
    missing_books = sorted(title for title in titles if title not in by_title)
    if missing_books:
        raise SeedError(f"books missing from Readarr: {', '.join(missing_books)}")
    for title in titles:
        if by_title[title].get("authorId") not in author_ids:
            raise SeedError(f"{title} hangs off an author that is not in the six")

    print(
        f"[readarr-seed] authors {len(authors)}/{len(authors)}: "
        + ", ".join(author["name"] for author in authors)
    )
    print(
        f"[readarr-seed] books {len(titles)}/{len(titles)}: "
        + ", ".join(sorted(titles))
    )
    return {"authors": len(authors), "books": len(titles)}


def container_running() -> bool:
    result = subprocess.run(
        ["docker", "inspect", "--format", "{{.State.Running}}", CONTAINER],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SeedError(f"{CONTAINER} is not in this lab: {result.stderr.strip()}")
    return result.stdout.strip() == "true"


def _docker(*args: str, timeout: float = 180) -> None:
    result = subprocess.run(["docker", *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise SeedError(f"docker {' '.join(args)} failed: {result.stderr.strip()}")


def stop() -> bool:
    if not container_running():
        return False
    _docker("stop", CONTAINER)
    print("[readarr-seed] container stopped")
    return True


def start() -> None:
    _docker("start", CONTAINER)
    print("[readarr-seed] container started")
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        try:
            api("/system/status", timeout=5)
            return
        except SeedError:
            time.sleep(1)
    raise SeedError("Readarr did not answer its API after the restart")


def _require(conn: sqlite3.Connection, table: str, needed: set[str]) -> None:
    columns = {row[1] for row in conn.execute(f'PRAGMA table_info("{table}")')}
    if not columns:
        raise SeedError(f"the table {table} is not in readarr.db")
    missing = sorted(needed - columns)
    if missing:
        raise SeedError(
            f"{table} lacks {', '.join(missing)}: this Readarr schema is not the one "
            "the seed knows"
        )


def _author_metadata_id(conn: sqlite3.Connection, author: dict[str, Any]) -> int | None:
    row = conn.execute(
        'SELECT "Id" FROM "AuthorMetadata" WHERE "ForeignAuthorId" = ?',
        (author["foreignAuthorId"],),
    ).fetchone()
    if row is not None:
        return int(row[0])
    row = conn.execute(
        'SELECT "Id" FROM "AuthorMetadata" WHERE "Name" = ?', (author["name"],)
    ).fetchone()
    return int(row[0]) if row is not None else None


def _insert_author(
    conn: sqlite3.Connection, author: dict[str, Any], now: str
) -> tuple[int, bool]:
    """Insert the metadata and the library row; return (metadata id, added)."""
    metadata_id = _author_metadata_id(conn, author)
    added = False
    if metadata_id is None:
        cursor = conn.execute(
            'INSERT INTO "AuthorMetadata" ("ForeignAuthorId", "TitleSlug", "Name",'
            ' "Overview", "Disambiguation", "Gender", "Hometown", "Born", "Died",'
            ' "Status", "Images", "Links", "Genres", "Ratings", "Aliases",'
            ' "SortName", "NameLastFirst", "SortNameLastFirst")'
            " VALUES (?, ?, ?, NULL, NULL, NULL, NULL, NULL, NULL, ?, ?, ?, ?, ?,"
            " ?, ?, ?, ?)",
            (
                author["foreignAuthorId"],
                _slug(author["name"]),
                author["name"],
                1,  # AuthorStatusType.Ended
                "[]",
                "[]",
                "[]",
                RATINGS,
                "[]",
                author["name"],
                _last_first(author["name"]),
                _last_first(author["name"]),
            ),
        )
        metadata_id = int(cursor.lastrowid)
        added = True

    row = conn.execute(
        'SELECT "Id" FROM "Authors" WHERE "AuthorMetadataId" = ?', (metadata_id,)
    ).fetchone()
    if row is None:
        conn.execute(
            'INSERT INTO "Authors" ("CleanName", "Path", "Monitored", "LastInfoSync",'
            ' "QualityProfileId", "Tags", "Added", "AddOptions", "MetadataProfileId",'
            ' "AuthorMetadataId", "MonitorNewItems")'
            " VALUES (?, ?, 1, ?, 1, '[]', ?, ?, 1, ?, 0)",
            (
                _clean(author["name"]),
                f"{ROOT_FOLDER}/{author['name']}",
                now,
                now,
                AUTHOR_ADD_OPTIONS,
                metadata_id,
            ),
        )
        added = True
    return metadata_id, added


def _insert_book(
    conn: sqlite3.Connection, book: dict[str, Any], metadata_id: int, now: str
) -> bool:
    row = conn.execute(
        'SELECT "Id" FROM "Books" WHERE "ForeignBookId" = ?', (book["foreignBookId"],)
    ).fetchone()
    added = False
    if row is None:
        cursor = conn.execute(
            'INSERT INTO "Books" ("AuthorMetadataId", "ForeignBookId", "TitleSlug",'
            ' "Title", "ReleaseDate", "Links", "Genres", "Ratings", "CleanTitle",'
            ' "Monitored", "AnyEditionOk", "LastInfoSync", "Added", "AddOptions",'
            ' "RelatedBooks")'
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1, ?, ?, ?, '[]')",
            (
                metadata_id,
                book["foreignBookId"],
                _slug(book["title"]),
                book["title"],
                _release_date(int(book["year"])),
                "[]",
                "[]",
                RATINGS,
                _clean(book["title"]),
                now,
                now,
                BOOK_ADD_OPTIONS,
            ),
        )
        book_id = int(cursor.lastrowid)
        added = True
    else:
        book_id = int(row[0])

    foreign_edition_id = f"{book['foreignBookId']}-ebook"
    edition = conn.execute(
        'SELECT "Id" FROM "Editions" WHERE "ForeignEditionId" = ?',
        (foreign_edition_id,),
    ).fetchone()
    if edition is None:
        conn.execute(
            'INSERT INTO "Editions" ("BookId", "ForeignEditionId", "Title",'
            ' "TitleSlug", "Language", "Format", "IsEbook", "ReleaseDate", "Images",'
            ' "Links", "Ratings", "Monitored", "ManualAdd")'
            " VALUES (?, ?, ?, ?, 'eng', 'eBook', 1, ?, '[]', '[]', ?, 1, 0)",
            (
                book_id,
                foreign_edition_id,
                book["title"],
                _slug(book["title"]),
                _release_date(int(book["year"])),
                RATINGS,
            ),
        )
        added = True
    return added


def write_database(state: Path) -> tuple[list[str], list[str]]:
    """Insert what is missing, in one transaction, with the container stopped."""
    if container_running():
        raise SeedError("Readarr is running: its database is never written while it is")
    db = state / "readarr" / "readarr.db"
    if not db.exists():
        raise SeedError(f"{db} is missing")
    backup = db.parent / BACKUP_NAME
    if not backup.exists():
        shutil.copy2(db, backup)
        print(f"[readarr-seed] backup {backup.name}")

    authors = expected(state)
    now = _now()
    added_authors: list[str] = []
    added_books: list[str] = []
    conn = sqlite3.connect(db, isolation_level=None)
    try:
        _require(conn, "AuthorMetadata", AUTHOR_METADATA_COLUMNS)
        _require(conn, "Authors", AUTHOR_COLUMNS)
        _require(conn, "Books", BOOK_COLUMNS)
        _require(conn, "Editions", EDITION_COLUMNS)
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("BEGIN IMMEDIATE")
        try:
            for author in authors:
                metadata_id, author_added = _insert_author(conn, author, now)
                if author_added:
                    added_authors.append(author["name"])
                for book in author["books"]:
                    if _insert_book(conn, book, metadata_id, now):
                        added_books.append(book["title"])
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise
        conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    except sqlite3.Error as error:
        raise SeedError(f"readarr.db refused the seed: {error}") from error
    finally:
        conn.close()
    return added_authors, added_books


def seed(state: Path | None = None) -> tuple[int, int]:
    """Bring the six authors and their books in, skipping what is already there."""
    state = state or state_root()
    authors = expected(state)
    titles = [book["title"] for author in authors for book in author["books"]]

    running = container_running()
    if running:
        try:
            names = {item.get("authorName") for item in api_authors()}
            present = {item.get("title") for item in api_books()}
            if all(author["name"] in names for author in authors) and all(
                title in present for title in titles
            ):
                print("[readarr-seed] nothing to do: the library is already there")
                return 0, 0
        except SeedError:
            pass

    stopped_here = stop()
    try:
        added_authors, added_books = write_database(state)
    finally:
        if stopped_here or not running:
            start()

    print(
        f"[readarr-seed] inserted {len(added_authors)} authors"
        + (f": {', '.join(added_authors)}" if added_authors else "")
    )
    print(
        f"[readarr-seed] inserted {len(added_books)} books"
        + (f": {', '.join(added_books)}" if added_books else "")
    )
    return len(added_authors), len(added_books)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--state-dir",
        type=Path,
        default=None,
        help="the lab state directory (default: CUPOLA_TESTLAB_STATE_DIR)",
    )
    arguments = parser.parse_args(argv)
    state = arguments.state_dir.resolve() if arguments.state_dir else state_root()
    try:
        seed(state)
        verify(state)
    except SeedError as error:
        print(f"[readarr-seed] stopped: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
