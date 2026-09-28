# FloatingBottomNavBar

The detached glass bar that carries the four canonical tabs on phones: Dashboard, Activity, Search, Settings.

Hand-written from `lib/core/widgets/floating_bottom_nav_bar.dart` and `lib/features/settings/domain/nav_tab.dart`.

- Bar: 60px tall, inset `space-lg` from the sides, `radius-xl`, `glass-surface` fill (a semi-opaque tint, not a backdrop blur), `glass` shadow, 1px border (white 12% on dark, `outline` 85% on light), inner padding 6px.
- Selected destination: a 36px pill, `radius-pill`, min width 84px, padding 0 × 14px, icon + label with a 6px gap; the section accent (`nav-dashboard`, `nav-activity`, `nav-search`, `nav-settings`) at 16% / 13% with a 27% border; icon and label walked by `onTint`. Label `label-medium` at 600.
- Unselected: icon only, outlined variant, 20px, `on-surface-variant`, 48px target.
- Badge: 15px tall, radius 8px, the destination's own accent (never a status tone), a 1.5px `surface` ring, count in `label-small` 600 tabular, capped at `9+`.

Below `bp-nav-compact` (360px) the items switch to compact targets. The bar clamps its text scale at 1.3× and reserves clearance so the last row of any list can scroll above it. Above 840px a `NavigationRail` takes over with the same destinations and accents. Each item is announced as “Label, Tab N of M” with its selected state.
