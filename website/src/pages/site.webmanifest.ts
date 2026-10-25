import type { APIRoute } from 'astro';

export const GET: APIRoute = () =>
  new Response(
    JSON.stringify({
      name: 'Cupola',
      short_name: 'Cupola',
      icons: [
        { src: '/apple-touch-icon.png', sizes: '180x180', type: 'image/png' },
        { src: '/icon-512.png', sizes: '512x512', type: 'image/png' },
      ],
      theme_color: '#0a0a0d',
      background_color: '#0a0a0d',
      display: 'browser',
    }),
    { headers: { 'Content-Type': 'application/manifest+json' } },
  );
