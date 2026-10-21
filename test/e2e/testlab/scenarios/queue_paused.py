"""A download stopped by a person, keeping what has already arrived.

The client is told to stop mid-transfer: the torrent is added stopped, given a
download limit so the stop lands on a real percentage instead of on a finished
file, started, and stopped again once some bytes are in. qBittorrent reports
``stoppedDL`` (``pausedDL`` on older builds) and the progress stays where it
was, which is the app's ``Stopped``: a pause the user asked for is neutral, not
a fault (``lib/features/services/domain/download_client_faults.dart``).

``teardown`` removes the torrent and its bytes.
"""

from __future__ import annotations

import queue_probe as probe

from .base import Scenario, ScenarioError

# Slow enough that the stop lands between 5% and 90% every time: the release is
# 5.3 MiB, so at 64 KiB/s the transfer takes well over a minute.
DOWNLOAD_LIMIT = 64 * 1024
STOP_AT = 0.05


class QueuePaused(Scenario):
    name = "queue-paused"
    profiles = ("core", "downloads")

    def apply(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        probe.seeder_reannounce(probe.opener_for(probe.SEEDER))
        probe.remove(client, probe.TORRENT_NAME)
        probe.add(client, what="the release", stopped=True)
        torrent = probe.wait_torrent(
            client,
            predicate=lambda item: probe.state(item) in probe.HELD_STATES,
            what="the download arriving stopped",
            timeout=60,
        )
        probe.limit_download(client, torrent["hash"], DOWNLOAD_LIMIT)
        probe.start(client, torrent["hash"])
        moving = probe.wait_torrent(
            client,
            predicate=lambda item: probe.progress(item) >= STOP_AT,
            what="the download reaching a few percent",
            timeout=180,
            nudge=True,
        )
        probe.stop(client, moving["hash"])
        probe.wait_torrent(
            client,
            predicate=lambda item: probe.state(item) in probe.HELD_STATES,
            what="the download stopping",
            timeout=60,
        )

    def teardown(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        probe.seeder_reannounce(probe.opener_for(probe.SEEDER))
        probe.remove(client, probe.TORRENT_NAME)
        probe.remove_client_data()

    def verify(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        torrent = probe.require_named(client, probe.TORRENT_NAME)
        if probe.state(torrent) not in probe.HELD_STATES:
            raise ScenarioError(
                f"the download reads {probe.state(torrent)}, not a pause"
            )
        if not STOP_AT <= probe.progress(torrent) < 1:
            raise ScenarioError(
                "the download is at "
                f"{probe.progress(torrent):.4f}; a pause must keep what arrived "
                "and leave something to fetch"
            )
        if float(torrent.get("dlspeed") or 0) != 0:
            raise ScenarioError("the download is still moving")
        # A pause is a pause: the percentage does not drift while we look.
        before = probe.progress(torrent)
        probe.wait_torrent(
            client,
            predicate=lambda item: probe.progress(item) == before,
            what="the percentage holding still",
            timeout=10,
            interval=3,
        )

    def verify_absent(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        probe.ensure_absent(client)


SCENARIO = QueuePaused()
