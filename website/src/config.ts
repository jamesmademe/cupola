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
  // One public TestFlight link serves iPhone, iPad and Mac. The APK, the dmg
  // and the unsigned ipa are assets of a GitHub release: set them, with the
  // release's own tag and file names, only once that release is published,
  // e.g. `${repo}/releases/download/v1.0.0-beta.1/cupola-1.0.0-beta.1.apk`.
  // Until then the site offers no release at all, Windows and Linux included.
  downloads: {
    testflight: 'https://testflight.apple.com/join/tqmwnCMj' as string | null,
    apk: null as string | null,
    macos: null as string | null,
    ipa: null as string | null,
  },
} as const;
