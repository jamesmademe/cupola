"""A download that stopped for good at 47%: the seeder itself only has half.

The state is made of bytes, not of a field. The seeder's file is copied to a
backup, truncated to 47% of the release rounded down to a whole piece (40 of
86), and rechecked, so the tracker's only peer can serve exactly those pieces.
The app's qBittorrent then fetches the release and stops at 0.4696 with nothing
left to ask for: qBittorrent reports ``stalledDL``, and the app reads a stall
once nothing has arrived for 30 minutes
(``lib/features/services/domain/download_client_faults.dart``).

``teardown`` removes the client's torrent and its bytes, puts the whole file
back, rechecks the seeder, and checks the seeder is complete again.
"""

from __future__ import annotations

import queue_probe as probe

from .base import Scenario, ScenarioError


class QueueStuck47(Scenario):
    name = "queue-stuck-47"
    profiles = ("core", "downloads")

    def apply(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        seeder = probe.opener_for(probe.SEEDER)
        # The same infohash already complete in the client would recheck to
        # 100% instead of stopping at the seeder's 47%.
        probe.remove(client, probe.TORRENT_NAME)
        probe.backup_seed_file()
        probe.truncate_seed_file()
        seeded = probe.seeder_recheck(
            seeder, expected_progress=probe.STUCK_PROGRESS
        )
        if abs(probe.progress(seeded) - probe.STUCK_PROGRESS) > 0.001:
            raise ScenarioError(
                "the seeder is at "
                f"{probe.progress(seeded):.4f} after the truncation, "
                f"not {probe.STUCK_PROGRESS:.4f}"
            )
        probe.add(client, what="the release")
        probe.wait_torrent(
            client,
            predicate=lambda item: abs(
                probe.progress(item) - probe.STUCK_PROGRESS
            )
            <= 0.001,
            what="the client reaching 47%",
            timeout=180,
            nudge=True,
        )
        probe.wait_torrent(
            client,
            predicate=lambda item: item.get("state") == "stalledDL",
            what="the client's download stalling",
            timeout=180,
        )

    def teardown(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        seeder = probe.opener_for(probe.SEEDER)
        # Take the client out first: with the seeder whole again it would
        # finish the release while the teardown runs.
        probe.remove(client, probe.TORRENT_NAME)
        probe.restore_seed_file()
        seeded = probe.seeder_recheck(seeder, expected_progress=1.0)
        if probe.progress(seeded) < 1:
            raise ScenarioError(
                "the seeder did not come back whole: "
                f"{probe.progress(seeded):.4f}"
            )
        # The backup exists only while the seeder's file is cut; leaving it
        # behind would put a stray copy of the release into every snapshot.
        if probe.SEED_BACKUP.exists():
            probe.SEED_BACKUP.unlink()
        probe.drop_scenario_state()

    def verify(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        seeder = probe.opener_for(probe.SEEDER)
        torrent = probe.require_named(client, probe.TORRENT_NAME)
        if abs(probe.progress(torrent) - probe.STUCK_PROGRESS) > 0.001:
            raise ScenarioError(
                "the download is at "
                f"{probe.progress(torrent):.4f}, not {probe.STUCK_PROGRESS:.4f}"
            )
        if probe.state(torrent) != "stalledDL":
            raise ScenarioError(
                f"the download reads {probe.state(torrent)}, not stalledDL"
            )
        if float(torrent.get("dlspeed") or 0) != 0:
            raise ScenarioError("the download is still moving")
        if int(torrent.get("amount_left") or 0) <= 0:
            raise ScenarioError("the download has nothing left to fetch")
        seeded = probe.require_named(
            seeder, probe.TORRENT_NAME, base=probe.SEEDER
        )
        if abs(probe.progress(seeded) - probe.STUCK_PROGRESS) > 0.001:
            raise ScenarioError(
                "the seeder is at "
                f"{probe.progress(seeded):.4f}, not {probe.STUCK_PROGRESS:.4f}"
            )
        if probe.SEED_FILE.stat().st_size != probe.STUCK_BYTES:
            raise ScenarioError("the seeder's file is not the truncated one")

    def verify_absent(self) -> None:
        client = probe.opener_for(probe.CLIENT)
        seeder = probe.opener_for(probe.SEEDER)
        probe.ensure_absent(client)
        seeded = probe.require_named(
            seeder, probe.TORRENT_NAME, base=probe.SEEDER
        )
        if probe.progress(seeded) < 1:
            raise ScenarioError(
                "the seeder is still partial: " f"{probe.progress(seeded):.4f}"
            )
        if probe.SEED_FILE.stat().st_size != probe.FULL_SIZE:
            raise ScenarioError(
                "the seeder's file is "
                f"{probe.SEED_FILE.stat().st_size} bytes, not {probe.FULL_SIZE}"
            )
        if probe.SEED_BACKUP.exists():
            raise ScenarioError(f"the scenario kept a backup at {probe.SEED_BACKUP}")


SCENARIO = QueueStuck47()
