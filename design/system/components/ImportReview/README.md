# ImportReview

The Review of the downloads one arr's connection finished and would not import, and what the import reports afterwards. Needs you's `Review 18` opens it. Under its title: why the arr stopped, in a sentence, and `Why?`.

The files come in two parts:

- the ones the arr would take as they are, selected (`12 clear matches`);
- the ones that need the user (`6 need you`), each with the choice it needs.

The bar imports what is chosen, and the page goes back to where it was opened. There the import reports itself first in Needs you.

Rendered from:

- `lib/features/import/presentation/blocked_import_review_page.dart` (`BlockedImportReviewPage`);
- `lib/features/import/presentation/blocked_import_parts.dart` (`BlockedImportWhy`, `BlockedImportPartHeading`, `BlockedImportMark`, `BlockedImportClearGroup`, `BlockedImportNeedYouRow`, `BlockedImportBar`);
- `lib/features/activity/presentation/widgets/import_done_card.dart` (`ImportDoneCard`, `importReportProvider`).

The catalog test is `test/design_catalog/import_review_catalog_test.dart`. The words come from `lib/features/import/domain/blocked_import.dart`, never from a widget.

## Where it is drawn

| place | what | how it opens |
|---|---|---|
| `/import/blocked?service=&i=`, on the root navigator like the import wizard | the page | `Review 18` on a Needs you card (All, the page), `Manual import` on the Home's row |
| Needs you on All and the Needs you page, first | `ImportDoneCard` | the import the page sent, while it runs, if it failed, and for 10 minutes once done |

The single import of a title, its room or the ⋯ menu stays the wizard (Locate → Review → Track).

## The page

- **Title** (in the glass bar): `Review 18 imports`, one import per file.
  - Under it, in `AppType.body` `inkSecondary`, the arr's cause in a sentence: `The file names don't match the series name, so Sonarr won't guess.`
- **Why?**: an outlined button with a chevron. Open, a quiet box (`fillQuiet`, slab radius, hairline) shows:
  - `What Sonarr says`, then each distinct message of the queue, then of each file listed, in `AppType.mono`, word for word. The sentence above takes the first cause the app recognises among them; `One or more episodes expected in this release were not imported` is only the sum of its files' and names the cause only when nothing else does;
  - `In plain words: …` in `AppType.meta`.
- **The jump**: `PageTabs` with `Clear 12` and `Need you 6`, the second count in amber. It shows only when both parts have files.
  - A tap scrolls to the part.
  - The thumb follows the scroll: it moves to `Need you` once that heading reaches the top.
- **Clear**: `12 clear matches` in `AppType.section`, with `● 12 of 12 selected` in blue on its right. Then one slab per title the files were grabbed for:
  - the poster (`HomeRowArt`);
  - the title in `AppType.row`;
  - what the files bring, in `AppType.meta` (`1080p WEB · English · each replaces a 720p file`);
  - `Clear all` or `Select all` as an outlined button;
  - a row per file: the mark, the code (`S1 E1`; a movie's quality) in `AppType.row`, and the file's name in `AppType.mono`, elided in the middle.
- **Need you**: `6 need you`, then a sentence on what each row asks for. One slab of rows.
  - Closed, a row shows the dashed amber mark, the file's name in mono, and what it waits for in amber `AppType.meta` w600 (`Which episode?`). Once placed, it reads `Added · Cosmos Laundromat · S1 E3` in `inkSecondary`.
  - Open, a row shows the choice its kind needs (`NeedYouKind`):
    - **episode**: the series it was grabbed for with `Change` (the match sheet), the seasons (four or fewer share the row; the specials last; with several, the one every other file of the series in this Review is on, when they agree; otherwise none until one is picked), an `E3` stepper started on the number in the name or, when the name has none, on the episode after the last one placed in the season, and the quality from the file name. Under them, the ink fill: `Pick a season to add it` until a season is chosen, then `Add to the import`. A season without that episode says so in amber; an episode another file of the Review is already on says which, in `inkSecondary` (`S1 E3 is already on` and the file in mono), since a better copy is a choice.
    - **identity**: the arr's words, then `Pick the series` (the match sheet).
- **The match sheet** (`manual_import_fix_sheet.dart`), the add sheet's chrome at 86% of the height, closed from its header, its title the question (`Which series?`, `Which episode?`, `Which movie?`). Picking the title, the file's name in mono and the search field stay put over the library's rows (`SearchRow.title`: the poster, `Series · 2015 · 2 seasons`); tapping a series or an album is the step, a movie is picked and matched with the button. Past it, the title picked with `Change`, the seasons as pills, and one `MediaGroup` of episodes: a ring, `E4 · The Island`, `Aired 14 May 2016 · Missing` (`On disk`, `Airs 21 Oct`), and `Chosen for` the file another row already put there. One file starts on the episode its name says and brings it into view. Several files: a row each, the file in mono over its episode, opening the value sheet; picking one fills the empty files after it in order. One ink lead at the foot: `Match to S1 E4`, `Match 3 files`.
    - **refused**: the arr's reasons, then `Add it anyway` (`Leave it out` once added). A matched file the arr refused (not an upgrade) is never preselected, since importing it replaces a file in the library.
- **The mark**: 24pt, centred in a 44pt target. Selected: filled in the primary ink with its tick. Not selected: an empty ring in `edge`. Waiting for a choice: dashed, in amber.
- **The bar**, on the slab with a hairline above:
  - on the left, `6 left for later` (or `12 clear · 1 picked by you`); on the right, `Imports can't be undone` in `inkTertiary`;
  - the import itself in the amber fill, the fault's remedy: `Import 12 clear matches`, `Import 13 selected`, or `Select something to import`, disabled.
- **Under the parts**: what stays out (`2 other files stay where they are.`, samples, files the arr does not import and files it already took from this download) and a download that would not list its files.
- **A season pack's unnamed file**: Sonarr maps a file whose name names no episode to every episode of the season (`Single episode file contains all episodes in seasons`). The Review reads no episode into it and asks `Which episode?`, never `Add it anyway`, which would import one file as the whole season. `Unknown Series` asks `Which series?`.
- **Nothing left to import**: when the arr still lists the download and every file in it went in already (Sonarr keeps a season pack queued until each episode it expected arrives), the page says so, `Sonarr took what this download had and waits for files that aren't in it. Removing it keeps what went in.`, with `Remove download` in the amber fill and Needs you's neutral question before it.
- **While reading**: `Reading the files of each download…` above skeleton rows.

## After the import

`ImportDoneCard` takes the first place in Needs you:

- **running**: a blue disc with a spinner, `● Sonarr is moving the files`, `Importing 12 episodes`. The command is read again every two seconds, behind the visibility gate (`VisibilityPoller`).
- **done**: a green disc with a tick, `● Imported just now`, `12 episodes imported` (`AppType.section` on the page), then:
  - `Cosmos Laundromat S1 and S2 E1–E2 are now 1080p.` A whole season is named by its code; a gap starts a new run.
  - The episodes on a grid: a row per season, the numbers on squares washed in green.
  - The step: `720p › 1080p WEB`, the old struck through.
  - `Open in library`, when every file went into one title.

  Activity is read again, so the downloads that went in leave the faults.
- **failed**: a `FaultCard`, `The import didn't finish`, with the arr's words behind `Why?` and `Retry` in the amber fill.

## The consumer provides

- The page: the `service` and the connection (`instanceId`, from `?i=`). It reads the queue's blocked downloads itself (`ManualImportFlowNotifier.startBlocked`), each by the client's id for it (`GET /manualimport?downloadId=`), never by scanning a folder.
- The parts: what the page computes for them (files, selection, callbacks).
- `ImportDoneCard`: an `ImportReport` from `importReportProvider`, plus `divided` or `whole`.

## Semantics

- Each clear row is one node: a checkbox that speaks `S1 E1, Kosmische…mkv` and toggles on tap.
- A Need you row's header is one node, a button with its expanded state: `Laundromat.Tapes.E01.720p.WEB.mkv, Which episode?`.
- A season is a button in a mutually exclusive group (`Season 2`).
- The stepper's buttons say `Previous episode` and `Next episode`.
- The report's words are one live region, so `12 episodes imported` is said as it arrives.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the phone and on the desktop.

- The page over J's eighteen: the sentence, `Why?`, the jump, the clear matches, the bar.
- `Why?` open, with the plain words.
- A clear group with one file left out.
- Three Need you rows: one open on its choice, one waiting, one placed.
- The bar, in its two counts.
- Nothing left to import, with Remove download.
- The report running, done (whole), and failed.
- Text at 200%: a row open.
- The desktop: a clear group and the bar in the page well.

## Do / don't

- Do read a blocked download by its id: the arr knows the series and where the files are.
- Do keep a placed file in Need you, where the user put it, with what it became.
- Do say an import cannot be undone beside the button, not in a dialog: the button is the decision.
- Don't preselect a file the arr refused, even when it is matched.
- Don't paint the selection blue: it is the ink. Blue is the count of what is selected, and the running import.
