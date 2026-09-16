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

  /// Aspect ratio at or above which a frame stops stacking and starts putting
  /// two things side by side.
  ///
  /// Decision 46, in one number: **the compact frame is not a narrow one.** The
  /// gate is the window's *shape*, not its width. 720x450 is 1.6:1 and gets the
  /// two-column arrangement exactly as 1440x900 does — the drawn compact frame
  /// puts the certificate beside the form at 308pt columns — while the phone, at
  /// 390x844, is the only portrait frame in the flow and the only one that
  /// stacks and scrolls.
  ///
  /// 1.2 rather than a bare `width > height`: the three drawn frames measure
  /// 1.6, 1.6 and 0.46, so anything between them separates the two arrangements,
  /// and a window dragged to nearly square has no room for a second column
  /// whatever its orientation says.
  ///
  /// It sits here rather than in the onboarding feature — where it was born,
  /// with a comment saying it belonged here — because it is a size class like
  /// [touchRail] and [desktopCompact], not a fact about onboarding: any screen
  /// whose two-column arrangement is governed by shape rather than measure asks
  /// this same question. It is *not* a width, which is the whole point:
  /// [desktopCompact] answers "how much room", this answers "what shape", and
  /// the onboarding walk asking the first one is why four drawn compact frames
  /// were code the app could never reach.
  static const double landscapeAspect = 1.2;

  /// Whether [context]'s frame is landscape enough for a side-by-side
  /// arrangement.
  ///
  /// A zero (or absent) height answers false rather than dividing by it: the
  /// first frame of a test harness and a window mid-restore both hand out a
  /// degenerate size, and "stack it" is the safe answer to a frame whose shape
  /// is not known yet.
  static bool isLandscapeFrame(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.height <= 0) return false;
    return size.width / size.height >= landscapeAspect;
  }

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
