"""SABnzbd over the lab's local NNTP server: D-10, D-11, D-12 and its D-16 states.

The app talks to SABnzbd through its HTTP API, so the scenario drives the same
API: the news server is an entry in ``section=servers``, the NZB arrives through
``mode=addurl`` from the lab's own HTTP surface, and the queue is read back with
``mode=queue`` and ``mode=history``. The articles are real yEnc parts served by
``nntp_server`` from a deterministic test file, so a completed job is a real
download and its bytes are compared against the source.

The state left behind, one job per catalog state:

- ``Complete``: finished, in the history, its file on disk.
- ``Missing``: every article answers 430, so SABnzbd fails it by itself.
- ``Slow``: many small articles with a pause before each, so the job stays
  downloading.
- ``Paused``: a job stopped by a person, still in the queue.

SABnzbd runs several jobs at once, so there is no ``Queued`` job here: the
client has no per-job queue to wait in. NZBGet, which runs one job at a time,
carries that state.
"""

from __future__ import annotations

import usenet_forge as forge

from .base import Scenario, ScenarioError

STATE = "usenet-sab"


class UsenetSab(Scenario):
    name = "usenet-sab"
    profiles = ("core", "downloads")

    def apply(self) -> None:
        forge.ensure_server()
        client = forge.Sabnzbd()
        client.configure_server()
        client.clean()

        client.add(forge.COMPLETE)
        forge.wait_for(
            lambda: client.history_item(forge.COMPLETE),
            lambda item: item is not None and item.get("status") == "Completed",
            what="SABnzbd finishing the complete job",
        )

        client.add(forge.MISSING)
        forge.wait_for(
            lambda: client.history_item(forge.MISSING),
            lambda item: item is not None and item.get("status") == "Failed",
            what="SABnzbd failing the job with missing articles",
        )

        client.add(forge.SLOW)
        forge.wait_for(
            lambda: client.slot(forge.SLOW),
            lambda slot: slot is not None and slot.get("status") == "Downloading",
            what="SABnzbd downloading the slow job",
        )

        client.add(forge.PAUSED)
        slot = forge.wait_for(
            lambda: client.slot(forge.PAUSED),
            lambda item: item is not None,
            what="SABnzbd queueing the paused job",
        )
        client.pause(str(slot["nzo_id"]))
        forge.wait_for(
            lambda: client.slot(forge.PAUSED),
            lambda item: item is not None and item.get("status") == "Paused",
            what="SABnzbd pausing the job",
        )
        forge.write_state(STATE, {"server": forge.SAB_SERVER_NAME})

    def teardown(self) -> None:
        client = forge.Sabnzbd()
        client.clean()
        client.remove_server()
        for name in forge.JOB_NAMES:
            forge.remove_download(name)
        forge.stop_server()
        forge.drop_state(STATE)

    def verify(self) -> None:
        client = forge.Sabnzbd()
        server = client.server()
        if server.get("host") != "host.docker.internal":
            raise ScenarioError(
                f"SABnzbd reads host {server.get('host')!r}, not host.docker.internal"
            )
        if int(server.get("port") or 0) != forge.NNTP_PORT:
            raise ScenarioError(
                f"SABnzbd reads port {server.get('port')}, not {forge.NNTP_PORT}"
            )
        if int(server.get("connections") or 0) != 2:
            raise ScenarioError(
                f"SABnzbd reads {server.get('connections')} connections, not 2"
            )
        if not server.get("enable"):
            raise ScenarioError("the lab news server is disabled in SABnzbd")
        if server.get("ssl"):
            raise ScenarioError("the lab news server asks for TLS")

        slow = client.slot(forge.SLOW)
        if slow is None or slow.get("status") != "Downloading":
            raise ScenarioError(
                f"the slow job reads {slow and slow.get('status')}, not Downloading"
            )
        paused = client.slot(forge.PAUSED)
        if paused is None or paused.get("status") != "Paused":
            raise ScenarioError(
                f"the paused job reads {paused and paused.get('status')}, not Paused"
            )

        completed = client.history_item(forge.COMPLETE)
        if completed is None or completed.get("status") != "Completed":
            raise ScenarioError(
                f"the complete job reads {completed and completed.get('status')}"
            )
        if int(completed.get("bytes") or 0) <= 0:
            raise ScenarioError("the complete job reports no bytes")
        forge.verify_download(
            "sabnzbd",
            forge.COMPLETE,
            "Cupola.Testlab.Usenet.mkv",
            3 * 64 * 1024,
        )
        failed = client.history_item(forge.MISSING)
        if failed is None or failed.get("status") != "Failed":
            raise ScenarioError(
                f"the missing job reads {failed and failed.get('status')}, not Failed"
            )
        if not failed.get("fail_message"):
            raise ScenarioError("the failed job carries no reason")

        stats = client.call("server_stats")
        if int(stats.get("total") or 0) <= 0:
            raise ScenarioError("SABnzbd reports no transfer volume")
        usage = (stats.get("servers") or {}).get(forge.SAB_SERVER_NAME)
        if not isinstance(usage, dict):
            raise ScenarioError("SABnzbd reports no usage for the lab server")
        if int(usage.get("total") or 0) <= 0:
            raise ScenarioError("SABnzbd reports no volume for the lab server")

    def verify_absent(self) -> None:
        client = forge.Sabnzbd()
        if any(
            entry.get("name") == forge.SAB_SERVER_NAME
            for entry in client.servers()
        ):
            raise ScenarioError("SABnzbd still has the lab news server")
        for slot in client.slots():
            if str(slot.get("filename") or slot.get("name")) in forge.JOB_NAMES:
                raise ScenarioError(
                    f"SABnzbd still has the job {slot.get('filename')}"
                )
        for item in client.history():
            if str(item.get("name")) in forge.JOB_NAMES:
                raise ScenarioError(f"SABnzbd still has {item.get('name')} in history")
        if forge.scenario_state(STATE).exists():
            raise ScenarioError("the scenario state was not removed")


SCENARIO = UsenetSab()
