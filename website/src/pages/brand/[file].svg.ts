import type { APIRoute, GetStaticPaths } from 'astro';
import { brandSvg } from '../../lib/repo';

const files = ['cupola_mark', 'cupola_icon', 'cupola_launcher'] as const;

export const getStaticPaths: GetStaticPaths = () => files.map((file) => ({ params: { file } }));

export const GET: APIRoute = ({ params }) =>
  new Response(brandSvg(params.file as (typeof files)[number]), { headers: { 'Content-Type': 'image/svg+xml' } });
