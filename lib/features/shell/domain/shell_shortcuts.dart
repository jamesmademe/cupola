import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// How this platform spells the two modifiers, and how it binds them.
///
/// The keyboard map is the one place a per-OS difference reaches *inside* the
/// app: the command modifier is Command on macOS and Control everywhere else,
/// and the label printed next to a menu item has to match the key that actually
/// fires it. Both come from here so they cannot drift apart: a tooltip that
/// promises Ctrl+K on a Mac is worse than no tooltip.
abstract final class AppModifier {
  /// Whether the command modifier is Command rather than Control.
  static bool get isApple => !kIsWeb && (Platform.isMacOS || Platform.isIOS);

  /// The command modifier, written the way this platform writes it.
  static String get commandLabel => isApple ? '⌘' : 'Ctrl';

  /// The alternate modifier: Option on a Mac, Alt elsewhere.
  static String get altLabel => isApple ? '⌥' : 'Alt';

  /// Shift, which is a glyph on a Mac and a word elsewhere.
  static String get shiftLabel => isApple ? '⇧' : 'Shift';

  /// `⌘K` on a Mac, `Ctrl+K` elsewhere.
  ///
  /// The separator differs because the platforms differ: Apple's glyphs abut,
  /// Windows and GNOME join with a plus.
  static String command(String key) =>
      isApple ? '$commandLabel$key' : '$commandLabel+$key';

  /// `⌥I` / `Alt+I`.
  static String alt(String key) => isApple ? '$altLabel$key' : '$altLabel+$key';

  /// `⌘⇧C` / `Ctrl+Shift+C`.
  static String commandShift(String key) => isApple
      ? '$commandLabel$shiftLabel$key'
      : '$commandLabel+$shiftLabel+$key';

  /// A command-modifier activator, bound to whichever key this platform uses.
  static SingleActivator cmd(
    LogicalKeyboardKey key, {
    bool shift = false,
    bool alt = false,
  }) => SingleActivator(
    key,
    meta: isApple,
    control: !isApple,
    shift: shift,
    alt: alt,
  );

  /// An alt-only activator: the inspector toggle and `open in inspector`.
  ///
  /// Alt alone rather than the command modifier on purpose: both of those
  /// actions move a *pane*, not the document, and the command modifier's
  /// letters are spoken for by the OS in places we do not control.
  static SingleActivator opt(LogicalKeyboardKey key) =>
      SingleActivator(key, alt: true);
}

/// Open the command deck, the desktop `⌘K` panel. The phone's Portal is not
/// this: a drag on the navigation bar opens it, and it has no shortcut.
class OpenCommandDeckIntent extends Intent {
  const OpenCommandDeckIntent();
}

/// Show or hide the inspector pane.
class ToggleInspectorIntent extends Intent {
  const ToggleInspectorIntent();
}

/// Jump to one of the sections of the person's bar, by its rail position.
class GoToSectionIntent extends Intent {
  const GoToSectionIntent(this.index);

  /// Zero-based, in the order of the person's bar (`NavTab.barFor`) and
  /// therefore of the rail.
  final int index;
}

/// Open Settings, which has no place in the bar: `⌘,`, as on every Mac.
class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

/// Move the lens to the next or previous *configured* service.
///
/// Carries a direction rather than a target because that is what a keyboard
/// gesture knows: the caller resolves it against the current order, so the
/// wrap-around and the skipping of unconfigured services stay in one place.
class CycleServiceIntent extends Intent {
  const CycleServiceIntent(this.delta);

  final int delta;
}

/// Re-fetch everything the visible section shows.
class RefreshAllIntent extends Intent {
  const RefreshAllIntent();
}

/// Focus this screen's own search field, if it has one.
class SearchThisScreenIntent extends Intent {
  const SearchThisScreenIntent();
}

/// Close whatever the shell has put on top of the content.
///
/// The shell's own escape, not Flutter's [DismissIntent], and the difference is
/// load-bearing: a route's modal scope already claims `DismissIntent` and
/// swallows it before a window-level action can be reached, so an overlay this
/// shell owns has to be closed by an intent this shell owns. Bound to an action
/// that is *disabled* while nothing is open, which is what leaves escape free
/// to keep clearing a field or closing a dialog.
class CloseOverlayIntent extends Intent {
  const CloseOverlayIntent();
}

/// Send the focused row or card to the inspector instead of opening it.
class OpenInInspectorIntent extends Intent {
  const OpenInInspectorIntent();
}

/// Back and forward through where this window has been: the toolbar's two
/// arrows, `⌘[` and `⌘]` on a Mac, `Alt+←` and `Alt+→` elsewhere, and a
/// mouse's own back and forward buttons.
class GoBackIntent extends Intent {
  const GoBackIntent();
}

class GoForwardIntent extends Intent {
  const GoForwardIntent();
}

/// Fold the sidebar to its rail of glyphs, or open it again.
class ToggleSidebarIntent extends Intent {
  const ToggleSidebarIntent();
}

/// Show every key of the window, in one sheet.
class ShowShortcutsIntent extends Intent {
  const ShowShortcutsIntent();
}

/// The complete keyboard map, exactly as the design sheet prints it.
///
/// One map, built once per platform, and the only source for both the bindings
/// and the labels shown in tooltips and context menus. Every entry here also
/// has a visible control somewhere: hover, right-click and shortcuts are
/// accelerators, never the only door, because the phone has none of them and no
/// action may become desktop-only.
abstract final class ShellShortcuts {
  static Map<ShortcutActivator, Intent> get map => {
    AppModifier.cmd(LogicalKeyboardKey.keyK): const OpenCommandDeckIntent(),
    AppModifier.opt(LogicalKeyboardKey.keyI): const ToggleInspectorIntent(),
    AppModifier.cmd(LogicalKeyboardKey.digit1): const GoToSectionIntent(0),
    AppModifier.cmd(LogicalKeyboardKey.digit2): const GoToSectionIntent(1),
    AppModifier.cmd(LogicalKeyboardKey.digit3): const GoToSectionIntent(2),
    AppModifier.cmd(LogicalKeyboardKey.digit4): const GoToSectionIntent(3),
    AppModifier.cmd(LogicalKeyboardKey.comma): const OpenSettingsIntent(),
    AppModifier.cmd(LogicalKeyboardKey.arrowRight, alt: true):
        const CycleServiceIntent(1),
    AppModifier.cmd(LogicalKeyboardKey.arrowLeft, alt: true):
        const CycleServiceIntent(-1),
    AppModifier.cmd(LogicalKeyboardKey.keyR): const RefreshAllIntent(),
    AppModifier.cmd(LogicalKeyboardKey.keyF): const SearchThisScreenIntent(),
    AppModifier.opt(LogicalKeyboardKey.enter): const OpenInInspectorIntent(),
    if (AppModifier.isApple) ...{
      AppModifier.cmd(LogicalKeyboardKey.bracketLeft): const GoBackIntent(),
      AppModifier.cmd(LogicalKeyboardKey.bracketRight): const GoForwardIntent(),
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true, control: true):
          const ToggleSidebarIntent(),
    } else ...{
      AppModifier.opt(LogicalKeyboardKey.arrowLeft): const GoBackIntent(),
      AppModifier.opt(LogicalKeyboardKey.arrowRight): const GoForwardIntent(),
      AppModifier.cmd(LogicalKeyboardKey.keyS, shift: true):
          const ToggleSidebarIntent(),
    },
    AppModifier.cmd(LogicalKeyboardKey.slash): const ShowShortcutsIntent(),
    const SingleActivator(LogicalKeyboardKey.escape):
        const CloseOverlayIntent(),
  };

  /// The label for a shortcut, for tooltips and context menus.
  static String get commandDeck => AppModifier.command('K');
  static String get inspector => AppModifier.alt('I');
  static String get refreshAll => AppModifier.command('R');
  static String get searchScreen => AppModifier.command('F');
  static String get openInInspector => AppModifier.isApple ? '⌥⏎' : 'Alt+Enter';
  static String section(int index) => AppModifier.command('${index + 1}');
  static String get settings => AppModifier.command(',');
  static String get back => AppModifier.isApple ? '⌘[' : 'Alt+←';
  static String get forward => AppModifier.isApple ? '⌘]' : 'Alt+→';
  static String get sidebar => AppModifier.isApple ? '⌃⌘S' : 'Ctrl+Shift+S';
  static String get shortcuts => AppModifier.command('/');
  static String get cycleService =>
      AppModifier.isApple ? '⌘⌥← →' : 'Ctrl+Alt+← →';

  /// Every key, as the shortcuts sheet lists them: what it does, then the key.
  ///
  /// The [operatorOnly] ones reach the stack (the deck, the services, the
  /// inspector), which the requester's window has none of.
  static List<({String does, String keys, bool operatorOnly})> get legend => [
    (does: 'Jump to anything', keys: commandDeck, operatorOnly: true),
    (does: 'Search this screen', keys: searchScreen, operatorOnly: false),
    (
      does: 'Go to a section',
      keys: '${section(0)}–${AppModifier.isApple ? '4' : section(3)}',
      operatorOnly: false,
    ),
    (does: 'Back, forward', keys: '$back  $forward', operatorOnly: false),
    (does: 'Previous or next service', keys: cycleService, operatorOnly: true),
    (does: 'Refresh everything', keys: refreshAll, operatorOnly: false),
    (does: 'Show or hide the inspector', keys: inspector, operatorOnly: true),
    (does: 'Open in the inspector', keys: openInInspector, operatorOnly: true),
    (does: 'Show or hide the sidebar', keys: sidebar, operatorOnly: false),
    (does: 'Settings', keys: settings, operatorOnly: false),
    (does: 'These keys', keys: shortcuts, operatorOnly: false),
  ];
}
