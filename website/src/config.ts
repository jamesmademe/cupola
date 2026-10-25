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
  downloads: {
    testflight: null as string | null,
    apk: null as string | null,
    macos: null as string | null,
  },
  // A YouTube id for the launch trailer. Left null, the trailer is not shown.
  trailerYouTubeId: null as string | null,
} as const;
