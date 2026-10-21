"""NZBGet over the lab's local NNTP server: D-13, D-14, D-15 and its D-16 states.

NZBGet's only news-server API is its config file, which the daemon re-reads on
``reload`` (``saveconfig`` rewrites the whole file from what it is handed, so it
cannot be used for a single field). The scenario changes five non-secret
``Server1.*`` lines, keeps the old values, and puts them back in the teardown.
The username and password are never read, stored or changed: the lab server
accepts any credentials.

The state left behind, one job per catalog state:

- ``Complete``: finished, in the history, its file on disk.
- ``Missing``: articles the server answers 430 for, so NZBGet fails it.
- ``Slow``: many small articles with a pause before each, so the job stays
  downloading.
- ``Waiting``: queued behind the slow job, because the client runs one job at
  a time.
- ``Paused``: a job stopped by a person, still in the queue.
"""

from __future__ import annotations

import re
import time

import usenet_forge as forge

from .base import Scenario, ScenarioError

STATE = "usenet-nzbget"


class UsenetNzbget(Scenario):
    name = "usenet-nzbget"
    profiles = ("core", "downloads")

    def apply(self) -> None:
        forge.ensure_server()
        client = forge.Nzbget()
        # Save the original news-server values before touching the file, so a
        # run that dies half way can still be undone by the next teardown.
        original = forge.read_state(STATE).get("server") or client.read_fields()
        forge.write_state(STATE, {"server": original})
        client.point_at_lab(original)
        client.clean()
        client.pause_seed()

        client.append(forge.COMPLETE)
        forge.wait_for(
            lambda: client.history_item(forge.COMPLETE),
            lambda item: item is not None
            and str(item.get("Status", "")).startswith("SUCCESS"),
            what="NZBGet finishing the complete job",
        )

        client.append(forge.MISSING)
        forge.wait_for(
            lambda: client.history_item(forge.MISSING),
            lambda item: item is not None
            and str(item.get("Status", "")).startswith("FAILURE"),
            what="NZBGet failing the job with missing articles",
        )

        client.append(forge.SLOW)
        forge.wait_for(
            lambda: client.group(forge.SLOW),
            lambda group: group is not None and group.get("Status") == "DOWNLOADING",
            what="NZBGet downloading the slow job",
        )

        client.append(forge.WAITING)
        forge.wait_for(
            lambda: client.group(forge.WAITING),
            lambda group: group is not None and group.get("Status") == "QUEUED",
            what="NZBGet queueing the waiting job",
        )

        paused = client.append(forge.PAUSED)
        forge.wait_for(
            lambda: client.group(forge.PAUSED),
            lambda group: group is not None,
            what="NZBGet queueing the paused job",
        )
        # The queue coordinator may still be placing the group when the append
        # returns, and a pause asked for too early is dropped. Ask again until
        # the daemon reports the group as paused.
        for _ in range(10):
            client.edit("GroupPause", paused)
            time.sleep(0.4)
            group = client.group(forge.PAUSED)
            if group is not None and group.get("Status") == "PAUSED":
                break
        else:
            raise ScenarioError("NZBGet never reported the job as paused")

    def teardown(self) -> None:
        client = forge.Nzbget()
        client.clean()
        state = forge.read_state(STATE)
        original = state.get("server")
        if original:
            client.write_fields(original)
        # The seed's specimen was running when the scenario started, so it is
        # started again here.
        client.resume_seed()
        for name in forge.JOB_NAMES:
            forge.remove_download(name)
        forge.stop_server()
        forge.drop_state(STATE)

    def verify(self) -> None:
        client = forge.Nzbget()
        config = client.config()
        if config.get("Server1.Host") != "host.docker.internal":
            raise ScenarioError(
                f"NZBGet reads host {config.get('Server1.Host')!r}, "
                "not host.docker.internal"
            )
        if config.get("Server1.Port") != str(forge.NNTP_PORT):
            raise ScenarioError(
                f"NZBGet reads port {config.get('Server1.Port')}, "
                f"not {forge.NNTP_PORT}"
            )
        if config.get("Server1.Encryption") != "no":
            raise ScenarioError("NZBGet still asks the lab server for TLS")
        if config.get("Server1.Connections") != "1":
            raise ScenarioError(
                f"NZBGet reads {config.get('Server1.Connections')} connections, not 1"
            )

        expected = {
            forge.SLOW: "DOWNLOADING",
            forge.WAITING: "QUEUED",
            forge.PAUSED: "PAUSED",
        }
        for name, status in expected.items():
            group = client.group(name)
            if group is None or group.get("Status") != status:
                raise ScenarioError(
                    f"{name} reads {group and group.get('Status')}, not {status}"
                )

        completed = client.history_item(forge.COMPLETE)
        if completed is None or not str(completed.get("Status", "")).startswith(
            "SUCCESS"
        ):
            raise ScenarioError(
                f"the complete job reads {completed and completed.get('Status')}"
            )
        forge.verify_download(
            "nzbget",
            forge.COMPLETE,
            "Cupola.Testlab.Usenet.mkv",
            3 * 64 * 1024,
        )
        failed = client.history_item(forge.MISSING)
        if failed is None or not str(failed.get("Status", "")).startswith("FAILURE"):
            raise ScenarioError(
                f"the missing job reads {failed and failed.get('Status')}"
            )

        # D-15: the two reads behind the History, Feeds and Messages tabs. A
        # feed is a numbered group with a URL, the rule the app's own parser
        # uses (``nzbgetFeedsFromConfig``); ``FeedHistory`` is a global option
        # and not a feed.
        feeds = [
            name
            for name, value in config.items()
            if re.fullmatch(r"Feed\d+\.Url", name, re.IGNORECASE) and value.strip()
        ]
        if feeds:
            raise ScenarioError(f"NZBGet has feeds configured: {feeds}")
        if not client.call("log", [0, 50]):
            raise ScenarioError("NZBGet reports no log entries")

    def verify_absent(self) -> None:
        client = forge.Nzbget()
        config = client.config()
        if config.get("Server1.Host") == "host.docker.internal":
            raise ScenarioError("NZBGet still points Server1 at the lab")
        for group in client.groups():
            if group.get("NZBName") in forge.JOB_NAMES:
                raise ScenarioError(f"NZBGet still has the job {group.get('NZBName')}")
        for item in client.history() + list(client.call("history", [True]) or []):
            if item.get("Name") in forge.JOB_NAMES:
                raise ScenarioError(f"NZBGet still has {item.get('Name')} in history")
        if forge.scenario_state(STATE).exists():
            raise ScenarioError("the scenario state was not removed")


SCENARIO = UsenetNzbget()
