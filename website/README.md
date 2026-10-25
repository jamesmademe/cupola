# get-seekarr.org

The website for Cupola: a static site built with [Astro](https://astro.build), served by Cloudflare Pages.

## Run it

```bash
cd website
npm ci
npm run dev      # http://localhost:4321
npm run check    # types
npm run build    # writes dist/
```

Node 22.23.4 or later (24 recommended). Run the scripts from `website/`: the build reads files from the rest of the repository.

## What it reads from the repository

The site copies none of these, so it cannot drift from the app:

- **The services table** comes from the README's *Supported services* section (`src/lib/repo.ts`). A change of shape there fails the build.
- **The service marks** come from `tool/service_glyphs/svg/`, the **brand mark** from `assets/brand/`.
- **The version** comes from `pubspec.yaml`.
- **The claim and the promise** are quoted in `src/config.ts`, exactly as the brand book has them.

## Links that change

`src/config.ts` holds every download link. A link left `null` is not offered: its platform reads *Not open yet* and points at GitHub releases, so no button leads nowhere. Set `downloads.testflight`, `downloads.apk` and `downloads.macos` when each is public, and `trailerYouTubeId` once the trailer is on YouTube (it loads only when someone presses play).

## Deploy on Cloudflare Pages

Connect the GitHub repository to a Pages project with:

| Setting | Value |
| --- | --- |
| Root directory | `website` |
| Build command | `npm run build` |
| Build output directory | `dist` |
| Environment variable | `NODE_VERSION` = `24` |

Then add the custom domain `get-seekarr.org`, and turn on **Web Analytics** in the project: Cloudflare injects its cookieless beacon, which `public/_headers` already allows. Security headers, caching and short redirects (`/download`, `/sonarr`, `/lunasea`, ...) live in `public/_headers` and `public/_redirects`.

## Artwork

The posters and stills are Blender open movies under Creative Commons Attribution, credited on `/credits/`. `scripts/build_art.py` bakes them into `public/art/` (WebP), `src/og/` (JPEG for the social cards) and `src/data/light.json` (each title's light); it needs Pillow and a folder of the original images.

The social cards (`/og/<page>.png`) are drawn at build time from `src/og/`, which also holds static instances of Bricolage Grotesque (600, width 80) and Onest (500) cut from `assets/fonts/` with fontTools, since the card renderer reads no variable axes.

## Words

The copy follows the brand book (`design/system/README.md`, *Who Cupola is* and *Words*): American English, sentence case, no em dash, no selling words, *movie* never *film*, and nothing promised that the app does not do.
