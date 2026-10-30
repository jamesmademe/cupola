# Changelog

## 1.0.0-beta.1

The first release of Cupola, published as a beta. Everything before it was published
as Seekarr (up to 0.8.0) and covered five services; this one is a new app rather than
an update. The [release notes](https://github.com/matthw-labs/cupola/releases/tag/v1.0.0-beta.1)
go through every area in detail.

### Coming from Seekarr

- Cupola installs **beside** Seekarr and starts empty: the Android package changed
  from `labs.matthw.seekarr` to `com.matthwlabs.cupola`, and the Apple bundle ids
  changed too. Add your services again (same addresses, same API keys), check that
  they answer, then uninstall Seekarr. *Set up another device* copies them to the
  next device.
- **Obtainium:** remove the Seekarr entry and add Cupola as a new app, with
  *Include prereleases* on while Cupola is in beta.
- The minimums went up: Android 7.0 (was 6.0), iOS 17, and macOS 12 on an Apple
  silicon Mac (Seekarr also ran on Intel Macs and on macOS 10.15).
- Cupola is released under Apache 2.0; Seekarr 0.8.0 and earlier stay under MIT
  (see `NOTICE`).

### What is in it

- **17 services in one app:** Seerr, Radarr, Sonarr, Lidarr, Readarr, Bazarr,
  qBittorrent, Transmission, SABnzbd, NZBGet, Prowlarr, Jellyfin, Plex, TrueNAS,
  Unraid, Dockge and Nginx Proxy Manager. The README says, per service, how far
  Cupola goes and whether we have tested it against a real instance.
- **Home:** what arrived, what comes out next, what you were halfway through and what
  needs you, as modules you keep, order or leave out.
- **Discover:** trending, a calendar, every way in (genres, networks, studios,
  people, decades, moods), one search across Seerr, the arrs, Jellyfin and Plex, and
  one page per title to decide and act on it.
- **Activity:** *Needs you* says what went wrong in plain words and leads with the
  way out; downloads from all four clients sit in one list, and a client whose
  figures stop coming back says how old they are.
- **Stack:** every service in its own room, with an Overview and its own tabs.
  Add movies and series from the app, and choose a release in a search that waits
  for you in Activity.
- **For the household:** a member signs in to Seerr with their own account and gets
  Home, Discover and their requests, without the operator's controls.
- **At home and away:** a second address per connection, Cloudflare Access service
  tokens, proxy passwords or custom headers, and self-signed certificates trusted on
  first use and pinned per host.
- **A new device in one code:** *Set up another device* copies every connection over
  your home network, encrypted. *Invite someone* hands a household member the way to
  your Seerr, never its API key.
- **Widgets and notifications** on iOS and Android, worked out on the phone itself:
  no push server. Notifications are off until you turn them on.
- **Phone first, then tablet and desktop**, light and dark, large text, VoiceOver and
  TalkBack. No server at hand? *Explore a demo home* on the first screen.

### Install

| Platform | Get it | Notes |
| --- | --- | --- |
| iPhone, iPad | TestFlight | The link is in the release notes. iOS 17. |
| iPhone, iPad | unsigned `.ipa` | Sideload with AltStore, SideStore or Sideloadly. With a free Apple ID the install lasts **7 days**, and the widgets may stay empty. |
| Android | `.apk` | Android 7.0. Allow installs from unknown sources, or use Obtainium. |
| macOS | `.dmg` | macOS 12, Apple silicon. Signed with a Developer ID and notarized by Apple. |
| Windows | `.zip` | Built by GitHub Actions and not signed: SmartScreen asks once. |
| Linux | `.tar.gz` | Built by GitHub Actions; needs GTK 3 and libsecret. |

`SHA256SUMS` on the release lists the digest of every file, taken from the copies a
reader downloads.

### Known limits

- **Unraid** is tested against recorded answers from its API, never against a real
  server: we do not run one. A report from someone who does is very welcome.
- **Plex, Bazarr, Readarr, TrueNAS and Nginx Proxy Manager** have been read against
  real instances, but not every action has been run against one.
- **Readarr is manage only:** no adding authors, because Readarr is retired and its
  metadata service no longer answers. **Bazarr** is mostly read.
- **TrueNAS** needs SCALE 25.04 or later.
- **Background refresh is the operating system's call.** Widgets and notifications
  update when iOS or Android lets the app run, which can be hours apart on iOS.
- **Windows and Linux** builds are made by CI and we have not run them ourselves.
- **English only**, by design.
