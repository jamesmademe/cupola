import type { APIRoute, GetStaticPaths } from 'astro';
import { pages, type Page } from '../../data/pages';
import { card } from '../../lib/og';

export const getStaticPaths: GetStaticPaths = () =>
  Object.values(pages).map((p) => ({ params: { slug: p.slug }, props: { page: p } }));

export const GET: APIRoute = async ({ props }) => {
  const { page } = props as { page: Page };
  const body = await card(page.heading, page.light);
  return new Response(body, { headers: { 'Content-Type': 'image/png' } });
};
