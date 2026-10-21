"""Readarr's six authors and their six books, straight from its database.

Readarr's metadata host is unreachable in an offline lab, so its API cannot add
an author (testlab plan, decision 4): ``readarr_seed`` writes the records into
``readarr.db`` with the container stopped, in one transaction, and reads them
back through the API.  The library belongs to the lab rather than to a single
scenario, so ``teardown`` never deletes it and only proves it is still whole.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import readarr_seed  # noqa: E402

from .base import Scenario  # noqa: E402


class ReadarrLibraryScenario(Scenario):
    name = "readarr-library"
    profiles = ("core",)

    def apply(self) -> None:
        readarr_seed.seed()

    def teardown(self) -> None:
        # The library is lab state, not scenario state: there is nothing to undo.
        pass

    def verify(self) -> None:
        readarr_seed.verify()

    def verify_absent(self) -> None:
        # Teardown leaves the library in place, so absence would be the fault.
        readarr_seed.verify()


SCENARIO = ReadarrLibraryScenario()
