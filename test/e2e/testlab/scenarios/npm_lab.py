"""NPM's real proxy hosts, certificate, access list and view-only account:
the flow catalogue's I-04, I-05, I-06 and I-08.

The state itself is arranged by ``npm_lab``; this module is the scenario the
lab's command knows, so ``apply``, ``verify`` and ``teardown`` run the same
code the e2e test's ``testlab.py scenario`` calls see.

``apply`` is idempotent: hosts are matched by domain, the certificate by its
nice name (replaced only when it has left the amber window), the access list by
name and the account by email, whose password is the one in the state file so
a second run keeps the credential the test is about to carry.
"""

from __future__ import annotations

import npm_lab as lab

from .base import Scenario


class NpmLab(Scenario):
    name = "npm-lab"
    profiles = ("core",)

    def apply(self) -> None:
        lab.apply()

    def teardown(self) -> None:
        lab.teardown()

    def verify(self) -> None:
        lab.verify()

    def verify_absent(self) -> None:
        lab.verify_absent()


SCENARIO = NpmLab()
