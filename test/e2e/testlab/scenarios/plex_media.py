"""Plex's three libraries, the watch state and the on-deck row.

The libraries belong to the lab rather than to one scenario, the same way the
Readarr library and the Seerr world do: ``apply`` builds them through Plex's
own API (idempotently) and writes ``<state>/plex-media.json`` for the e2e
tests, ``teardown`` takes nothing away because the next flow reads the same
libraries, and both ``verify`` methods read the server back instead of trusting
the last run.

The three declared limits, a movie that cannot be put on deck through the API, a
stream that cannot be stopped without Plex Pass, and a household user that is
never created on the owner's real account, are explained in ``plex_media.py``
and, for the stop, in ``plex_play.py``.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import plex_media  # noqa: E402

from .base import STATE_ROOT, Scenario, ScenarioError  # noqa: E402


class PlexMediaScenario(Scenario):
    name = "plex-media"
    profiles = ("core", "media")

    def apply(self) -> None:
        try:
            plex_media.seed(STATE_ROOT)
        except plex_media.PlexError as error:
            raise ScenarioError(
                f"building the Plex libraries failed: {error}"
            ) from error

    def teardown(self) -> None:
        # The libraries are lab state, not scenario state: there is nothing to
        # undo, and a teardown that deleted them would break every later flow.
        pass

    def verify(self) -> None:
        problems = plex_media.verify_only(STATE_ROOT)
        if problems:
            raise ScenarioError(
                f"the Plex libraries are not whole: {'; '.join(problems)}"
            )

    def verify_absent(self) -> None:
        # Teardown leaves the libraries in place, so absence would be the fault.
        problems = plex_media.verify_only(STATE_ROOT)
        if problems:
            raise ScenarioError(
                "the Plex libraries left by teardown are not whole: "
                f"{'; '.join(problems)}"
            )


SCENARIO = PlexMediaScenario()
