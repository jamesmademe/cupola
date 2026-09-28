# TextField

A filled input with no border at rest — the fill draws the boundary.

Hand-written from `lib/core/theme.dart` (`inputDecorationTheme`). Every `TextField` / `TextFormField` in the app takes this theme; none restyles it locally.

## Values

- Fill `surface-container-highest`, `radius-md`, content padding `space-lg` horizontal × `space-md` vertical.
- Text `body-medium` in `on-surface`; hint `body-medium` in `on-surface-variant` (clears AA on the fill in both themes).
- Rest and enabled: no border.
- Focused: a 2px `primary` border.
- Error: a 1px `error` border at rest, 2px when focused, and the validation message under the field in `body-small`.

## Consumer provides

The hint, the value, the keyboard type and the validation message.

## Semantics

The hint doubles as the field's accessible name when no label is given, so write it as the name of the value ("Base URL", "API key"), not as an instruction.

## Do / don't

- Do obscure secrets (API keys, passwords); they are stored only in the device keychain.
- Do show credentials and certificate fingerprints in `mono`.
- Don't add an outline at rest or a local fill colour: the theme owns both.
