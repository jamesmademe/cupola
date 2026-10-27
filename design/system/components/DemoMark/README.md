# DemoMark

The demo's mark: a neutral `Demo` after each tab's name while the demo runs, and Settings' first card, which says where the visitor is and holds the way out. Nothing of it exists outside the demo.

Rendered from `lib/demo/presentation/demo_mark.dart` and `lib/demo/presentation/demo_settings_card.dart` by `test/design_catalog/demo_mark_catalog_test.dart`.

## Anatomy

- **The mark.** `ScreenTitle` (`lib/core/widgets/screen_title.dart`) is every tab's name (the Home's day, Discover, Activity, Requests, Stack) in `AppType.screen` and the room's ink; in the demo it is followed, `AppSpacing.sm` after the name, by a `TagChip` reading `Demo` in the primary ink, which is neutral: the demo is not a state, so it takes none of the five tones. The chip is centred in a 44pt target.
- **Settings' card.** The first thing under Settings' name, phone and window alike: a `SettingsGroupCard` of two rows, `You're exploring a demo home` · *Its servers are made up, and nothing you do here is kept.* (up to four lines at a large reading size), then `Leave demo` · *Back to the start, to set up your own*, `AppSpacing.xl` above the Connections card.

## The consumer provides

Nothing: both read `demoRunningProvider`, and the card reads `demoDoorProvider`, whose `leave` ends the session and starts the app again on the Welcome (`main.dart`).

## Behaviour

- A tap on the mark opens Settings, where the card is.
- `Leave demo` asks nothing: nothing real is lost.

## Semantics

The mark is one button, `Demo home`, with the hint *Opens Settings, where you can leave the demo.*; the chip's own text is silenced. The tab's name stays a header.

## States in the catalog

Three tab names with the mark, Settings' card, and both at 200%, each in the dark and the light room.

## Do / don't

- Do keep the mark neutral and small: it says where the visitor is, not that something is wrong.
- Don't draw it, or the card, outside the demo.
