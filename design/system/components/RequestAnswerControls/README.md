# RequestAnswerControls

Approve and Decline for one Seerr request that waits: the one pair every list of waiting requests draws. Approve is
the ink fill, Decline the outline; while an answer is on its way the tapped button is busy and the other waits; once it
went through, the pair gives way to what happened.

Rendered from `lib/features/requests/presentation/widgets/request_answer_controls.dart` (`RequestAnswerControls`), its
write path `lib/features/activity/presentation/widgets/activity_actions.dart` (`ActivityActions.approveRequest`,
`declineRequest`, `requestAnswersInFlightProvider`), the approve sheet
`lib/features/discover/presentation/widgets/approve_request_sheet.dart` (`showApproveRequestSheet`) and its outcome `lib/features/home/data/answered_requests.dart`
(`answeredRequestsProvider`), by `test/design_catalog/request_answer_controls_catalog_test.dart`.

## Where it is drawn

| place | variant | the pair sits |
|---|---|---|
| Home, Requests module (`DecisionRow`) | `.row` | under the row's words, in line with the title |
| Activity, a request's card on a phone | `.row` | under the card's words |
| Activity Requests (`/activity/requests`) and Seerr's Requests tab: `RequestsBoard`, through `DecisionRow` | `.row` | under the row's words, in line with the title |
| Activity's Needs you page (`/activity/needs-you`), through `DecisionRow` | `.row` | under the row's words, in line with the title |
| Seerr overview, Needs a decision | `.row` | under the row's words, in line with the title |
| A title's page that holds a waiting request (`MediaDecisionCard`) | `.card` | the card's end |

A request is judged by its **own** status, `pendingApproval`, never by `displayStatus`: media that exists anywhere
makes `displayStatus` read Available, and the request would lose the only answer it needs.

## Variants

- **`.row`**: the pair side by side, one width each, filling the width it is given. Approve is the ink fill and Decline
  the outline, both 44pt high and with no glyph. The Home's pair, and the one of every list. When a verb, with the busy
  ring beside it, no longer fits its half (a narrow row at a large reading size), the pair goes one under the other at
  the row's width, Approve first: a verb is never cut.
- **`.card`**: the pair one under the other, the width of the card they close. Approve takes the check glyph and the
  fill the page chooses (`approveStyle`: the page's lit fill when nothing else leads, the quiet one under a lead that
  plays or fixes a copy); `onDone` reads the page again once the answer is over, however it ended.

## Asking, busy, answered

Every answer goes through `ActivityActions`, so every place asks the same question.

- **Approve** reads where the request goes, then opens a sheet on it (`lib/features/discover/presentation/widgets/
  approve_request_sheet.dart`): `Approve Charge` · `Anna asked · Standard`; the server (pills when Seerr has another of
  the request's copy, a row otherwise), `Quality profile` and `Root folder` (with its free space) as rows that open the
  value sheet; `Charge goes to Radarr and starts downloading.` (`Radarr 4K` once there are two; a server Cupola has no
  connection to says so in a second sentence) · `Approve request`. Another server brings its own profile and folder. A
  choice other than the one the sheet opened on is written first (`PUT /api/v1/request/{id}`), then approved; the
  same choice writes nothing. A series request carrying no seasons only shows: Seerr edits a series with them. When the
  server could not be read in the budget, the old question stands: `Approve this request?` · the same sentence ·
  `Approve request`. Then `Request approved`.
- **Decline** asks, neutrally: `Decline this request?` · `Charge will not be downloaded. The request stays on record as
  declined.` · `Decline request`. Then `Request declined`. Never red: red means unreachable and nothing else.
- **Busy**: from the tap. The tapped button wears a ring (18pt in `.row`, 20pt in `.card`) with its
  verb; the other button is dimmed and a tap on it starts nothing. Approve is busy while the server is read and while it
  is sent, and idle behind the confirmation, which a person is answering; Decline is busy while it is sent. A second tap
  on either does nothing. In `.row` and `.card` the button keeps its size.
- **Answered**: the pair gives way to one line in `meta`, `Approved · sent to Radarr` (where Seerr sent it) or
  `Declined`. A refused, overtaken or cancelled answer leaves the pair as it was,
  and says why on a toast (a request somebody answered meanwhile is told apart from a fault). The line is kept in
  `answeredRequestsProvider` under the request's own key, so a request answered from any list leaves the Home's module at
  once, and the Home empties it when it is read again.

## Gate

The gate of the Seerr the request lives on decides (`roleGateProvider(instanceId)`). The requester's app has no pair at
all. An account of the operator's that may not approve keeps it, dimmed, and a press says why: `Your account on Jellyseerr
can't approve requests.` The control never carries `Semantics(enabled: false)`: a disabled button is skipped by a screen
reader.

## Semantics

Each button is a button of its own that says its verb and its title: `Approve Charge`, `Decline Charge`, also as the
tooltip, because a page of them is a page of identical words. A busy button adds the phase as its value: `Checking where
it goes`, `Approving`, `Declining`. A gated one adds the reason as its hint. The row's own sentence stays the row's.

## States in the catalog

Each sheet is drawn in the dark and the light room: `.row` idle, with Approve busy while the server is read and with
Decline busy while it is sent; answered (`Approved · sent to Radarr`, `Declined`); dimmed for an account that may not
approve; text at 200% with a long title and a busy Approve. `.card` stacked, in ink and quiet, with a busy Approve.

## Do / don't

- Do put the control where the request is listed: answering must not need a second page.
- Do hand it the connection the request lives on. A request id is per Seerr, and an id sent to the wrong server approves
  somebody else's request.
- Don't draw it for a request that is not waiting, and don't build another pair beside it: a variant is a named
  constructor here.
- Don't tone it. A request is somebody waiting politely, not a fault.
