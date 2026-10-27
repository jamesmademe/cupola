// The questions people ask about Cupola, answered once. Pages pick from here,
// and so do the FAQPage data and llms-full.txt.
import type { Qa } from '../lib/seo';
import { services } from '../lib/repo';

const s = services();
const verified = s.filter((x) => x.tested === 'verified').length;
const partial = s.filter((x) => x.tested === 'partial').length;
const untested = s.filter((x) => x.tested === 'untested').map((x) => x.name);

export const faq = {
  arrApp: {
    q: 'Is there a Radarr or Sonarr app for iPhone and Android?',
    a: 'Yes. Cupola is a native app for Radarr, Sonarr, Lidarr and Readarr on iPhone, Android and Mac, together with Seerr, four download clients, Prowlarr, Bazarr, Jellyfin, Plex and the server they run on. It is free and open source, and it talks directly to your own instances. See <a href="/radarr-sonarr-app/">Radarr and Sonarr on your phone</a>.',
  },
  account: {
    q: 'Does Cupola need a server or an account?',
    a: 'No Cupola account and no Cupola server. The app talks straight to your services, on your home network, over a VPN or through a reverse proxy. Your services keep their own sign-in: an API key, a password or a Seerr account, stored in the Keychain on Apple devices and in the Keystore on Android.',
  },
  away: {
    q: 'How do I manage my home server from my phone when I am away?',
    a: 'Cupola uses the way in you already have: a VPN such as WireGuard or Tailscale, or a reverse proxy. A connection can carry two addresses, one for home and one for away, and Cupola uses whichever answers. A service that only exists at home says so, with the last thing it knew, instead of failing. Cupola does not open a tunnel for you.',
  },
  player: {
    q: 'Is Cupola a media player?',
    a: 'No. Cupola finds, requests, downloads and keeps an eye on things; you still watch in Jellyfin, Plex or the player you use today. It does show who is watching on Jellyfin and Plex, and can pause or stop a session.',
  },
  free: {
    q: 'Is Cupola free?',
    a: 'Yes. It is open source under the Apache License 2.0, with no ads, no subscription and nothing to unlock. If it is useful to you, a donation on <a href="https://ko-fi.com/matthwlabs">Ko-fi</a> helps keep it moving.',
  },
  seerr: {
    q: 'Does it work with Overseerr and Jellyseerr?',
    a: 'Yes. Seerr, Overseerr and Jellyseerr all go through the same integration, which powers Discover: trending, a calendar, genres, networks, studios, people and collections, and sending, approving and declining requests.',
  },
  household: {
    q: 'Can my family request movies without access to Radarr?',
    a: 'Yes. A household member signs in to Seerr with their own account (email, Jellyfin or Plex) and gets a simpler Cupola: what is ready to watch, Discover and their own requests, with no operator controls and nothing the server would refuse them. Invite them from Seerr with a link or a QR code that carries the server address, never its API key. See <a href="/seerr-requests/">requests with Seerr</a>.',
  },
  leaves: {
    q: 'What data leaves my network?',
    a: 'Two things, each for one reason. Poster and cast artwork comes from TMDB\'s image CDN, because that is where Seerr\'s metadata points; those requests carry no credential of yours. Signing in to Seerr with a Plex account goes through plex.tv once. Nothing else: no telemetry, no analytics, no crash reports. See <a href="/privacy/">privacy</a>.',
  },
  address: {
    q: 'What address do I type for a service?',
    a: 'The one you open its web interface at, with the port: <code>http://192.168.1.20:7878</code> for Radarr, for instance, or <code>https://radarr.example.com</code> behind a reverse proxy. If you leave out <code>http://</code>, Cupola tries https, so a service on plain http needs the <code>http://</code> written out. A URL base (<code>/radarr</code>) goes on the end. A container name such as <code>radarr:7878</code> only works inside Docker: from your phone, use the address of the machine it runs on. When the connection fails, Cupola says what it found, such as a port that answers in plain http, a sign-in page in front of the service, or an address where nothing answered.',
  },
  apiKey: {
    q: 'Where do I find the API key?',
    a: 'In the service\'s own web interface. Radarr, Sonarr, Lidarr, Readarr, Prowlarr, Bazarr and Seerr keep it under Settings, General; SABnzbd under Config, General; Jellyfin under Dashboard, Advanced, API Keys; TrueNAS under Credentials, API Keys; Unraid under Settings, Management Access, API Keys. Plex calls it a token: open any item, then Get Info, View XML. qBittorrent, Transmission, NZBGet, Dockge and Nginx Proxy Manager take the login you already use for their web interface instead. The connection form says, for each service, where to look. Household members signing in to Seerr with their own account need no key at all.',
  },
  discoverSeerr: {
    q: 'Do I need Seerr for Discover?',
    a: 'For most of it, yes. Trending, genres, networks, people, collections and requests all come from Seerr (or Overseerr, or Jellyseerr). Without it, Discover still shows the calendar from Radarr, Sonarr and Lidarr and searches your libraries, and everything else in Cupola works as usual.',
  },
  certs: {
    q: 'My services are behind a reverse proxy with a self-signed certificate. Will it work?',
    a: 'Yes, that is the expected setup. Cupola asks before trusting a certificate it has not seen, then pins its SHA-256 fingerprint to that host, so two services behind the same proxy are trusted together. Cloudflare Access service tokens, proxy passwords and custom headers are supported too.',
  },
  tested: {
    q: 'Which services have been tested against real servers?',
    a: `${verified} of the ${s.length} integrations have been verified end to end against real, running instances, and ${partial} partly. ${untested.join(' and ')} ${untested.length === 1 ? 'is' : 'are'} tested against recorded answers from ${untested.length === 1 ? 'its' : 'their'} API only. The <a href="/services/">services page</a> says which is which. If you run one that is not fully verified, a report either way helps.`,
  },
  lunasea: {
    q: 'Is Cupola an alternative to LunaSea?',
    a: 'It covers the same ground and more: Radarr, Sonarr, Lidarr, the download clients, plus Seerr, Jellyfin, Plex and the server underneath. LunaSea\'s author published a final release before archiving the project. Cupola does not import LunaSea\'s settings, so connections are set up again. See <a href="/alternatives/lunasea/">coming from LunaSea</a>.',
  },
  nzb360: {
    q: 'Is there an nzb360 for iPhone?',
    a: 'nzb360 is an Android app, with no iPhone version. Cupola covers much of the same ground (Sonarr, Radarr, Lidarr, Seerr, Prowlarr, Bazarr and the download clients) on iPhone, Android and Mac, free and open source. See <a href="/alternatives/nzb360/">Cupola and nzb360</a>.',
  },
  seekarr: {
    q: 'What happened to Seekarr?',
    a: 'Seekarr is now Cupola. Releases up to 0.8.0 were published as Seekarr and covered five services; Cupola 1.0 covers seventeen and is a new app rather than an update. It installs beside Seekarr and starts empty, so add your services again (same addresses, same keys), check they answer, then remove Seekarr. On Android the package name changed too, so Obtainium needs Cupola added as a new app. The source, the issues and the history are in the same repository.',
  },
  widgets: {
    q: 'Are there widgets and notifications?',
    a: 'Yes, on iOS and Android: home-screen widgets for what is coming up, downloads and requests, and two notifications, both off until you turn them on: Needs you, when something on the stack turns into a fault, and Ready to watch, when something you asked for arrives. The phone works them out itself against your own services: there is no push server, so the operating system decides how often that happens.',
  },
  desktop: {
    q: 'Does it run on Windows and Linux?',
    a: 'Every release includes a Windows and a Linux build, with the same desktop window as on the Mac. Neither has been tested on a real machine yet, so a report is welcome. There is no web version.',
  },
  english: {
    q: 'Why is Cupola only in English?',
    a: 'It is a choice rather than missing work: the app has no translations. Titles, posters and descriptions still come from your services, in whatever language they hold them.',
  },
} satisfies Record<string, Qa>;

export type FaqId = keyof typeof faq;
export const pick = (...ids: FaqId[]) => ids.map((id) => faq[id]);
