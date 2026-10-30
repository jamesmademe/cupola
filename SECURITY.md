# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| Cupola 1.0.x | Yes |
| Seekarr up to 0.8.0 | No |

Fixes land on the latest 1.0.x release only. If you still run Seekarr, update to
Cupola.

## Reporting a vulnerability

Please do not open a public issue, discussion or pull request for a vulnerability.
Report it privately instead, in either of these ways:

- GitHub private vulnerability reporting:
  <https://github.com/matthw-labs/cupola/security/advisories/new>
- Email: [matthw.labs@gmail.com](mailto:matthw.labs@gmail.com)

Include the version and platform, what an attacker can do, and the steps to
reproduce it. A proof of concept helps, but leave out real credentials and real
server addresses.

## What to expect

- Cupola has a single maintainer, working in spare time.
- You will get an acknowledgement within a week.
- There is no bug bounty.
- A confirmed issue is fixed in a patch release. The advisory is published after
  that release ships, with credit to you unless you prefer otherwise.

## Scope

Cupola is a client app with no Cupola server and no account. It talks directly to
the user's own instances and stores on the device what it needs to reach them:
API keys, session cookies, proxy passwords, access tokens and certificate pins.

In scope:

- Secrets leaking out of secure storage, into logs, error text, crash output,
  backups, the code that sets up another device, or the clipboard.
- Requests, credentials or access headers reaching a host other than the one the
  user configured for that service.
- Ways around certificate pinning (trust on first use), including through artwork
  and background requests.
- Anything in this repository's code that lets a malicious server or network
  attacker go further than the user intended.

Out of scope:

- Vulnerabilities in the services Cupola connects to (Sonarr, Radarr, Seerr,
  qBittorrent and the others). Report those to their own projects.
- Attacks that need an unlocked device or a compromised operating system.
