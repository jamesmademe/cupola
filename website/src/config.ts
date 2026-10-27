// Every link the site hands out lives here. A download link left null is not
// offered: its platform reads "Not open yet" and the page points at GitHub
// releases instead, so no button leads to a dead end.
const repo = 'https://github.com/matthw-labs/seekarr';

export const site = {
  name: 'Cupola',
  url: 'https://get-seekarr.org',
  repo,
  releases: `${repo}/releases`,
  watch: `${repo}/subscription`,
  issues: `${repo}/issues`,
  contributing: `${repo}/blob/main/CONTRIBUTING.md`,
  kofi: 'https://ko-fi.com/matthwlabs',
  claim: 'A Cupola over your server.',
  promise: 'Nothing left in the dark.',
  description:
    'Cupola is a free, open-source app for Radarr, Sonarr, Seerr, qBittorrent and the rest of your self-hosted media stack, on iPhone, Android and Mac. It talks straight to your own services: no Cupola account, no cloud.',
  // The APK and the dmg are assets of a pinned release, named as its notes
  // name them: they 404 until that release is published, and move with the
  // next one only when these lines do.
  downloads: {
    testflight: null as string | null,
    apk: `${repo}/releases/download/v1.0.0/cupola-1.0.0.apk` as string | null,
    macos: `${repo}/releases/download/v1.0.0/cupola-1.0.0.dmg` as string | null,
  },
} as const;
