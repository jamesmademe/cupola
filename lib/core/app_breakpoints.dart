import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';

/// The window sizes the app is designed at, and the one test that decides which
/// shell paints them.
///
/// Three sizes, drawn rather than derived: 1440x900 (full), 720x450 (compact)
/// and 390x844 (mobile). Everything between them is interpolation, which is why
/// there are only two numbers here and not a scale.
///
/// The important distinction is that [isDesktopShell] asks about the
/// **platform**, not about the width. A 720pt desktop window still gets the
/// window chrome, the rail and the deck — it just gets their compact variants —
/// while a 900pt iPad must never grow a window strip it has no window for.
/// Width alone cannot tell those two apart, and the shell that tried ended up
/// putting a caption bar on an iPad. The phone used to be the second half of
/// that argument, at roughly 850pt on its side; it is portrait-only now (The
/// Portrait Rule, DESIGN.md) and never reaches those widths at all, which
/// removes an example and none of the reasoning.
abstract final class AppBreakpoints {
  /// Width at or above which a *touch* shell moves its navigation from the
  /// bottom bar to a side rail.
  ///
  /// 840 rather than 600, and the reason has changed shape. It was 840 because
  /// at 600 a phone on its side — roughly 850pt on a modern iPhone — also got
  /// the rail, replacing a thumb-reachable bottom bar on a device held in one
  /// hand. The phone is portrait-only now (The Portrait Rule, DESIGN.md) and
  /// tops out near 440pt, so it can no longer cross either number and the
  /// original argument is moot.
  ///
  /// The number stays, on the other half of its justification: 840 is
  /// Material's expanded-window breakpoint, which is where a touch surface
  /// stops being one-handed — a tablet, an unfolded foldable. That is also the
  /// width at which a touch build leaves the drawn design entirely (decision 7:
  /// out of scope at or above 840), so this is less a switch between two
  /// supported layouts than the edge of the supported range, with the rail as
  /// the least-wrong thing on the far side.
  static const double touchRail = 840;

  /// Width below which the desktop shell uses its compact variants.
  ///
  /// The two drawn desktop sizes are 1440 and 720; this sits between them,
  /// nearer the top, because the things that collapse — the deck's four glyph
  /// bands, the TrueNAS section list, a second results column — all stop
  /// fitting well before the window is halved. Below it the shell keeps every
  /// part it had and shows fewer items in each, never smaller ones.
  static const double desktopCompact = 1100;

  /// Widest the main content well is allowed to grow.
  ///
  /// A dashboard stretched across a 27-inch display is not more information, it
  /// is the same information with the reading line broken. The well centres in
  /// whatever is left after the rail and the inspector.
  static const double contentWell = 1140;

  /// Whether this build draws its own window chrome and desktop shell.
  ///
  /// Answers on the platform, so it is a constant per build rather than
  /// something a resize can change: the shell may switch between full and
  /// compact all day, but never between desktop and touch.
  ///
  /// [defaultTargetPlatform] rather than `Platform.isMacOS`, and the difference
  /// matters: widget tests run on a developer's Mac, so `dart:io` would answer
  /// "desktop" for every test in the suite and quietly re-point the whole
  /// mobile shell at the window layout. `defaultTargetPlatform` is Android
  /// under `flutter_test` unless a test says otherwise, so each shell is tested
  /// by asking for it.
  static bool get isDesktopShell =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Whether this desktop window is narrow enough for the compact variants.
  ///
  /// False on every touch build, so a caller can ask it without first asking
  /// [isDesktopShell].
  static bool isCompactDesktop(BuildContext context) =>
      isDesktopShell && MediaQuery.sizeOf(context).width < desktopCompact;
}
