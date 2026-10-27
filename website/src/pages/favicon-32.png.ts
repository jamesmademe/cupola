import type { APIRoute } from 'astro';
import { brandSvg } from '../lib/repo';
import { png } from '../lib/og';

export const GET: APIRoute = () =>
  new Response(png(brandSvg('cupola_launcher'), 32), { headers: { 'Content-Type': 'image/png' } });
