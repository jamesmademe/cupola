# AppCard

The container every panel, tile and settings group is built on.

Rendered from `lib/core/widgets/app_card.dart` by `test/design_catalog/app_card_catalog_test.dart`.

## Variants

- `AppCard.filled` (default), the slab: `surface-container` with its `line.hair` edge, flat in the dark room and lifted softly on paper (`AppElevation.level1`, 0 in the dark).
- `AppCard.outlined`: transparent with a 1px `outline` edge.
- `AppCard.surfaceOutlined`: the slab with an edge of the caller's (`borderColor`), `line.hair` by default.
- `AppCard.elevated`: the slab with an explicit `AppElevation.level2` shadow stack.
- All: `radius.slab` (26) corners, padding `space-lg` unless overridden. The edge is drawn over the card, never as a border that insets the child, so a card keeps its interior size whether it is tappable or not. It drew `radius-md` (14) with no edge, against the brand book's slab.
- Optional `accentColor` paints one radial glow behind the content (`AppGradients.serviceGlow`), from `accentGlowCenter` (default top-right) at `accentGlowAlpha` (default 0.22), one card lit on its own. The light is the lamp for a service (`ServiceKey.accent`) or a tone on a card about a state. A grid of cells lighting from the same light should pass a fraction of that, e.g. 0.08 from `Alignment.topLeft`, or thirteen cells at full strength stop reading as lit cells and start reading as decoration.

## Press feedback

`AppCardPressFeedback`, a parameter rather than a constructor cross product, because feedback is orthogonal to variant:

- `.ink` (default): Material's ink ripple painted above the card's background. Right for a card with room for a splash to read as a touch spreading across a surface.
- `.scale`: the card dips to 0.96 under the thumb (`PressableScale`) with a light haptic, and paints no ink at all. For cards too small for a ripple to read as anything but a flood.

Ignored when the card has no `onTap`.

## The consumer provides

The child, and for a tappable card a `semanticLabel` (the card speaks one sentence; `AppCard`/`SettingsCard` are the reference for composing it), plus optional `semanticValue` and `semanticHint`. `excludeChildSemantics` hides the child's own nodes behind that label; leave it off when `child` holds a control of its own (a popup menu, a delete button) and wrap only the parts the label already speaks in `ExcludeSemantics` at the call site. A card that silences its subtree still offers a descendant's custom actions through `customSemanticsActions`, published on the card's own node beside the tap (the copy action of a `MachineName` in the row's body: `MachineName.fileCopyActions`).

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The four containers: filled, outlined, surface outlined, elevated.
- Tappable and lit (`accentColor`), a grid cell's fraction of the glow, `pressFeedback: scale`.
- Text at 200%: the four containers, the elevated one tappable and lit.

## Do / don't

- Do reach for `.elevated` only when the card has earned it; flat (`.filled`) is the default, and a shadow is a claim about depth.
- Do pass the card's own background as the chip/text `surface` for anything measured on top of it; an `accentColor` glow changes the composite.
- Don't add a shadow under `.scale` press feedback expecting an `InkWell`: `.scale` paints no ink at all, by design.
