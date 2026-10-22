"""Jellyfin with three libraries, a household and two watch states.

The seeded lab already has the administrator, the requester and a `Films`
library. This scenario adds what the flow catalogue's S rows read: `Series` and
`Music` libraries over the forge's real episode and FLAC tracks, the film
watched by `cupola-viewer`, and the second episode of *Breaking Bad* at 30%, in
Continue watching.

What the teardown takes back is the one thing this scenario creates that is not
part of the lab's world: any playback session the helper opened. The libraries
and the watch states stay, on purpose. Deleting a library removes its metadata
and its ids, every later e2e that quotes a title would have to scan again, and
the lab's reset is the command that rebuilds a world, not a teardown. The
scenario says so in ``verify_absent`` so a green teardown cannot be mistaken for
"the libraries are gone".
"""

from __future__ import annotations

from typing import Any, Callable

import jellyfin_media as media
from scenarios.base import Scenario, ScenarioError


def _guard(action: str, work: Callable[[], Any]) -> Any:
    try:
        return work()
    except media.MediaError as error:
        raise ScenarioError(f"jellyfin-media {action}: {error}") from error


class JellyfinMediaScenario(Scenario):
    name = "jellyfin-media"
    profiles = ("core", "media")

    def apply(self) -> None:
        _guard("apply", media.setup)

    def verify(self) -> None:
        state = _guard("verify", media.audit)
        _guard("verify", lambda: media.assert_ready(state))

    def teardown(self) -> None:
        # A session is per run: the next apply must not inherit one. Nothing
        # else here is disposable; see the module docstring.
        _guard("teardown", media.play.stop_all)

    def verify_absent(self) -> None:
        """No lab playback session is left; the libraries stay, and must.

        Called by ``testlab.py scenario teardown`` after ``teardown``. The
        scenario's promise is that its world survives the teardown, so this
        asserts the survival and the absence of the session, in that order.
        """
        playing = [
            session
            for session in media.play.playing_sessions(media.token())
            if session.get("NowPlayingItem")
            and str(session.get("DeviceId") or "").startswith(media.play.DEVICE_PREFIX)
        ]
        if playing:
            raise ScenarioError(
                "a playback session the helper opened is still playing: "
                + ", ".join(str(session.get("DeviceName")) for session in playing)
            )
        state = _guard("verify_absent", media.audit)
        _guard("verify_absent", lambda: media.assert_ready(state))


SCENARIO = JellyfinMediaScenario()
