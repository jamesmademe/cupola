# TrueNasCredentials

The Credentials section of the TrueNAS console: the NAS's users and groups, one tab each, with the accounts the server owns above the ones a person made and one create action per tab.

Rendered from `lib/features/truenas/presentation/system/truenas_credentials_screen.dart`, over the shell's `lib/core/widgets/floating_bottom_nav_bar.dart`, by `test/design_catalog/true_nas_credentials_catalog_test.dart`. The section chrome, the version banner and the capability banner slot come from `lib/features/truenas/presentation/widgets/truenas_section_scaffold.dart`. The Users and Groups tabs share `_CrudList`, the body-owned list and FAB that this card is drawn to hold.

## Values

- Chrome: `TrueNasSectionScaffold` draws the glass app bar in page mode, the page name (`PageTitle`, the `headlineSmall` role) above the tabs, then the version and capability banners above the body. The page is pushed inside the app shell; the floating bar overlays its bottom.
- Tabs: Users and Groups, in the app bar's bottom slot. A user row is the `username` in the row title role and a second line with the full name, the uid and `built-in` when the server owns the account, in the data role and the dim text token. A group row is the same shape with the group name and its gid.
- The FAB: 56pt, `AppSpacing.lg` (16) from the right edge, and `AppSpacing.lg + FloatingNavBarMetrics.getScrollViewBottomPadding(context)` from the bottom. The list ends on the same bar clearance, so the button's whole 56pt sits 16pt above the last row and 40pt above the glass on a phone; on a desktop window, where the shell shows a rail instead of the bar, the same expression leaves the console's standard 16pt inset.
- Built-in accounts: no delete control, and the row says `built-in` rather than leaving the absence unexplained.
- Copy: sentence case, the tab name in the row's own words; the empty state is "No users configured." / "No groups configured."

## Anatomy

- `Users`: the user rows; `New` opens the "New user" form sheet (username, full name, password) and the create action is gated by the accounts area. A row's delete is a gated icon with a confirmation that says what goes.
- `Groups`: the group rows with their members; `New` opens the "New group" sheet.
- `_CrudList` owns the refresh indicator, the list padding (the bar's height plus `AppSpacing.lg`), the empty state and the FAB; the tabs only supply the rows and the create verb.

## Semantics

The page is one route with a title; the tabs are destinations. A user or group row speaks its name and its second line as one row; the delete icon keeps its tooltip as a label. The FAB is labelled `New`, with the tab's create verb as its hint ("create users"); a read-only key dims it, keeps the 44pt target, and puts the server's reason in the same hint.

## States in the catalog

Each sheet is drawn in the dark and the light room, on a phone.

- Credentials · Users: one user row (`matt`, uid 1000) and the `New` FAB over the shell's floating bar.
- Text at 200%: the same page at twice the reading size; the bar's own labels clamp at 1.3×, the FAB keeps its clearance.

## Do / don't

- Do keep the FAB on `FloatingNavBarMetrics`, never a bare 16: the shell's bar is translucent, and a FAB under it cannot be read or reliably tapped.
- Do keep the row's second line in the dim text token: a full name, a uid and `built-in` are context, not a second title.
- Don't give a built-in account a delete that the server will refuse; the absence of the control is the correct answer.
