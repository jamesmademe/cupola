"""The service answers, but far too late.

A latency the client outwaits is the amber line, not the red one."""

from __future__ import annotations

import faults_lab


class FaultSlow(faults_lab.FaultScenario):
    name = "fault-slow"
    mode = "slow"
    milliseconds = 2000


SCENARIO = FaultSlow()
