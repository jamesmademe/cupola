# ServiceRecordRow

One record in a service list — a queue entry, an alert, a proxy host — that speaks as a single sentence.

Hand-written from `lib/core/widgets/service_record_row.dart`. Built on `AppCard.outlined` (transparent fill, 1px `outline`, `radius-md`) with padding `space-md`.

## Values

- A `Row` centred on the cross axis.
- Leading 24px icon in the tone colour (`statusToneColor`), then `space-md`.
- Body: title in `row-title`, up to 2 lines; `space-xs`; detail in `body-small`, `dim-text`, up to 3 lines. Both ellipsize.
- `space-sm`, then the trailing text in `data`, in the tone colour, end-aligned, up to 2 lines, flexible so a long value yields to the title.

## Consumer provides

`icon`, `tone`, `title`, `detail`, `trailing` and one composed `semanticLabel`.

## Semantics

The row is one container node speaking `semanticLabel`; icon, title, detail and trailing are excluded beneath it. Compose the sentence so it carries what the colour carries ("Dune: Part Two, stalled, no peers for 40 minutes").

## Do / don't

- Do follow the five-arm tone rule: a stalled download is amber (`warning`), a queued one blue (`info`), a missing episode neutral.
- Don't use `error` for anything but an unreachable source.
- Don't put a control inside the row; it is a readout. Example content in the preview is illustrative.
