"""The service drops the connection: a reset peer on its proxy.

The app reads this as "did not answer", the red line, and the service
comes back when the toxic is taken away."""

from __future__ import annotations

import faults_lab


class FaultDown(faults_lab.FaultScenario):
    name = "fault-down"
    mode = "down"


SCENARIO = FaultDown()
