"""The same services at a second address, switched off on their own.

The away address is the "out of home" one: a second listener on the same
upstream that answers nothing while it is off. The address at home keeps
answering, which is the case the app draws as "only works at home".

P7 reaches six services away from home. Switching only Radarr off would leave
the other five listeners untested, and a listener the host cannot reach is not
an away address at all: each one is switched off and on again here.
"""

from __future__ import annotations

import app_config
import faults_lab
from scenarios.base import Scenario, ScenarioError


def away_services() -> list[str]:
    """The services P7 reaches away from home, once each."""
    services = {
        instance.service
        for instance in app_config.instances_for("P7")
        if instance.away
    }
    return sorted(services)


class AwayHome(Scenario):
    name = "away-home"
    profiles = ("core",)

    def apply(self) -> None:
        for service in away_services():
            faults_lab.away(service, False)

    def teardown(self) -> None:
        for service in away_services():
            faults_lab.away(service, True)

    def verify(self) -> None:
        for service in away_services():
            answered, _ = faults_lab.probe_proxy(service)
            if not answered:
                raise ScenarioError(
                    f"the address at home of {service} stopped answering"
                )
            away_answered, _ = faults_lab.probe_proxy(
                service, port=faults_lab.away_port(service)
            )
            if away_answered:
                raise ScenarioError(
                    f"the away address of {service} still answers"
                )

    def verify_absent(self) -> None:
        for service in away_services():
            away_answered, _ = faults_lab.probe_proxy(
                service, port=faults_lab.away_port(service)
            )
            if not away_answered:
                raise ScenarioError(
                    f"the away address of {service} does not answer again"
                )


SCENARIO = AwayHome()
