"""The edge in front of the services: three origins with a certificate of their
own, and a rotation.

The edge is up while the scenario is applied and gone when it is torn down.
It is the one service the lab starts on demand, so the rest of the lab never
pays for it and the certificates it holds can be thrown away and made again
at will.
"""

from __future__ import annotations

import re
import ssl

import caddy_lab
from scenarios.base import Scenario, ScenarioError


class CaddyEdge(Scenario):
    name = "caddy-edge"
    profiles = ("core",)

    def apply(self) -> None:
        caddy_lab.up()

    def teardown(self) -> None:
        caddy_lab.down()

    def verify(self) -> None:
        values = caddy_lab.fingerprints()
        for origin, value in values.items():
            if not re.fullmatch(r"[0-9a-f]{64}", value):
                raise ScenarioError(
                    f"the {origin} origin has no SHA-256 fingerprint: {value}"
                )
        if len(set(values.values())) != len(values):
            raise ScenarioError(f"the origins share a certificate: {values}")

    def verify_absent(self) -> None:
        for origin in caddy_lab.ORIGINS:
            try:
                caddy_lab.fingerprint(origin)
            except (OSError, ssl.SSLError):
                continue
            raise ScenarioError(
                f"the {origin} origin is still presenting a certificate"
            )


SCENARIO = CaddyEdge()
