# CapabilityBanner

The quiet line at the top of a page that says what this credential cannot do — the `FaultBand` shape in the informational tone, because nothing is wrong.

Rendered from `lib/core/widgets/capability_banner.dart` (`CapabilityBanner`, `CapabilityBannerSlot`) and `lib/core/capability/capability_copy.dart` by `test/design_catalog/capability_banner_catalog_test.dart`.

## Anatomy

- A line, no fill, no border. Padding `AppSpacing.xs` top and bottom, `AppSpacing.lg` leading, `AppSpacing.sm` trailing; `AppSpacing.sm` gaps.
- Glyph `Icons.key_outlined`, 16px, the info tone walked against `colorScheme.surface` through `statusToneColor` — the only coloured thing on the line.
- Message in `textTheme.bodySmall`, coloured `onSurfaceVariant`.
- Verb: `TextButton` in `colorScheme.primary`, `minimumSize: Size(56, 44)`, `AppSpacing.sm` horizontal padding. No compact density.
- When a 12px measure scaled by the reading size exceeds `CapabilityBanner.stackThreshold` (20 logical pixels, about 1.6×) the verb moves to its own line, right-aligned, `AppSpacing.xs` below the glyph and sentence. A `Row` cannot shrink a 44pt-target button, so past that scale the layout stacks instead of overflowing.

## Variants

`CapabilityBannerSlot` picks the sentence and the verb from why the scope is what it is (`CapabilityBasis`):

| Basis | Sentence | Verb |
|---|---|---|
| The service answered (`answered`) | The feature's `CapabilityCopy.answered` — what the key can do, then what it cannot: *This Unraid key can read. Starting and stopping VMs needs a key with write access to VMs.* A page gating several resources with a `partial` credential names only what it cannot change *there*. | The service's `capabilityFixLabel` — `Update the key`, or `Change account` for Nginx Proxy Manager, whose credential is a role on an account |
| A write was refused earlier (`refused`) | *Unraid refused a change from this key. It can still read; changes need write access to VMs.* | Same as above |
| Cupola could not ask (`unanswered`) | *Cupola couldn't check what this TrueNAS key may change, so changes are held back until it can. Reads are unaffected.* | *Check again* — re-runs the probe |

The slot renders nothing (`SizedBox.shrink()`) for a read-write credential, an unprobed connection (`CapabilityScope.unknown` stays live on purpose), or a page whose own `resources` this credential may write.

## The consumer provides

For the slot: `connectionId`, the feature's `CapabilityCopy` and the page's `resources` (`null` asks about the whole connection). For the bare banner: `message`, `onFix` and optionally `actionLabel` (defaults to `'Update the key'`). One banner per page, first under the page's own chrome, above the first section.

## Semantics

One container node (`Semantics(container: true, explicitChildNodes: true, label: message)`); the verb stays its own reachable control. **Not** a live region: the banner is drawn on every visit to every page of a read-only connection, and announcing it each time would interrupt each visit with the same sentences. The dimmed controls below carry the same fact in their own hints.

## Do / don't

- Do keep it blue: a read-only credential is a configuration fact, not a fault.
- Do keep every write below it visible, dimmed to 38% and reachable through `CapabilityGatedAction`; readouts keep refreshing.
- Don't make it dismissible — the scope is still true a second later.
- Don't write a generic "limited permissions": name the service, the credential and the scope in the service's own terms.
