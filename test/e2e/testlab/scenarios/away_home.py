"""The same service at a second address, switched off on its own.

The away address is the "out of home" one: a second listener on the same
upstream that answers nothing while it is off. The address at home keeps
answering, which is the case the app draws as "only works at home".
"""

from __future__ import annotations

import faults_lab
from scenarios.base import Scenario, ScenarioError


class AwayHome(Scenario):
    name = "away-home"
    profiles = ("core",)

    def apply(self) -> None:
        faults_lab.away(faults_lab.SERVICE, False)

    def teardown(self) -> None:
        faults_lab.away(faults_lab.SERVICE, True)

    def verify(self) -> None:
        answered, _ = faults_lab.probe_proxy()
        if not answered:
            raise ScenarioError("the address at home stopped answering")
        away_answered, _ = faults_lab.probe_proxy(port=faults_lab.away_port())
        if away_answered:
            raise ScenarioError("the away address still answers")

    def verify_absent(self) -> None:
        away_answered, _ = faults_lab.probe_proxy(port=faults_lab.away_port())
        if not away_answered:
            raise ScenarioError("the away address does not answer again")


SCENARIO = AwayHome()
