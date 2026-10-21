"""A download whose data is no longer where the client left it.

The release is fetched whole, then its folder is moved out of the client's
downloads and the app's qBittorrent is restarted. On start-up qBittorrent looks
for a torrent's data and, finding none, brings it up stopped with the state
``missingFiles``, which the app reads as a failure with its reason: *Files
missing* (``lib/features/services/domain/download_client_faults.dart``).

The restart is qBittorrent's alone, and it is what makes this state reachable at
all: without it a recheck only resets the progress and downloads the pieces
again, and a seeding torrent does not notice its files are gone. The arrs and
the indexers are never touched.

``teardown`` puts the folder back, starts the torrent so it rechecks, removes it
and its bytes, and checks that the client's downloads are clean.
"""

from __future__ import annotations

import queue_probe as probe

from .base import Scenario, ScenarioError


class QueueMissingFiles(Scenario):
    name = "queue-missing-files"
    profiles = ("core", "downloads")

    def apply(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        probe.seeder_reannounce(probe.opener_for(probe.SEEDER))
        probe.remove(client, probe.TORRENT_NAME)
        probe.restore_client_data()
        probe.add(client, what="the release")
        probe.wait_torrent(
            client,
            predicate=lambda item: probe.progress(item) >= 1,
            what="the release arriving whole",
            timeout=180,
            nudge=True,
        )
        probe.move_client_data_away()
        probe.restart_client()
        client = probe.wait_webui()
        probe.wait_torrent(
            client,
            predicate=lambda item: probe.state(item) == "missingFiles",
            what="qBittorrent reporting the files missing",
            timeout=120,
        )

    def teardown(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        probe.restore_client_data()
        torrent = probe.named(client, probe.TORRENT_NAME)
        if torrent is not None:
            # Starting it makes qBittorrent recheck the restored data, so the
            # removal that follows deletes the real file rather than a
            # half-known one.
            probe.start(client, torrent["hash"])
            probe.wait_torrent(
                client,
                predicate=lambda item: probe.state(item)
                not in ("checkingUP", "checkingDL", "checkingResumeData"),
                what="the restored data being checked",
                timeout=120,
                interval=2,
            )
        probe.remove(client, probe.TORRENT_NAME)
        probe.remove_client_data()

    def verify(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        torrent = probe.require_named(client, probe.TORRENT_NAME)
        if probe.state(torrent) != "missingFiles":
            raise ScenarioError(
                f"the download reads {probe.state(torrent)}, not missingFiles"
            )
        if probe.progress(torrent) != 0:
            raise ScenarioError(
                "the client still believes it has "
                f"{probe.progress(torrent):.4f} of the data"
            )
        if probe.CLIENT_DATA.exists():
            raise ScenarioError(f"{probe.CLIENT_DATA} came back by itself")

    def verify_absent(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        probe.ensure_absent(client)


SCENARIO = QueueMissingFiles()
