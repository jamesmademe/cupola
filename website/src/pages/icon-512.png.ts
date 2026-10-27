import type { APIRoute } from 'astro';
import { brandSvg } from '../lib/repo';
import { png } from '../lib/og';

export const GET: APIRoute = () =>
  new Response(png(brandSvg('cupola_icon'), 512), { headers: { 'Content-Type': 'image/png' } });
