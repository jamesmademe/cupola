# EditHome

The page where a person arranges their own Home: modules reordered and switched off, nothing added.

Rendered from `lib/features/home/presentation/edit_home_page.dart` (`EditHomePage`), by
`test/design_catalog/edit_home_catalog_test.dart`. It edits `homeLayoutProvider`
(`lib/features/home/data/home_layout_provider.dart`), the person's layout read against the `HomeModule` registry;
the rules of reading it are in `lib/features/home/domain/home_layout.dart`.

## Where it opens

At `/home/edit`, from the Edit Home row at the foot of the operator's Home, and at `/settings/home`, from the `Home`
row of Settings (`8 modules · Requests hidden`: the modules the Home draws, and the ones the person switched off; a
module that starts off is added, not unhidden), the desktop's Settings rail and the command deck. The way back is
the page it was opened from (`MediaBackPlate`).

## Parts

- The back plate, `Edit Home` in the room role, and one paragraph: the Home starts from the default for its person;
  reorder and hide, nothing else is added.
- **Modules, in order**: one row per module, Needs you first by default, its handle (`drag_indicator`, 44pt), its name in
  the row role and its line in `meta`, its switch. Needs you has no switch: it can be moved, never hidden. A switched-off module's words dim to half. While none of the services that feed a module
  is set up, its line says what it needs instead (`Needs TrueNAS or Unraid`, `Needs Seerr`). Stack health, Storage and
  Discover shelf start off. Held, the handle drags the row; tapped, it
  lifts the row (`fillQuiet`) and its switch gives way to two 44pt arrows, the one at the end of the order dimmed.
  Dragging, arrows and screen-reader moves preserve the same saved order in either direction.
- The hint: `Hold a handle and drag, or tap it and use the arrows. With VoiceOver: Move up, Move down.` (TalkBack on
  Android, a screen reader elsewhere).
- **At the foot of Home**: Set up next, which stands last, with a switch and no handle.
- `Reset to default`, full width, dimmed while the layout already is the default; it also forgets the stored layout.
- One line on the other person's default, built from the registry, so it never names a module the app does not have.

Groups are `slab` under a `hair` edge, `AppRadius.group`, rows at least 64pt with a hairline between them.

## Semantics

Each group is named (`Modules, in order`, `At the foot of Home`). The handle is a toggle button,
`Move Arrived` and, lifted, `Put Arrived down`; the arrows say `Move Arrived up` and `Move Arrived down`. The switch
carries the module's name and line. The handle and the switch both carry the custom actions Move up and Move down, so
a screen reader can reorder from wherever it lands on the row.

## States in the catalog

Each sheet is drawn in the dark and the light room: the operator's default; arranged (Requests moved up, Downloads
switched off, Reset lit); the requester's own Home; text at 200%.

## Do / don't

- Do keep each person's layout apart: an operator who becomes a requester on the same device finds her own Home.
- Don't add a module here: the registry gives each person their modules, this page only moves and hides them.
