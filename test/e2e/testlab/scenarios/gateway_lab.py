"""The gateway the app meets in front of a service.

One process, one port, and every part a gateway can take: Cloudflare Access,
a proxy's own password, required custom headers, a sign-in page, and another
application answering in the service's place.
"""

from __future__ import annotations

import gateway_lab
from scenarios.base import Scenario, ScenarioError


class GatewayLab(Scenario):
    name = "gateway-lab"
    profiles = ("core",)

    def apply(self) -> None:
        gateway_lab.start()

    def teardown(self) -> None:
        gateway_lab.stop()

    def verify(self) -> None:
        status, _ = gateway_lab.ask("service")
        if status != 200:
            raise ScenarioError(f"the gateway does not answer: {status}")
        status, _ = gateway_lab.ask("cf")
        if status != 302:
            raise ScenarioError(f"the Access login does not redirect: {status}")
        status, _ = gateway_lab.ask("cf", {"CF-Access-Client-Id": gateway_lab.TOKEN_ID})
        if status != 200:
            raise ScenarioError(f"the service token was refused: {status}")
        status, _ = gateway_lab.ask("basic")
        if status != 401:
            raise ScenarioError(f"the password prompt did not refuse: {status}")
        status, _ = gateway_lab.ask("basic", {"Authorization": gateway_lab.basic_header()})
        if status != 200:
            raise ScenarioError(f"the password was refused: {status}")
        status, _ = gateway_lab.ask("headers")
        if status != 403:
            raise ScenarioError(f"the custom header was not required: {status}")
        status, body = gateway_lab.ask("signin")
        if status != 200 or "password" not in body:
            raise ScenarioError("the sign-in page is not one")

    def verify_absent(self) -> None:
        if gateway_lab.listening():
            raise ScenarioError("the gateway is still listening")
        status, _ = gateway_lab.ask("service")
        if status == 200:
            raise ScenarioError("the gateway still answers")


SCENARIO = GatewayLab()
