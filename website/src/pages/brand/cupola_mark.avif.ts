import type { APIRoute } from 'astro';
import sharp from 'sharp';
import { brandSvg } from '../../lib/repo';
import { png } from '../../lib/og';

// The mark as pixels, for the home page's descent. Scaled twentyfold, the SVG
// has its blurs drawn again at every size, which stalls Firefox for seconds;
// a bitmap is only stretched. 2048 px keeps the round window sharp until the
// mark fades, and AVIF keeps it near 200 KiB.
export const GET: APIRoute = async () =>
  new Response(new Uint8Array(await sharp(png(brandSvg('cupola_mark'), 2048)).avif({ quality: 55 }).toBuffer()), {
    headers: { 'Content-Type': 'image/avif' },
  });
