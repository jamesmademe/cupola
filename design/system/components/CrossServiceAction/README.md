# CrossServiceAction

A control whose precondition is not met — another service not set up, or a credential that may only read — stays visible, reachable and pressable, dims its foreground, and answers a tap with the fix.

Rendered from `lib/core/widgets/cross_service_action.dart` (`GatedAffordance`, `CrossServiceAction`, `CapabilityGatedAction`, `CapabilityGatedMenuLabel`) by `test/design_catalog/cross_service_action_catalog_test.dart`.

## The rule

- Enabled: an ordinary control.
- Blocked: the **foreground only** drains to 38% (`GatedAffordance.dimmedOpacity`, Material's own disabled level). The target, padding and any plate or fill stay at full strength.
- The control keeps a real callback, so it is still a button, enabled, with its name and a hint. Never `onPressed: null`, never hidden: a disabled node is skipped by VoiceOver and TalkBack, and a hidden one teaches that the feature does not exist.
- **Dimmed means not configured, never unreachable.** A saved service that is down keeps full ink and gets a `FaultBand`; the jump stays live and the destination reports its own fault.

## Shapes

| Widget | Gated on | Hint | Blocked tap |
|---|---|---|---|
| `CrossServiceAction` — the cell, around a non-interactive child (a glyph, a caption) | `isServiceConfigured(target)`, never health | *requires qBittorrent* (`requires <Service>`, overridable with `hint`) | Toast with the caller's sentence (*Connect qBittorrent to open this transfer.*), action **Settings** → that service's own settings page |
| `CrossServiceAction.builder` — a control that is already a button | same | same | same |
| `CapabilityGatedAction` / `.builder` | the connection's grant for `resource` | the feature's hint, e.g. *requires a key that can write VMs*; default *requires a read-write key* | Toast with the caller's sentence (*This Unraid key can't start or stop VMs.*), action **Update the key** (**Change account** for Nginx Proxy Manager) → that connection's settings |
| `CapabilityGatedAction.icon` | same | on the icon inside the `IconButton` | same |
| `CapabilityGatedAction.toggle` | same | merged onto the switch's own node; the whole switch dims and keeps the server's value | same |
| `CapabilityGatedMenuLabel` | same | on the menu item's label; the item stays enabled and its `onSelected` asks `capabilityWriteAllowed` | same |

The cell draws its child through `PressableScale`: a 44 × 44 minimum target around the child, a 0.97 press dip, and the haptic only when it can act. The builder shapes hand the caller's button the gated `onPressed` and an `annotate` function that dims and hints the button's **content** — `HeaderActionButton` (an outlined 48pt square with a caption under it) takes it as its `annotate` parameter and dims glyph and caption together; a `TextButton` or `FilledButton` wraps its label in it. `.icon` keeps the `IconButton`'s own target.

When Cupola could not ask the service (`CapabilityBasis.unanswered`), every capability shape switches to the hint *this key's permissions are unknown* and the toast *Cupola couldn't check this key's permissions, so it's holding changes back.* with **Check again**, which re-asks instead of sending the user to replace a key that may work. Nginx Proxy Manager says *account* where the others say *key*. While the probe is still out the grant is `unknown`, which stays live.

Toasts are `SnackBarHelper.withAction`: the theme's floating snackbar — `inverseSurface`, `AppRadius.borderRadiusMd`, `bodyMedium` in `onInverseSurface`, action ink `inversePrimary` — for 4 s, one sentence, one action. When the sentence and the action do not fit one line, Material moves the action under the sentence.

## The consumer provides

The target `ServiceKey` (or `service`, `connectionId` and `resource`), the accessible `label` or the builder, the toast sentence — only the caller knows what the jump was for — and `onTap`. The toggle takes a controlled `value` and `onChanged`.

## Semantics

One node per control: button, enabled, the name, and the hint. A cross-service jump publishes *requires &lt;Service&gt;* in both states; a capability gate publishes its hint only while blocked. The cell excludes its child's semantics, so `label` is required even when the child shows text. Annotate the button's **content**, never wrap the button in `Semantics(hint:)` — that annotation lands on a node the screen reader never focuses.

## Do / don't

- Do use a builder shape for anything that is already a button; wrapping a Material button in the cell nests a button inside a button.
- Do gate a flow (a form sheet, a typed confirmation) at the tap that opens it, never after the form is filled.
- Don't use `Semantics(enabled: false)`, `onPressed: null` or `SizedBox.shrink()` for a blocked control.
- Don't dim the plate or the fill, and don't shrink the target.
