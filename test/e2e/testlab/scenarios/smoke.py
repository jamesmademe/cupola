"""A smoke scenario: a Prowlarr tag that exists only while the scenario runs.

It proves the control plane end to end without touching media: the tag is
created through Prowlarr's API, verified by reading it back, removed by
``teardown``, and its absence is verified too. The lab starts with no tag of
this name, and a second ``apply`` is a no-op.
"""

from __future__ import annotations

from .base import Scenario, ScenarioError, request, require_ok

LABEL = "testlab-smoke"
PROWLARR = "http://127.0.0.1:9696"
HEADERS = {"X-Api-Key": "test-key"}


def _tags() -> list[dict]:
    status, body = request(f"{PROWLARR}/api/v1/tag", headers=HEADERS)
    require_ok(status, body, "Prowlarr tags")
    if not isinstance(body, list):
        raise ScenarioError(f"Prowlarr returned {type(body).__name__}, not a list")
    return body


def _matching() -> list[dict]:
    return [tag for tag in _tags() if tag.get("label") == LABEL]


class SmokeScenario(Scenario):
    name = "smoke"
    profiles = ("core",)

    def apply(self) -> None:
        if _matching():
            return
        status, body = request(
            f"{PROWLARR}/api/v1/tag",
            method="POST",
            payload={"label": LABEL},
            headers=HEADERS,
        )
        require_ok(status, body, f"creating the tag {LABEL!r}")

    def teardown(self) -> None:
        for tag in _matching():
            status, body = request(
                f"{PROWLARR}/api/v1/tag/{tag['id']}",
                method="DELETE",
                headers=HEADERS,
            )
            require_ok(status, body, f"deleting the tag {LABEL!r}")

    def verify(self) -> None:
        if not _matching():
            raise ScenarioError(f"the tag {LABEL!r} is not in Prowlarr")

    def verify_absent(self) -> None:
        if _matching():
            raise ScenarioError(f"the tag {LABEL!r} is still in Prowlarr")


SCENARIO = SmokeScenario()
