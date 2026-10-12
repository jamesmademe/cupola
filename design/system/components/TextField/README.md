# TextField

A filled input with a hairline edge at rest; the quiet fill and the edge draw the boundary.

Rendered from `lib/core/theme.dart` (`inputDecorationTheme`) by `test/design_catalog/text_field_catalog_test.dart`. Every `TextField` / `TextFormField` in the app takes this theme; the one deliberate exception is the Dockge compose editor, which pins its own fill and border because its panel stays dark-toned in both app themes (see `dockge_stack_edit_screen.dart`).

## Values

- Fill `room.fillQuiet` (white at 6% dark, ink at 5% light), `AppRadius.borderRadiusField` (16), content padding `AppSpacing.lg` horizontal × `AppSpacing.md` vertical.
- Hint in `textTheme.bodyMedium`, coloured `onSurfaceVariant`.
- Rest and enabled: a 1px `room.edge` border.
- Focused: a 1.5px `room.focus` border, the secondary ink.
- Error: a 1.5px border in the amber fault tone (`room.toneAmber`), at rest and focused, and the validation message under the field in `bodySmall` in the same tone; a refusal is a fault, and red is reserved for unreachable.

## Consumer provides

The label, the hint, the value, the keyboard type and the validation or error message. The settings forms wrap each field in its own `Semantics(label:, hint:)` rather than relying on the visible label/hint alone, so a screen reader hears the field's purpose stated plainly (e.g. "Enter your API key") rather than reading the on-screen hint text verbatim.

## Semantics

Give every field a `labelText`; a field with only a hint loses its floating label the moment it fills, and VoiceOver/TalkBack read a hint as placeholder text, not as the field's name.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- Rest, focused (the phone sheet), error, the obscured API-key field, disabled.
- A long label, value and helper on a 280pt field.
- Text at 200%: rest with a hint, and with an error.
- Focused and in error on the desktop sheet, where the keyboard holds focus.

## Do / don't

- Do obscure secrets (API keys, passwords) and pair `obscureText` with a reveal action rather than putting the value on the clipboard to check it.
- Do keep `keyboardType: TextInputType.visiblePassword` on obscured fields: it is what stops the platform offering autocorrect and word suggestions on a secret.
- Don't add a local outline or fill colour: the theme owns both, outside the one documented exception above.
