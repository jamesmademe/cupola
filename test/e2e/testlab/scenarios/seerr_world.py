"""The main Seerr's world: its people, every request state, an issue, a watchlist.

The world belongs to the lab rather than to a single scenario, the same way the
Readarr library does: ``apply`` seeds it through Seerr's API (idempotently, and
writes `<state>/seerr-world.json` for the e2e tests), ``teardown`` takes nothing
away because the next flow needs the same people and requests, and both
``verify`` methods read the world back instead of trusting the last run.

The two deliberate limits, a 4K Radarr that never answers and a series request
that waits rather than adding Sonarr's eleventh series, are explained in
``seerr_world.py``.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import seerr_world  # noqa: E402

from .base import STATE_ROOT, Scenario, ScenarioError  # noqa: E402


class SeerrWorldScenario(Scenario):
    name = "seerr-world"
    profiles = ("core", "media")

    def apply(self) -> None:
        try:
            seerr_world.seed(STATE_ROOT)
        except seerr_world.SeerrError as error:
            raise ScenarioError(f"seeding the Seerr world failed: {error}") from error

    def teardown(self) -> None:
        # The world is lab state, not scenario state: there is nothing to undo.
        pass

    def verify(self) -> None:
        try:
            seerr_world.verify_only(STATE_ROOT)
        except seerr_world.SeerrError as error:
            raise ScenarioError(f"the Seerr world is not whole: {error}") from error

    def verify_absent(self) -> None:
        # Teardown leaves the world in place, so absence would be the fault.
        try:
            seerr_world.verify_only(STATE_ROOT)
        except seerr_world.SeerrError as error:
            raise ScenarioError(
                f"the Seerr world left by teardown is not whole: {error}"
            ) from error


SCENARIO = SeerrWorldScenario()
