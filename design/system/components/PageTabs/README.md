# PageTabs

A page's views, side by side in one track: the control at the head of a tab's root page whose views are whole pages with their own addresses (Activity's All · Downloads · Requests · History). One of them is the page; every view is on screen at once and none scrolls away.

Rendered from `lib/core/widgets/page_tabs.dart` (`PageTabs<T>`), as Activity draws it from `lib/features/activity/domain/activity_tab.dart` (`ActivityTab`), by `test/design_catalog/page_tabs_catalog_test.dart`.

## Where it is drawn

| place | values | a tap |
|---|---|---|
| Activity, under the page's name | `ActivityTab.values` (All, Downloads, Requests, History) | `context.go(tab.location)`: the address changes and the same page draws the view |
| The Review of blocked imports, above its two parts | `Clear 12`, `Need you 6` (the second count in amber) | a jump: the page scrolls to the part, and the thumb follows the scroll ([ImportReview](../ImportReview/README.md)) |

A choice inside a section keeps [`SelectionPills`](../SelectionPills/README.md); `PageTabs` is the page's own, so a page carries one of it and never two rows that filter one axis.

## Anatomy

- Track: a rounded rectangle (radius 14) in the room's quiet fill (`fillQuiet`) with a 1px hairline (`hair`) and 1px of padding inside it. It takes the width it is given and is as tall as its rows.
- Segment: one share of the track, the whole share its target and at least `PageTabs.height` (44) tall at the default reading size. A 2px gap separates two segments.
- Thumb: inside the selected segment, inset 2px, in the primary ink (`colorScheme.primary`) under the label in `onPrimary`: the same ink as the navigation bar's selected pill, in both rooms. Monochrome: no service or section colours it.
- Unselected label: `AppType.label` in `inkSecondary`. Selected label: the same face in `onPrimary`.
- Label: one line, centred, `AppSpacing.xs` on each side; it fades rather than ellipsising if it is ever cut.
- Count (`countOf`): after the label, two spaces and tabular figures, in the label's colour or in a tone when it carries one (`Need you 6`, amber); on the thumb the tone is resolved against the ink.
- Motion: the thumb and the label's colour ease over `AppAnimation.durationLg`; with Reduce Motion (`MediaQuery.disableAnimations`) they change at once. A change of view gives a selection haptic.

## Layout

The views share the track equally. When the widest label plus its padding no longer fits its share (a long word, a large reading size) and there are three or more views, the track lays them two by two: a row of two, then the rest, every segment the width of the ones above (a short last row keeps its segment's width). A word is never cut and the target never shrinks. Two views never wrap: a pair has no second row.

## The consumer provides

`values`, the `selected` value, a `labelBuilder`, `onSelected`, and optionally a `semanticLabel` (the group's name to a screen reader, `Show` by default; Activity says `Activity views`, the Review `Jump to`) and a `countOf` (a count and its tone, per value). No colour: the thumb takes none.

## Semantics

The track is one container with the group's label. Each segment is a button that announces its own label (with its count: `Need you, 6`), whether it is selected, and that it belongs to a mutually exclusive group; the selected one has no tap action (`onTap` is null) and the press animation and ripple are excluded from the tree, so a segment reads as one thing.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the phone and on the desktop.

- The four views at 390pt with All selected, then Downloads, then Requests and History together on the widest phone (430pt).
- A long label at 320pt: the track two by two at the default reading size.
- Text at 200%: the four views two by two at 390pt and at 430pt, none cut, every segment 44pt tall at least.
- The desktop: the same track in the page well, at the default size and at 200%.
- With counts: the Review's `Clear 12` and `Need you 6`, the second in amber, each selected in turn.

## Do / don't

- Do use it for the views of a page that has its own addresses, and make each tap an address change so Back and a link name the view.
- Do use it, as the one other use, to jump between the parts of one long page, with the thumb following the scroll: it names where you are, it filters nothing.
- Do keep one of it on a page: it is the page's views, not a filter.
- Don't use it for a choice inside a section: that is `SelectionPills`.
- Don't give it a fixed height or squeeze the labels: the two-by-two layout is how it keeps a word whole at a large reading size.
- Don't colour the thumb from a service or a tone: it is the ink.
