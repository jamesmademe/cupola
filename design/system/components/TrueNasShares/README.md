# TrueNasShares

The Shares section of the TrueNAS console: one page for the three ways the NAS hands out storage, with the protocol service's own state above the rows and the section's one create action in a body-owned FAB.

Rendered from `lib/features/truenas/presentation/shares/truenas_shares_screen.dart`, over the shell's `lib/core/widgets/floating_bottom_nav_bar.dart`, by `test/design_catalog/true_nas_shares_catalog_test.dart`. The version and capability banners above the tabs come from `lib/features/truenas/presentation/widgets/truenas_section_scaffold.dart`; the rows and their controls are the page's own.

## Values

- Chrome: `TrueNasSectionScaffold` draws the glass app bar in page mode, the page name (`PageTitle`, the `headlineSmall` role) above the protocol tabs, the version banner and the capability banner slot above the body. The page is pushed inside the app shell, so the shell's floating bar overlays its bottom.
- Tabs: SMB, NFS, iSCSI, one protocol each, in the app bar's bottom slot. The share rows are `AppCard.surfaceOutlined` inside the list, one row per share: the share name in the row title role, the path in the data role, the enabled switch and the edit/delete icons at the end.
- State tones: a running protocol is the success tone (a check, "SMB service running"); a stopped one is neutral (a pause, "SMB service stopped"), never a fault, because two of the three protocols are off on most servers. The share's enabled switch is the page's only inline write.
- The FAB: 56pt, `AppSpacing.lg` (16) from the right edge, and `AppSpacing.lg + FloatingNavBarMetrics.getScrollViewBottomPadding(context)` from the bottom. The list ends on the same bar clearance, so the button's whole 56pt sits 16pt above the last row and 40pt above the glass on a phone; on a desktop window, where the shell shows a rail instead of the bar, the same expression leaves the console's standard 16pt inset.
- Copy: sentence case; the empty state names the protocol ("No SMB shares."); the service banner says "SMB service running" / "SMB service stopped", not a version or a device name.

## Anatomy

- `SMB`: the CIFS state banner (check or pause, the sentence, a gated switch), then the SMB share rows; `New` opens the "New SMB share" form sheet.
- `NFS`: the NFS state banner, the export rows with their hosts, the create action; `iSCSI`: the target rows and their create action.
- Each row: name and path, the enabled switch, and the edit/delete controls. Every write is gated by the capability areas the page declares (`smb`, `nfs`, `iscsi`, `service:*`), so a read-only key draws them dimmed with the server's reason rather than hiding the page.

## Semantics

The page is one route with a title; the tabs are the app bar's tab bar, each tab a destination with its protocol name. A share row speaks the share's name and path as its two lines; the switch keeps its own switch semantics; the edit and delete icons carry their tooltips as labels. The FAB is labelled `New`: its hint names the protocol's create verb ("create SMB shares"), and a blocked FAB keeps its 44pt target, dims, and says why in the same hint.

## States in the catalog

Each sheet is drawn in the dark and the light room, on a phone.

- Shares · SMB: the SMB service running, the `media` and `backups` shares, the enabled and the disabled row, and the `New` FAB over the shell's floating bar.
- Text at 200%: the same page at twice the reading size; the bar's own labels clamp at 1.3×, the FAB keeps its clearance.

## Do / don't

- Do keep the FAB's bottom on `FloatingNavBarMetrics`, never a bare 16: the shell's bar is translucent, and a FAB under it is neither readable nor reliably tappable.
- Do let the list's last row scroll under the glass, with `getScrollViewBottomPadding`; the bar is a lens, not a footer.
- Don't add a second create action to the page. The section has one, and it lives in the FAB at the end of the row space.
