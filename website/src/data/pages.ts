// Every page's name, words for search and social cards, and the title that
// lights its card. The OG images, the sitemap order in llms.txt and the
// related links all read from here.
import type { LightId } from './titles';

export interface Page {
  path: string;
  slug: string;
  /** Short name, for links and breadcrumbs. */
  name: string;
  /** The <title>. */
  title: string;
  /** What the page answers, shown on its social card. */
  heading: string;
  description: string;
  light: LightId;
}

export const pages = {
  home: {
    path: '/',
    slug: 'home',
    name: 'Cupola',
    title: 'Cupola: Radarr, Sonarr and Seerr app for iPhone and Android',
    heading: 'A Cupola over your server.',
    description: '',
    light: 'tos',
  },
  services: {
    path: '/services/',
    slug: 'services',
    name: 'Services',
    title: 'Cupola services: Radarr, Sonarr, Seerr, qBittorrent, TrueNAS',
    heading: 'Seventeen services, each one tested honestly.',
    description: 'Every service Cupola connects to, what it can do with each, how it signs in, and whether it has been verified against a real, running instance.',
    light: 'lamp',
  },
  install: {
    path: '/install/',
    slug: 'install',
    name: 'Install',
    title: 'Install Cupola on iPhone, Android, Mac, Windows and Linux',
    heading: 'Get Cupola on every device you use.',
    description: 'How to install Cupola: TestFlight on iPhone and iPad, an APK on Android, a notarized app on the Mac, builds for Windows and Linux, and building from source. Plus what you need before you start.',
    light: 'spring',
  },
  privacy: {
    path: '/privacy/',
    slug: 'privacy',
    name: 'Privacy',
    title: 'Privacy and security · Cupola',
    heading: 'No Cupola server. Nowhere for your data to go.',
    description: 'Cupola talks straight to your own services. How it stores keys, pins self-signed certificates, reaches your server away from home, and the only two third parties it ever contacts.',
    light: 'lamp',
  },
  faq: {
    path: '/faq/',
    slug: 'faq',
    name: 'FAQ',
    title: 'Questions about Cupola, answered',
    heading: 'Questions, answered plainly.',
    description: 'Does Cupola need an account? Does it work away from home, with Overseerr and Jellyseerr, with self-signed certificates? Is it free? The answers, in one place.',
    light: 'lamp',
  },
  arr: {
    path: '/radarr-sonarr-app/',
    slug: 'radarr-sonarr-app',
    name: 'Radarr and Sonarr',
    title: 'Radarr and Sonarr app for iPhone and Android · Cupola',
    heading: 'Radarr, Sonarr and Lidarr, on your phone.',
    description: 'Cupola is a free, native Radarr, Sonarr, Lidarr and Readarr client for iPhone, Android and Mac: libraries, calendar, queue, interactive search, quality profiles and manual import, straight to your own instances.',
    light: 'tos',
  },
  seerr: {
    path: '/seerr-requests/',
    slug: 'seerr-requests',
    name: 'Requests with Seerr',
    title: 'Overseerr and Jellyseerr app for iPhone and Android · Cupola',
    heading: 'Requests for everyone at home.',
    description: 'Cupola turns Seerr, Overseerr or Jellyseerr into a native app: Discover, requests and approvals for whoever runs the server, and a simpler app for household members who sign in with their own account.',
    light: 'sintel',
  },
  downloads: {
    path: '/download-clients/',
    slug: 'download-clients',
    name: 'Download clients',
    title: 'qBittorrent, SABnzbd and NZBGet from your phone · Cupola',
    heading: 'Every download, one list, and a way out when one is stuck.',
    description: 'Manage qBittorrent, Transmission, SABnzbd, NZBGet and Prowlarr from iPhone or Android: a live queue across all clients, stuck downloads explained with their remedy, speed limits, categories and indexers.',
    light: 'charge',
  },
  stream: {
    path: '/jellyfin-plex/',
    slug: 'jellyfin-plex',
    name: 'Jellyfin and Plex',
    title: 'Jellyfin and Plex sessions from your phone · Cupola',
    heading: 'Who is watching, and why it is transcoding.',
    description: 'See who is watching on Jellyfin and Plex, why a stream transcodes, and pause, stop or message a session from your phone. Libraries, devices and tasks too.',
    light: 'sintel',
  },
  homelab: {
    path: '/homelab/',
    slug: 'homelab',
    name: 'NAS and homelab',
    title: 'TrueNAS, Unraid and Dockge from your phone · Cupola',
    heading: 'The machine under the media, in the same app.',
    description: 'Cupola reaches past the media apps to the box they run on: TrueNAS pools, disks and apps, Unraid arrays and VMs, Dockge compose stacks with a live terminal, and Nginx Proxy Manager hosts and certificates.',
    light: 'lamp',
  },
  lunasea: {
    path: '/lunasea-alternative/',
    slug: 'lunasea-alternative',
    name: 'Coming from LunaSea',
    title: 'A LunaSea alternative for Radarr, Sonarr and more · Cupola',
    heading: 'Coming from LunaSea.',
    description: 'LunaSea has published its final release. Cupola is a free, open-source client that covers the same services and more, on iPhone, Android and Mac. What carries over, and what to set up again.',
    light: 'spring',
  },
  contribute: {
    path: '/contribute/',
    slug: 'contribute',
    name: 'Contribute',
    title: 'Contribute to Cupola',
    heading: 'Help make it work on your stack too.',
    description: 'Cupola is open source. The most useful contribution is a report from a service you run, verified or not. Then accessibility, integrations and code: here is how.',
    light: 'lamp',
  },
  press: {
    path: '/press/',
    slug: 'press',
    name: 'Press kit',
    title: 'Press kit · Cupola',
    heading: 'Writing about Cupola?',
    description: 'Cupola described in a line and in a paragraph, the mark, the tagline, and the facts worth checking.',
    light: 'lamp',
  },
  credits: {
    path: '/credits/',
    slug: 'credits',
    name: 'Credits',
    title: 'Credits and trademarks · Cupola',
    heading: 'Credits.',
    description: 'The open movies that light this site, the typefaces, and the trademarks of the services Cupola connects to.',
    light: 'lamp',
  },
} satisfies Record<string, Page>;

export type PageId = keyof typeof pages;
