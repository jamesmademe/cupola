// The social card for a page, 1200 × 630: the room lit by the page's title,
// the mark, and what the page answers.
import { readFileSync } from 'node:fs';
import satori from 'satori';
import { Resvg } from '@resvg/resvg-js';
import { brandSvg } from './repo';
import { lightOf, type LightId } from '../data/titles';

import { inSite } from './paths';

const display = readFileSync(inSite('src/og/Bricolage-600-80.ttf'));
const text = readFileSync(inSite('src/og/Onest-500.ttf'));
const fonts = [
  { name: 'Bricolage', data: display, weight: 600 as const, style: 'normal' as const },
  { name: 'Onest', data: text, weight: 500 as const, style: 'normal' as const },
];

type Node = { type: string; props: Record<string, unknown> };
const h = (type: string, style: Record<string, unknown>, ...children: (Node | string)[]): Node => ({
  type,
  props: { style, children: children.length === 1 ? children[0] : children },
});
const img = (src: string, style: Record<string, unknown>): Node => ({ type: 'img', props: { src, style } });

/** An SVG drawn as PNG bytes, ready to be a Response body. */
export const png = (svg: string, width: number): Uint8Array<ArrayBuffer> =>
  new Uint8Array(new Resvg(svg, { fitTo: { mode: 'width', value: width } }).render().asPng());

const markPng = `data:image/png;base64,${Buffer.from(png(brandSvg('cupola_mark'), 240)).toString('base64')}`;
const posterOf = (id: LightId) => {
  try {
    return `data:image/jpeg;base64,${readFileSync(inSite(`src/og/${id}.jpg`)).toString('base64')}`;
  } catch {
    return null;
  }
};

export async function card(heading: string, light: LightId, kicker = 'Cupola'): Promise<Uint8Array<ArrayBuffer>> {
  const { light: glow } = lightOf(light);
  const poster = posterOf(light);
  const tree = h(
    'div',
    {
      width: 1200,
      height: 630,
      display: 'flex',
      position: 'relative',
      background: '#0a0a0d',
      backgroundImage: `radial-gradient(900px 520px at 22% -10%, ${glow}55, #0a0a0d00), radial-gradient(700px 500px at 100% 110%, ${glow}22, #0a0a0d00)`,
      color: '#f7f6f2',
      fontFamily: 'Onest',
    },
    h(
      'div',
      { display: 'flex', flexDirection: 'column', justifyContent: 'space-between', padding: '64px 72px', width: poster ? 820 : 1200 },
      h(
        'div',
        { display: 'flex', alignItems: 'center', gap: 18 },
        img(markPng, { width: 64, height: 64 }),
        h('div', { fontFamily: 'Bricolage', fontSize: 40, letterSpacing: -0.5 }, kicker),
      ),
      h('div', { fontFamily: 'Bricolage', fontSize: heading.length > 46 ? 70 : 84, lineHeight: 0.98, letterSpacing: -2 }, heading),
      h('div', { fontSize: poster ? 22 : 26, color: 'rgba(247,246,242,0.66)' }, 'Free and open source · iPhone, Android and Mac · get-seekarr.org'),
    ),
    ...(poster
      ? [
          h(
            'div',
            { display: 'flex', alignItems: 'center', justifyContent: 'center', width: 380, paddingRight: 40 },
            img(poster, {
              width: 280,
              height: 410,
              objectFit: 'cover',
              borderRadius: 22,
            }),
          ),
        ]
      : []),
  );
  const svg = await satori(tree as never, { width: 1200, height: 630, fonts });
  return png(svg, 1200);
}

/** A screen of the app in its demo, captured from a dev build (src/og/app-*.jpg). */
const screenOf = (id: 'phone' | 'mac') =>
  `data:image/jpeg;base64,${readFileSync(inSite(`src/og/app-${id}.jpg`)).toString('base64')}`;

/**
 * The phone as drawn, `width` wide outside: the screen inside an even bezel,
 * the island centred over it. An absolute child is placed from inside the
 * border, so the island counts from the bezel.
 */
const phone = (width: number, style: Record<string, unknown>): Node => {
  const edge = 2;
  const bezel = Math.round(width * 0.03);
  const screen = width - (bezel + edge) * 2;
  const island = Math.round(screen * 0.31);
  return h(
    'div',
    {
      display: 'flex',
      position: 'absolute',
      boxSizing: 'border-box',
      width,
      padding: bezel,
      background: '#050507',
      borderRadius: Math.round(width * 0.16),
      border: `${edge}px solid rgba(255,255,255,0.14)`,
      ...style,
    },
    img(screenOf('phone'), { width: screen, height: Math.round((screen * 874) / 402), borderRadius: Math.round(width * 0.13) }),
    h('div', {
      position: 'absolute',
      top: bezel + Math.round(screen * 0.028),
      left: bezel + Math.round((screen - island) / 2),
      width: island,
      height: Math.round(screen * 0.09),
      borderRadius: 999,
      background: '#000',
    }),
  );
};

/**
 * The repository's social preview, 1280 × 640: the name, the claim, what the
 * app is, and the app itself in its demo on a Mac and a phone. `glow` is the
 * light the phone took from the title leading its screen, so the room matches.
 */
export async function repoCard(glow: string): Promise<Uint8Array<ArrayBuffer>> {
  const tree = h(
    'div',
    {
      width: 1280,
      height: 640,
      display: 'flex',
      position: 'relative',
      overflow: 'hidden',
      background: '#0a0a0d',
      backgroundImage: `radial-gradient(1000px 560px at 20% -12%, ${glow}55, #0a0a0d00), radial-gradient(800px 560px at 88% 112%, ${glow}33, #0a0a0d00)`,
      color: '#f7f6f2',
      fontFamily: 'Onest',
    },
    h(
      'div',
      { display: 'flex', flexDirection: 'column', justifyContent: 'space-between', padding: '64px 0 60px 80px', width: 640 },
      h(
        'div',
        { display: 'flex', alignItems: 'center', gap: 20 },
        img(markPng, { width: 76, height: 76 }),
        h('div', { fontFamily: 'Bricolage', fontSize: 56, letterSpacing: -1 }, 'Cupola'),
      ),
      h(
        'div',
        { display: 'flex', flexDirection: 'column', gap: 26, maxWidth: 540 },
        h('div', { fontFamily: 'Bricolage', fontSize: 74, lineHeight: 0.98, letterSpacing: -2 }, 'A Cupola over your server.'),
        h(
          'div',
          { fontSize: 25, lineHeight: 1.3, color: 'rgba(247,246,242,0.72)' },
          'One app for Radarr, Sonarr, Seerr, your download clients and the server they run on.',
        ),
      ),
      h(
        'div',
        { display: 'flex', flexDirection: 'column', gap: 4, fontSize: 22, color: 'rgba(247,246,242,0.6)' },
        h('div', {}, 'Free and open source · iPhone, Android and Mac'),
        h('div', {}, 'get-seekarr.org'),
      ),
    ),
    img(screenOf('mac'), {
      position: 'absolute',
      left: 770,
      top: 96,
      width: 820,
      height: 513,
      objectFit: 'cover',
      objectPosition: 'left top',
      borderRadius: 16,
      border: '2px solid rgba(255,255,255,0.14)',
    }),
    phone(270, { left: 680, top: 236 }),
  );
  const svg = await satori(tree as never, { width: 1280, height: 640, fonts });
  return png(svg, 1280);
}
