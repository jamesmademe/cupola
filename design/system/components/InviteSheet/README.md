# InviteSheet

What the person who runs a Seerr hands a household member: the invite as a QR to scan and a link to send, with what it cannot do said under it. Opened from the Seerr connection's form, *Invite someone*.

Rendered from `lib/features/settings/presentation/widgets/invite_sheet.dart` (`InviteSheet`, `showInviteSheet`) by `test/design_catalog/invite_sheet_catalog_test.dart`; the code is `QrCodeView`, the invite is `lib/features/discover/domain/seerr_invite.dart`. The catalog draws the panel as it stands open, over the modal barrier.

## Anatomy

The panel is `AppBottomSheet`'s (the room's raised step, handle, `AppSpacing.lg` at the sides, a body that scrolls inside the 92% cap), shown through `SheetUtils.showCupolaModalSheet`. Top to bottom:

- **Title**, `Invite someone`: `titleLarge` at 600, a semantics header.
- **Lede**, `AppSpacing.sm` below: `bodyMedium`, *They scan this with their phone's camera and sign in to Seerr with their own account.*
- **The code**, `AppSpacing.xl` below, centred: `QrCodeView`, 232 on a side, there from the first frame: the invite is made at once from the saved connection and carries no name, so nothing holds it back.
- **Name and host**, `AppSpacing.md` below, centred, `bodySmall` in `dimText`: `<name> · <host>` once the server has answered with the name it gave itself (then `invite.home`'s host, hyphens kept from breaking a line), or the host alone before that, when the server has no name, or when it never answers. Only this line waits for the server; the code and the link do not change when it arrives.
- **Limits**, `AppSpacing.sm` below the name and `AppSpacing.xs` apart, the same ink, centred, one line each in the order the domain gives them (`inviteLimitsOf`). None is a fault, so none has a tone or an icon:
  - *The address at home asks for a token, and an invite never carries one.* (`homeBehindGateway`)
  - *It works at home: Seerr has no address away from home.* (`homeOnly`)
  - *It works at home: the address away asks for a token, and an invite never carries one.* (`awayBehindGateway`)
  - A connection with both addresses, neither behind a gateway, has none.
- **Copy link**, `AppSpacing.xl` below: the theme's `FilledButton` (the ink fill, 44pt, standard density), the full width, with an 18pt `link_rounded`. It copies exactly the invite's link, then for two seconds reads *Link copied* with `check_rounded`, and goes back. Enabled from the first frame.
- **Where the link goes**, `AppSpacing.md` below, centred, `bodySmall` in `dimText`: *Sent as a message, they paste it where Cupola asks where their Seerr is.*

Where the invite comes from: the saved connection (`SeerrInvite.of`), never the form's unsaved edits. The name on the line under the code comes from `seerrServerFactsProvider` and is in no link: the receiving app reads the server on arrival and names it from the server itself. A connection removed while the sheet is open closes it.

## The consumer provides

`connectionId`, the saved Seerr connection that signs in with its API key. The form shows the row (`SettingsCard.grouped`, `qr_code_2_rounded`, *Invite someone*, hint *shows an invite to this Seerr*) only to the operator, on a configured Seerr whose `account` is null.

## Semantics

A header, an image labelled `QR code of the invite`, the host line and the limits as plain text, and one button. The change to *Link copied* is announced (`announce()`), since a label that changes under a focused button is not read by itself.

## States in the catalog

Each sheet is drawn in the dark and the light room: the phone at 390pt, and one scene on a desktop window.

- Both addresses with their certificates and the server's name on the line under the code; an address at home only and no name; the address away behind a gateway; the address at home behind a gateway and no address away (two limits).
- On a desktop window: the modal sheet caps at 640pt wide, centred.
- Text at 200%: the whole sheet on a tall screen. On a phone it scrolls inside its cap, the button reached by scrolling.

*Link copied* is a moment after a tap and is not drawn: the catalog has no taps.

## Do / don't

- Do say what the invite cannot do, beside it: the operator should know before the person scanning does.
- Do build the invite from the saved connection through `SeerrInvite`, which never carries a key, a session or a gateway's access.
- Don't tone the limits amber or red: an address away behind a gateway is not a fault, only a limit.
- Don't put the server's name in the invite, or make the code wait for anything: the code and the link say the same thing, from the first frame.
