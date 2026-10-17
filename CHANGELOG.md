# Changelog

## 1.0.0

The first release of Cupola. Everything before it was published as Seekarr (up to
0.8.0) and covered fewer services; this one is a new app rather than an update.

### What is in it

- **17 services in one app:** Seerr, Radarr, Sonarr, Lidarr, Bazarr, Readarr,
  qBittorrent, Transmission, Prowlarr, SABnzbd, NZBGet, Jellyfin, Plex, TrueNAS,
  Dockge, Unraid and Nginx Proxy Manager. The README says, per service, how far
  Cupola goes and whether we have tested it against a real instance.
- **Home:** what arrived, what comes out next, what you were halfway through and what
  needs you, as modules you keep, order or leave out.
- **Discover:** trending, a calendar, every way in (genres, networks, studios,
  people, decades), one search across Seerr, the *arrs, Jellyfin and Plex, and one
  page per title to decide and act.
- **Activity:** *Needs you* says what went wrong in plain words and leads with the
  way out; downloads from all four clients sit in one list that keeps itself up to
  date.
- **Stack:** every service in its own room, with its own tabs.
- **For the household:** a member signs in to Seerr with their own account and gets
  Home, Discover and their requests, without the operator's controls.
- **Widgets and notifications** on iOS and Android, worked out on the phone itself:
  no push server. Notifications are off until you turn them on.
- **At home and away:** a connection can carry a second address for when you are out,
  and Cupola uses whichever answers.
- **A new phone in one code:** *Set up another device* copies every connection over
  your home network, encrypted. *Invite someone* hands a household member the way to
  your Seerr, never its API key.
- **Self-signed certificates and gateways:** trust on first use with pinning per
  host; Cloudflare Access service tokens, proxy passwords and custom headers.
- Light and dark themes, large text, VoiceOver and TalkBack, phone first and then
  tablet and desktop.

### Install

| Platform | File | Notes |
| --- | --- | --- |
| Android | `.apk` | Allow installs from unknown sources for your browser or file manager. |
| macOS | `.dmg` | Not notarized: the first time, right-click Cupola and choose **Open**. |
| iOS | unsigned `.ipa` | Install with AltStore, SideStore or Sideloadly. With a free Apple ID the install lasts **7 days** and has to be refreshed. |
| Windows | `.zip` | Built by GitHub Actions and not signed: SmartScreen asks once. |
| Linux | `.tar.gz` | Built by GitHub Actions; needs GTK 3 and libsecret. |

### Known limits

- **Unraid** is tested against recorded answers from its API, never against a real
  server: we do not run one. A report from someone who does is very welcome.
- **Windows and Linux** builds are made by CI and we have not run them ourselves.
- **Plex, Bazarr, Readarr, TrueNAS and Nginx Proxy Manager** have been read against
  real instances, but not every action has been run against one.
- **Readarr is manage-only:** no adding authors, because Readarr is retired and its
  metadata service no longer answers. Everything already in your library works.
- **Background refresh is the operating system's call.** Widgets and notifications
  update when iOS or Android lets the app run, which can be less often than you
  would like, especially on iOS.
- **English only**, by design.
