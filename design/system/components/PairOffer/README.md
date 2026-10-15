# PairOffer

The page that hands everything this device has to a new one: a code to scan or a link to copy, what moves with it, and what the code does once it has done its job. Settings › `Set up another device`.

Rendered from `lib/features/pairing/presentation/pair_offer_screen.dart` (`PairOfferScreen`) and `lib/features/pairing/presentation/pair_words.dart` by `test/design_catalog/pair_offer_catalog_test.dart`; the code is `QrCodeView`, the protocol is `lib/features/pairing/`. The catalog draws each state the notifier can stand in, with a notifier that opens no socket.

## Anatomy

A page of Settings: `AmbientScaffold` under a `GlassAppBar` titled `Set up another device`, a `ListView` at `AppSpacing.lg` on each side, its column at most 560pt wide. Top to bottom:

- **Lede**, `bodyMedium`: *On the other phone, open Cupola and choose Copy from another device.*
- **The code's place**, `AppSpacing.xl` below, centred: a 232pt square, there from the first frame in every state but the two notices, so nothing below it jumps when the code arrives or goes. The code is `QrCodeView` of the link (black on white in both rooms, as the invite's is); in the other states the same square is a `surfaceContainer` tile with an `outlineVariant` border and `AppRadius.md`.
- **While the code is up**, `AppSpacing.md` below it, centred:
  - *Scan with the camera on the other phone*, `bodyMedium`.
  - **The countdown**, `AppSpacing.xs` below, `bodySmall` in `dimText`: *Closes in 1:52*, minutes and seconds to the code's own closing time, ticking each second and never below 0:00. Not a live region: a reader hears the time it is on, and the end says nothing new, because the page changes by itself.
  - **Copy link**, a text button in ink with an 18pt `link_rounded`, 44pt: it copies exactly the link, then for two seconds reads *Link copied* with `check_rounded` and goes back; the change is announced (`announce()`).
  - On a Mac only, a `bodySmall` dim line: *If your Mac asks, allow Cupola to accept incoming connections.*
  - **What moves**, `AppSpacing.xl` below, a section label and a `SettingsGroupCard` of rows that are not doors (no chevron, no hint): the glyph's well, a title, and under it a sentence in `onSurfaceVariant` that wraps to four lines. In this order, each only when it applies:
    - `key_rounded` · *4 services and their keys* · the first four titles in the order they go, then *and 8 more* (*1 service and its key* · *Radarr*; four or fewer are joined with commas and an *and*).
    - `verified_user_outlined` · *1 trusted certificate* · *So the new phone trusts the same servers you already trusted*.
    - `person_outline_rounded` · *Seerr signs in again on the new phone* · *A sign-in stays on the device it was made on*, when a Seerr account travels.
    - `key_off_rounded` · *Radarr's key stays behind* (`password`, `token` or `access` as the service calls it), one row for each connection whose secret the device could not read · *This device could not read it. Paste it on the new phone.*
    - `wifi_rounded` · *Encrypted, over your home network only* · *Both phones need to be on your Wi-Fi*.
  - **Why it's safe**, `AppSpacing.xl` below, a section label and a `bodyMedium` sentence: *The code holds no secrets: only where to fetch them and the key to open them. It works once.*
  - **Close the code now**, `AppSpacing.lg` below, a text button in ink, centred.
- **Sent**: in the square, a 72pt `check_rounded` in `statusToneColor(…, StatusTone.success)`; under it, `AppSpacing.lg` below, *Copied to the other phone* (`titleMedium` at 600) and *It has everything now. The code is closed.* (`bodySmall`, `dimText`); `AppSpacing.xl` below, a filled **Done**, which goes back to Settings.
- **Closed**, the same way: in the square a neutral 72pt `qr_code_2_rounded`; *The code closed* and why, by how it ended: *Its two minutes are up.* · *It can't be used any more.* · *Something on your network asked for the wrong thing three times.*; a filled **Make a new code**.
- **No home network**: a blue `NoticeLine` in the code's place: *Join your Wi-Fi to make a code* · *The other phone fetches everything over your home network.* · `Retry` in ink.
- **The server did not open**: an amber `NoticeLine`: *Cupola could not open the code* · *Wait a moment, then make a new code.* · **Make a new code**, the one amber fill.

What moves and why it is safe only exist while the code is up: the package is in that state and nowhere else.

## Behaviour

The page makes the code on its first frame, as the kind of device it is (`PairDevice.of`: iPhone or iPad, an Android phone or tablet, a Mac, a PC, a computer), and **closes it when it goes**: `pairOfferProvider` is `autoDispose`, the page watches it, and disposing it closes the server. A new code closes the one before. The page is the operator's: the requester has no connection to hand over, and `/settings/another-device` sends her to Settings.

## The consumer provides

Nothing: the page reads the settings through the provider and builds the package itself. Settings offers it (`SettingsAnotherDeviceRow`) to the operator with at least one connection, in the group before About on a phone and in the Onboarding card on a window.

## Semantics

The QR is an image labelled `QR code to copy from this device`. Every row of What moves is one node, `Title, sentence`. The countdown is plain text, not a live region. A notice is one live node (`NoticeLine`); the result of a closed or sent code is one live node, `Title. Why.`

## States in the catalog

Each page is drawn in the dark and the light room: the phone at 390pt, and the code on a Mac at 860pt.

- Making the code; the code up with everything moving; twelve services (the first four named, the rest counted); one service and nothing else.
- On a Mac: the firewall question is said.
- Sent; closed after two minutes; closed after three wrong requests.
- No home network; the server did not open.
- Text at 200%: the code up. The page scrolls, the code keeps its side.

*Link copied* is a moment after a tap and is not drawn: the catalog has no taps.

## Do / don't

- Do say what moves, and what does not, beside the code: the operator should know before the other phone scans it.
- Do close the code with the page. A code that outlives the screen is a door left open.
- Don't put an address, a key or a secret in any word the page draws: counts and titles only (`pairMovesOf`).
- Don't tone the countdown: a code that is about to close is not a fault.
