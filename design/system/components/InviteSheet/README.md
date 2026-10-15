# InviteSheet

What the person who runs a Seerr hands a household member, in one of two ways. **A link**: the invite as a QR to scan and a link to send, nothing secret in either, with what it cannot do said under it. **In person**: when an address of the server asks for a token a link never carries, a code that works once, for two minutes, on the same Wi-Fi, and brings Seerr with what its addresses ask for, never the key. Opened from the Seerr connection's form, *Invite someone*.

Rendered from `lib/features/settings/presentation/widgets/invite_sheet.dart` (`InviteSheet`, `showInviteSheet`) by `test/design_catalog/invite_sheet_catalog_test.dart`; the code is `QrCodeView`, the invite is `lib/features/discover/domain/seerr_invite.dart`, the code shown in person is the pairing protocol (`inviteOfferProvider`, `PairPackage.invite`) and its slot, countdown and outcome are `lib/features/pairing/presentation/pair_code.dart`, the same as Set up another device's (`PairOffer`). The catalog draws the panel as it stands open, over the modal barrier, the code in person standing still.

## Which way it opens

On the code shown in person whenever an address asks for a token (`invitesInPerson`: a limit that is a token, at home or away), the link one tap away; on the link otherwise, with nothing about a code. The person's choice holds while the sheet is open. Turning to the link lets the code go (nothing watches its provider, and its server closes); turning back makes a new one.

## Anatomy: in person

The same panel, title and code side as the link's. Below the title:

- **Lede**, `AppSpacing.sm` below: `bodyMedium`, *On your Wi-Fi, they scan this with their phone's camera and sign in to Seerr with their own account.*
- **The code**, `AppSpacing.xl` below: while it is made, `PairCodeSlot` (the code's square, `surfaceContainer`, `outlineVariant` border, `AppRadius.md`) with a 24pt spinner; then `QrCodeView` of the `cupola://pair?…&t=invite` link. Then, centred, `bodySmall` in `dimText`: the name and host (as the link's), `AppSpacing.xs` below *Closes in 1:52* ticking each second (`PairCountdown`), `AppSpacing.sm` below what it brings: *It brings the token the address away asks for. Seerr's key stays here.* (*the token the address at home asks for*, *the tokens both addresses ask for*). On macOS, *If your Mac asks, allow Cupola to accept incoming connections.* No Copy link: beside *Send a link instead* a second link would say two different things with the same word.
- **Taken by their phone**: the slot with a 72pt `check_rounded` in the green tone, then `PairCodeOutcome`: *They have the invite* (`titleMedium` at 600) · *They sign in to Seerr on their phone now. The code is closed.* · a filled **Done** that closes the sheet.
- **Closed unused**: the slot with a 72pt `qr_code_2_rounded`, neutral · *The code closed* · why (*Its two minutes are up.*, *Something on your network asked for the wrong thing three times.*, *It can't be used any more.*) · a filled **Make a new code**.
- **Off the Wi-Fi**: a blue `NoticeLine`, *Join your Wi-Fi to invite in person* · *Their phone fetches the invite over your home network.* · `Retry` in ink.
- **The code would not open**: an amber `NoticeLine`, *Cupola could not open the code* · *Wait a moment, then make a new code.* · **Make a new code**, the amber fill.
- **The way to the link**, `AppSpacing.xl` below, in every state but taken: **Send a link instead**, a text button in ink, then, centred in `dimText`, why it does less: *A link works only at home: it never carries a token.*, or with the address at home asking, *A link never carries a token: they would be asked for it.*

## Anatomy: the link

The panel is `AppBottomSheet`'s (the room's raised step, handle, `AppSpacing.lg` at the sides, a body that scrolls inside the 92% cap), shown through `SheetUtils.showCupolaModalSheet`. Top to bottom:

- **Title**, `Invite someone`: `titleLarge` at 600, a semantics header.
- **Lede**, `AppSpacing.sm` below: `bodyMedium`, *They scan this with their phone's camera and sign in to Seerr with their own account.*
- **The code**, `AppSpacing.xl` below, centred: `QrCodeView`, 232 on a side, there from the first frame: the invite is made at once from the saved connection and carries no name, so nothing holds it back.
- **Name and host**, `AppSpacing.md` below, centred, `bodySmall` in `dimText`: `<name> · <host>` once the server has answered with the name it gave itself (then `invite.home`'s host, hyphens kept from breaking a line), or the host alone before that, when the server has no name, or when it never answers. Only this line waits for the server; the code and the link do not change when it arrives.
- **Limits**, `AppSpacing.sm` below the name and `AppSpacing.xs` apart, the same ink, centred, one line each in the order the domain gives them (`inviteLimitsOf`). None is a fault, so none has a tone or an icon:
  - *The address at home asks for a token, and a link never carries one.* (`homeBehindGateway`)
  - *It works at home: Seerr has no address away from home.* (`homeOnly`)
  - *It works at home: the address away asks for a token, and a link never carries one.* (`awayBehindGateway`)
  - A connection with both addresses, neither behind a gateway, has none.
- **Copy link**, `AppSpacing.xl` below: the theme's `FilledButton` (the ink fill, 44pt, standard density), the full width, with an 18pt `link_rounded`. It copies exactly the invite's link, then for two seconds reads *Link copied* with `check_rounded`, and goes back. Enabled from the first frame.
- **Where the link goes**, `AppSpacing.md` below, centred, `bodySmall` in `dimText`: *Sent as a message, they paste it where Cupola asks where their Seerr is.*
- **The way back to the code**, `AppSpacing.lg` below, only when an address asks for a token: **Invite in person instead**, a text button in ink.

Where the invite comes from: the saved connection (`SeerrInvite.of`), never the form's unsaved edits. The name on the line under the code comes from `seerrServerFactsProvider` and is in no link: the receiving app reads the server on arrival and names it from the server itself. A connection removed while the sheet is open closes it.

## The consumer provides

`connectionId`, the saved Seerr connection that signs in with its API key. The form shows the row (`SettingsCard.grouped`, `qr_code_2_rounded`, *Invite someone*, hint *shows an invite to this Seerr*) only to the operator, on a configured Seerr whose `account` is null.

## Semantics

A header, an image labelled `QR code of the invite` (the link's and the code's alike), the host line, the countdown and the limits as plain text, and the buttons. The change to *Link copied* is announced (`announce()`), since a label that changes under a focused button is not read by itself; so is a turn between the two ways (*The invite is a link*, *The invite is a code to scan here*), which replaces what was under the finger. The outcome of the code is one live node.

## States in the catalog

Each sheet is drawn in the dark and the light room: the phone at 390pt, and one scene on a desktop window.

- The link: both addresses with their certificates and the server's name on the line under the code; an address at home only and no name.
- In person: the address away behind a gateway; the address at home behind a gateway and no address away; taken by their phone; closed unused; off the Wi-Fi.
- On a desktop window: the modal sheet caps at 640pt wide, centred.
- Text at 200%: the code shown in person on a tall screen. On a phone it scrolls inside its cap.

*Link copied*, and the link of a server whose address asks for a token (reached by *Send a link instead*), come after a tap and are not drawn: the catalog has no taps.

## Do / don't

- Do say what the invite cannot do, beside it: the operator should know before the person scanning does.
- Do build the link from the saved connection through `SeerrInvite.of`, which never carries a key, a session or a gateway's access; a gateway's access travels only sealed, in the code shown in person (`SeerrInvite.inPerson`), and never the key.
- Do open on the code shown in person when a token would be left behind: it is the way that works.
- Don't tone the limits amber or red: an address away behind a gateway is not a fault, only a limit.
- Don't put the server's name in the invite, or make the code wait for anything: the code and the link say the same thing, from the first frame.
