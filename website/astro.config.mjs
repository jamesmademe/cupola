import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import { site } from './src/config.ts';

export default defineConfig({
  site: site.url,
  trailingSlash: 'always',
  devToolbar: { enabled: false },
  build: { format: 'directory', inlineStylesheets: 'auto' },
  integrations: [sitemap({ filter: (page) => !page.includes('/404') })],
  // The site reads the README, the brand mark and the service marks from the
  // repository itself, so none of them is copied here.
  vite: { server: { fs: { allow: ['..'] } } },
});
