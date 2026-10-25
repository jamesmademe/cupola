import type { APIRoute } from 'astro';
import { brandSvg } from '../lib/repo';

export const GET: APIRoute = () =>
  new Response(brandSvg('cupola_launcher'), { headers: { 'Content-Type': 'image/svg+xml' } });
