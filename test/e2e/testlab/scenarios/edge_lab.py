"""The edge in front of the services: a certificate of its own, and a rotation.

The edge is up while the scenario is applied and gone when it is torn down, and
the rotation is the lab's own: a new certificate, a new fingerprint, and the
old pin stops working.
"""

from __future__ import annotations

import ssl

import edge_lab
from scenarios.base import Scenario, ScenarioError


class EdgeLab(Scenario):
    name = "edge-lab"
    profiles = ("core",)

    def apply(self) -> None:
        edge_lab.up()

    def teardown(self) -> None:
        edge_lab.stop()

    def verify(self) -> None:
        try:
            value = edge_lab.fingerprint()
        except (OSError, ssl.SSLError) as error:
            raise ScenarioError(f"the edge has no certificate: {error}")
        if len(value) != 64:
            raise ScenarioError(f"the fingerprint is not a SHA-256: {value}")

    def verify_absent(self) -> None:
        try:
            edge_lab.fingerprint()
        except (OSError, ssl.SSLError):
            return
        raise ScenarioError("the edge is still presenting a certificate")


SCENARIO = EdgeLab()
