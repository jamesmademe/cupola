"""A download waiting its turn behind the client's active limit.

The client is told to run one download at a time. The magnet the seed already
left in it holds that one slot (it waits for metadata no peer will ever send,
which is a download in qBittorrent's eyes), so the release added after it waits
in ``queuedDL``: the app's ``Queued``, blue and informational, never a fault
(``lib/features/services/domain/download_client_faults.dart``).

``teardown`` removes the added torrent and puts the client's queueing
preferences back exactly as they were, so a second run finds the same lab.
"""

from __future__ import annotations

import queue_probe as probe

from .base import Scenario, ScenarioError


class QueueQueued(Scenario):
    name = "queue-queued"
    profiles = ("core", "downloads")

    def apply(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        probe.save_preferences(client)
        probe.set_preferences(
            client, {"max_active_downloads": 1, "queueing_enabled": True}
        )
        magnet = probe.named(client, probe.QUEUED_MAGNET_NAME)
        if magnet is None:
            probe.add(
                client,
                url=probe.QUEUED_MAGNET,
                what="the waiting magnet",
                category="",
            )
            magnet = probe.wait_torrent(
                client,
                probe.QUEUED_MAGNET_NAME,
                predicate=lambda item: True,
                what="the waiting magnet arriving",
                timeout=60,
            )
        if probe.state(magnet) in probe.HELD_STATES:
            probe.start(client, magnet["hash"])
            probe.wait_torrent(
                client,
                probe.QUEUED_MAGNET_NAME,
                predicate=lambda item: probe.state(item)
                not in probe.HELD_STATES,
                what="the waiting magnet taking its slot",
                timeout=60,
            )
        probe.remove(client, probe.TORRENT_NAME)
        probe.add(client, what="the release")
        probe.wait_torrent(
            client,
            predicate=lambda item: probe.state(item) == "queuedDL",
            what="the release waiting in the queue",
            timeout=90,
        )

    def teardown(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        probe.remove(client, probe.TORRENT_NAME)
        probe.remove_client_data()
        probe.restore_preferences(client)
        probe.drop_scenario_state()

    def verify(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        torrent = probe.require_named(client, probe.TORRENT_NAME)
        if probe.state(torrent) != "queuedDL":
            raise ScenarioError(
                f"the release reads {probe.state(torrent)}, not queuedDL"
            )
        if probe.progress(torrent) != 0:
            raise ScenarioError("a queued download has already fetched bytes")
        if int(torrent.get("dlspeed") or 0) != 0:
            raise ScenarioError("a queued download is moving")
        current = probe.preferences(client)
        if current.get("max_active_downloads") != 1:
            raise ScenarioError(
                "the client's active limit is "
                f"{current.get('max_active_downloads')}, not 1"
            )
        if not current.get("queueing_enabled"):
            raise ScenarioError("the client's queueing is off")
        magnet = probe.named(client, probe.QUEUED_MAGNET_NAME)
        if magnet is None:
            raise ScenarioError("the waiting magnet left the client")
        if probe.state(magnet) not in probe.DOWNLOADING_STATES:
            raise ScenarioError(
                f"the slot holder reads {probe.state(magnet)}, not a download"
            )

    def verify_absent(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        probe.ensure_absent(client)
        if probe.PREFERENCES_FILE.exists():
            raise ScenarioError("the client's original preferences were not restored")
        if probe.named(client, probe.QUEUED_MAGNET_NAME) is None:
            raise ScenarioError("the seed's waiting magnet is no longer in the client")


SCENARIO = QueueQueued()
