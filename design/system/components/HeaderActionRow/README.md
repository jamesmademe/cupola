# HeaderActionRow

The two button styles of a media header action: the promoted primary, and the square disc beside it. The row widget that once composed them is gone; the app draws its buttons with these styles directly.

Rendered from `lib/core/widgets/header_action_row.dart` (`HeaderActionRow`) by `test/design_catalog/header_action_row_catalog_test.dart`. The catalog builds plain buttons from the styles, in the variants `lib/` uses.

## The constants

- `HeaderActionRow.buttonHeight` is **52**, `size.button-l`: the brand book's primary, above the 48 touch floor (the larger of iOS 44pt and Android 48dp). The media actions and the back button size their rows to it.
- `HeaderActionRow.glyphSize` is **18**: the glyph every action control draws its icon at.

## The styles

- **Primary** (`expandedButtonStyle`): a `FilledButton.icon`, the ink button: `primary` fill with the label and glyph in `on-primary`, on every service. The promoted verb is never the service's colour. Enabled and disabled are both drawn: disabled drops the fill and keeps the label.
- **Disc** (`iconOnlyButtonStyle`): a `FilledButton` square, the ink equivalent of the primary, at `buttonHeight` across, with the glyph inside. Enabled and disabled are both drawn.

## Where `lib/` uses them

- `expandedButtonStyle`: the Videos button on a title (`discover_videos_button.dart`), enabled when the title has videos and disabled when it has none.
- `iconOnlyButtonStyle`: the square Videos button beside it, with the same two states.
- `buttonHeight`: the media detail actions, the value sheet and the detail back button take their row height from it.
- `glyphSize`: the same glyph size in the detail actions, the value sheet and the manual-import fix sheet.

## Do / don't

- Do keep the primary at `buttonHeight` and every label wrapped in the reading-size clamp.
- Don't make a visible Delete; don't round a control into a pill.
- Don't use `fixedSize` on a labelled control.

## States in the catalog

- Primary enabled and disabled, on the phone and the desktop.
- Disc enabled and disabled.
- Primary beside its disc at 2× reading size.
