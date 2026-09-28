# SectionHeader

The heading of a region on a screen, optionally tappable through to its full list.

Hand-written from `lib/core/widgets/section_header.dart`.

- Title `title-large` at 600, `on-surface`; optional subtitle `body-small` tabular in `on-surface-variant`, 2px below.
- Padding `space-lg` horizontal, `space-xs` vertical. Sections sit `space-xl` apart.
- Default constructor: tappable, with a `primary` `chevron_right`; the whole row is the target, floored at 44 tall (a one-line title alone is 36). `.action`: the trailing slot is its own control and the header itself is not tappable.
- Above 1.4× reading size the row becomes a stack (title, then trailing full width); the title clamps at 1.6× so a long word does not break.

The consumer provides a sentence-case title (`Needs attention`, `Pool health`, `Array disks`) and an optional subtitle or trailing control. It is announced as a header; a tappable header is also a button (the "See all" pattern).

Do keep titles in sentence case. Don't put a second tap target in the default constructor's trailing slot — use `.action`.
