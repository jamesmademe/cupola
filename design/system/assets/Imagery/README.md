Sample artwork for renditions of media surfaces: one poster (`poster.jpg`, 300×450, from TMDB's `w500`) and one backdrop (`backdrop.jpg`, 800×450, from TMDB's `w1280`), taken from Cupola's own image cache and reduced, so previews show artwork the way the app receives it. The title is *Nosferatu* (1922).

- Artwork is content, never palette: it sits in `plate-*` wells, under `AppGradients.heroScrim` on a backdrop, cropped with cover fit. Never sample colours from it into the UI.
- A missing image is a real state and stays a plate — these files do not replace the no-artwork renditions.

Cards reference them as `__POSTER__` and `__BACKDROP__`; the gallery (`tool/design_system/gallery.py`) substitutes the files.
