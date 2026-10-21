"""Prowlarr's tags and applications, and the sync that carries an indexer into
the arrs. The flow catalogue's A-16.

The scenario works beside the lab, never through it:

* a tag is created, given to a throwaway indexer, read back through
  ``/tag/detail`` (what the tag manager shows) and deleted;
* a second application is added next to the seeded four, tested, listed and
  deleted. It is a Sonarr pointed at the lab's own Sonarr, so the add path is
  exercised without a fifth server and without pushing an indexer anywhere;
* a throwaway Torznab indexer is added, and ``ApplicationIndexerSync`` is run
  the way the app's "Sync App Indexers" button runs it. The indexer reaches
  Radarr, and the seeded one stays there.

The fake indexer advertises Movies only, so Prowlarr's category filter keeps
the throwaway out of Sonarr, Lidarr and Readarr. ``teardown`` records those
three before the sync and proves the sync left them alone; ``verify`` checks
it again after the sync has run.

Deleting an indexer does not remove the copy an app holds: only a sync does.
``teardown`` therefore deletes, syncs, and waits for Radarr to drop the copy,
then proves the seeded indexer is still the one Radarr queries.
"""

from __future__ import annotations

import copy
import json

import prowlarr_lab as lab

from .base import STATE_ROOT, Scenario, ScenarioError

TAG = "cupola-testlab"
INDEXER = "Cupola testlab sync probe"
APP = "Cupola testlab app"
MARKER = STATE_ROOT / "backup" / "prowlarr_apps" / "state.json"


def _load() -> dict:
    if not MARKER.exists():
        return {}
    try:
        return json.loads(MARKER.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ScenarioError(f"the scenario marker is unreadable: {error}") from error


def _forget() -> None:
    """Take the marker out, and the folder it lived in when it is the last one."""
    if MARKER.exists():
        MARKER.unlink()
    if MARKER.parent.is_dir() and not any(MARKER.parent.iterdir()):
        MARKER.parent.rmdir()


def _save(marker: dict) -> None:
    MARKER.parent.mkdir(parents=True, exist_ok=True)
    MARKER.write_text(json.dumps(marker, indent=2, sort_keys=True), encoding="utf-8")


def _others() -> dict[str, list[str]]:
    """The apps that must not receive a movie-only indexer, as they are now."""
    return {
        name: lab.app_indexer_names(name)
        for name in lab.APPLICATIONS
        if name != lab.MOVIE_APP
    }


def _application_payload() -> dict:
    """A second Sonarr application, cloned from the seeded one.

    Prowlarr masks the saved key in ``GET /applications`` and refuses a masked
    key in ``POST /applications/test``, so the clone carries the lab's own.
    """
    seeded = lab.application_by_name("Sonarr")
    if seeded is None:
        raise ScenarioError("Prowlarr has no Sonarr application to clone")
    payload = copy.deepcopy(seeded)
    payload.pop("id", None)
    payload["name"] = APP
    payload["enable"] = True
    for field in payload.get("fields") or []:
        if isinstance(field, dict) and field.get("name") == "apiKey":
            field["value"] = "test-key"
    return payload


def _require_others(recorded: dict) -> None:
    current = _others()
    if current != recorded:
        raise ScenarioError(
            "an app received an indexer it should not have: the fake indexer "
            f"advertises Movies only, so only Radarr matches. {current} != {recorded}"
        )


class ProwlarrApps(Scenario):
    name = "prowlarr-apps"
    profiles = ("core",)

    def apply(self) -> None:
        seeded = lab.seeded()
        if not seeded.get("enable"):
            raise ScenarioError(
                f"the lab's {lab.SEEDED_INDEXER!r} indexer is disabled; "
                "this scenario does not fix lab state"
            )
        marker = _load()
        recorded = marker.get("seeded")
        if isinstance(recorded, dict) and recorded != lab.summary(seeded):
            raise ScenarioError(
                f"the lab's indexer changed since the marker was written: "
                f"{lab.summary(seeded)} != {recorded}"
            )
        marker["seeded"] = lab.summary(seeded)
        marker.setdefault("apps", _others())
        _save(marker)

        tag = lab.tag_by_label(TAG)
        if tag is None:
            tag = lab.create_tag(TAG)
        marker["tag"] = tag["id"]
        _save(marker)

        item = lab.by_name(INDEXER)
        if item is None:
            item = lab.create(INDEXER)
        item["tags"] = [tag["id"]]
        item = lab.save(item)
        marker["indexer"] = item["id"]
        _save(marker)
        if list(item.get("tags") or []) != [tag["id"]]:
            raise ScenarioError(f"{INDEXER} did not keep its tag: {item.get('tags')}")

        # Prowlarr pushes a new indexer to a matching app on its own; wait for
        # that before the explicit sync, so the sync is measured on a steady
        # state rather than racing the add.
        lab.wait_app(lab.MOVIE_APP, f"{INDEXER}{lab.SYNC_SUFFIX}", present=True)

        application = lab.application_by_name(APP)
        if application is None:
            payload = _application_payload()
            lab.test_application(payload)
            application = lab.create_application(payload)
        marker["app"] = application["id"]
        _save(marker)

        lab.test_application(lab.require_application(APP))
        lab.sync_apps()
        lab.wait_app(lab.MOVIE_APP, f"{INDEXER}{lab.SYNC_SUFFIX}", present=True)
        _require_others(marker["apps"])

    def teardown(self) -> None:
        marker = _load()

        application = lab.application_by_name(APP)
        if application is not None:
            lab.delete_application(application["id"])
            if lab.application_by_name(APP) is not None:
                raise ScenarioError(f"{APP!r} survived the application delete")

        item = lab.by_name(INDEXER)
        if item is not None:
            lab.bulk_delete([item["id"]])
            if lab.by_name(INDEXER) is not None:
                raise ScenarioError(f"{INDEXER!r} survived the indexer delete")
        lab.sync_apps()
        lab.wait_app(lab.MOVIE_APP, f"{INDEXER}{lab.SYNC_SUFFIX}", present=False)

        tag = lab.tag_by_label(TAG)
        if tag is not None:
            lab.delete_tag(tag["id"])
            if lab.tag_by_label(TAG) is not None:
                raise ScenarioError(f"the tag {TAG!r} survived the delete")
            if any(
                entry.get("label") == TAG for entry in lab.tag_detail()
            ):
                raise ScenarioError(f"the tag {TAG!r} is still in /tag/detail")

        recorded = marker.get("apps")
        if isinstance(recorded, dict):
            _require_others(recorded)

        seeded = marker.get("seeded")
        if isinstance(seeded, dict) and seeded.get("id"):
            current = lab.require_by_name(lab.SEEDED_INDEXER)
            if lab.summary(current) != seeded:
                restore = {
                    key: seeded[key]
                    for key in ("enable", "priority", "appProfileId")
                    if seeded.get(key) is not None
                }
                lab.bulk([seeded["id"]], **restore)
        _forget()

    def verify(self) -> None:
        marker = _load()
        expected = marker.get("seeded")
        seeded = lab.require_by_name(lab.SEEDED_INDEXER)
        if isinstance(expected, dict) and lab.summary(seeded) != expected:
            raise ScenarioError(
                f"the seeded indexer changed: {lab.summary(seeded)} != {expected}"
            )

        item = lab.require_by_name(INDEXER)
        if not item.get("enable"):
            raise ScenarioError(f"{INDEXER} is not enabled")
        tag = lab.tag_by_label(TAG)
        if tag is None:
            raise ScenarioError(f"Prowlarr lists no {TAG!r} tag")
        if list(item.get("tags") or []) != [tag["id"]]:
            raise ScenarioError(
                f"{INDEXER} reads tags {item.get('tags')}, not the {TAG!r} tag"
            )
        detail = next(
            (entry for entry in lab.tag_detail() if entry.get("label") == TAG), None
        )
        if detail is None:
            raise ScenarioError(f"/tag/detail does not list {TAG!r}")
        if item["id"] not in (detail.get("indexerIds") or []):
            raise ScenarioError(
                f"/tag/detail does not tie {TAG!r} to {INDEXER}: {detail}"
            )

        application = lab.require_application(APP)
        lab.test_application(application)

        names = lab.app_indexer_names(lab.MOVIE_APP)
        for wanted in (
            f"{INDEXER}{lab.SYNC_SUFFIX}",
            f"{lab.SEEDED_INDEXER}{lab.SYNC_SUFFIX}",
        ):
            if wanted not in names:
                raise ScenarioError(f"{lab.MOVIE_APP} does not hold {wanted!r}: {names}")
        recorded = marker.get("apps")
        if isinstance(recorded, dict):
            _require_others(recorded)

    def verify_absent(self) -> None:
        if lab.application_by_name(APP) is not None:
            raise ScenarioError(f"{APP!r} is still in Prowlarr")
        if lab.by_name(INDEXER) is not None:
            raise ScenarioError(f"{INDEXER!r} is still in Prowlarr")
        if lab.tag_by_label(TAG) is not None:
            raise ScenarioError(f"the tag {TAG!r} is still in Prowlarr")
        for application in lab.APPLICATIONS:
            names = lab.app_indexer_names(application)
            if f"{INDEXER}{lab.SYNC_SUFFIX}" in names:
                raise ScenarioError(f"{application} still holds {INDEXER!r}: {names}")
        names = lab.app_indexer_names(lab.MOVIE_APP)
        if f"{lab.SEEDED_INDEXER}{lab.SYNC_SUFFIX}" not in names:
            raise ScenarioError(f"{lab.MOVIE_APP} lost the lab's indexer: {names}")
        if MARKER.exists():
            raise ScenarioError("the scenario left its marker behind")


SCENARIO = ProwlarrApps()
