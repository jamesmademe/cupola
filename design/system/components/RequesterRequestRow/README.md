# RequesterRequestRow

One of the requester's requests: where it stands in her words, and when. A row on her Home's Your requests and on her
Requests tab, and the card of a request that still waits for an answer, with its steps and the one thing she may do,
`Cancel request`.

Rendered from `lib/features/requests/presentation/widgets/requester_request_row.dart` (`RequesterRequestRow`,
`RequesterWaitingCard`), its words from `lib/features/requests/domain/my_requests.dart` (`MyRequest`,
`myRequestsOf`), read by `lib/features/requests/data/my_requests_provider.dart`, by
`test/design_catalog/requester_request_row_catalog_test.dart`. The same sheet draws her Home's two modules,
`HomeReadyToWatchModule` and `HomeYourRequestsModule` (see [HomeModule](../HomeModule/README.md)), and her page,
`RequestsScreen` (`lib/features/requests/presentation/requests_screen.dart`).

## Where a request stands

Read from her own Seerr session: Seerr answers an account that may not manage requests with its own only, and each
row carries what Seerr follows of the download (`downloadStatus`, the first rows of each queue, read once a minute),
Seerr's link to the title in the player and the time the player first held it. Never a service's name, a release or a
fault.

| state | tone | the line under it |
|---|---|---|
| `Waiting for approval` | blue | `Asked 2 h ago · Standard` (`4K` for a 4K request) |
| `Downloading 62%` (`62%` at the Home row's end) | blue, with the bar | `Ready around 21:10`, `Ready around tomorrow 09:10`; `Being fetched` with no time |
| `On its way` | blue | `Being fetched`: queued, held, stuck or failed on the stack, or nothing Seerr can see |
| `Finishing on the server` | blue | `Being fetched` |
| `Ready to watch` | green | `Since 18:40`, `Since yesterday`, `Since Wednesday`: arrived in the last seven days |
| `On the server` | green | `Since 12 Sep` |
| `Declined` | neutral, hollow dot | `Declined by the server's owner` |
| `Didn't go through` | neutral | `Whoever runs the server can send it again.` |
| `Removed from the server` · `Blocked` | neutral | `You can ask for it again.` · the owner's block |

A series downloads as one: its episodes' bytes together, the last of them to end. A list read before the server went
quiet keeps its rows and claims no figure: a download reads `On its way`, no bar, no time.

## Parts

- **`RequesterRequestRow.home`**: the 36×54 poster (`HomeRowArt`), the title in `row`, the state at the row's end in
  `meta` 600 and its tone (up to half the row, so `Waiting for approval` stays whole), the 4pt bar under it while it
  downloads, the line in `meta`. At a large reading size the state goes under the title.
- **`RequesterRequestRow.page`**: the 52×78 poster, the title, the state under it with a 7pt dot (hollow for an
  answer), the line, the bar under the words; `Watch`, quiet, at the end of a row on the server with Seerr's link,
  under the words at a large reading size.
- **`RequesterWaitingCard`**: on its own slab, the 68×100 poster, the title in `section`, the state and when she asked;
  then the steps, `Asked` (done, the check), `Approval` (the ring it waits on, `By the server's owner`) and `Ready to
  watch` (ahead, dashed), one under the other at a large reading size; `Cancel request`, outlined, at its end.
- The dot rides the first line of its word, however many lines the word takes.

## Cancel request

Only on her own request, only while it waits (`RoleGate.cancelAction`). A neutral confirmation, `Cancel request?` ·
`Cancel request` · `Keep it`, then `Request canceled`. Once it was approved: `It was already approved, so it can't be
canceled here.` A failure: `Could not cancel the request. Nothing changed.` Her list is read again either way.

## Her page

One column, as her Home: on a tablet and in a window it stops at the reading well (720), centred, and beside an open
title it keeps the phone's 440.
`Requests` in `screen`, then `● 1 ready to watch · ● 3 on the way` (green, blue; a part with nothing in it is left
out). Each request that waits on its card, newest first; then one slab of the rest, what moves first: downloading, on
its way, ready to watch, the answers, what has long been on the server. Empty: `Requests you make will appear here.`
and `Discover`. A server that does not answer: one line with its time and `Retry` (`BriefFailureLine`), and the list as
it last was. Read again on a pull, on a second tap of the tab, and on coming back after a minute.

## Semantics

A row is one button that says it in one sentence (`Sprite Fright, Downloading 62%, Ready around 21:10`) and opens the
title's page; `Watch` is a button of its own, `Watch Coffee Run`. The card's sentence adds what comes next (`Next,
approval by the server's owner, then ready to watch.`); `Cancel request` says whose it is.

## States in the catalog

Each sheet is drawn in the dark and the light room: the Home's rows (downloading, on its way, waiting, declined); the
page's rows with Watch; the card that waits; the rows of a server gone quiet; her page, empty and with the server
silent; Ready to watch with a second arrival; Your requests, and with nothing on its way; text at 200%.

## Do / don't

- Do say when: `Ready around 21:10`, never a countdown in seconds.
- Don't paint anything of hers amber: a stuck download is the operator's fault, and to her it is on its way.
- Don't promise what the app cannot keep: no `you'll be told` until a background check can tell her.
- Don't name a service, a release or another person.
