"""The service accepts the connection and never answers it.

A timeout is not a refusal: the host was reached, and the app says so."""

from __future__ import annotations

import faults_lab


class FaultTimeout(faults_lab.FaultScenario):
    name = "fault-timeout"
    mode = "timeout"


SCENARIO = FaultTimeout()
