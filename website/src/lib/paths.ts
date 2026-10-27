// Paths on disk at build time. Bundling moves this code, so paths come from
// the working directory (the website folder, where npm runs its scripts)
// rather than from import.meta.url.
import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

export const SITE_DIR = process.cwd();
export const REPO_DIR = resolve(SITE_DIR, '..');

if (!existsSync(join(REPO_DIR, 'pubspec.yaml')) || !existsSync(join(SITE_DIR, 'astro.config.mjs'))) {
  throw new Error(`Run the website's scripts from website/ inside the Cupola repository (cwd: ${SITE_DIR})`);
}

export const inRepo = (path: string) => join(REPO_DIR, path);
export const inSite = (path: string) => join(SITE_DIR, path);
