import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'package:cupola/core/app_breakpoints.dart';

/// Which OS owns the window buttons, and where it puts them.
///
/// The design's whole per-OS budget is spent here: everything below the deck is
/// identical on the three targets, and only the top strip moves. Modelling that
/// as an enum rather than as scattered `Platform.isX` tests is what keeps the
/// budget honest: a widget asks for the *shape* of the chrome, never for the
/// operating system, so nothing else can quietly start branching on it.
enum WindowChromeStyle {
  /// Traffic lights at the leading edge, drawn by AppKit over our strip.
  ///
  /// We hide the title bar but keep the buttons: lookalikes would be wrong in
  /// tone, wrong on hover, and wrong the day the user turns on Reduce
  /// Transparency.
  macos,

  /// No lights; 44x44 caption buttons at the trailing edge, close last.
  ///
  /// Nothing of ours may cover the maximise button: Windows 11 snap layouts
  /// open from a hover on exactly that rectangle, and an overlay that eats the
  /// hover removes a system feature.
  windows,

  /// GNOME client-side decoration: 26pt round buttons at the trailing edge.
  ///
  /// Also the fallback for tiling window managers, where nothing in the strip
  /// may be load-bearing for dragging.
  gnome,
}

/// The frameless window, and the few facts the chrome needs from the OS.
///
/// One place, called once from `main`, and inert everywhere else: on iOS and
/// Android every member either answers false or returns without doing anything,
/// so the mobile builds never reach the plugin. That is deliberate rather than
/// defensive: `window_manager` has no mobile implementation, and a call that
/// slipped through would fail at the channel with a `MissingPluginException`
/// during startup, before any error UI exists to report it.
abstract final class DesktopWindow {
  /// Whether this build manages its own window.
  static bool get isSupported => AppBreakpoints.isDesktopPlatform;

  /// Which chrome shape this OS wants. Only meaningful when [isSupported].
  /// Asked of [defaultTargetPlatform] rather than of `dart:io`, so a test can
  /// render all three chromes: see [AppBreakpoints.isDesktopPlatform].
  static WindowChromeStyle get style => switch (defaultTargetPlatform) {
    TargetPlatform.macOS => WindowChromeStyle.macos,
    TargetPlatform.windows => WindowChromeStyle.windows,
    _ => WindowChromeStyle.gnome,
  };

  /// Leading inset the chrome must leave free for OS-drawn window buttons.
  ///
  /// macOS only, and measured rather than guessed: 12pt inset, three 12pt
  /// lights, 8pt apart (12 + 36 + 16 = 64), then the 8pt gap the design puts
  /// between the last light and the first crumb.
  static double get leadingButtonGutter =>
      style == WindowChromeStyle.macos ? 72 : 0;

  /// Whether the app draws the window buttons itself.
  static bool get drawsOwnButtons => style != WindowChromeStyle.macos;

  /// Prepares the frameless window, and leaves it hidden: [showWhenDrawn]
  /// shows it. Safe to await on any platform.
  ///
  /// Deliberately does **not** set a size. On macOS the native runner owns the
  /// frame through `setFrameAutosaveName`, so a size here would throw away the
  /// window the user left behind on every launch; Windows and Linux set their
  /// default in their own runners, once, at creation. The minimum is set here
  /// because it is a design constant rather than a platform one: a small
  /// phone's width, since below the 720pt compact artboard the window paints
  /// the phone layout instead of stopping: see [AppBreakpoints.desktopMobile].
  static Future<void> ensureReady() async {
    if (!isSupported) return;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      minimumSize: AppBreakpoints.desktopMinimumWindow,
      titleBarStyle: TitleBarStyle.hidden,
      // macOS keeps its traffic lights over our strip; the other two get
      // nothing, because we draw their buttons.
      windowButtonVisibility: true,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (style != WindowChromeStyle.macos) {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
      }
    });
  }

  /// Shows the window once the frame now scheduled has been drawn.
  ///
  /// The macOS runner creates the window hidden (`hiddenWindowAtLaunch`), so
  /// nobody sees it before Flutter has drawn into it: shown any earlier, it was
  /// a black rectangle for as long as the start took, and for good when the
  /// start threw. Windows' runner already waits for the first frame on its
  /// own; GNOME's shows the window at creation, so there this only focuses it.
  ///
  /// A second pass covers a frame that never comes: a window that stayed
  /// hidden would be an app with no window at all, which is worse than a
  /// black one. Showing twice is harmless.
  static void showWhenDrawn() {
    if (!isSupported) return;
    Future<void> show() async {
      await windowManager.show();
      await windowManager.focus();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => show());
    Future<void>.delayed(const Duration(seconds: 2), () async {
      if (!await windowManager.isVisible()) await show();
    });
  }
}
