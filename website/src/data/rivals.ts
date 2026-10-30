// Other apps people search for, described only by what their own website and
// store listing say, with the sources and the day they were read. When a fact
// is not on those pages it is left out rather than guessed. Re-check every
// row before changing `checked`.

export interface Fact {
  label: string;
  them: string;
  cupola: string;
}

export interface Rival {
  id: string;
  name: string;
  /** The <title>. */
  title: string;
  /** What the page answers, as its H1. */
  heading: string;
  description: string;
  /** The answer, first sentence of the page. */
  lede: string;
  checked: string;
  facts: Fact[];
  /** Where the other app is ahead, said plainly. */
  ahead: string[];
  /** Where Cupola differs. */
  differs: string[];
  moving: string[];
  sources: { label: string; url: string }[];
}

const cupola = {
  platforms: 'iPhone, iPad, Android and Mac; Windows and Linux builds not yet tested on real machines',
  price: 'Free, nothing to unlock',
  source: 'Open source, Apache License 2.0',
  account: 'None. Your services keep their own sign-in',
};

export const rivals: Rival[] = [
  {
    id: 'nzb360',
    name: 'nzb360',
    title: 'An nzb360 alternative for iPhone, Android and Mac · Cupola',
    heading: 'Looking for nzb360 on iPhone?',
    description:
      'nzb360 is Android only. Cupola is a free, open-source client for Sonarr, Radarr, Seerr and the download clients, on iPhone, Android and Mac.',
    lede: 'nzb360 is an Android app, and there is no iPhone version. Cupola covers much of the same ground (Sonarr, Radarr, Lidarr, Seerr, Prowlarr, Bazarr and the download clients) on iPhone, Android and Mac, and it is free and open source.',
    checked: '25 October 2026',
    facts: [
      { label: 'Platforms', them: 'Android', cupola: cupola.platforms },
      { label: 'Price', them: 'Free to install, with a paid Pro upgrade', cupola: cupola.price },
      { label: 'Source code', them: 'No public source found', cupola: cupola.source },
      { label: 'Around since', them: '2012', cupola: '2026 as Cupola, earlier as Seekarr' },
      {
        label: 'Download clients',
        them: 'SABnzbd, NZBGet, qBittorrent, Transmission, Deluge, µTorrent, rTorrent',
        cupola: 'SABnzbd, NZBGet, qBittorrent, Transmission',
      },
      {
        label: 'Media and requests',
        them: 'Sonarr, Radarr, Lidarr, Bazarr, Seerr, Chaptarr, Sick Beard',
        cupola: 'Sonarr, Radarr, Lidarr, Readarr, Bazarr, Seerr (with sign-in for household members)',
      },
      { label: 'Indexers', them: 'Prowlarr, NZBHydra2, Jackett, Newznab', cupola: 'Prowlarr' },
      {
        label: 'Server and streaming',
        them: 'Unraid, Docker containers, Tautulli, Tracearr',
        cupola: 'Unraid, TrueNAS, Dockge, Nginx Proxy Manager, Jellyfin and Plex sessions',
      },
    ],
    ahead: [
      'Years of maturity: nzb360 has been around since 2012 and lists more than 800,000 downloads on Google Play.',
      'More download clients and indexers: Deluge, µTorrent, rTorrent, NZBHydra2, Jackett and Newznab, which Cupola does not support.',
      'Wake-on-LAN, Tautulli and Tracearr, which Cupola does not have.',
    ],
    differs: [
      'It runs on iPhone, iPad and Mac as well as Android, with one design everywhere.',
      'It is free and open source, with nothing to unlock and no Cupola account.',
      'It reaches the machine under the media apps: TrueNAS, Dockge and Nginx Proxy Manager.',
      'Household members can sign in to Seerr with their own account and get a simpler app for requests.',
    ],
    moving: [
      'Cupola does not import nzb360 settings. Add each connection again with the same address and API key or password.',
      'Each connection can be tested before you save it, and says why when it fails.',
    ],
    sources: [
      { label: 'nzb360 website', url: 'https://nzb360.com/' },
      { label: 'nzb360 on Google Play', url: 'https://play.google.com/store/apps/details?id=com.kevinforeman.nzb360' },
    ],
  },
  {
    id: 'helmarr',
    name: 'Helmarr',
    title: 'A free Helmarr alternative, also on Android · Cupola',
    heading: 'Comparing Helmarr and Cupola.',
    description:
      'Helmarr is Apple-only, with paid unlocks and iOS 26 or later. Cupola is a free, open-source client for your media stack on iPhone, Android and Mac.',
    lede: 'Helmarr is an app for iPhone, iPad, Mac and Vision Pro, free to install with paid unlocks, that needs iOS 26 or later. Cupola is free and open source with nothing to unlock, and runs on Android as well as on Apple devices.',
    checked: '25 October 2026',
    facts: [
      { label: 'Platforms', them: 'iPhone, iPad, Mac (Apple silicon) and Vision Pro', cupola: cupola.platforms },
      { label: 'Oldest system', them: 'iOS 26', cupola: 'iOS 17, Android 7, macOS 12 (Apple silicon)' },
      {
        label: 'Price',
        them: 'Free to install. Pro at $3.99 a month or $34.99 once, Ultra at $4.99 a month, or single services from $3.99',
        cupola: cupola.price,
      },
      { label: 'Source code', them: 'No public source found', cupola: cupola.source },
      {
        label: 'Data collected by the app',
        them: 'Usage data for analytics and crash data, not linked to you (App Store privacy label)',
        cupola: 'None: no analytics, no crash reporting',
      },
      {
        label: 'Media and requests',
        them: 'Sonarr, Radarr, Lidarr, Bazarr, Seerr, Overseerr, Jellyseerr, Wizarr',
        cupola: 'Sonarr, Radarr, Lidarr, Readarr, Bazarr, Seerr (with sign-in for household members)',
      },
      {
        label: 'Download clients and indexers',
        them: 'SABnzbd, NZBGet, qBittorrent, Transmission, Deluge, rTorrent, Prowlarr, NZBHydra2, Jackett',
        cupola: 'SABnzbd, NZBGet, qBittorrent, Transmission, Prowlarr',
      },
      {
        label: 'Streaming and server',
        them: 'Plex, Emby, Tautulli, Jellystat, Tracearr, Tdarr, Unraid, SSH',
        cupola: 'Jellyfin, Plex, Unraid, TrueNAS, Dockge, Nginx Proxy Manager',
      },
    ],
    ahead: [
      'More services in some areas: Emby, Tdarr, Deluge, rTorrent, NZBHydra2, Jackett, Tautulli, Jellystat and Wizarr, which Cupola does not support.',
      'An SSH and SFTP client, and an app for Vision Pro.',
      'A large following on the App Store, with a rating of 4.8.',
    ],
    differs: [
      'It runs on Android as well as on iPhone, iPad and Mac, and does not need iOS 26.',
      'Everything is free and open source: no subscription, no per-service unlocks.',
      'The app collects nothing, not even anonymous analytics.',
      'It reaches TrueNAS, Dockge and Nginx Proxy Manager, and lets household members request titles with their own Seerr account.',
    ],
    moving: [
      'Cupola does not import Helmarr settings. Add each connection again with the same address and API key, and an address for away from home if you use one.',
      'Each connection can be tested before you save it, and says why when it fails.',
    ],
    sources: [
      { label: 'Helmarr website', url: 'https://helmarr.com/' },
      { label: 'Helmarr on the App Store', url: 'https://apps.apple.com/app/id1638624921' },
    ],
  },
  {
    id: 'lunasea',
    name: 'LunaSea',
    title: 'A LunaSea alternative for Radarr, Sonarr and more · Cupola',
    heading: 'Coming from LunaSea.',
    description:
      'LunaSea has published its final release. Cupola is a free, open-source client that covers the same services and more, on iPhone, Android and Mac.',
    lede: 'LunaSea has published its final release and is no longer developed. Cupola does the same job for Radarr, Sonarr and the download clients, reaches further (Seerr, Prowlarr, Bazarr, Jellyfin, Plex and the server underneath), and is free, open source and actively developed for iPhone, Android and Mac.',
    checked: '25 October 2026',
    facts: [
      { label: 'Status', them: 'Final release, v11.0.0, on 3 April 2025; repository archived', cupola: 'Actively developed' },
      { label: 'Source code', them: 'On GitHub, archived', cupola: cupola.source },
      { label: 'Platforms', them: 'No longer updated for new system versions', cupola: cupola.platforms },
    ],
    ahead: [],
    differs: [
      'It is built around what needs you rather than each service\'s menus: Home says what arrived and what is stuck, Activity leads every fault with its remedy, and Discover searches every service at once.',
      'Each service still has its own room, with its own tabs, when you want the details.',
    ],
    moving: [
      'Cupola does not read LunaSea\'s configuration or backups. Each connection is set up again with the same address and API key you gave LunaSea.',
      'There is no Tautulli integration (Cupola reads sessions from Jellyfin and Plex directly) and no Wake-on-LAN.',
    ],
    sources: [{ label: 'LunaSea releases on GitHub', url: 'https://github.com/JagandeepBrar/LunaSea/releases' }],
  },
];
