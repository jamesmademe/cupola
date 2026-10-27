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
  const svg = await satori(tree as never, {
    width: 1200,
    height: 630,
    fonts: [
      { name: 'Bricolage', data: display, weight: 600, style: 'normal' },
      { name: 'Onest', data: text, weight: 500, style: 'normal' },
    ],
  });
  return png(svg, 1200);
}
