import type { APIRoute } from 'astro';
import { site } from '../config';

// Search engines and AI assistants are both welcome: being found by people
// who ask either is the point of this site. The Content-Signal line
// (contentsignals.org) says so in words a crawler can read, and goes in every
// group because a crawler named below reads only its own.
const signal = 'Content-Signal: search=yes, ai-input=yes, ai-train=yes';

export const GET: APIRoute = () =>
  new Response(
    [
      ...['*', 'GPTBot', 'OAI-SearchBot', 'ChatGPT-User', 'ClaudeBot', 'Claude-SearchBot', 'Claude-User', 'PerplexityBot', 'Google-Extended', 'Applebot-Extended'].flatMap((bot) => [
        `User-agent: ${bot}`,
        signal,
        'Allow: /',
        '',
      ]),
      `Sitemap: ${new URL('/sitemap-index.xml', site.url)}`,
      '',
    ].join('\n'),
    { headers: { 'Content-Type': 'text/plain; charset=utf-8' } },
  );
