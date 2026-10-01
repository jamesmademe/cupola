import 'package:flutter/widgets.dart';

/// How wide a slot's content is allowed to run inside its track.
///
/// One number for the whole body was the mistake: `bodyMaxWidth` is a *reading*
/// measure, derived from where the eye loses the line it came from on the return
/// sweep, and a table has no return sweep — it is read down its columns. Capping
/// an episode table at 720 inside a 1000pt window does not make it readable, it
/// makes it a table with a margin and four columns fighting for 688pt.
enum MediaDetailMeasure {
  /// The centred reading column, capped at `MediaDetailMetrics.bodyMaxWidth`.
  /// The default, and what prose, fact grids and cards want.
  column,

  /// The whole track, inset by the screen gutter only. For tables and grids.
  track,
}

/// One addressable block inside a [MediaDetailBody] region.
///
/// The region label is a `String` and never a `Widget`: the spine builds every
/// heading, so every heading on every page is `Semantics(header: true)` with the
/// page accent by construction. A caller physically cannot ship an unlabelled or
/// accent-less section, and cannot inset one either — the spine owns the gutter.
///
/// A slot is emitted only when it has something to say. There is no "empty
/// slot" state: the widget cannot see through its own child, so a slot holding
/// an empty list would still spend a label and 24pt of air. **Omit the slot.**
@immutable
class MediaDetailSlot {
  /// Region label, drawn in sentence case in the micro role. Null renders no
  /// label at all.
  ///
  /// **Pass sentence case** — `'Missing subtitles'`, not `'MISSING SUBTITLES'`.
  /// The widget draws it as given and hands the same string to
  /// `Semantics(label:)`, so a pre-shouted label is read out as shouting by
  /// VoiceOver and cannot be un-shouted downstream.
  final String? label;

  /// Tabular count beside the label ('41 of 48 · 5 seasons'). Joined into the
  /// spoken label.
  final String? count;

  /// An interactive trailing control on the label row (a jump-to button, a
  /// refresh). Stays OUTSIDE the silenced region, so it remains reachable.
  final Widget? labelAction;

  /// Box content, inset by the spine's gutter. Mutually exclusive with
  /// [sliver] and [railBuilder].
  final Widget? box;

  /// Sliver content, wrapped in a `SliverPadding` carrying the gutter.
  ///
  /// This is what makes a lazy child list land mid-page: it contributes a real
  /// top-level sliver, so a `SliverList.builder` inside `operate` builds the
  /// eight rows on screen rather than all 250.
  final Widget? sliver;

  /// `.lazy` only: a box emitted between the label and [sliver] — a selector
  /// row, a summary line. Never staggered separately from the label.
  ///
  /// **Not auto-inset, horizontally or vertically.** A selector rail is supposed
  /// to bleed past the content column, so the caller owns this widget's
  /// horizontal padding; pad it with the screen gutter (`AppSpacing.lg`) when
  /// the content should align to the column. The caller also owns the gap
  /// between this box and the first row of [sliver] — the spine emits them
  /// flush, because a pill rail and a summary line want different air above the
  /// list and neither is the page's rhythm.
  ///
  /// Known limit, on a resizable macOS window only: unlike [railBuilder] this
  /// receives no resolved gutter, so above `MediaDetailMetrics.bodyMaxWidth` a
  /// leading box sits one surplus short of the centred column. Exact at every
  /// phone width. If a variant needs it exact on macOS, the fix is a
  /// `leadingBoxBuilder(EdgeInsets)` here rather than padding at the call site.
  final Widget? leadingBox;

  /// `.rail` only: receives the resolved gutter to hand to its own
  /// `ListView.padding`, so the first item aligns to the content column while
  /// the rail bleeds past it.
  final Widget Function(EdgeInsets padding)? railBuilder;

  /// How wide this slot runs inside its track. See [MediaDetailMeasure].
  ///
  /// Declared per slot rather than inferred from the content, because the spine
  /// cannot see through its own child: a `SliverList` of episode rows and a
  /// `SliverList` of prose paragraphs are the same type here.
  final MediaDetailMeasure measure;

  /// The name [MediaDetailBody.sideTrack] addresses this slot by. Defaults to
  /// [label], which is the name the page already gave it.
  ///
  /// Pass it only where the label cannot serve: an unlabelled slot that has to
  /// move, or two slots on one page sharing a label. Everything else is keyed by
  /// the heading the user reads, which keeps the declaration legible — a page
  /// says `sideTrack: {'Overview', 'Details', 'Collection'}` and that is exactly
  /// what stands in the side track.
  ///
  /// The cost of that legibility: renaming a label moves the region unless the
  /// set is renamed with it. That is why a slot the page did *not* name stays in
  /// the main track — the failure mode is a section in the wrong column, never a
  /// section that disappears.
  final String? id;

  /// The key [MediaDetailBody.sideTrack] matches against.
  String? get trackKey => id ?? label;

  const MediaDetailSlot.box({
    required Widget child,
    this.label,
    this.count,
    this.labelAction,
    this.measure = MediaDetailMeasure.column,
    this.id,
  }) : box = child,
       sliver = null,
       leadingBox = null,
       railBuilder = null;

  const MediaDetailSlot.lazy({
    required this.sliver,
    this.label,
    this.count,
    this.labelAction,
    this.leadingBox,
    this.measure = MediaDetailMeasure.column,
    this.id,
  }) : box = null,
       railBuilder = null;

  /// A rail bleeds by definition, so it is always [MediaDetailMeasure.column]:
  /// it receives the resolved gutter and runs past it either way.
  const MediaDetailSlot.rail({
    required Widget Function(EdgeInsets padding) builder,
    this.label,
    this.count,
    this.labelAction,
    this.id,
  }) : railBuilder = builder,
       box = null,
       sliver = null,
       leadingBox = null,
       measure = MediaDetailMeasure.column;
}

/// The media detail body's six regions, in canonical order.
///
/// Named regions rather than one list: the order is a structural guarantee, not
/// a per-caller declaration. A variant omits a region; it never reorders one.
///
/// This replaces the `contentSections` + `slivers` pair, which was the
/// mechanical cause of the ordering bug — every content section was emitted
/// inside one `SliverToBoxAdapter(Column(...))` and only then the slivers, so
/// any caller that needed a lazy child list got it rendered *after* everything
/// else on the page. Lidarr's Albums landed after the genre chips and Bazarr's
/// wanted episodes after Details and Tags for exactly that reason.
@immutable
class MediaDetailBody {
  /// Above region 1 — one line about the whole page: a `FaultBand` over a
  /// read that failed, or the `InlineErrorRetry` that says a source the
  /// answer needs did not answer. No label, and drawn only when there is
  /// one.
  ///
  /// Its own slot rather than a line inside [deck], because both lines carry
  /// the screen gutter themselves (`space-lg` on their leading edge) so they
  /// align on a page that has no gutter of its own. Inside the deck the
  /// gutter was paid twice and the glyph landed 16pt inside the edge of the
  /// actions under it. The spine hands this slot only the surplus a centred
  /// column takes on, as it does [readout], so the glyph lands on the column
  /// edge at every width.
  final Widget? band;

  /// Region 1 — the answer. One box, no label: every variant is *supposed* to
  /// have a state, even a reference page whose state is 'seven movies'.
  ///
  /// Null only where the status resolver a deck needs does not exist yet — the
  /// Seerr collection and person pages and the two Bazarr pages, which have no
  /// `seerrCollectionStatus`, `seerrPersonStatus` or `resolveBazarrAction`. It is
  /// nullable rather than defaulted to a blank box so that gap is visible in the
  /// type instead of hidden behind a `SizedBox.shrink()` — which is what those
  /// four passed, and which cost them 16pt of dead air that sat their first
  /// region lower than every other page's. **A page with a resolvable status
  /// must pass one**; a promoted verb is the whole point of the region.
  final Widget? deck;

  /// Region 2 — the decisive facts, glyph-led, as a bleeding rail. No label.
  ///
  /// Pass it with its own default screen-gutter padding (`AppSpacing.lg`): a
  /// caller builds this above `MediaDetailView` and so cannot see the resolved
  /// column gutter. The spine adds the surplus a centred column takes on above
  /// `MediaDetailMetrics.bodyMaxWidth`, which is zero on a phone, so the first
  /// cell lands on the column edge at every width while the rail still bleeds
  /// off the trailing edge. Do **not** pre-pad it by more than the screen
  /// gutter or the two insets compound.
  final Widget? readout;

  /// Region 3 — **the manifest**: the child records the service tracks under
  /// this title, checked against what actually arrived.
  ///
  /// A shipping manifest is a list of what a thing is supposed to consist of,
  /// checked against what actually turned up. That gap — `41 of 48`,
  /// `3 missing · 2 languages`, `No file` — exists only because the -arr
  /// services model *expected* children separately from *present* children
  /// (`episodeCount` vs `episodeFileCount`, `trackCount` vs `trackFileCount`,
  /// `missingSubtitlesCount`), and rendering it is the reason this page is an
  /// instrument rather than an article about a film.
  ///
  /// Region 3 sits above the synopsis on purpose: the hero says what this is
  /// and what state it is in, the deck says what to do about it, and this is
  /// the thing whose state that was. Prose about a film is never more
  /// operational than the list of episodes you are missing. Where a service
  /// tracks no children this is the file (Radarr) or the request ledger (a
  /// Seerr movie).
  final List<MediaDetailSlot> operate;

  /// Region 4 — running prose: the overview, or a person's biography.
  final List<MediaDetailSlot> synopsis;

  /// Region 5 — the encyclopaedic block, in this internal order: the `DETAILS`
  /// fact grid, then `WHERE TO WATCH`, then `SCORES`, then the catalogue
  /// (`GENRES` / `KEYWORDS` / `TAGS`).
  final List<MediaDetailSlot> reference;

  /// Region 6 — everything that is about **other** titles: the `CAST` rail,
  /// then `COLLECTION`, then `FILMOGRAPHY`.
  ///
  /// `WHERE TO WATCH` used to end this list and does not belong here: where a
  /// title streams is a fact about that title, and one that can settle the
  /// request outright, so it reads as reference and sits under `DETAILS`.
  final List<MediaDetailSlot> related;

  /// Which slots stand in the desktop side track, by [MediaDetailSlot.trackKey].
  ///
  /// **The split is per slot, not per region**, and the region-based one it
  /// replaces was the inverse of what is drawn. The spine used to send `operate`
  /// and `related` to the side track and keep `synopsis` and `reference` in the
  /// main one; every board does the opposite — the Overview, the Details grid
  /// and the Reference block stand in the 380 column while the file, the
  /// episode table, the releases and the history run the wide one.
  ///
  /// It cannot be a smarter rule either, because two facts kill every candidate:
  /// **History is not a fixed side region** (wide on Radarr and Sonarr, side on
  /// Lidarr and Readarr) and **`related` is not atomic** (Radarr puts Cast wide
  /// and Collection side, out of one list). What column a section belongs in is
  /// a per-service editorial judgement, which is the same thing the binding rule
  /// says about details generally: they share the chrome and nothing else.
  ///
  /// Null means the page has not declared, and the legacy region split applies.
  /// It is not a default worth having — it is there so a page that predates this
  /// keeps the layout it shipped with instead of silently collapsing to one
  /// column. An empty set is a real declaration: everything in the main track.
  ///
  /// A key naming no slot is not an error: a page omits the region it has
  /// nothing to say in, and the set describes where a section goes *if* it is
  /// there.
  final Set<String>? sideTrack;

  const MediaDetailBody({
    this.band,
    this.deck,
    this.readout,
    this.operate = const <MediaDetailSlot>[],
    this.synopsis = const <MediaDetailSlot>[],
    this.reference = const <MediaDetailSlot>[],
    this.related = const <MediaDetailSlot>[],
    this.sideTrack,
  });

  /// This body with only the slots on [inSideTrack]'s side of [sideTrack].
  ///
  /// The band, the deck and the readout never move: the answer and the
  /// decisive facts are the top of the page in both layouts, and a line about
  /// the whole page stays over them.
  MediaDetailBody partition({required bool inSideTrack}) {
    final side = sideTrack ?? const <String>{};
    List<MediaDetailSlot> keep(List<MediaDetailSlot> slots) => slots
        .where((slot) => side.contains(slot.trackKey) == inSideTrack)
        .toList(growable: false);

    return MediaDetailBody(
      band: inSideTrack ? null : band,
      deck: inSideTrack ? null : deck,
      readout: inSideTrack ? null : readout,
      operate: keep(operate),
      synopsis: keep(synopsis),
      reference: keep(reference),
      related: keep(related),
    );
  }

  /// Every slot, flattened in canonical region order.
  ///
  /// The spine walks this; nothing else should need it, but it is public so a
  /// test can assert the order without reaching into `build`.
  List<MediaDetailSlot> get slots => <MediaDetailSlot>[
    ...operate,
    ...synopsis,
    ...reference,
    ...related,
  ];
}
