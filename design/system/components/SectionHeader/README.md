# SectionHeader

The heading of a region on a screen, optionally tappable through to its full list.

Rendered from `lib/core/widgets/section_header.dart` by `test/design_catalog/section_header_catalog_test.dart`.

- Title `title-large` at 600, `on-surface`; optional subtitle `body-small` tabular in `on-surface-variant`, 2px below — tabular because a subtitle is often a live count ("3 of 12 selected") that must not shuffle sideways as it changes.
- Padding `space-lg` horizontal, `space-xs` vertical, around the whole header. The gap after a header, and the gap between sections, belong to the caller — `ServiceOverviewSection` follows its own with `space-sm` before the body and `space-lg` after it.
- Default constructor: tappable, with a `primary` `chevron_right`; the whole row is the target, floored at 44pt tall (a one-line title alone is 36pt). `.action`: the trailing slot is its own control and the header itself is not tappable — never a second tap target in the default constructor's trailing slot.
- Above 1.4× reading size, a header whose trailing slot is occupied stacks: title first, then that slot at full width below it. This also fires for a default, chevron-only header with no explicit `trailing` — the bare chevron becomes the same "end" slot internally, so it can end up alone on its own line rather than staying beside the title. The title itself clamps its scaling at 1.6× so a long word wraps between words instead of breaking mid-word.

## The consumer provides

A sentence-case title (`Needs attention`, `Pool health`, `Array disks`), an optional subtitle, and either nothing (default chevron), an `onTap` with `showChevron: false`, or `.action`'s own `trailing` control. `semanticLabel` overrides the spoken name when the visible title folds in a count or the trailing carries information (a non-interactive trailing is otherwise silenced); `semanticHint` says where a tap leads.

## Semantics

The whole header is one node: `header: true`, plus `button: true` when tappable. Title, subtitle and a non-interactive trailing are excluded and folded into one composed label; an interactive `.action` trailing keeps its own node.

## Do / don't

- Do keep titles in sentence case.
- Don't put a second tap target in the default constructor's trailing slot — use `.action`.
