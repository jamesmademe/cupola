# CrossServiceAction

A control whose precondition is not met — another service not set up, or a credential that may only read — stays visible, reachable and pressable, dims its foreground, and answers a tap with the fix.

Hand-written from `lib/core/widgets/cross_service_action.dart` (`GatedAffordance`, `CrossServiceAction`, `CapabilityGatedAction`, `CapabilityGatedMenuLabel`).

## The rule

- Enabled: an ordinary control.
- Blocked: the **foreground only** drains to 38% (`GatedAffordance.dimmedOpacity`, Material's disabled level). The 44 × 44 minimum target, padding and any plate stay at full strength. The press still dips (`PressableScale`), without the haptic.
- The control keeps a real callback, so it is still a button, enabled, with its name and a hint. Never `onPressed: null`, never hidden.
- **Dimmed means not configured, never unreachable.** A down service keeps full ink and gets a FaultBand.

## Shapes

| Widget | Gated on | Hint | Blocked tap |
|---|---|---|---|
| `CrossServiceAction` (cell around a non-interactive child) | `isServiceConfigured(target)` — never health | *requires qBittorrent* (overridable) | Toast with the caller's sentence (*Connect qBittorrent to open this transfer.*), action **Settings** → that service's settings page |
| `CrossServiceAction.builder` | same | same | same; the builder's own button (`HeaderActionButton`, a `TextButton`) receives the gated `onPressed` and an `annotate` function that dims and hints its content |
| `CapabilityGatedAction` / `.builder` | the connection's grant for `resource` | the feature's hint, e.g. *requires a key that can write VMs*; default *requires a read-write key* | Toast with the caller's sentence (*This Unraid key can't start or stop VMs.*), action *Update the key* / *Change account* → that connection's settings |
| `CapabilityGatedAction.icon` | same | on the icon inside the `IconButton` | same |
| `CapabilityGatedAction.toggle` | same | merged onto the switch's node; the whole switch dims | same |
| `CapabilityGatedMenuLabel` | same | on the menu item's label; `onSelected` asks `capabilityWriteAllowed` | same |

When Cupola could not ask the service, every capability shape switches to *this key's permissions are unknown* as the hint and *Cupola couldn't check this TrueNAS key's permissions, so it's holding changes back.* with **Check again** as the toast.

Toasts are the app snackbar: floating, `inverse-surface`, `radius-md`, `body-medium` in `on-inverse-surface`, 4 s, action ink `inverse-primary`.

## The consumer provides

The target `ServiceKey` (or service, `connectionId` and `resource`), the accessible label or the builder, the toast sentence — only the caller knows what the jump was for — and `onTap`.

## Semantics

One node per control: button, enabled, the name, and the hint. A cross-service jump publishes *requires &lt;Service&gt;* in both states; a capability gate publishes its hint only while blocked. Annotate the button's **content**, never wrap the button in `Semantics(hint:)` — that annotation is dropped.

## Do / don't

- Do use the builder shape for anything that is already a button; wrapping a Material button in the cell nests a button inside a button.
- Do keep a saved-but-down target live: the destination reports its own fault.
- Don't use `Semantics(enabled: false)` or `SizedBox.shrink()` for a blocked control.
- Don't dim the plate or shrink the target.
