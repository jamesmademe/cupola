# PairReceive

The screen that takes everything another device has: where its code comes from, what arrived before anything is added, and the one button that adds it. Outside the shell, at `/welcome/pair`. It also opens an invite shown in person (`InviteSheet`), and hands it over to the sign-in.

Rendered from `lib/features/pairing/presentation/pair_receive_screen.dart` (`PairReceiveScreen`) and `lib/features/pairing/presentation/pair_words.dart` by `test/design_catalog/pair_receive_catalog_test.dart`; the protocol is `lib/features/pairing/`. The catalog draws each state the notifier can stand in, with a notifier that opens no socket.

## Anatomy

Framed as the sign-in with an account is (`RequesterSignInScreen`): a `Scaffold` with a back arrow at the top, then a column at most 480pt wide that scrolls, at `AppSpacing.xl` on each side and `AppSpacing.xl` from the top, the keyboard dismissing it on drag. No ring: the stack is the operator's, and nothing is set up yet. Top to bottom:

- **Title**, `headlineSmall`, a semantics header: *Copy from another device*. `AppSpacing.lg` below, the state.
- **Waiting for a link**: *On the device that has Cupola set up, open Settings › Set up another device, then point this phone's camera at its code.* (`bodyMedium`); on macOS, Windows and Linux, which have no camera to point: *…copy its link and paste it here.* `AppSpacing.xl` below, the field `OnboardingField`, *Link from the other device*. A link in it, alone or inside a message, is fetched and gone from the field (the key must not sit in a text field); anything that names a pairing link and does not read is *This link isn't whole*; anything else, an address, is left alone. A link that arrives by its code (the router took it off the location) never touches the field.
- **Fetching**: the sign-in's busy primary, *Fetching from the other device*, not tappable.
- **A copy that did not arrive**: a `NoticeLine`, the cause once in the tone it has, the remedy first:
  - red, *Cupola could not reach the other device* · *Both need to be on the same Wi-Fi.* · `Retry`, then `Start again`, both in ink: red is a device that did not answer and nothing else, and the same request can still succeed.
  - blue, *This code has expired* · *Make a new code on the other device.* · `Start again` in ink.
  - amber, *Cupola could not read what the other device sent* · *Make a new code on the other device.* · `Start again`, the one amber fill.
  - amber, *This came from a newer Cupola* · *Update Cupola on this device, then make a new code.* · `Start again`, the amber fill.
  - amber, *This link isn't whole* · *Copy it again, or make a new code on the other device.* · `Start again`, the amber fill.
- **What arrived**:
  - **Headline**, `titleMedium` at 600, a header: *From your iPhone* (*your iPad*, *your Mac*, *your Android phone*, *your PC*, *your computer*).
  - **Counts**, `AppSpacing.xs` below, `bodySmall` in `dimText`: the ones that are not zero, joined by ` · `: *3 services* · *1 trusted certificate* · *1 already here*.
  - **The connections to add**, `AppSpacing.lg` below, in a `SettingsGroupCard`, one row each and none a door: the service's mark in its well, its title (the label after it when it has one: *Radarr · 4K*), and the host of its address under it. Each is one sentence for a reader: *Radarr at radarr.home.arpa*.
  - **The certificates Add would trust**, `AppSpacing.lg` below, in a second `SettingsGroupCard`, one row each: `verified_user_outlined`, *Trusted certificate*, and the origin under it. Only for origins a connection being added actually uses: a pin for a server this device already has is not applied and gets no row.
  - **Notes**, `AppSpacing.md` below each, only when they apply: a 16pt `info_outline_rounded` and a `bodySmall` sentence in `dimText`, neutral since none is a fault: *Sign in to Seerr again here. A sign-in stays on the device it was made on.* · *Radarr arrives without its key. Paste it here once it's added.* (`password` or `token` as the service calls it; `access` for a gateway's) · *1 service this version of Cupola doesn't know stays behind.* (*N services … stay behind.*)
  - **Add**, `AppSpacing.xl` below: a filled **Add 14 services** (*Add 1 service*; with only certificates new, *Add 3 trusted certificates*), then a text **Start again** in ink. While it writes the primary is busy and cannot be tapped twice, and Start again waits.
  - When Add has nothing to write: *Everything from your iPhone is already here.* (or *Nothing to add from your iPhone.* when the package held nothing, or only services this version does not know), a filled **Done**, and Start again.
- **Added**: the screen leaves for the Home, the shell drawn for whoever the connections make this device's person.
- **An invite shown in person** (its link says `t=invite`): the title reads *Your invite*, the busy primary *Opening the invite*. Arrived, it goes on at once: to the sign-in, filled (`pendingInviteProvider`, never the location: it carries what a gateway asks for), or, with a Seerr here at its addresses, to that connection (the account's page, or the form when it signs in with the key), filled where it lacked the address away or what an address asks for (*Updated from the invite*, a snackbar, when anything was). Nothing that arrived wrong is copying a device: red *Cupola could not reach the other device* · *Both need to be on the same Wi-Fi.* · `Retry`; blue *This code has expired* · *Ask for a new one.*; amber *Cupola could not read the invite* · *Ask for a new code.*; amber *This came from a newer Cupola* · *Update Cupola on this device, then ask for a new code.* None offers `Start again`: the remedy is a new code from the person who showed it.

Back goes one step: from a notice or from what arrived, to waiting for a link (from an invite's notice, off the screen); from waiting, to the page under it (the Welcome), or with nothing under it to the Welcome on a first run and the Home otherwise.

## Behaviour

Nothing is written until Add, and Add only adds: a connection this device already has is left as it is, a certificate it already trusts keeps its pin, and nothing is removed (`PairPlan`). A pin travels only with a connection the package adds: a certificate for a server already here is not applied, because trusting that server is this device's decision, not the package's. A connection arrives under an id this device mints. The link is held only while it can still be used: dropped once the package arrived, and with the screen.

## The consumer provides

Nothing. The router takes a `cupola://pair` link off the location, holds it in `pendingPairProvider` and opens `/welcome/pair` without it; the screen's notifier takes it from there. Opened by the Welcome's, the Home at zero's and Settings' Connections' *Copy from another device*.

## Semantics

A header; the field labelled; a notice is one live node (`NoticeLine`); each connection is one node, `Title at host`; each certificate is one node, `Trusted certificate for origin`; a note is one node. The busy line is the button, disabled.

## States in the catalog

Each screen is drawn in the dark and the light room: the phone at 390pt, and the waiting screen on a Mac at 860pt.

- Waiting for a link; fetching; on a Mac, where the link is pasted.
- Each way a copy does not arrive: red, blue, and the three amber.
- An invite shown in person: opening; red, with Retry; blue.
- What arrived, with a Seerr account and a secret left behind; adding; a certificate for a server already here is not applied, and two unknown services stay behind; everything here already.
- Text at 200%: what arrived.

## Do / don't

- Do show what Add would write before it writes it, and say what stays behind.
- Do clear the link from the field the moment it is read: a key in a text field is a key in a screenshot.
- Don't offer `Retry` for a code that ran out or a package that did not open: the same request cannot succeed.
- Don't paint a code that ran out amber: it is the person's own step, blue.
