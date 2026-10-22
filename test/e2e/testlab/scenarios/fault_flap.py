"""The link is half broken: some connections die, some do not.

An intermittent link is what a flapping connection reads like at the socket,
and it is repeatable without a daemon behind it."""

from __future__ import annotations

import faults_lab


class FaultFlap(faults_lab.FaultScenario):
    name = "fault-flap"
    mode = "flap"


SCENARIO = FaultFlap()
