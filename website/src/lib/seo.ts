import { site } from '../config';
import { services } from './repo';

// The version people download, so the footer, the press kit and llms.txt name
// the same release the buttons lead to.
export const version = site.release;

export const abs = (path: string) => new URL(path, site.url).toString();

export function softwareApplication() {
  const download = site.downloads.testflight ?? site.downloads.apk ?? site.releases;
  return {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: 'Cupola',
    alternateName: 'Seekarr',
    url: site.url,
    description: site.description,
    applicationCategory: 'MultimediaApplication',
    applicationSubCategory: 'Media server client',
    operatingSystem: 'iOS, Android, macOS, Windows, Linux',
    softwareVersion: version,
    license: 'https://www.apache.org/licenses/LICENSE-2.0',
    isAccessibleForFree: true,
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
    downloadUrl: download,
    installUrl: abs('/install/'),
    image: abs('/og/home.png'),
    screenshot: abs('/og/home.png'),
    featureList: services().map((s) => `${s.name}: ${s.what}`),
    sameAs: [site.repo],
    author: { '@type': 'Organization', name: 'matthw-labs', url: 'https://github.com/matthw-labs' },
  };
}

export function sourceCode() {
  return {
    '@context': 'https://schema.org',
    '@type': 'SoftwareSourceCode',
    name: 'Cupola',
    codeRepository: site.repo,
    programmingLanguage: 'Dart',
    runtimePlatform: 'Flutter',
    license: 'https://www.apache.org/licenses/LICENSE-2.0',
  };
}

export function website() {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    name: 'Cupola',
    alternateName: ['Seekarr', 'get-seekarr.org'],
    url: site.url,
  };
}

export function breadcrumbs(items: { name: string; path: string }[]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: [{ name: 'Cupola', path: '/' }, ...items].map((item, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: item.name,
      item: abs(item.path),
    })),
  };
}

export interface Qa {
  q: string;
  a: string; // HTML allowed: links and emphasis only.
  id?: string; // The question's anchor, so a link can open it.
}

export function faqPage(qas: Qa[]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: qas.map((x) => ({
      '@type': 'Question',
      name: x.q,
      acceptedAnswer: { '@type': 'Answer', text: x.a },
    })),
  };
}
