# QrCodeView

A QR code on a tile a camera can read: the invite's code, and any short text a person has to hand over by showing a screen.

Rendered from `lib/core/widgets/qr_code_view.dart` by `test/design_catalog/qr_code_view_catalog_test.dart`.

## Anatomy

- **Tile**: a square, `size` on a side, `AppRadius.md` (14, the control radius) at every corner, painted white. It does not take the room's ground: a scanner looks for dark modules on a light one, so the tile is white in the dark room too. In the light room it sits on a white panel and its edge disappears; the quiet zone is the same white, and the code reads the same. Black and white are written as such, in the one place in the app where they are the right paint.
- **Code**: the `qr` package's encoding of `data` at error correction level M, drawn in black. The quiet zone is the standard's four modules on each side, and the module is snapped **down to a whole logical pixel** (`side / (modules + 8)`, floored), so no module straddles a pixel and softens into its neighbour. The code is centred in the tile, and the pixels the snap leaves over are more quiet zone. A tile too small for a whole pixel per module at the payload's density falls back to the fraction that fits, so the code never draws past its tile.
- **One path**: every dark module goes into a single `Path`, so two modules that touch are one shape and no hairline shows between them at a fractional device pixel ratio.
- **Density**: a link of 57 characters is 33 modules (5 pixels each at 232); an invite with both addresses and both certificates is 65 (3 pixels); the longest an invite can be, with long hosts and a 64-character name, is 77 (2 pixels). Level M keeps the longest readable.
- The code is encoded once per `data`, in the state, never per frame. The painter repaints only when the code changes; a change of `size` lays the box out again, which paints it.

## The consumer provides

`data`, the text a scanner reads out of the code; `size`, the tile's side; `semanticLabel`, what the image is.

## Semantics

One image node with the label the caller passes (`QR code of the invite` in the invite sheet). The code itself says nothing to a screen reader, so whatever it carries must also be offered another way: the invite sheet's *Copy link*.

## States in the catalog

Each sheet is drawn in the dark and the light room, and the tile is white and black in both.

- A short payload and a long one at 232, the short at 120, and the long one on a desktop window.
- Text at 200%: the tile beside text at twice the reading size keeps its side.

## Do / don't

- Do give it a `semanticLabel`, and an alternative to scanning.
- Do keep it at 160 or more on a phone: under that, a long payload falls to a pixel a module.
- Don't paint it from the theme, tint it, put a logo in it or round its modules: dark on light is the one thing a scanner asks.
- Don't put a secret in `data`: a code is shown on a screen anyone can see.
