# StartupFailurePage

What the app draws when it cannot start: a read before the first frame threw, or never answered. Before it, `main` awaited those reads with nothing around them, and a failure left the window black for good (on a phone, the launch screen).

Rendered from `lib/features/shell/presentation/startup_failure_page.dart` (words from `lib/features/shell/domain/startup_failure.dart`) by `test/design_catalog/startup_failure_page_catalog_test.dart`.

## When

`main` runs its reads inside `attemptStartup`, which knows the step it reached: the settings file (`SharedPreferences`), then the connections (the secure store's keys, passwords and sessions, and the migration of an older version's plaintext ones). A throw, or no answer within `startupLimit` (20 s), is a `StartupFailure` for that step (one secret that will not be read is not: it costs its connection only, see [NotConfiguredPlaceholder](../NotConfiguredPlaceholder/README.md); the start stops when every read is refused, `SecureStorageUnavailable`), and `StartupFailureApp` is drawn instead of the app. Retry runs the start again from the top; on success the app replaces the page.

On the desktop the window is created hidden and shown once something is drawn in it (`DesktopWindow.showWhenDrawn`; on macOS `hiddenWindowAtLaunch` in the runner), so nobody sees an empty window while the reads run.

## Anatomy

The page form of [AppErrorState](../AppErrorState/README.md), because it is the same sentence:

- Centred column, at most 420 wide, padding `space-xl`; on the desktop the [WindowChrome](../WindowChrome/README.md) drag strip above it, trail *Cupola*, so the frameless window can still be moved (and closed, off macOS).
- A 32px glyph in amber, no well: `key_off` for the connections, `error_outline` for the settings file. Amber because something answered wrong or not in time; nothing is unreachable.
- `space-lg`, the headline in `title-medium` 600, amber, a header for a screen reader: *Cupola could not read your saved connections* · *Cupola could not open its settings*.
- `space-xs`, the sentence in `label-small` `dim-text`, naming the platform's store: *The Keychain didn't hand them over.* (iOS, macOS) · *Android's secure storage …* · *Windows Credential Manager …* · *The system keyring didn't hand them over. It may still be locked.* (Linux, the one cause a person can see to). Never answered: *The Keychain hasn't answered.* An error the step does not explain has no sentence.
- `space-xl`, *Retry* with an 18px `refresh` glyph in the fault's one amber fill (`remedyFillStyle`), held while the start runs again. No service is named, so no connection-form remedy applies.
- Where asking again may never help (`StartupFailure.canForget`: secure storage refused the reads, as a key store lost to a system update does), `space-sm`, *Forget saved keys* as a text button in ink: the fault's one fill stays on Retry, the step that loses nothing. It asks first (`showAppConfirmDialog`): *Forget the saved keys?* · *Addresses, Home and your preferences stay. Each service asks for its key or password again.* · *Forget keys*. Then `SettingsService.forgetSecrets` empties the store, keeps every connection, and each loads asking for its secret again ([NotConfiguredPlaceholder](../NotConfiguredPlaceholder/README.md)'s unread state). A store that never answered offers no forgetting: it would not answer that either. A store that will not even be emptied is its own page: *Cupola could not forget the saved keys* · *The Keychain refused that too.* (Linux: *The system keyring isn't answering. Start GNOME Keyring or KWallet, then retry.*), with Retry.
- `space-sm`, *Why?* in `dim-text`, opening the platform's own words in `meta`, selectable for a bug report: its message and code (*User interaction is not allowed. (-25308)*), never the details map, which can name a stored key. A timeout has no Why?: its sentence says all it knows.

The app's theme is not known yet (it is in the settings that did not load), so the page follows the system's light or dark.
