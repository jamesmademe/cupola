"""Dockge's three stacks in the lab's own ``docker:dind``: the flows I-01 to
I-03 of the flow catalogue, as state the app can read.

The stacks are the three compose files in ``test/e2e/testlab/dind_stacks``:
one that writes a log line a second, one that is never started, one that exits
1. They are not written by hand into ``/opt/stacks``: ``apply`` sends them to
Dockge with ``saveStack``, so Dockge's own database, path and permissions are
the ones at work, and ``getStack`` reads them back byte for byte.

What the lab can and cannot reach is measured, never assumed. Dockge's ``Start``
runs ``docker compose up -d``; whether the dind can create that container is
decided by the dind's storage, which in this lab is a bind mount of the state
folder on the Mac and therefore refuses overlayfs. ``apply`` deploys the log
stack and records both the answer and the daemon's own words from the action
terminal. The marker says ``runtime.available``; the e2e verifies the branch
that holds and prints the other one's evidence, instead of a green that lies.

``teardown`` deletes exactly the stacks ``apply`` created (and refuses, on a
first apply, to overwrite a stack of the same name it did not create), removes
the crate image when this scenario loaded it, and takes its marker out.
"""

from __future__ import annotations

import asyncio

import dockge_lab as lab

from .base import Scenario, ScenarioError

# The terminal Dockge uses for a stack's combined log, as the app's client
# spells it (`DockgeClient.combinedTerminalName`, endpoint empty for the hub).
def combined(name: str) -> str:
    return f"combined--{name}"


def compose_terminal(name: str) -> str:
    return f"compose--{name}"


class DockgeLabScenario(Scenario):
    name = "dockge-lab"
    profiles = ("infra",)

    # -- apply ------------------------------------------------------------

    def apply(self) -> None:
        asyncio.run(self._apply())

    async def _apply(self) -> None:
        marker = lab.load_marker()
        owned = list(marker.get("created") or [])
        image = lab.ensure_image()
        marker["image"] = image
        marker.setdefault("actions", {})
        lab.save_marker(marker)

        async with lab.session() as dockge:
            await dockge.refresh()
            present = dockge.names()
            marker.setdefault("before", [name for name in present if name not in owned])

            created: list[str] = []
            for name in lab.STACKS:
                if name in present and name not in owned:
                    raise ScenarioError(
                        f"Dockge already has a stack called {name!r} that this "
                        "scenario did not create; it will not overwrite it"
                    )
                compose = lab.compose_for(name)
                is_add = name not in dockge.stacks
                try:
                    await dockge.save(name, compose, is_add=is_add)
                except lab.DockgeRefused as error:
                    marker["actions"].setdefault(name, {})["save"] = {
                        "ok": False,
                        "msg": error.message,
                    }
                    lab.save_marker(marker)
                    raise ScenarioError(
                        f"Dockge refused to save {name}: {error.message}"
                    ) from error
                created.append(name)
                marker["created"] = sorted(set(owned) | set(created))
                marker["actions"].setdefault(name, {})["save"] = {"ok": True}
                lab.save_marker(marker)

            # The log stack is the one that is meant to run, so it is the probe
            # for the dind's runtime: a deploy that works means containers work.
            await dockge.refresh()
            mark = len(dockge.output)
            runtime: dict = {"available": False, "evidence": ""}
            try:
                await dockge.deploy(lab.LOG_STACK, lab.compose_for(lab.LOG_STACK), is_add=False)
                await dockge.wait_status(lab.LOG_STACK, (lab.RUNNING,), timeout=40)
                runtime = lab.probe_runtime()
            except (lab.DockgeRefused, lab.DockgeLabError) as error:
                runtime = {
                    "available": False,
                    "evidence": _evidence(error, dockge, mark, compose_terminal(lab.LOG_STACK)),
                }
            marker["runtime"] = runtime
            marker["actions"][lab.LOG_STACK]["deploy"] = {
                "ok": runtime["available"],
                "msg": "" if runtime["available"] else runtime["evidence"],
            }
            lab.save_marker(marker)

            # The failing stack: with a working runtime it deploys and settles on
            # Stopped; without one its deploy is refused like the log stack's, and
            # that refusal is recorded as its own evidence rather than copied.
            mark = len(dockge.output)
            marker["actions"][lab.CRASH_STACK] = {"save": {"ok": True}}
            try:
                await dockge.deploy(
                    lab.CRASH_STACK, lab.compose_for(lab.CRASH_STACK), is_add=False
                )
                if runtime["available"]:
                    await dockge.wait_status(lab.CRASH_STACK, (lab.EXITED,), timeout=40)
                marker["actions"][lab.CRASH_STACK]["deploy"] = {"ok": True}
            except (lab.DockgeRefused, lab.DockgeLabError) as error:
                marker["actions"][lab.CRASH_STACK]["deploy"] = {
                    "ok": False,
                    "msg": _evidence(
                        error, dockge, mark, compose_terminal(lab.CRASH_STACK)
                    ),
                }
            lab.save_marker(marker)

            # The idle stack is created and left alone. If a run with a working
            # runtime left it up, take it down so "never started" is true again.
            await dockge.refresh()
            if dockge.status(lab.IDLE_STACK) in (lab.RUNNING, lab.EXITED, lab.CREATED_STACK):
                await dockge.down(lab.IDLE_STACK)
                await dockge.refresh()

            marker["statuses"] = {
                name: dockge.status(name) for name in lab.STACKS
            }
            lab.save_marker(marker)

    # -- verify -----------------------------------------------------------

    def verify(self) -> None:
        asyncio.run(self._verify())

    async def _verify(self) -> None:
        marker = lab.load_marker()
        if not marker:
            raise ScenarioError("the scenario left no marker: apply it first")
        created = marker.get("created") or []
        for name in lab.STACKS:
            if name not in created:
                raise ScenarioError(f"the marker does not own {name!r}")
        if lab.dind_image_id() is None:
            raise ScenarioError(f"{lab.BASE_IMAGE} is not in the dind any more")

        runtime = marker.get("runtime") or {}
        available = bool(runtime.get("available"))
        if available and not runtime.get("evidence"):
            raise ScenarioError("the marker says the runtime works but gives no proof")

        async with lab.session() as dockge:
            await dockge.refresh()
            for name in lab.STACKS:
                if name not in dockge.stacks:
                    raise ScenarioError(f"Dockge does not list {name!r}")
                row = dockge.stacks[name]
                if row.get("composeFileName") not in (None, "compose.yaml"):
                    raise ScenarioError(
                        f"{name} is not the compose.yaml this scenario wrote: {row}"
                    )
                detail = await dockge.stack(name)
                expected = lab.compose_for(name)
                if (detail.get("composeYAML") or "").strip() != expected.strip():
                    raise ScenarioError(
                        f"Dockge holds a different compose file for {name}"
                    )
                await dockge.services(name)

            for name in marker.get("before") or []:
                if name not in dockge.stacks:
                    raise ScenarioError(
                        f"the scenario lost the stack {name!r} it did not create"
                    )

            statuses = {name: dockge.status(name) for name in lab.STACKS}
            recorded = marker.get("statuses") or {}
            if statuses != recorded:
                raise ScenarioError(
                    f"the stacks moved since apply: {statuses} != {recorded}"
                )
            if available:
                wanted = {
                    lab.LOG_STACK: lab.RUNNING,
                    lab.IDLE_STACK: lab.CREATED_FILE,
                    lab.CRASH_STACK: lab.EXITED,
                }
                for name, status in wanted.items():
                    if statuses.get(name) != status:
                        raise ScenarioError(
                            f"{name} reads {lab.STATUS_LABEL.get(statuses.get(name), statuses.get(name))}, "
                            f"not {lab.STATUS_LABEL[status]}"
                        )

            # I-03's transport: joining the combined log is accepted, and the
            # socket carries whatever the stack has to say. On a dind that cannot
            # run containers there is nothing to say, and that is the finding,
            # not a failure of the join.
            mark = len(dockge.output)
            await dockge.join_combined(lab.LOG_STACK)
            await asyncio.sleep(2.0)
            chunks = dockge.chunks(combined(lab.LOG_STACK), since=mark)
            if available and not any("cupola-log" in chunk.text for chunk in chunks):
                raise ScenarioError(
                    "the combined log of the running stack said nothing in two seconds"
                )
            if not available and chunks:
                raise ScenarioError(
                    "the combined log has output although the stack never ran: "
                    f"{[chunk.text for chunk in chunks[:3]]}"
                )

    # -- teardown ---------------------------------------------------------

    def teardown(self) -> None:
        asyncio.run(self._teardown())

    async def _teardown(self) -> None:
        marker = lab.load_marker()
        if not marker:
            raise ScenarioError("there is no marker to tear down")
        created = list(marker.get("created") or [])

        async with lab.session() as dockge:
            await dockge.refresh()
            for name in sorted(created, reverse=True):
                if name not in dockge.stacks:
                    continue
                try:
                    await dockge.delete(name)
                except lab.DockgeRefused as error:
                    # Dockge's delete is `docker compose down`, which refuses an
                    # empty compose file: a stack emptied through the socket
                    # cannot be deleted until a real file is written back.
                    if not (await dockge.stack(name)).get("composeYAML", "").strip():
                        await dockge.save(
                            name, lab.compose_for(name), is_add=False
                        )
                        await dockge.delete(name)
                    else:
                        raise ScenarioError(
                            f"Dockge refused to delete {name}: {error.message}"
                        ) from error
                if name in (await dockge.refresh()):
                    raise ScenarioError(f"{name} is still listed after its delete")

            for name in marker.get("before") or []:
                if name not in dockge.stacks:
                    raise ScenarioError(
                        f"the teardown lost the stack {name!r} it did not create"
                    )

        for name in created:
            if lab.dind_containers(name):
                raise ScenarioError(f"{name} left containers in the dind behind")
        image = marker.get("image") or {}
        if image.get("loaded"):
            lab.remove_image()
            if image.get("sourceLoaded"):
                lab.remove_image(str(image.get("source") or lab.SOURCE_IMAGE))
        lab.forget_marker()

    def verify_absent(self) -> None:
        asyncio.run(self._verify_absent())

    async def _verify_absent(self) -> None:
        if lab.load_marker():
            raise ScenarioError("the scenario left its marker behind")
        for name in lab.STACKS:
            if lab.dind_containers(name):
                raise ScenarioError(f"{name} still has containers in the dind")
        projects = lab.dind_projects()
        for name in lab.STACKS:
            if name in projects:
                raise ScenarioError(f"the dind still knows a project called {name}")
        async with lab.session() as dockge:
            await dockge.refresh()
            for name in lab.STACKS:
                if name in dockge.stacks:
                    raise ScenarioError(f"Dockge still lists {name!r}")


def _evidence(
    error: Exception, dockge: lab.Dockge, mark: int, terminal: str
) -> str:
    """The refusal, and the daemon's own words the action terminal carried."""
    lines = [str(error)]
    for chunk in dockge.chunks(terminal, since=mark):
        text = chunk.text
        if text and text not in lines:
            lines.append(text)
    return " · ".join(lines[-3:])


SCENARIO = DockgeLabScenario()
