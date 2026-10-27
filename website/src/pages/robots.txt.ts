import type { APIRoute } from 'astro';
import { site } from '../config';

// Search engines and AI assistants are both welcome: being found by people
// who ask either is the point of this site.
export const GET: APIRoute = () =>
  new Response(
    [
      'User-agent: *',
      'Allow: /',
      '',
      ...['GPTBot', 'OAI-SearchBot', 'ChatGPT-User', 'ClaudeBot', 'Claude-SearchBot', 'Claude-User', 'PerplexityBot', 'Google-Extended', 'Applebot-Extended'].flatMap((bot) => [
        `User-agent: ${bot}`,
        'Allow: /',
        '',
      ]),
      `Sitemap: ${new URL('/sitemap-index.xml', site.url)}`,
      '',
    ].join('\n'),
    { headers: { 'Content-Type': 'text/plain; charset=utf-8' } },
  );
