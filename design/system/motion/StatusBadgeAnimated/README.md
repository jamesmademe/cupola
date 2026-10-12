# StatusBadgeAnimated

`StatusBadge.animated`, the one badge that moves: on the media detail hero it cross-fades when the status changes and sweeps its progress ring on each poll, so a title can be watched going from queued to available.

Hand-written from `lib/core/widgets/status_badge.dart`; static anatomy is on the **StatusBadge** card. The walk is Queued → Downloading (8, 23, 41, 57, 76, 94%) → Importing → Available, over `__BACKDROP__` as on the hero, plus the same badge at ×2.

- **Cross-fade**: an `AnimatedSwitcher`, `durationSm` 320ms, `switchInCurve` `emphasizedCurve` = `Cubic(0.2, 0.8, 0.2, 1)`, default linear out. The incoming row fades in, the outgoing fades out, stacked centred. The switcher's key is `availability-pipeline-label`, not the percentage; so a poll that only moves the number keeps the key and nothing fades: the digits snap and only the arc moves.
- **Ring**: a 12pt `CircularProgressIndicator`, stroke 2, track at 25%, from 12 o'clock clockwise, driven by `TweenAnimationBuilder(Tween(end: progress))` over `durationMd` 320ms on `standardCurve` = `Cubic(0.2, 0.8, 0.2, 1)`. Each new value sweeps from wherever the arc is. The tween has no `begin`, so a ring that has just appeared starts **at** its value (8% here) rather than sweeping up from 0.
- **Tone**: no colour is tweened; the tone changes only as the old row fades out and the new one fades in. `statusToneColor` walked against `surface` (info for queued/downloading/importing, success for available), resolved per row; the badge chrome (`surface` 80%, 1px `on-surface` 12%) does not change.
- **Width**: the switcher's default layout sizes to the larger of the two rows during the fade, and the badge chrome is not animated, so the badge jumps to its new width when the old row is removed at 320ms.

**Reduce Motion**: `animate = _animated && !disableAnimations`. No switcher and no tween: the new row replaces the old on the frame, the ring shows the live value. It renders exactly like the default badge.

Web rendition limits: fades and the ring are driven by `requestAnimationFrame`; the ring is an SVG arc with butt caps, matching Material's determinate indicator at this size.

## Do / don't

- Do use `.animated` only where one badge's change is the point of the surface, such as the media detail hero.
- Don't roll or count up the percentage.
- Don't add a tone tween or a label roll on top of the cross-fade and the ring.
