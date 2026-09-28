# CapabilityBanner

The quiet line at the top of a page that says what this credential cannot do — the FaultBand shape in the informational tone, because nothing is wrong.

Hand-written from `lib/core/widgets/capability_banner.dart` (`CapabilityBanner`, `CapabilityBannerSlot`) and `lib/core/capability/capability_copy.dart`.

## Anatomy

- A line, no fill, no border. Padding `space-xs` vertical, `space-lg` leading, `space-sm` trailing; `space-sm` gaps.
- Glyph `key` outlined, 16px, `info` walked against `surface` through `statusToneColor` — the only coloured thing on the line.
- Message `body-small`, `on-surface-variant`.
- Verb: text button in `primary`, `label-large`, horizontal padding `space-sm`, minimum 56 × 44.
- When the scaled `body-small` exceeds 20px (`stackThreshold`, about 1.6× reading size) the verb moves to its own line, right-aligned, `space-xs` below the glyph and sentence.

## Variants

`CapabilityBannerSlot` picks the sentence and the verb from why the scope is what it is:

| Basis | Sentence | Verb |
|---|---|---|
| The service answered | The feature's `CapabilityCopy.answered` — what the key can do, then what it cannot: *This Unraid key can read. Starting and stopping VMs needs a key with write access to VMs.* A page that gates several resources may use `partial`. | *Update the key*; *Change account* for Nginx Proxy Manager, whose credential is a role on an account |
| A write was refused earlier (learned from the refusal) | *Unraid refused a change from this key. It can still read; changes need write access to VMs.* | *Update the key* / *Change account* |
| Cupola could not ask | *Cupola couldn't check what this TrueNAS key may change, so changes are held back until it can. Reads are unaffected.* | *Check again* — re-runs the probe |

The slot renders nothing for a read-write credential, an unprobed connection, or a page whose own resources this credential may write.

## The consumer provides

For the slot: `connectionId`, the feature's `CapabilityCopy` and the page's `resources`. For the bare banner: `message`, `onFix` and optionally `actionLabel`. One banner per page, first under the page's own chrome, above the first section.

## Semantics

One container node labelled with the sentence; the verb stays its own control. **Not** a live region: the banner is drawn on every visit to every page of a read-only connection, and announcing it each time would interrupt each visit with the same sentences. The dimmed controls below carry the same fact in their hints.

## Do / don't

- Do keep it blue: a read-only credential is a configuration fact, not a fault.
- Do keep every write below it visible, dimmed to 38% and reachable through `CapabilityGatedAction`; readouts keep refreshing.
- Don't make it dismissible — the scope is still true a second later.
- Don't write a generic "limited permissions": name the service, the credential and the scope in the service's own terms.
