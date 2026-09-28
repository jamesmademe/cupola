# AppEmptyState

What a list says when it is truly empty — calm, never alarming, and never a disguise for a failure.

Hand-written from `lib/core/widgets/app_empty_state.dart`.

- **Full** — a 72px circular well (`surface-container-high`, or the accent at 14%) with a 34px icon, `space-lg`, title `title-medium` 600, `space-sm`, message `body-medium` in `on-surface-variant`, optional action `space-xl` below. Padding `space-xxl` × 40px.
- **Compact** — 52px well, 26px icon, title `title-small` 600, padding `space-xl`, action `space-lg` below.
- **Inline** — a left-aligned note: 16px icon, `space-sm`, title `body-small` 600 and optional message, both `on-surface-variant`. No action.
- With an accent, the icon is walked by `onTint` against the 14% well.

The consumer provides icon, title, optional message and action. The state is a leaf: the page owns scrolling and centring so it can grow at accessibility sizes. An unconfigured service is not an empty list — it uses the Not set up placeholder; a failed load is a FaultBand, not an empty state.
