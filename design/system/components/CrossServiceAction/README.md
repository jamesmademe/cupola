# CrossServiceAction

A control whose precondition is not met — another service not set up, or a credential that may only read — stays visible, reachable and pressable, dims its foreground, and answers a tap with the fix.

Rendered from `lib/core/widgets/cross_service_action.dart` (`GatedAffordance`, `CrossServiceAction`, `CapabilityGatedAction`, `CapabilityGatedMenuLabel`, `RoleGatedAction`) by `test/design_catalog/cross_service_action_catalog_test.dart`.

## The rule

- Enabled: an ordinary control.
- Blocked: the **foreground only** drains to 38% (`GatedAffordance.dimmedOpacity`, Material's own disabled level). The target, padding and any plate or fill stay at full strength.
- The control keeps a real callback, so it is still a button, enabled, with its name and a hint. Never `onPressed: null`, never hidden: a disabled node is skipped by VoiceOver and TalkBack, and a hidden one teaches that the feature does not exist.
- **Dimmed means not configured, never unreachable.** A saved service that is down keeps full ink and gets a `FaultBand`; the jump stays live and the destination reports its own fault.

## Shapes

| Widget | Gated on | Hint | Blocked tap |
|---|---|---|---|
| `CrossServiceAction` — the cell, around a non-interactive child (a glyph, a caption) | `isServiceConfigured(target)`, never health | *requires qBittorrent* (`requires <Service>`, overridable with `hint`) | Toast with the caller's sentence (*Set up qBittorrent to open this transfer.*), action **Set up qBittorrent** → that service's own setup form (`ServiceRoutes.setUp`, where every *Set up X* goes) |
| `CrossServiceAction.builder` — a control that is already a button | same | same | same |
| `CapabilityGatedAction` / `.builder` | the connection's grant for `resource` | the feature's hint, e.g. *requires a key that can write VMs*; default *requires a read-write key* | Toast with the caller's sentence (*This Unraid key can't start or stop VMs.*), action **Update the key** (**Change account** for Nginx Proxy Manager) → that connection's settings |
| `CapabilityGatedAction.icon` | same | on the icon inside the `IconButton` | same |
| `CapabilityGatedAction.toggle` | same | merged onto the switch's own node; the whole switch dims and keeps the server's value | same |
| `CapabilityGatedMenuLabel` | same | on the menu item's label; the item stays enabled and its `onSelected` asks `capabilityWriteAllowed` | same |
| `RoleGatedAction.builder` | the verdict a Seerr connection's `RoleGate` gives the control: `Live`, `Dimmed` with its reason, or `Absent` | the reason, while dimmed: *Your account on Seerr can't manage media.*, *You can't ask for series on this server.* | Toast with the reason and no action: the fix is on the server, with whoever runs it. `Absent` draws nothing, the one gate that may leave a control out, because the control is not part of the requester's app |

The cell draws its child through `PressableScale`: a 44 × 44 minimum target around the child, a 0.96 press dip, and the haptic only when it can act. The builder shapes hand the caller's button the gated `onPressed` and an `annotate` function that dims and hints the button's **content** — an `OutlinedButton` with a glyph wraps glyph and label in it and dims them together; a `TextButton` or `FilledButton` wraps its label in it. `.icon` keeps the `IconButton`'s own target.

When Cupola could not ask the service (`CapabilityBasis.unanswered`), every capability shape switches to the hint *this key's permissions are unknown* and the toast *Cupola could not check this key's permissions, so it's holding changes back.* with **Check again**, which re-asks instead of sending the user to replace a key that may work. Nginx Proxy Manager says *account* where the others say *key*. While the probe is still out the grant is `unknown`, which stays live.

Toasts are `SnackBarHelper.withAction`: the theme's floating snackbar — `inverseSurface`, `AppRadius.button` (16) with a 1px `room.edge` line, `bodyMedium` in `onInverseSurface`, action ink `inversePrimary` — for 4 s, one sentence, one action. When the sentence and the action do not fit one line, Material moves the action under the sentence.

## The consumer provides

The target `ServiceKey` (or `service`, `connectionId` and `resource`), the accessible `label` or the builder, the toast sentence — only the caller knows what the jump was for — and `onTap`. The toggle takes a controlled `value` and `onChanged`.

## Semantics

One node per control: button, enabled, the name, and the hint. A cross-service jump publishes *requires &lt;Service&gt;* in both states; a capability gate publishes its hint only while blocked. The cell excludes its child's semantics, so `label` is required even when the child shows text. Annotate the button's **content**, never wrap the button in `Semantics(hint:)` — that annotation lands on a node the screen reader never focuses.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- Each shape enabled and blocked: the cell around a glyph, the builder around a glyph button and a text button, the capability icon, switch, filled button and menu label (read-write, read-only and not yet checked keys), and the role-gated Manage (live, dimmed, absent).
- The toast a blocked tap raises: a cross-service jump, a read-only key, permissions unknown.
- Text at 200%: the blocked shapes together, and the toast with its action moved under the sentence.

## Do / don't

- Do use a builder shape for anything that is already a button; wrapping a Material button in the cell nests a button inside a button.
- Do gate a flow (a form sheet, a typed confirmation) at the tap that opens it, never after the form is filled.
- Don't use `Semantics(enabled: false)`, `onPressed: null` or `SizedBox.shrink()` for a blocked control. The requester's `Absent` is not a blocked control: it is one the requester's app does not have.
- Don't dim the plate or the fill, and don't shrink the target.
