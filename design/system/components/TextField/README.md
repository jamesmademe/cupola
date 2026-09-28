# TextField

A filled input with no border at rest — the fill draws the boundary.

Rendered from `lib/core/theme.dart` (`inputDecorationTheme`) by `test/design_catalog/text_field_catalog_test.dart`. Every `TextField` / `TextFormField` in the app takes this theme; the one deliberate exception is the Dockge compose editor, which pins its own fill and border because its panel stays dark-toned in both app themes (see `dockge_stack_edit_screen.dart`).

## Values

- Fill `colorScheme.surfaceContainerHighest`, `AppRadius.borderRadiusMd`, content padding `AppSpacing.lg` horizontal × `AppSpacing.md` vertical.
- Hint in `textTheme.bodyMedium`, coloured `onSurfaceVariant`.
- Rest and enabled: no border (`BorderSide.none`).
- Focused: a 2px `colorScheme.primary` border.
- Error: a 1px `colorScheme.error` border at rest, 2px when focused, and the validation message under the field.

## Consumer provides

The label, the hint, the value, the keyboard type and the validation or error message. The settings forms wrap each field in its own `Semantics(label:, hint:)` rather than relying on the visible label/hint alone, so a screen reader hears the field's purpose stated plainly (e.g. "Enter your API key") rather than reading the on-screen hint text verbatim.

## Semantics

Give every field a `labelText`; a field with only a hint loses its floating label the moment it fills, and VoiceOver/TalkBack read a hint as placeholder text, not as the field's name.

## Do / don't

- Do obscure secrets (API keys, passwords) and pair `obscureText` with a reveal action rather than putting the value on the clipboard to check it.
- Do keep `keyboardType: TextInputType.visiblePassword` on obscured fields — it is what stops the platform offering autocorrect and word suggestions on a secret.
- Don't add an outline at rest or a local fill colour: the theme owns both, outside the one documented exception above.
