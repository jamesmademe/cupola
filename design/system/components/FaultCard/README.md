# FaultCard

One fault in Needs you, with its way out on the card: a headline that is a sentence by an amber warning glyph, what it means, which service raised it, the service's own words behind Why?, the proof a download carries, and the remedy. `StuckDownloadCard` builds one for each stuck download, with its four ways out; `StorageAlertCard` one for a TrueNAS alert about a disk, with its pool's evidence and Scrub; `DecisionFaultCard` one for every other kind of fault, with the control the Home's row has.

Rendered from `lib/features/activity/presentation/widgets/fault_card.dart` (`FaultCard`, `FaultCard.whole`) by `test/design_catalog/fault_card_catalog_test.dart`. The words come from `lib/features/activity/domain/stuck_download_fault.dart` and `lib/features/activity/domain/fault_words.dart`, never from the widget.

## Where it is drawn

Needs you on Activity's All, one card per fault inside the section's slab, divided by hairlines; a stuck download that was folded with others on the Home's list is a card of its own here, since each has a way out of its own. The requests that wait sit under the faults on a slab of their own, as rows with Approve and Decline: a request is somebody waiting, not something broken. `FaultCard.whole` is the Needs you page's card. Above the cards, the import a Review of blocked imports sent reports itself first ([ImportReview](../ImportReview/README.md)); a failed one is a `FaultCard`.

## Anatomy

- Art: the poster at 44×66 (`HomeRowArt.large`), or the service's glyph on a plate, `AppSpacing.md` before the words.
- Headline: `AppType.row` in the ink (`AppType.section` on the page), after a 16px `warning_rounded` glyph in amber (20px on the page), `AppSpacing.xs` between. A sentence: `Big Buck Bunny is stuck at 47%`, `18 downloads need a manual import`.
- Explanation: `AppType.body` in `inkSecondary`. Source: `AppType.meta` in `inkTertiary` (`Sonarr`, `TrueNAS · pool tank`); a stuck download has none on All, its proof already names its route.
- Why?: a 44pt text button in `inkSecondary` with a chevron; open, the service's words in `AppType.meta`.
- Proof, for a download: the release in `AppType.mono` on one line that fades, then `Nothing for 3 h · Radarr → qBittorrent` in `AppType.meta`, then a 4pt bar in amber on `fillTrack` at how far it got. On the page, `evidence` adds a line per fact (`Pool tank · Healthy · 72%`).
- Remedy: the one amber fill, full width (`remedyFillStyle`), what it does under it in `AppType.meta` (`Radarr drops this one (1.1 GB so far), won't pick it again, and looks for another.`), then at most two quieter ways out as `OutlinedButton`s side by side, each taking half.
- Work the remedy started and that still runs (`running`) takes the fill's place, in blue since it is information and not a fault: `Scrubbing tank · 2% · about 9 h left` in `AppType.label`, a 4pt bar under it, the quieter ways out still beside it. The card reads it again every minute while it runs.
- Once a way out was taken, the controls give way to a note in `AppType.label` (`Dropped · Radarr is looking for another download`), with `Undo` where it can be taken back (Keep waiting). The note stays where the card was until Activity is read again.

## The consumer provides

`headline`; optionally `explanation`, `source`, `why`, `art`, `release`, `proof`, `progress`, `evidence`, `primary` (the fill, built by the consumer so it can be gated or busy), `primarySubtitle`, `running` (text, progress), `secondary` (label, callback, spoken label), `note` (text, Undo callback) and, inside a slab, `divided`.

## Semantics

The words are one node: headline, explanation, source, release, proof and evidence, as one sentence. The buttons are their own: each names its title (`Try another download, Big Buck Bunny`). The note is a live region, so the outcome is said as it appears.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the phone and on the desktop.

- A stuck download: proof, fill, what it does, Remove and Keep waiting.
- A group of blocked imports with its cause behind Why? and one way out.
- Two cards after a way out: a note alone, and one with Undo.
- A scrub that runs, in place of the fill, with Open alert beside it.
- `FaultCard.whole`: a storage alert with its evidence and Why? open.
- Text at 200%.
- The desktop: a stuck download in the page well.

## Do / don't

- Do lead with the remedy the cause points to: Look for peers again when somebody has the whole file, another download when nobody does.
- Do say what a way out will do before it is taken, and what it did after.
- Do confirm Remove, which deletes what arrived and looks for nothing else. The fill does not ask: what it will do is written under it.
- Don't paint anything but the glyph, the bar and the fill amber: the words are the ink's.
