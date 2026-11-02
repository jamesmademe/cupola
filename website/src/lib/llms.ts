// The site in plain Markdown, for language models and the assistants that
// answer people's questions with them (https://llmstxt.org).
import { site } from '../config';
import { allPages } from '../data/pages';
import { faq } from '../data/faq';
import { services } from './repo';
import { abs, version } from './seo';

const d = site.downloads;

const text = (html: string) =>
  html
    .replace(/<a href="([^"]+)">([^<]+)<\/a>/g, (_, href: string, label: string) => `[${label}](${href.startsWith('/') ? abs(href) : href})`)
    .replace(/<[^>]+>/g, '');

export function llms(): string {
  const list = allPages
    .filter((p) => p.path !== '/')
    .map((p) => `- [${p.name}](${abs(p.path)}): ${p.description}`)
    .join('\n');
  return `# Cupola

> ${site.description}

Cupola (formerly Seekarr) is a native client for the self-hosted media stack: one app for ${services().length} services, on iOS, Android and macOS, with Windows and Linux builds. It is free and open source (Apache-2.0), has no Cupola account, server or telemetry, and connects directly to the user's own instances on the home network, over a VPN or through a reverse proxy. It is not a media player. Current version: ${version}.

Services: ${services().map((s) => s.name).join(', ')}.

## Pages

${list}

## Source

- [GitHub repository](${site.repo}): source, releases, issues
- [Full text for language models](${abs('/llms-full.txt')})
`;
}

export function llmsFull(): string {
  const rows = services()
    .map((s) => `| ${s.name}${s.aka ? ` (${s.aka})` : ''} | ${s.category} | ${s.what} | ${s.auth} | ${s.control} | ${{ verified: 'Verified on a real server', partial: 'Partly verified', untested: 'Recorded answers only' }[s.tested]} |`)
    .join('\n');
  const qa = Object.values(faq)
    .map((x) => `### ${x.q}\n\n${text(x.a)}`)
    .join('\n\n');
  return `${llms()}
## What Cupola does

- Home: what arrived on the server, what comes out next, what the person was halfway through, and what needs attention, as modules they keep, order or leave out.
- Discover (through Seerr, Overseerr or Jellyseerr): trending, a calendar, genres, networks, studios, people, decades, collections, and one search across Seerr, Radarr, Sonarr, Jellyfin and Plex. A title's page shows where it stands on the server and offers adding it to Radarr or Sonarr, requesting it, or choosing a release.
- Activity: "Needs you" lists faults (a stuck download, files waiting for import, a stopped container, a disk with errors, an unreachable service) in plain words with the remedy for the cause. Downloads from qBittorrent, Transmission, SABnzbd and NZBGet in one list.
- Stack: every service in its own room with its own tabs.
- Household: a member signs in to Seerr with their own account (email, Jellyfin or Plex) and gets Home, Discover and their requests, without operator controls.
- Widgets and notifications on iOS and Android, computed on the device; no push server.
- Home and away: a connection can carry a second address; Cupola uses whichever answers. It does not create a tunnel.
- Security: keys in the Keychain or Keystore; self-signed certificates trusted on first use and pinned per host; artwork from TMDB's image CDN; plex.tv only for a Plex sign-in to Seerr.

## Services

| Service | Category | What Cupola does | Signs in with | Control | Tested |
| --- | --- | --- | --- | --- | --- |
${rows}

## Install

- iPhone and iPad: TestFlight beta${d.testflight ? '' : ' (not open yet)'}${d.ipa ? ', or an unsigned .ipa to sideload' : ''}.
- Android: APK from GitHub releases${d.apk ? '' : ' (not out yet)'}.
- Mac: ${d.testflight ? 'TestFlight beta' : 'TestFlight beta (not open yet)'}${d.macos ? ', or a signed and notarized .dmg' : ''}.
- Windows and Linux: builds in every GitHub release${d.apk || d.macos ? '' : ' (from the first one, not out yet)'}, not yet tested on real machines.
- From source: Flutter; see the repository.

Details: ${abs('/install/')}

## Questions

${qa}
`;
}
