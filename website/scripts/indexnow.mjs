// Tells the IndexNow search engines (Bing, Yandex, Seznam, Naver and the
// others that share submissions) which pages exist, so they crawl a change
// within hours instead of on their next pass. Run it after each deploy:
//
//   npm run indexnow
//
// It reads the live sitemap, not the local build, so it only ever submits
// what is actually served. The key is public by design: the site serves it at
// /indexnow-key.txt, which proves the site is ours. Google does not take part;
// it reads the sitemap through Search Console.
import { readFileSync } from 'node:fs';
import { site } from '../src/config.ts';

const key = readFileSync(new URL('../public/indexnow-key.txt', import.meta.url), 'utf8').trim();
const host = new URL(site.url).host;
const keyLocation = `${site.url}/indexnow-key.txt`;

async function text(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url} answered ${res.status}`);
  return res.text();
}

const locs = (xml) => [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);

const served = (await text(keyLocation)).trim();
if (served !== key) throw new Error(`${keyLocation} does not serve the key: deploy first`);

const sitemaps = locs(await text(`${site.url}/sitemap-index.xml`));
const urlList = (await Promise.all(sitemaps.map(async (s) => locs(await text(s))))).flat();
if (urlList.length === 0) throw new Error('The sitemap lists no pages');

const res = await fetch('https://api.indexnow.org/indexnow', {
  method: 'POST',
  headers: { 'content-type': 'application/json; charset=utf-8' },
  body: JSON.stringify({ host, key, keyLocation, urlList }),
});
// 200 and 202 both mean accepted; 202 while the key is still being checked.
if (res.status !== 200 && res.status !== 202) {
  throw new Error(`IndexNow answered ${res.status}: ${await res.text()}`);
}
console.log(`Submitted ${urlList.length} pages to IndexNow (${res.status}).`);
